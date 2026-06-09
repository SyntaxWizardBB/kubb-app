-- Stage-graph local ranking — parity refinement (System 3 F2).
--
-- CREATE OR REPLACE of public.tournament_stage_ranking (20261225000000)
-- with two changes; the KO/loss-tracking logic is otherwise preserved:
--
--  (1) CONSOLATION DISPATCH. In the stage-graph framework a 'consolation'
--      node is a STANDALONE bracket fed by routing edges (F1 generates it as
--      a single-elimination bracket, phase ko/final), NOT the integrated
--      ADR-0028 main+consolation bracket that skv_consolation_placements
--      models. So a consolation STAGE is now ranked with
--      skv_single_elim_placements (same as single_elim). The old dispatch to
--      skv_consolation_placements was dead code (the generator could not
--      produce consolation stages before F1).
--
--  (2) FULL NON-KO TIEBREAKER PARITY. The pool/round_robin/swiss path
--      previously used a deliberately simplified "wins desc, point_diff desc,
--      id" order. It now mirrors the proven pool-standings tiebreak
--      (tournament_pool_standings, CF2/ADR-0019 §5) scoped to the stage:
--        * scoring-aware total_points (EKC: sum final_score on the
--          participant's side; classic: sum sets won from the consensus set
--          proposals),
--        * wins, kubb_difference (basekubbs scored - conceded),
--        * Buchholz (sum of opponents' total_points), head-to-head,
--      ordered by tournaments.tiebreaker_order for total_points / wins /
--      kubb_difference, then Buchholz desc, kubb_diff desc, head-to-head,
--      registered_at asc, participant_id asc. This is the same sort the live
--      pool standings apply, so routing cuts match what an organizer sees.
--
-- Read-only / STABLE, SECURITY INVOKER, search_path = '' (every reference
-- schema-qualified), unchanged from 20261225000000.

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
  v_type        text;
  v_ko_matches  jsonb;
  v_prelim      text[];
  v_part_count  int;
  v_chain       text[];
  v_scoring     text;
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

  -- 2. Distinct, deterministically ordered stage participants.
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

  if v_part_count = 0 then
    return;
  end if;

  if v_type in ('single_elim', 'double_elim', 'consolation') then
    -- ============================================================
    -- KO path. Build the KO-match jsonb with the SAME shape/mapping as
    -- tournament_skv_compute_awards (ko->winners, final->finals, passthrough),
    -- then delegate rank to the matching skv_* helper. consolation ranks as
    -- single_elim (standalone routed bracket, F2 (1)).
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
      -- single_elim AND consolation -> single-elim placements (F2 (1)).
      select p.participant_id, p.rank
      from (
        select * from public.skv_single_elim_placements(v_ko_matches, v_prelim, 'a', false)
          where v_type in ('single_elim', 'consolation')
        union all
        select * from public.skv_double_elim_placements(v_ko_matches, v_prelim, 'a', false)
          where v_type = 'double_elim'
      ) p
    ),
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
           case when pl.rank = 1 then null else e.elim_round end as ko_elimination_round
    from placements pl
    left join elim e on e.pid = pl.participant_id::uuid
    order by pl.rank, pl.participant_id;
    return;
  end if;

  if v_type in ('pool', 'round_robin', 'swiss') then
    -- ============================================================
    -- Non-KO path with full tiebreaker parity (F2 (2)). Mirrors
    -- tournament_pool_standings scoped to this stage. ko_elimination_round
    -- is NULL throughout.
    -- ============================================================
    select t.tiebreaker_order, coalesce(t.scoring, 'ekc')
      into v_chain, v_scoring
    from public.tournaments t
    where t.id = p_tournament_id;
    v_chain := coalesce(v_chain, array[]::text[]);

    return query
    with roster as (
      select tp.id            as pid,
             tp.registered_at as reg
      from public.tournament_participants tp
      where tp.id::text = any(v_prelim)
    ),
    agreed_sets as (
      select distinct on (sp.match_id, sp.set_number)
             sp.match_id,
             sp.set_number,
             sp.basekubbs_knocked_by_a,
             sp.basekubbs_knocked_by_b,
             sp.set_winner
      from public.tournament_set_score_proposals sp
      join public.tournament_matches m
        on m.id = sp.match_id
       and sp.consensus_round = m.consensus_round
      where m.tournament_id = p_tournament_id
        and m.stage_node_id = p_node_id
        and m.status in ('finalized', 'overridden')
      order by sp.match_id, sp.set_number, sp.submitter_user_id
    ),
    match_kubbs as (
      select s.match_id,
             coalesce(sum(s.basekubbs_knocked_by_a), 0) as kubbs_a,
             coalesce(sum(s.basekubbs_knocked_by_b), 0) as kubbs_b,
             coalesce(count(*) filter (where s.set_winner = 'A'), 0) as sets_a,
             coalesce(count(*) filter (where s.set_winner = 'B'), 0) as sets_b
      from agreed_sets s
      group by s.match_id
    ),
    matches as (
      select m.id,
             m.participant_a,
             m.participant_b,
             m.winner_participant,
             coalesce(m.final_score_a, 0) as fs_a,
             coalesce(m.final_score_b, 0) as fs_b,
             coalesce(k.kubbs_a, 0)       as k_a,
             coalesce(k.kubbs_b, 0)       as k_b,
             coalesce(k.sets_a, 0)        as sw_a,
             coalesce(k.sets_b, 0)        as sw_b
      from public.tournament_matches m
      left join match_kubbs k on k.match_id = m.id
      where m.tournament_id = p_tournament_id
        and m.stage_node_id = p_node_id
        and m.status in ('finalized', 'overridden')
        and m.participant_a is not null
        and m.participant_b is not null
    ),
    match_view as (
      select m.id as match_id, m.participant_a as pid, m.participant_b as opp,
             m.fs_a as points_for, m.sw_a as set_wins,
             m.k_a as k_for, m.k_b as k_against,
             case when m.winner_participant = m.participant_a then 1
                  when m.winner_participant is null          then 0
                  else -1 end as h2h_delta,
             case when m.winner_participant = m.participant_a then 1 else 0 end as win
      from matches m
      union all
      select m.id, m.participant_b, m.participant_a,
             m.fs_b, m.sw_b, m.k_b, m.k_a,
             case when m.winner_participant = m.participant_b then 1
                  when m.winner_participant is null          then 0
                  else -1 end,
             case when m.winner_participant = m.participant_b then 1 else 0 end
      from matches m
    ),
    scoped as (
      select v.* from match_view v
      join roster r1 on r1.pid = v.pid
      join roster r2 on r2.pid = v.opp
    ),
    per_part as (
      select r.pid,
             r.reg,
             case when v_scoring = 'classic'
                  then coalesce(sum(v.set_wins),   0)
                  else coalesce(sum(v.points_for), 0)
             end                          as total_points,
             coalesce(sum(v.win),       0) as wins,
             coalesce(sum(v.k_for),     0) as kubbs_scored,
             coalesce(sum(v.k_against), 0) as kubbs_conceded
      from roster r
      left join scoped v on v.pid = r.pid
      group by r.pid, r.reg
    ),
    totals as (
      select pid, total_points from per_part
    ),
    enriched as (
      select pp.pid,
             pp.reg,
             pp.total_points,
             pp.wins,
             (pp.kubbs_scored - pp.kubbs_conceded) as kubb_diff,
             coalesce(
               (select sum(t.total_points)
                  from scoped sc
                  join totals t on t.pid = sc.opp
                 where sc.pid = pp.pid),
               0)                                  as buchholz,
             coalesce(
               (select sum(sc.h2h_delta)
                  from scoped sc
                 where sc.pid = pp.pid),
               0)                                  as h2h_sum
      from per_part pp
    )
    select e.pid,
           (row_number() over (
              order by
                case when 'total_points'    = any(v_chain) then -e.total_points else 0 end,
                case when 'wins'            = any(v_chain) then -e.wins         else 0 end,
                case when 'kubb_difference' = any(v_chain) then -e.kubb_diff    else 0 end,
                -e.buchholz,
                -e.kubb_diff,
                -e.h2h_sum,
                e.reg asc,
                e.pid asc
            ))::int as rank,
           null::int as ko_elimination_round
    from enriched e
    order by rank;
    return;
  end if;

  -- Known table value but not handled here (e.g. shootout_quali) -> 0 rows.
  return;
end;
$$;

comment on function public.tournament_stage_ranking(uuid, text) is
  'Local per-stage ranking for the stage-graph runner (ADR-0030 step 1). KO '
  'stages reuse skv_*_placements for rank; consolation ranks as single_elim '
  '(standalone routed bracket, F2). Non-KO stages (pool/round_robin/swiss) use '
  'FULL pool-standings tiebreaker parity scoped to the stage: scoring-aware '
  'total_points (EKC final_score / classic set wins), wins, kubb_difference, '
  'Buchholz, head-to-head, ordered by tournaments.tiebreaker_order then '
  'Buchholz/kubb_diff/h2h/registered_at/id. ko_elimination_round = round of the '
  'FINAL elimination (champion -> NULL). Read-only/STABLE. Incomplete KO '
  'brackets propagate the helpers 22023. shootout_quali / unknown -> 0 rows.';
