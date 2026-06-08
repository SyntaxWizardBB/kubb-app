-- SKV tour-points award computation (System 1), additive, READ-ONLY.
--
-- Pure SELECT function (no writes). Given a tournament, it derives the SKV
-- placement points for every confirmed participant and projects them onto every
-- season the tournament is assigned to (season_tournaments), applying the
-- per-assignment tournament_factor and league_factor. The actual persistence
-- into season_standings_awards is a LATER finalize step (B2c2) and is NOT done
-- here; likewise the rated / club_id eligibility gate (CF1) is applied by the
-- finalize step, not by this read-only computation.
--
-- Point math is delegated entirely to the existing, parity-tested helpers:
--   public.skv_points                  (20261213000000)
--   public.skv_single_elim_placements  (20261214000000)
--   public.skv_double_elim_placements  (20261215000000)
--   public.skv_consolation_placements  (20261215000000)
-- This function only assembles their jsonb input from tournament_matches and
-- joins the resulting placements back to season assignments.
--
-- IMPORTANT phase mapping: the DB stores KO phases as
--   ko | final | third_place | wb | lb | grand_final | grand_final_reset
--   | consolation | consolation_third_place
-- (see tournament_matches_phase_check). The placement helpers, however, consume
-- the Dart bracket vocabulary, where the main single-elim winners phase is
-- 'winners' and the main final is 'finals'. We therefore translate
--   ko    -> winners
--   final -> finals
-- while passing the remaining phases through unchanged. 'group' and NULL phases
-- are excluded entirely (they are not part of any KO bracket).
--
-- search_path = '' => every reference is schema-qualified.

create or replace function public.tournament_skv_compute_awards(
  p_tournament_id uuid
) returns table(
  season_id      uuid,
  league_id      uuid,
  participant_id uuid,
  placement      int,
  base_points    int,
  final_points   numeric
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_team_size        smallint;
  v_league_cats      text[];
  v_league           text;            -- 'einzel' | 'c' | 'a'
  v_prelim           text[];          -- confirmed participant ids, deterministic order
  v_ko_matches       jsonb;           -- mapped KO matches as jsonb array
  v_db_phases        text[];          -- distinct DB KO phases present
  v_is_double        boolean;
  v_is_consolation   boolean;
begin
  -- 1. Load tournament. (No rated / club_id gate here -- that is the finalize
  --    step's responsibility, B2c2.)
  select t.team_size, t.league_categories
    into v_team_size, v_league_cats
  from public.tournaments t
  where t.id = p_tournament_id;

  if not found then
    -- Unknown tournament: nothing to compute.
    return;
  end if;

  -- 2. Derive the league text (case-insensitive on league_categories).
  --    team_size = 1                                  -> 'einzel'
  --    contains 'C' and neither 'A' nor 'B'           -> 'c'
  --    otherwise                                      -> 'a'
  if v_team_size = 1 then
    v_league := 'einzel';
  elsif exists (
          select 1 from unnest(coalesce(v_league_cats, '{}'::text[])) c
          where lower(c) = 'c'
        )
    and not exists (
          select 1 from unnest(coalesce(v_league_cats, '{}'::text[])) c
          where lower(c) in ('a', 'b')
        )
  then
    v_league := 'c';
  else
    v_league := 'a';
  end if;

  -- 3. Participant set + deterministic preliminary ranking.
  --    All confirmed/approved participants, ordered by seed ASC NULLS LAST,
  --    then id. ('approved' is tolerated for forward-compat; the current
  --    registration_status check constraint only emits 'confirmed'.)
  select array_agg(tp.id::text order by tp.seed asc nulls last, tp.id)
    into v_prelim
  from public.tournament_participants tp
  where tp.tournament_id = p_tournament_id
    and tp.registration_status in ('confirmed', 'approved');

  v_prelim := coalesce(v_prelim, array[]::text[]);

  -- 4. Build the KO-match jsonb array. Only KO phases; 'group'/NULL excluded.
  --    DB phase -> helper phase: ko -> winners, final -> finals, rest passthrough.
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'round',  m.round_number,
               'phase',  case m.phase
                           when 'ko'    then 'winners'
                           when 'final' then 'finals'
                           else m.phase
                         end,
               'a',      m.participant_a::text,
               'b',      m.participant_b::text,
               'winner', m.winner_participant::text,
               'bye',    (m.participant_a is null or m.participant_b is null)
             )
           ),
           '[]'::jsonb
         )
    into v_ko_matches
  from public.tournament_matches m
  where m.tournament_id = p_tournament_id
    and m.phase in (
      'ko', 'final', 'third_place',
      'wb', 'lb', 'grand_final', 'grand_final_reset',
      'consolation', 'consolation_third_place'
    );

  -- 6. No KO matches -> empty result. SKV scoring requires a KO phase; a pure
  --    preliminary-round tournament without a bracket is a later extension.
  if jsonb_array_length(v_ko_matches) = 0 then
    return;
  end if;

  -- 5. Detect bracket type from the DB phases actually present.
  select array_agg(distinct m.phase)
    into v_db_phases
  from public.tournament_matches m
  where m.tournament_id = p_tournament_id
    and m.phase in (
      'ko', 'final', 'third_place',
      'wb', 'lb', 'grand_final', 'grand_final_reset',
      'consolation', 'consolation_third_place'
    );

  v_is_double := v_db_phases && array['wb', 'lb', 'grand_final', 'grand_final_reset']::text[];
  v_is_consolation := v_db_phases && array['consolation', 'consolation_third_place']::text[];

  -- 7 + 8. Resolve a stable award participant id (team_id for team tournaments,
  -- user_id for singles) and project onto every season assignment, applying the
  -- per-assignment factors. The placement helper is chosen by bracket type.
  return query
  with placements as (
    select * from public.skv_double_elim_placements(v_ko_matches, v_prelim, v_league, false)
      where v_is_double
    union all
    select * from public.skv_consolation_placements(v_ko_matches, v_prelim, v_league, false)
      where (not v_is_double) and v_is_consolation
    union all
    select * from public.skv_single_elim_placements(v_ko_matches, v_prelim, v_league, false)
      where (not v_is_double) and (not v_is_consolation)
  ),
  resolved as (
    -- Stable award id: team_id for team tournaments, else user_id.
    select coalesce(tp.team_id, tp.user_id) as award_participant_id,
           pl.rank   as placement,
           pl.points as base_points
    from placements pl
    join public.tournament_participants tp
      on tp.id = pl.participant_id::uuid
  )
  select st.season_id,
         s.league_id,
         r.award_participant_id,
         r.placement,
         r.base_points,
         (r.base_points * st.tournament_factor * st.league_factor)::numeric as final_points
  from resolved r
  cross join public.season_tournaments st
  join public.seasons s on s.id = st.season_id
  where st.tournament_id = p_tournament_id;
end;
$$;

comment on function public.tournament_skv_compute_awards(uuid) is
  'SKV tour-points award computation (System 1), read-only. For a tournament, '
  'derives placement points for every confirmed participant via the existing '
  'skv_*_placements helpers (DB phases ko/final mapped to winners/finals) and '
  'projects them onto every season_tournaments assignment with '
  'tournament_factor * league_factor. No rated/club_id gate and no persistence '
  '(both belong to the later finalize step). Returns empty when no KO matches '
  'exist.';
