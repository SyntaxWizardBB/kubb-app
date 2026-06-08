-- Local per-stage ranking for the tournament stage-graph runner, additive,
-- READ-ONLY.
--
-- public.tournament_stage_ranking(p_tournament_id, p_node_id) computes the LOCAL
-- ordering of a single (completed) stage. It is the implementation of ADR-0030
-- "Runner semantics" step 1 ("close stage -> local ranking"): the resulting
-- (participant_id, rank) drives downstream routing along tournament_stage_edges.
--
-- KO stages (single_elim/double_elim/consolation) REUSE the existing,
-- parity-tested placement helpers
--   public.skv_single_elim_placements   (20261214000000)
--   public.skv_double_elim_placements    (20261215000000)
--   public.skv_consolation_placements    (20261215000000)
-- to obtain rank. The KO-match jsonb input is assembled with the SAME shape and
-- SAME DB-phase mapping as public.tournament_skv_compute_awards (20261216000000):
-- ko -> winners, final -> finals, everything else passthrough. The helpers'
-- `points` column is intentionally DISCARDED here (routing needs rank, not
-- tour-points), so p_league is passed a fixed valid value ('a') and p_is_masters
-- = false; neither affects the rank ordering.
--
-- ko_elimination_round per participant = round_number of the TERMINAL stage
-- match in which the participant was a REAL loser (complete match, no bye, the
-- non-winner). The CHAMPION (placement rank 1) -> NULL, unconditionally: in
-- double-elim the eventual champion regularly LOSES the grand_final before
-- winning the grand_final_reset, so a naive "any real loss" rule would wrongly
-- mark the champion as eliminated. We therefore force NULL for rank 1.
--
-- When a participant has several real losses the LATEST (final) elimination
-- wins. round_number is PHASE-LOCAL (e.g. grand_final / grand_final_reset are
-- both round 1), so a plain max(round_number) does NOT identify the final loss
-- across phases. We instead order losses by (phase_order, round_number) where
-- phase_order encodes tournament progression depth:
--   ko/wb/consolation early rounds  -> base ladder (use round_number)
--   lb                              -> after wb (the real double-elim elim.)
--   third_place/consolation_third_place, final/finals, grand_final,
--   grand_final_reset               -> terminal stages, latest last.
-- The loss with the maximum (phase_order, round_number) is the final
-- elimination; its round_number is reported. Single-elim has exactly one loss
-- per non-champion, so the ordering is moot there; double-elim's runner-up
-- correctly reports the grand_final/reset loss (not the earlier WB loss), and
-- consolation reports the deepest real loss.
--
-- Non-KO stages (pool/round_robin/swiss) use a SIMPLIFIED, deterministic
-- standings purely from the stage matches: wins desc, then point_diff desc, then
-- participant_id. This is a DELIBERATE simplification -- it is sufficient for
-- routing; full tiebreaker parity (e.g. Buchholz for swiss, head-to-head) is a
-- later refinement. swiss runs through this same simplified path (no Buchholz
-- here). ko_elimination_round is NULL for every non-KO participant.
--
-- Specified for COMPLETED stages: for incomplete KO brackets the skv_* helpers
-- raise their own 22023 (missing/incomplete finals/grand_final/consolation
-- final). This function does NOT catch that exception -- propagation is wanted
-- (the runner only calls after the stage is closed).
--
-- shootout_quali is an existing tournament_stages type but is NOT covered here;
-- like any unknown/missing stage it returns 0 rows.
--
-- STABLE (reads tables, mutates nothing), SECURITY INVOKER (the skv_* helpers are
-- IMMUTABLE security invoker and callable from the caller context; no DEFINER
-- needed). search_path = '' => every reference is schema-qualified.

create or replace function public.tournament_stage_ranking(
  p_tournament_id uuid,
  p_node_id       text
) returns table(
  participant_id      uuid,
  rank                int,
  ko_elimination_round int
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_type        text;             -- stage type from tournament_stages
  v_ko_matches  jsonb;            -- mapped KO matches as jsonb array (KO path)
  v_prelim      text[];           -- stage participants, deterministic order
  v_part_count  int;              -- number of distinct stage participants
begin
  -- 1. Resolve the stage type. Unknown/missing stage -> 0 rows.
  select s.type
    into v_type
  from public.tournament_stages s
  where s.tournament_id = p_tournament_id
    and s.node_id = p_node_id;

  if not found then
    return;
  end if;

  -- 2. Distinct, deterministically ordered stage participants (id::text),
  --    ordered by seed asc nulls last, then id (same ordering idea as
  --    tournament_skv_compute_awards). Empty stage -> handled below (0 rows).
  select array_agg(tp.id::text order by tp.seed asc nulls last, tp.id)
    into v_prelim
  from public.tournament_participants tp
  where tp.id in (
    select pid
    from public.tournament_matches m
    cross join lateral (values (m.participant_a), (m.participant_b)) as v(pid)
    where m.tournament_id = p_tournament_id
      and m.stage_node_id = p_node_id
      and v.pid is not null
  );

  v_prelim := coalesce(v_prelim, array[]::text[]);
  v_part_count := coalesce(array_length(v_prelim, 1), 0);

  -- No participants (no matches / all-null slots) -> 0 rows.
  if v_part_count = 0 then
    return;
  end if;

  if v_type in ('single_elim', 'double_elim', 'consolation') then
    -- ============================================================
    -- KO path. Build the KO-match jsonb with the SAME shape/mapping as
    -- tournament_skv_compute_awards (ko->winners, final->finals, passthrough),
    -- then delegate rank to the matching skv_* helper.
    -- ============================================================
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
      and m.stage_node_id = p_node_id;

    return query
    with placements as (
      -- league 'a' / masters false: points are discarded; only rank is used.
      select p.participant_id, p.rank
      from (
        select * from public.skv_single_elim_placements(v_ko_matches, v_prelim, 'a', false)
          where v_type = 'single_elim'
        union all
        select * from public.skv_double_elim_placements(v_ko_matches, v_prelim, 'a', false)
          where v_type = 'double_elim'
        union all
        select * from public.skv_consolation_placements(v_ko_matches, v_prelim, 'a', false)
          where v_type = 'consolation'
      ) p
    ),
    -- Real-loser matches: complete/terminal, no bye, the non-winner. Per
    -- participant keep the FINAL elimination, ordered by (phase_order,
    -- round_number) -- NOT a plain max(round_number), since round_number is
    -- phase-local. phase_order encodes tournament progression depth so that a
    -- later-phase loss (e.g. grand_final_reset) outranks an earlier-phase loss
    -- (e.g. wb) regardless of their phase-local round numbers.
    losses as (
      select loser_id as pid,
             m.round_number::int as elim_round,
             case m.phase
               when 'ko'                      then 0
               when 'wb'                       then 0
               when 'consolation'              then 0
               when 'lb'                       then 1
               when 'third_place'              then 2
               when 'consolation_third_place'  then 2
               when 'final'                    then 3
               when 'finals'                   then 3
               when 'grand_final'              then 4
               when 'grand_final_reset'        then 5
               else 0
             end as phase_order
      from public.tournament_matches m
      cross join lateral (
        select case
          when m.participant_a is null or m.participant_b is null
            or m.winner_participant is null then null
          when m.winner_participant = m.participant_a then m.participant_b
          when m.winner_participant = m.participant_b then m.participant_a
          else null
        end as loser_id
      ) l
      where m.tournament_id = p_tournament_id
        and m.stage_node_id = p_node_id
        and l.loser_id is not null
    ),
    elim as (
      select distinct on (ls.pid)
             ls.pid, ls.elim_round
      from losses ls
      order by ls.pid, ls.phase_order desc, ls.elim_round desc
    )
    select pl.participant_id::uuid,
           pl.rank,
           -- Champion (placement rank 1) is never eliminated -> NULL, even
           -- though in double-elim they have a real grand_final loss.
           case when pl.rank = 1 then null else e.elim_round end as ko_elimination_round
    from placements pl
    left join elim e on e.pid = pl.participant_id::uuid
    order by pl.rank, pl.participant_id;
    return;
  end if;

  if v_type in ('pool', 'round_robin', 'swiss') then
    -- ============================================================
    -- Non-KO path. Simplified, deterministic standings from the stage matches
    -- (sufficient for routing; full tiebreaker parity is a later refinement;
    -- swiss uses this same path -- no Buchholz here). ko_elimination_round NULL.
    -- ============================================================
    return query
    with parts(pid) as (
      select s.id::uuid from unnest(v_prelim) as s(id)
    ),
    stats as (
      select pt.pid,
             count(*) filter (
               where m.winner_participant = pt.pid
             ) as wins,
             coalesce(sum(
               case
                 when m.participant_a = pt.pid
                   then coalesce(m.final_score_a, 0) - coalesce(m.final_score_b, 0)
                 when m.participant_b = pt.pid
                   then coalesce(m.final_score_b, 0) - coalesce(m.final_score_a, 0)
                 else 0
               end
             ), 0) as point_diff
      from parts pt
      left join public.tournament_matches m
        on m.tournament_id = p_tournament_id
       and m.stage_node_id = p_node_id
       and (m.participant_a = pt.pid or m.participant_b = pt.pid)
      group by pt.pid
    )
    select st.pid,
           (row_number() over (
              order by st.wins desc, st.point_diff desc, st.pid
            ))::int as rank,
           null::int as ko_elimination_round
    from stats st
    order by rank;
    return;
  end if;

  -- Known table value but not handled here (e.g. shootout_quali) -> 0 rows.
  return;
end;
$$;

comment on function public.tournament_stage_ranking(uuid, text) is
  'Local per-stage ranking for the stage-graph runner (ADR-0030 step 1: close '
  'stage -> local ranking that drives routing). KO stages reuse the '
  'skv_*_placements helpers for rank (their points column is discarded; '
  'p_league=a/masters=false do not affect ordering); ko_elimination_round = the '
  'round_number of the FINAL elimination, the loss with the maximum '
  '(phase_order, round_number) since round_number is phase-local (champion / '
  'placement rank 1 -> NULL even in double-elim where the champion loses the '
  'grand_final). Non-KO stages '
  '(pool/round_robin/swiss) use a SIMPLIFIED deterministic standings (wins desc, '
  'point_diff desc, participant_id) -- a deliberate simplification sufficient for '
  'routing; full tiebreaker parity is a later refinement. Read-only/STABLE. '
  'Specified for completed stages: incomplete KO brackets propagate the helpers '
  '22023. Unknown/missing stage or shootout_quali -> 0 rows.';
