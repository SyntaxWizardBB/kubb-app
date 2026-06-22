-- Stage-graph local ranking — schoch §5 Buchholz + bye credit + alias widen.
--
-- CREATE OR REPLACE of public.tournament_stage_ranking (last set in
-- 20261248000000) with three fixes. The KO path is untouched; only the
-- non-KO path changes. Additive and deploy-safe: an old app build keeps
-- writing the same match/stage rows, this only reads them differently.
--
--  (1) TYPE ALIASES. 20261293000000 renamed the wire values swiss->schoch
--      and pool->group_phase; the generator now writes 'schoch'/'group_phase'.
--      The old non-KO branch only matched 'pool','round_robin','swiss', so
--      every post-rename schoch and group_phase stage ranked to ZERO rows.
--      The branch now matches all aliases.
--
--  (2) BUCHHOLZ per schoch-swiss-pairing-buchholz-spec.md §5. The previous
--      Buchholz was the NAIVE opponent-total sum. §5 requires, per opponent G,
--      total(G) minus the score G made head-to-head against P. Aggregated:
--        Buchholz(P) = (Σ total of P's real opponents) − (Σ what those
--                       opponents scored against P).
--      The H2H subtraction is in the same unit as total_points (final_score
--      for EKC, set wins for classic), so match_view now carries the
--      opponent's score (points_against).
--
--  (3) BYE = 16 for the schoch path only. The schoch generator
--      (20261293000000) writes a bye as a finalized match with
--      participant_b NULL, winner = the bye player, final_score_a NULL. §4
--      credits the bye player a full win = 16 points; that 16 stays in the
--      player's total and so feeds every real opponent's Buchholz (§5.3). The
--      matches CTE dropped bye rows (participant_b filter), so the 16 was
--      lost. For schoch/swiss stages a byes CTE now adds 16 to the bye
--      player's total_points before totals is taken; the bye is NOT a
--      scoped opponent, so it adds nothing to the bye player's own Buchholz.
--      group_phase/pool/round_robin keep their old bye behaviour (0).
--
-- SCOPE BOUNDARY (M2-T05, NOT here): the full per-type chain split — group
-- phase ranking WITHOUT the Buchholz fallback (ADR-0035) — is deferred. Here
-- group_phase stays on the existing Buchholz-bearing tiebreak chain; the only
-- group_phase change is that it ranks at all again (fix 1). The §5 Buchholz +
-- bye=16 land on the schoch path. group_phase byes are not generated, so the
-- shared bye CTE is gated on the schoch/swiss type and leaves group_phase
-- untouched.
--
-- Read-only / STABLE, SECURITY INVOKER, search_path = '' (every reference
-- schema-qualified).

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
    -- single_elim (standalone routed bracket).
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

  if v_type in ('pool', 'group_phase', 'round_robin', 'swiss', 'schoch') then
    -- ============================================================
    -- Non-KO path. Pool-standings tiebreak parity scoped to the stage:
    -- scoring-aware total_points, wins, kubb_difference, §5 Buchholz, h2h,
    -- ordered by tournaments.tiebreaker_order then Buchholz/kubb_diff/h2h/
    -- registered_at/id. ko_elimination_round is NULL throughout.
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
    -- Schoch/swiss bye credit (§4): a bye is a finalized match with
    -- participant_b NULL, winner = the bye player. Worth 16 points, summed
    -- into the player's total_points so it also feeds opponents' Buchholz
    -- (§5.3). Gated on schoch/swiss; group_phase/pool/round_robin do not
    -- generate byes and stay at 0.
    byes as (
      select m.participant_a as pid,
             count(*)::int * 16 as bye_points
      from public.tournament_matches m
      where m.tournament_id = p_tournament_id
        and m.stage_node_id = p_node_id
        and m.status in ('finalized', 'overridden')
        and m.participant_a is not null
        and m.participant_b is null
        and m.winner_participant = m.participant_a
        and v_type in ('swiss', 'schoch')
      group by m.participant_a
    ),
    match_view as (
      select m.id as match_id, m.participant_a as pid, m.participant_b as opp,
             m.fs_a as points_for, m.fs_b as points_against,
             m.sw_a as set_wins, m.sw_b as set_wins_opp,
             m.k_a as k_for, m.k_b as k_against,
             case when m.winner_participant = m.participant_a then 1
                  when m.winner_participant is null          then 0
                  else -1 end as h2h_delta,
             case when m.winner_participant = m.participant_a then 1 else 0 end as win
      from matches m
      union all
      select m.id, m.participant_b, m.participant_a,
             m.fs_b, m.fs_a,
             m.sw_b, m.sw_a, m.k_b, m.k_a,
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
             end
               + coalesce(max(b.bye_points), 0) as total_points,
             coalesce(sum(v.win),       0) as wins,
             coalesce(sum(v.k_for),     0) as kubbs_scored,
             coalesce(sum(v.k_against), 0) as kubbs_conceded
      from roster r
      left join scoped v on v.pid = r.pid
      left join byes  b on b.pid = r.pid
      group by r.pid, r.reg
    ),
    totals as (
      select pid, total_points from per_part
    ),
    -- §5 head-to-head subtraction in the total_points unit (final_score for
    -- ekc, set wins for classic), so it cancels against the opponent total.
    opp_against as (
      select sc.pid,
             sum(case when v_scoring = 'classic' then sc.set_wins_opp
                      else sc.points_against end) as against
      from scoped sc
      group by sc.pid
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
               0)
             - coalesce(
                 (select oa.against from opp_against oa where oa.pid = pp.pid),
                 0)                               as buchholz,
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
  'stages reuse skv_*_placements for rank; consolation ranks as single_elim. '
  'Non-KO stages (pool/group_phase/round_robin/swiss/schoch) use pool-standings '
  'tiebreaker parity scoped to the stage: scoring-aware total_points, wins, '
  'kubb_difference, then schoch-swiss spec §5 Buchholz (opponent total minus '
  'their head-to-head score against the player), head-to-head, ordered by '
  'tournaments.tiebreaker_order then Buchholz/kubb_diff/h2h/registered_at/id. '
  'schoch/swiss byes credit 16 to the bye player''s total (feeds opponents'' '
  'Buchholz); group_phase/pool byes stay 0. The per-type chain split (group '
  'phase without Buchholz, ADR-0035) is deferred to M2. ko_elimination_round = '
  'round of the FINAL elimination (champion -> NULL). Read-only/STABLE. '
  'shootout_quali / unknown -> 0 rows.';
