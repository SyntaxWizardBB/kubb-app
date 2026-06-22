-- Stage-graph ranking — per-type tiebreak chain (ADR-0035 / vorrunde-ranking-spec §6.2).
--
-- 20261295000000 fixed the §5 Buchholz and the bye credit but still ranked
-- EVERY non-KO type through ONE generic chain: tiebreaker_order-gated
-- total_points/wins/kubb_difference followed by an always-on
-- "-e.buchholz, -e.kubb_diff, -e.h2h_sum" fallback. The spec (and ADR-0035)
-- forbids Buchholz in the group phase in ANY path — even as a silent
-- fallback — because in a full group every two point-equal players face the
-- SAME opponents and so have IDENTICAL Buchholz; it never separates them.
-- The kubb difference does.
--
-- This migration splits the chain strictly by stage type. The chain is
-- derived from the type, not from the per-tournament tiebreaker_order (which
-- ADR-0035 removes as a per-stage knob for the preliminary round):
--
--   schoch / swiss  (spec §6.2 / §2.2, identical to §6.1):
--       total_points DESC -> buchholz DESC -> stable seed (registered_at, id)
--     No wins, no kubb_diff, no h2h between points and Buchholz.
--
--   group_phase / pool / round_robin  (spec §6.2 / §2.1):
--       total_points DESC -> kubb_difference DESC -> stable seed
--     NO Buchholz, NO h2h, NO median in any branch.
--
-- Five live ranking/cut sites carry the generic chain today and are rebranched
-- here. The first two were already covered when this migration was first
-- written; the last three were found later — the claim that the pool-cut path
-- "ranks WITHOUT Buchholz, so it is conformant" missed that it ranks
-- total_points -> wins -> kubb_diff gated by tiebreaker_order. No Buchholz, yes,
-- but `wins` sits between points and kubb_diff and the chain is read from the
-- per-tournament tiebreaker_order — both forbidden by ADR-0035 (the chain
-- follows from the stage type, kubb_diff comes right after points, no wins).
--
--   * public.tournament_stage_ranking      (last set 20261295000000)
--       non-KO ORDER BY -> per-type chain (block 1).
--   * public.tournament_pool_standings     (last set 20261207000000)
--       group-phase `ordered` window -> points -> kubb_diff (block 2).
--   * public._tournament_compute_pool_cut  (last set 20260615000009)
--       per-pool KO cut. `ranked` row_number AND the `grouped` tie-detection
--       GROUP BY both dropped from tiebreaker-gated points/wins/kubb_diff to
--       the hard-coded group-phase chain points -> kubb_diff (block 3).
--   * public._tournament_detect_shootout_groups (last set 20261202000000)
--       cut-line shoot-out detector. Its `tie_fp` fingerprint AND its `ranked`
--       row_number must use the SAME group-phase chain so the rows it flags as
--       tied match the qualifier order (block 4).
--   * public.tournament_start_ko_phase     (last set 20261287000000)
--       three internal flat-preliminary seed-ranking CTEs (default seed,
--       shoot-out resolve order, consolation direct starters) on the same
--       points -> kubb_diff chain (block 5).
--
-- All three newly-fixed functions read ONLY phase = 'group' matches and the
-- group_label, i.e. they are exclusively classic group-phase (round-robin pool
-- -> KO) paths. None of them aggregates Buchholz and none is ever called for a
-- Schoch stage (Schoch is ranked by tournament_stage_ranking via the stage-graph
-- runner, block 1). So the group-phase chain needs kubb_diff only — Buchholz is
-- neither available nor required here, per the §4 reasoning (a full group gives
-- point-equal players identical Buchholz).
--
-- ADDITIVE / deploy-safe: CREATE OR REPLACE of the LATEST definition of each
-- function. No table change, no data migration, no edit of an old migration
-- file. The §5 Buchholz aggregation and the bye=16 credit from 20261295000000
-- are preserved verbatim; only the final ORDER BY of the schoch path keeps
-- Buchholz, and the group_phase path drops it for kubb_difference.

-- ====================================================================
-- 1. public.tournament_stage_ranking — per-type non-KO chain.
-- ====================================================================
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
    -- Non-KO path. Scoring-aware total_points, §5 Buchholz, kubb_diff and
    -- the bye=16 credit are computed exactly as in 20261295000000; only the
    -- final ORDER BY is split by stage type (ADR-0035):
    --   schoch/swiss          -> points -> buchholz -> stable seed
    --   group_phase/pool/rr   -> points -> kubb_diff -> stable seed (no buchholz)
    -- ko_elimination_round is NULL throughout.
    -- ============================================================
    select coalesce(t.scoring, 'ekc')
      into v_scoring
    from public.tournaments t
    where t.id = p_tournament_id;

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
    -- participant_b NULL, winner = the bye player, worth 16 points so it also
    -- feeds opponents' Buchholz (§5.3). group_phase/pool/round_robin do not
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
             m.k_a as k_for, m.k_b as k_against
      from matches m
      union all
      select m.id, m.participant_b, m.participant_a,
             m.fs_b, m.fs_a,
             m.sw_b, m.sw_a, m.k_b, m.k_a
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
             (pp.kubbs_scored - pp.kubbs_conceded) as kubb_diff,
             coalesce(
               (select sum(t.total_points)
                  from scoped sc
                  join totals t on t.pid = sc.opp
                 where sc.pid = pp.pid),
               0)
             - coalesce(
                 (select oa.against from opp_against oa where oa.pid = pp.pid),
                 0)                               as buchholz
      from per_part pp
    )
    select e.pid,
           (row_number() over (
              order by
                -e.total_points,
                -- ADR-0035: schoch/swiss keep Buchholz here, group_phase/pool/
                -- round_robin use kubb_difference and NEVER Buchholz.
                case when v_type in ('swiss', 'schoch') then -e.buchholz
                     else -e.kubb_diff end,
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
  'Non-KO stages compute scoring-aware total_points, §5 Buchholz and kubb_diff '
  'scoped to the stage, then ORDER BY a per-type chain (ADR-0035 / '
  'vorrunde-ranking-spec §6.2): schoch/swiss = points -> Buchholz -> stable '
  'seed (registered_at, id); group_phase/pool/round_robin = points -> '
  'kubb_difference -> stable seed, with NO Buchholz in any path. schoch/swiss '
  'byes credit 16 to the bye player''s total (feeds opponents'' Buchholz); '
  'group_phase/pool byes stay 0. ko_elimination_round = round of the FINAL '
  'elimination (champion -> NULL). Read-only/STABLE. shootout_quali / unknown '
  '-> 0 rows.';

-- ====================================================================
-- 2. public.tournament_pool_standings — group-phase chain WITHOUT Buchholz.
-- ====================================================================
-- This RPC reads ONLY phase = 'group' matches, i.e. it is exclusively a group
-- phase ranking. Per spec §6.2 / ADR-0035 §4 it must rank
-- total_points -> kubb_difference -> stable seed and carry no Buchholz in the
-- sort. The Buchholz / opponent-total / h2h payload columns stay in the JSON
-- (clients still display them as info), but they are removed from the ORDER BY.
-- Rebased on the latest definition (20261207000000); the scoring-mode logic
-- is preserved verbatim, only the `ordered` ORDER BY changes.
CREATE OR REPLACE FUNCTION public.tournament_pool_standings(
  p_tournament_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_creator    uuid;
  v_is_member  boolean;
  v_chain      text[];
  v_scoring    text;
  v_result     jsonb;
BEGIN
  -- ---- 1. Authentication + visibility gate ---------------------------
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, tiebreaker_order, scoring
    INTO v_creator, v_chain, v_scoring
    FROM public.tournaments
   WHERE id = p_tournament_id;
  IF v_creator IS NULL AND v_chain IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;

  v_scoring := coalesce(v_scoring, 'ekc');

  SELECT EXISTS (
    SELECT 1 FROM public.tournament_participants p
     WHERE p.tournament_id = p_tournament_id
       AND p.user_id       = v_caller
  ) INTO v_is_member;

  IF v_creator IS DISTINCT FROM v_caller AND NOT v_is_member THEN
    RAISE EXCEPTION 'not authorised' USING ERRCODE = '42501';
  END IF;

  -- ---- 2. Build per-participant stats via CTE pipeline --------------
  WITH roster AS (
    SELECT p.id            AS pid,
           p.group_label   AS lbl,
           p.registered_at AS reg
      FROM public.tournament_participants p
     WHERE p.tournament_id      = p_tournament_id
       AND p.registration_status = 'confirmed'
       AND p.group_label        IS NOT NULL
  ),
  agreed_sets AS (
    SELECT DISTINCT ON (sp.match_id, sp.set_number)
           sp.match_id,
           sp.set_number,
           sp.basekubbs_knocked_by_a,
           sp.basekubbs_knocked_by_b,
           sp.set_winner
      FROM public.tournament_set_score_proposals sp
      JOIN public.tournament_matches m
        ON m.id = sp.match_id
       AND sp.consensus_round = m.consensus_round
     WHERE m.tournament_id = p_tournament_id
       AND m.phase         = 'group'
       AND m.status        IN ('finalized','overridden')
     ORDER BY sp.match_id, sp.set_number, sp.submitter_user_id
  ),
  match_kubbs AS (
    SELECT s.match_id,
           coalesce(sum(s.basekubbs_knocked_by_a), 0) AS kubbs_a,
           coalesce(sum(s.basekubbs_knocked_by_b), 0) AS kubbs_b,
           coalesce(count(*) FILTER (WHERE s.set_winner = 'A'), 0) AS sets_a,
           coalesce(count(*) FILTER (WHERE s.set_winner = 'B'), 0) AS sets_b
      FROM agreed_sets s
     GROUP BY s.match_id
  ),
  matches AS (
    SELECT m.id,
           m.participant_a,
           m.participant_b,
           m.winner_participant,
           coalesce(m.final_score_a, 0) AS fs_a,
           coalesce(m.final_score_b, 0) AS fs_b,
           coalesce(k.kubbs_a, 0)       AS k_a,
           coalesce(k.kubbs_b, 0)       AS k_b,
           coalesce(k.sets_a, 0)        AS sw_a,
           coalesce(k.sets_b, 0)        AS sw_b
      FROM public.tournament_matches m
      LEFT JOIN match_kubbs k ON k.match_id = m.id
     WHERE m.tournament_id = p_tournament_id
       AND m.phase         = 'group'
       AND m.status        IN ('finalized','overridden')
       AND m.participant_a IS NOT NULL
       AND m.participant_b IS NOT NULL
  ),
  match_view AS (
    SELECT m.id                                  AS match_id,
           m.participant_a                       AS pid,
           m.participant_b                       AS opp,
           m.fs_a                                AS points_for,
           m.fs_b                                AS points_against,
           m.sw_a                                AS set_wins,
           m.k_a                                 AS k_for,
           m.k_b                                 AS k_against,
           CASE WHEN m.winner_participant = m.participant_a THEN 1
                WHEN m.winner_participant IS NULL          THEN 0
                ELSE -1 END                       AS h2h_delta,
           CASE WHEN m.winner_participant = m.participant_a THEN 1
                ELSE 0 END                        AS win
      FROM matches m
    UNION ALL
    SELECT m.id,
           m.participant_b,
           m.participant_a,
           m.fs_b,
           m.fs_a,
           m.sw_b,
           m.k_b,
           m.k_a,
           CASE WHEN m.winner_participant = m.participant_b THEN 1
                WHEN m.winner_participant IS NULL          THEN 0
                ELSE -1 END,
           CASE WHEN m.winner_participant = m.participant_b THEN 1
                ELSE 0 END
      FROM matches m
  ),
  scoped AS (
    SELECT v.*
      FROM match_view v
      JOIN roster r1 ON r1.pid = v.pid
      JOIN roster r2 ON r2.pid = v.opp
  ),
  per_part AS (
    SELECT r.pid,
           r.lbl,
           r.reg,
           CASE WHEN v_scoring = 'classic'
                THEN coalesce(sum(v.set_wins),   0)
                ELSE coalesce(sum(v.points_for), 0)
           END                                  AS total_points,
           coalesce(sum(v.win),            0) AS wins,
           coalesce(sum(v.k_for),          0) AS kubbs_scored,
           coalesce(sum(v.k_against),      0) AS kubbs_conceded,
           coalesce(array_agg(v.opp ORDER BY v.match_id)
                      FILTER (WHERE v.opp IS NOT NULL),
                    ARRAY[]::uuid[])           AS opponent_ids
      FROM roster r
      LEFT JOIN scoped v ON v.pid = r.pid
     GROUP BY r.pid, r.lbl, r.reg
  ),
  totals AS (
    SELECT pid, total_points FROM per_part
  ),
  opp_lookup AS (
    SELECT v.pid,
           jsonb_object_agg(t.pid::text, t.total_points) AS lookup
      FROM (
        SELECT DISTINCT pid, opp FROM scoped
      ) v
      JOIN totals t ON t.pid = v.opp
     GROUP BY v.pid
  ),
  h2h_lookup AS (
    SELECT v.pid,
           jsonb_object_agg(v.opp::text, v.delta) AS lookup
      FROM (
        SELECT pid, opp, sum(h2h_delta)::int AS delta
          FROM scoped
         GROUP BY pid, opp
      ) v
     GROUP BY v.pid
  ),
  enriched AS (
    SELECT pp.pid,
           pp.lbl,
           pp.reg,
           pp.total_points,
           pp.wins,
           pp.kubbs_scored,
           pp.kubbs_conceded,
           pp.opponent_ids,
           coalesce(ol.lookup, '{}'::jsonb) AS opp_lookup_json,
           coalesce(hl.lookup, '{}'::jsonb) AS h2h_lookup_json,
           (pp.kubbs_scored - pp.kubbs_conceded) AS kubb_diff
      FROM per_part pp
      LEFT JOIN opp_lookup ol ON ol.pid = pp.pid
      LEFT JOIN h2h_lookup hl ON hl.pid = pp.pid
  ),
  ordered AS (
    -- ADR-0035 / spec §6.2: the group phase ranks strictly
    -- total_points -> kubb_difference -> stable seed. No Buchholz, no h2h.
    SELECT e.*,
           row_number() OVER (
             PARTITION BY e.lbl
             ORDER BY
               -e.total_points,
               -e.kubb_diff,
               e.reg ASC,
               e.pid ASC
           ) AS rnk
      FROM enriched e
  )
  SELECT jsonb_build_object(
           'groups',
           coalesce(
             jsonb_agg(
               jsonb_build_object(
                 'group_label', g.lbl,
                 'stats',       g.stats
               ) ORDER BY g.lbl
             ),
             '[]'::jsonb))
    INTO v_result
    FROM (
      SELECT o.lbl,
             jsonb_agg(
               jsonb_build_object(
                 'participant_id',                o.pid::text,
                 'total_points',                  o.total_points,
                 'wins',                          o.wins,
                 'kubbs_scored',                  o.kubbs_scored,
                 'kubbs_conceded',                o.kubbs_conceded,
                 'opponent_ids',                  to_jsonb(
                                                   coalesce(
                                                     (SELECT array_agg(x::text)
                                                        FROM unnest(o.opponent_ids) AS x),
                                                     ARRAY[]::text[])),
                 'opponent_total_points_lookup',  o.opp_lookup_json,
                 'head_to_head_lookup',           o.h2h_lookup_json
               ) ORDER BY o.rnk
             ) AS stats
        FROM ordered o
       GROUP BY o.lbl
    ) g;

  RETURN coalesce(v_result, jsonb_build_object('groups', '[]'::jsonb));
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_pool_standings(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tournament_pool_standings(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_pool_standings(uuid) IS
  'Per-pool standings snapshot for the pool phase. total_points respects '
  'tournaments.scoring (EKC sums final_score, classic sums sets won). '
  'ADR-0035 / vorrunde-ranking-spec §6.2: the group phase ranks strictly '
  'total_points -> kubb_difference -> stable seed (registered_at, id) and '
  'carries NO Buchholz in the sort (a full group gives point-equal players '
  'identical Buchholz, so it never separates them). Buchholz/opponent-total/'
  'h2h payload columns remain in the JSON for display only. SECURITY DEFINER; '
  'visible to organizer or any registered participant. See ADR-0019 §5, '
  'ADR-0035.';

-- ====================================================================
-- 3. public._tournament_compute_pool_cut — per-pool KO cut.
-- ====================================================================
-- Rebased on the latest definition (20260615000009). The body is preserved
-- verbatim EXCEPT for the two ranking sites:
--   * the `ranked` row_number ORDER BY, and
--   * the `grouped` tie-detection GROUP BY (which decides who is "fully tied"
--     and so needs a shoot-out / cross-pool resolve).
-- Both dropped the tiebreaker_order-gated total_points/wins/kubb_diff for the
-- hard-coded group-phase chain total_points -> kubb_difference (ADR-0035 / spec
-- §6.2). `wins` is gone (it sat between points and kubb_diff) and so is the
-- v_chain gating. v_chain stays in the signature/payload for compatibility but
-- no longer drives the sort. registered_at/pid remain the deterministic tail.
CREATE OR REPLACE FUNCTION public._tournament_compute_pool_cut(
  p_tournament_id uuid,
  p_group_label   text,
  p_top_n         integer
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_chain         text[];
  v_qualifiers    uuid[] := ARRAY[]::uuid[];
  v_tied          jsonb := '[]'::jsonb;
  v_needs_resolve boolean := false;
BEGIN
  IF p_top_n < 1 THEN
    RAISE EXCEPTION 'top_n must be >= 1' USING ERRCODE = '22023';
  END IF;

  SELECT tiebreaker_order INTO v_chain
    FROM public.tournaments
    WHERE id = p_tournament_id;
  IF v_chain IS NULL THEN
    RAISE EXCEPTION 'tournament not found: %', p_tournament_id
      USING ERRCODE = '22023';
  END IF;

  -- Per-participant stats for this group. ADR-0035 / vorrunde-ranking-spec §6.2:
  -- the group-phase rank is total_points -> kubb_difference -> stable seed. No
  -- Buchholz/Median (those are Schoch-specific and never reach the pool cut),
  -- no wins, no tiebreaker_order gating. wins is still computed for the legacy
  -- payload but is NOT a sort key.
  WITH part AS (
    SELECT p.id AS pid,
           p.registered_at
      FROM public.tournament_participants p
     WHERE p.tournament_id  = p_tournament_id
       AND p.group_label    = p_group_label
       AND p.registration_status = 'confirmed'
  ),
  matches AS (
    SELECT m.*
      FROM public.tournament_matches m
     WHERE m.tournament_id = p_tournament_id
       AND m.group_label   = p_group_label
       AND m.phase         = 'group'
       AND m.status IN ('finalized','overridden')
  ),
  stats AS (
    SELECT p.pid,
           p.registered_at,
           coalesce(sum(CASE WHEN m.winner_participant = p.pid THEN 1 ELSE 0 END), 0) AS wins,
           coalesce(sum(
             CASE WHEN m.participant_a = p.pid THEN coalesce(m.final_score_a,0)
                  WHEN m.participant_b = p.pid THEN coalesce(m.final_score_b,0)
                  ELSE 0 END), 0) AS total_points,
           coalesce(sum(
             CASE WHEN m.participant_a = p.pid
                    THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                  WHEN m.participant_b = p.pid
                    THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                  ELSE 0 END), 0) AS kubb_diff
      FROM part p
      LEFT JOIN matches m
        ON (m.participant_a = p.pid OR m.participant_b = p.pid)
     GROUP BY p.pid, p.registered_at
  ),
  ranked AS (
    SELECT s.*,
           row_number() OVER (
             ORDER BY
               -s.total_points,
               -s.kubb_diff,
               s.registered_at ASC,
               s.pid ASC
           ) AS rank
      FROM stats s
  )
  SELECT array_agg(pid ORDER BY rank)
    INTO v_qualifiers
    FROM ranked
   WHERE rank <= p_top_n;

  -- Tie-detection on the SAME group-phase keys as the sort above: a tie group
  -- is a set of participants identical on total_points AND kubb_difference. If
  -- such a group straddles the qualification line the caller resolves it via a
  -- shoot-out (spec §3). Grouping on wins or any gated criterion would either
  -- split or merge ties inconsistently with the ranking, so it mirrors `ranked`.
  WITH stats AS (
    SELECT p.id AS pid, p.registered_at,
           coalesce(sum(
             CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                  WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                  ELSE 0 END), 0) AS total_points,
           coalesce(sum(
             CASE WHEN m.participant_a = p.id
                    THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                  WHEN m.participant_b = p.id
                    THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                  ELSE 0 END), 0) AS kubb_diff
      FROM public.tournament_participants p
      LEFT JOIN public.tournament_matches m
        ON m.tournament_id = p.tournament_id
       AND m.group_label   = p_group_label
       AND m.phase         = 'group'
       AND m.status IN ('finalized','overridden')
       AND (m.participant_a = p.id OR m.participant_b = p.id)
     WHERE p.tournament_id  = p_tournament_id
       AND p.group_label    = p_group_label
       AND p.registration_status = 'confirmed'
     GROUP BY p.id, p.registered_at
  ),
  grouped AS (
    SELECT array_agg(pid::text ORDER BY pid) AS ids,
           count(*) AS cnt
      FROM stats
     GROUP BY total_points, kubb_diff
  )
  SELECT coalesce(jsonb_agg(to_jsonb(ids) ORDER BY ids), '[]'::jsonb),
         bool_or(cnt > 1)
    INTO v_tied, v_needs_resolve
    FROM grouped
   WHERE cnt > 1;

  RETURN jsonb_build_object(
    'qualifiers',            coalesce(to_jsonb(v_qualifiers), '[]'::jsonb),
    'tie_resolution_needed', coalesce(v_needs_resolve, false),
    'tied_participants',     coalesce(v_tied, '[]'::jsonb),
    'chain',                 to_jsonb(v_chain));
END;
$$;

COMMENT ON FUNCTION public._tournament_compute_pool_cut(uuid, text, integer) IS
  'Per-pool KO cut (top-N qualifiers + straddling-tie detection). ADR-0035 / '
  'vorrunde-ranking-spec §6.2: ranks total_points -> kubb_difference -> stable '
  'seed (registered_at, id), with NO wins between points and kubb_diff, NO '
  'Buchholz, and NO tiebreaker_order gating (the chain follows from the stage '
  'type, not a per-tournament knob). Group-phase only — never used for Schoch. '
  'Tie-detection groups on the same total_points/kubb_difference keys so a flag '
  'matches the qualifier order.';

-- ====================================================================
-- 4. public._tournament_detect_shootout_groups — cut-line shoot-out detector.
-- ====================================================================
-- Rebased on the latest definition (20261202000000). Two ranking sites change:
--   * the `tie_fp` criteria fingerprint (two rows are tied iff fingerprints
--     match), and
--   * the `ranked` row_number ORDER BY.
-- Both drop the tiebreaker_order-gated total_points/wins/kubb_diff for the
-- hard-coded group-phase chain total_points -> kubb_difference (ADR-0035 / spec
-- §6.2). The fingerprint MUST use the same keys as the sort, otherwise the
-- detector would flag rows as tied (or not) inconsistently with the qualifier
-- order and fire spurious / missing shoot-outs (spec §7.1/§7.3).
CREATE OR REPLACE FUNCTION public._tournament_detect_shootout_groups(
  p_tournament_id   uuid,
  p_qualifier_count integer
)
RETURNS TABLE(start_rank integer, participant_ids uuid[])
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $$
DECLARE
  v_chain text[];
  v_n     int;
BEGIN
  SELECT tiebreaker_order INTO v_chain
    FROM public.tournaments
   WHERE id = p_tournament_id;
  IF v_chain IS NULL THEN
    RAISE EXCEPTION 'tournament not found: %', p_tournament_id
      USING ERRCODE = 'P0002';
  END IF;

  -- q<=0 or q>=N => no qualification-relevant tie possible (no cut line).
  SELECT count(*) INTO v_n
    FROM public.tournament_participants
   WHERE tournament_id = p_tournament_id
     AND registration_status = 'confirmed';

  IF p_qualifier_count <= 0 OR p_qualifier_count >= v_n THEN
    RETURN;  -- empty result set
  END IF;

  RETURN QUERY
  WITH stats AS (
    SELECT p.id AS pid,
           p.registered_at,
           coalesce(sum(
             CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                  WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                  ELSE 0 END), 0) AS total_points,
           coalesce(sum(
             CASE WHEN m.participant_a = p.id
                    THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                  WHEN m.participant_b = p.id
                    THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                  ELSE 0 END), 0) AS kubb_diff
      FROM public.tournament_participants p
      LEFT JOIN public.tournament_matches m
        ON m.tournament_id = p.tournament_id
       AND m.phase         = 'group'
       AND m.status        IN ('finalized','overridden')
       AND (m.participant_a = p.id OR m.participant_b = p.id)
     WHERE p.tournament_id      = p_tournament_id
       AND p.registration_status = 'confirmed'
     GROUP BY p.id, p.registered_at
  ),
  ranked AS (
    -- ADR-0035 / vorrunde-ranking-spec §6.2 group-phase chain. The fingerprint
    -- and the sort share the same keys (total_points, kubb_difference) so a tied
    -- run is exactly a run of equal qualifier-order rows. registered_at/pid are
    -- the deterministic ID tail, NOT a separating criterion.
    SELECT s.pid,
           s.total_points, s.kubb_diff,
           s.total_points::text || '|' || s.kubb_diff::text AS tie_fp,
           row_number() OVER (
             ORDER BY
               -s.total_points,
               -s.kubb_diff,
               s.registered_at ASC,
               s.pid ASC
           ) - 1 AS rnk0          -- zero-based rank
      FROM stats s
  ),
  marked AS (
    SELECT r.*,
           CASE WHEN lag(r.tie_fp) OVER (ORDER BY r.rnk0) IS DISTINCT FROM r.tie_fp
                THEN 1 ELSE 0 END AS is_new_run
      FROM ranked r
  ),
  runs AS (
    SELECT m.*,
           sum(m.is_new_run) OVER (ORDER BY m.rnk0) AS run_id
      FROM marked m
  ),
  grouped AS (
    SELECT run_id,
           min(rnk0)                                  AS first_rank,
           max(rnk0)                                  AS last_rank,
           count(*)                                   AS cnt,
           array_agg(pid ORDER BY rnk0)               AS pids
      FROM runs
     GROUP BY run_id
  )
  -- only runs of length >= 2 that STRADDLE the cut line.
  SELECT g.first_rank::int AS start_rank,
         g.pids            AS participant_ids
    FROM grouped g
   WHERE g.cnt > 1
     AND g.first_rank <  p_qualifier_count
     AND g.last_rank  >= p_qualifier_count
   ORDER BY g.first_rank;
END;
$$;

COMMENT ON FUNCTION public._tournament_detect_shootout_groups(uuid, integer) IS
  'Detects cut-line shoot-out groups for a flat (non-pool) group phase. '
  'ADR-0035 / vorrunde-ranking-spec §6.2: ranks and fingerprints on '
  'total_points -> kubb_difference (NO wins, NO Buchholz, NO tiebreaker_order '
  'gating). A shoot-out group is a run of >=2 rows equal on those keys that '
  'straddles the qualification line (spec §3/§7.2/§7.3). Group-phase only.';

-- ====================================================================
-- 5. public.tournament_start_ko_phase — three flat-preliminary seed CTEs.
-- ====================================================================
-- Rebased on the latest definition (20261287000000). The body is preserved
-- verbatim EXCEPT for three internal ranking CTEs, all on the same data
-- (phase = 'group', flat / no group_label):
--   * C6 default seed ranking  (`ranked.auto_seed`)
--   * SHOOTOUT-RESOLVE base order (`v_full_order`)
--   * CONSOLATION direct starters (`ranked.rnk`)
-- Each dropped the tiebreaker_order-gated total_points/wins/kubb_diff for the
-- hard-coded group-phase chain total_points -> kubb_difference -> stable seed
-- (ADR-0035 / spec §6.2). wins is gone, the v_chain gating is gone, and
-- tiebreaker_order is no longer read at all. The pool path delegates to
-- _tournament_compute_pool_cut (block 3), so it is fixed transitively.
CREATE OR REPLACE FUNCTION public.tournament_start_ko_phase(p_tournament_id uuid, p_ko_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller            uuid;
  v_creator           uuid;
  v_with_third_place  boolean;
  v_qualifier_count   int;
  v_incomplete        uuid[];
  v_ko_exists         int;
  v_has_pool_phase    boolean;
  v_seeds_jsonb       jsonb;
  v_match_count       int := 0;
  v_bye_count         int := 0;
  v_group_label       text;
  v_top_n             int;
  v_cut_result        jsonb;
  v_conflict_ids      jsonb := '[]'::jsonb;
  v_override_ids      uuid[];
  v_pool_count        int;
  v_bracket_type      text;
  v_with_reset        boolean;
  v_round             smallint;   -- PITCH-PLAN loop variable
  v_max_round         smallint;   -- ADR-0031 A1: final-round discriminator
  v_name              text;       -- GO-LIVE-NOTIFY
  v_grp               record;     -- SHOOTOUT-GATE
  v_pending_shootouts int := 0;   -- SHOOTOUT-GATE
  v_full_order        uuid[];     -- SHOOTOUT-RESOLVE
  v_so                record;     -- SHOOTOUT-RESOLVE
  v_k                 int;        -- SHOOTOUT-RESOLVE
  -- CONSOLATION (E2):
  v_cons_cfg          jsonb;      -- tournaments.consolation_bracket
  v_cons_enabled      boolean;
  v_cons_main_size    int;
  v_cons_direct_cnt   int;
  v_cons_direct_ids   jsonb := '[]'::jsonb;
  -- CF6 manual-seeding gate:
  v_seeding_mode      text;
  v_seed_override_cnt int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  -- tiebreaker_order is intentionally NOT read here: ADR-0035 removes it as a
  -- per-stage knob for the preliminary round; the seed ranking below follows
  -- the group-phase chain (points -> kubb_difference) derived from the type.
  SELECT created_by, bracket_type,
         coalesce((ko_config ->> 'with_bracket_reset')::boolean, true),
         display_name, consolation_bracket
    INTO v_creator, v_bracket_type, v_with_reset, v_name, v_cons_cfg
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_ko_config IS NULL OR jsonb_typeof(p_ko_config) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: ko_config must be a JSON object'
      USING ERRCODE = '22023';
  END IF;
  v_with_third_place := coalesce(
    (p_ko_config ->> 'with_third_place_playoff')::boolean, false);
  v_qualifier_count := coalesce((p_ko_config ->> 'qualifier_count')::int, 0);
  IF v_qualifier_count < 2 OR v_qualifier_count > 64 THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count must be in [2, 64]'
      USING ERRCODE = '22023';
  END IF;

  IF v_bracket_type = 'double_elimination' THEN
    v_with_reset := coalesce(
      (p_ko_config ->> 'with_bracket_reset')::boolean, v_with_reset);
    IF v_with_third_place THEN
      RAISE EXCEPTION 'INVALID_KO_CONFIG: with_third_place_playoff is not allowed for double_elimination'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  v_cons_enabled := coalesce((v_cons_cfg ->> 'enabled')::boolean, false)
                    AND v_bracket_type <> 'double_elimination';

  SELECT count(*) INTO v_ko_exists
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','third_place','final',
                    'wb','lb','grand_final','grand_final_reset',
                    'consolation','consolation_third_place');
  IF v_ko_exists > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: ko phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  SELECT coalesce(array_agg(id ORDER BY id), ARRAY[]::uuid[])
    INTO v_incomplete
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase = 'group'
      AND status NOT IN ('finalized','overridden','voided');
  IF array_length(v_incomplete, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'PHASE_NOT_COMPLETE: % group match(es) not terminal: %',
      array_length(v_incomplete, 1), v_incomplete
      USING ERRCODE = '22023';
  END IF;

  -- ==================================================================
  -- CF6 manual-seeding gate. SINGLE functional addition vs the
  -- 20261204000000_p6_fix_bundle baseline. When the tournament is
  -- configured for manual seeding (ko_config.seeding_mode = 'manual'),
  -- the organizer MUST set a complete seed list before the KO can
  -- start. We treat the seeding as "set" once at least
  -- `qualifier_count` overrides exist in tournament_seeding_overrides
  -- (the seeding screen writes one row per qualifier via
  -- tournament_set_seeding). For auto seeding (or a missing
  -- discriminator = default auto) no gate fires. Position: after the
  -- 40001 idempotency guard and the 22023 phase-complete guard, before
  -- the SHOOTOUT-GATE / pool detection / bracket insert, so it only
  -- fires on a legitimate Vorrunde->KO transition. The exception is
  -- machine-readable: ERRCODE 22023 + 'seeding_required' prefix, so the
  -- client can route the organizer to the seeding screen instead of
  -- showing a raw error.
  -- ==================================================================
  v_seeding_mode := coalesce(p_ko_config ->> 'seeding_mode', 'auto');
  IF v_seeding_mode = 'manual' THEN
    SELECT count(*) INTO v_seed_override_cnt
      FROM public.tournament_seeding_overrides
      WHERE tournament_id = p_tournament_id;
    IF v_seed_override_cnt < v_qualifier_count THEN
      RAISE EXCEPTION
        'seeding_required: manual seeding must be set before KO start'
        USING ERRCODE = '22023';
    END IF;
  END IF;
  -- ==================== end CF6 manual-seeding gate =================

  -- ==================================================================
  -- SHOOTOUT-GATE (P6 D2a). VERBATIM.
  -- ==================================================================
  FOR v_grp IN
    SELECT * FROM public._tournament_detect_shootout_groups(
                     p_tournament_id, v_qualifier_count)
  LOOP
    INSERT INTO public.tournament_shootouts(
        tournament_id, start_rank, tied_participant_ids)
      VALUES (p_tournament_id, v_grp.start_rank, v_grp.participant_ids)
      ON CONFLICT (tournament_id, tie_key) DO NOTHING;

    IF FOUND THEN
      PERFORM public._tournament_notify_shootout_group(
        p_tournament_id,
        v_grp.participant_ids,
        'Shoot-Out nötig',
        'Turnier "' || coalesce(v_name, '')
          || '": Gleichstand an der Qualifikations-Grenze — tragt den '
          || 'Shoot-Out-Sieger ein.',
        jsonb_build_object(
          'tournament_id', p_tournament_id,
          'kind',          'shootout',
          'start_rank',    v_grp.start_rank,
          'tied',          to_jsonb(v_grp.participant_ids)));
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.tournament_shootouts s
       WHERE s.tournament_id = p_tournament_id
         AND s.status = 'resolved'
         AND s.tied_participant_ids @> v_grp.participant_ids
         AND s.tied_participant_ids <@ v_grp.participant_ids
    ) THEN
      v_pending_shootouts := v_pending_shootouts + 1;
    END IF;
  END LOOP;

  IF v_pending_shootouts > 0 THEN
    RAISE EXCEPTION 'SHOOTOUT_PENDING: % qualification-relevant shoot-out(s) unresolved',
      v_pending_shootouts USING ERRCODE = 'P0001';
  END IF;
  -- ==================== end SHOOTOUT-GATE ===========================

  SELECT EXISTS (
    SELECT 1 FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL
  ) INTO v_has_pool_phase;

  IF v_has_pool_phase THEN
    SELECT coalesce(array_agg(participant_id), ARRAY[]::uuid[])
      INTO v_override_ids
      FROM public.tournament_seeding_overrides
     WHERE tournament_id = p_tournament_id;

    SELECT count(DISTINCT group_label) INTO v_pool_count
      FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL;
    v_top_n := greatest(1, ((v_qualifier_count + v_pool_count - 1) / v_pool_count));

    CREATE TEMP TABLE IF NOT EXISTS _tmp_pool_cuts (
      group_label text,
      rank_in_pool int,
      participant_id uuid
    ) ON COMMIT DROP;
    TRUNCATE _tmp_pool_cuts;

    FOR v_group_label IN
      SELECT DISTINCT group_label
        FROM public.tournament_participants
       WHERE tournament_id = p_tournament_id
         AND group_label IS NOT NULL
       ORDER BY 1
    LOOP
      v_cut_result := public._tournament_compute_pool_cut(
        p_tournament_id, v_group_label, v_top_n);

      IF coalesce((v_cut_result ->> 'tie_resolution_needed')::boolean, false) THEN
        v_conflict_ids := v_conflict_ids
          || coalesce(v_cut_result -> 'conflicting_participants', '[]'::jsonb);
      END IF;

      INSERT INTO _tmp_pool_cuts(group_label, rank_in_pool, participant_id)
      SELECT v_group_label,
             (ord)::int,
             (val #>> '{}')::uuid
        FROM jsonb_array_elements(v_cut_result -> 'qualifiers')
             WITH ORDINALITY AS t(val, ord);
    END LOOP;

    IF jsonb_array_length(v_conflict_ids) > 0 THEN
      SELECT coalesce(jsonb_agg(elem ORDER BY elem), '[]'::jsonb)
        INTO v_conflict_ids
        FROM (
          SELECT DISTINCT elem
            FROM jsonb_array_elements_text(v_conflict_ids) AS elem
           WHERE (elem)::uuid <> ALL (v_override_ids)
        ) sub;

      IF jsonb_array_length(v_conflict_ids) > 0 THEN
        RAISE EXCEPTION 'TIEBREAKER_NEEDS_RESOLUTION'
          USING ERRCODE = 'P0001',
                DETAIL = jsonb_build_object(
                  'conflicting_participants', v_conflict_ids)::text;
      END IF;
    END IF;

    WITH labels AS (
      SELECT group_label,
             dense_rank() OVER (ORDER BY group_label) AS label_idx
        FROM (SELECT DISTINCT group_label FROM _tmp_pool_cuts) g
    ),
    base AS (
      SELECT c.participant_id,
             (c.rank_in_pool - 1) * 1000 + l.label_idx AS interleave_seed
        FROM _tmp_pool_cuts c
        JOIN labels l USING (group_label)
    ),
    overrides AS (
      SELECT participant_id, seed_override
        FROM public.tournament_seeding_overrides
       WHERE tournament_id = p_tournament_id
    ),
    combined AS (
      SELECT b.participant_id,
             coalesce(o.seed_override::numeric,
                      b.interleave_seed::numeric + 1000000) AS effective_seed,
             b.interleave_seed
        FROM base b
        LEFT JOIN overrides o USING (participant_id)
    ),
    seeded AS (
      SELECT participant_id,
             row_number() OVER (ORDER BY effective_seed, interleave_seed) AS final_seed
        FROM combined
    )
    SELECT coalesce(jsonb_agg(to_jsonb(participant_id::text) ORDER BY final_seed), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM seeded
     WHERE final_seed <= v_qualifier_count;

  ELSE
    -- ============================================================
    -- C6: flat-preliminary (no group_label) default seed ranking. ADR-0035 /
    -- vorrunde-ranking-spec §6.2: total_points -> kubb_difference -> stable seed.
    -- No wins between points and kubb_diff, no tiebreaker_order gating; the chain
    -- follows from the group-phase type, not a per-tournament knob. This keeps
    -- the seed order identical to _tournament_detect_shootout_groups and
    -- SHOOTOUT-RESOLVE's v_full_order. registered_at/participant_id are the
    -- deterministic ID-fallback tail, not a separating criterion.
    -- ============================================================
    WITH stats AS (
      SELECT p.id AS participant_id,
             p.registered_at,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                    WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                    ELSE 0 END), 0) AS total_points,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id
                      THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                    WHEN m.participant_b = p.id
                      THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                    ELSE 0 END), 0) AS kubb_diff
        FROM public.tournament_participants p
        LEFT JOIN public.tournament_matches m
          ON m.tournament_id = p.tournament_id
         AND m.phase = 'group'
         AND m.status IN ('finalized','overridden')
         AND (m.participant_a = p.id OR m.participant_b = p.id)
       WHERE p.tournament_id = p_tournament_id
         AND p.registration_status = 'confirmed'
       GROUP BY p.id, p.registered_at
    ),
    ranked AS (
      SELECT participant_id,
             row_number() OVER (
               ORDER BY
                 -total_points,
                 -kubb_diff,
                 registered_at ASC,
                 participant_id ASC
             ) AS auto_seed
        FROM stats
    ),
    overrides AS (
      SELECT participant_id, seed_override
        FROM public.tournament_seeding_overrides
       WHERE tournament_id = p_tournament_id
    ),
    combined AS (
      SELECT r.participant_id,
             coalesce(o.seed_override::numeric,
                      r.auto_seed::numeric + 1000) AS effective_seed,
             r.auto_seed
        FROM ranked r
        LEFT JOIN overrides o USING (participant_id)
    ),
    seeded AS (
      SELECT participant_id,
             row_number() OVER (ORDER BY effective_seed, auto_seed) AS final_seed
        FROM combined
    )
    SELECT coalesce(jsonb_agg(to_jsonb(participant_id::text) ORDER BY final_seed), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM seeded
     WHERE final_seed <= v_qualifier_count;
  END IF;

  -- ==================================================================
  -- SHOOTOUT-RESOLVE (resolveWithShootouts).
  -- ==================================================================
  IF NOT v_has_pool_phase AND EXISTS (
    SELECT 1 FROM public.tournament_shootouts
     WHERE tournament_id = p_tournament_id AND status = 'resolved'
  ) THEN
    WITH stats AS (
      SELECT p.id AS pid,
             p.registered_at,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                    WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                    ELSE 0 END), 0) AS total_points,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id
                      THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                    WHEN m.participant_b = p.id
                      THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                    ELSE 0 END), 0) AS kubb_diff
        FROM public.tournament_participants p
        LEFT JOIN public.tournament_matches m
          ON m.tournament_id = p.tournament_id
         AND m.phase = 'group'
         AND m.status IN ('finalized','overridden')
         AND (m.participant_a = p.id OR m.participant_b = p.id)
       WHERE p.tournament_id = p_tournament_id
         AND p.registration_status = 'confirmed'
       GROUP BY p.id, p.registered_at
    )
    -- ADR-0035 / §6.2 group-phase chain: total_points -> kubb_difference ->
    -- stable seed. The shoot-out winners overwrite their slots below, so this
    -- base order must match the detector / default-seed order exactly.
    SELECT array_agg(pid ORDER BY rnk)
      INTO v_full_order
      FROM (
        SELECT s.pid,
               row_number() OVER (
                 ORDER BY
                   -s.total_points,
                   -s.kubb_diff,
                   s.registered_at ASC,
                   s.pid ASC
               ) AS rnk
          FROM stats s
      ) r;

    FOR v_so IN
      SELECT start_rank, ordered_winners
        FROM public.tournament_shootouts
       WHERE tournament_id = p_tournament_id
         AND status = 'resolved'
         AND ordered_winners IS NOT NULL
    LOOP
      FOR v_k IN 1 .. array_length(v_so.ordered_winners, 1) LOOP
        v_full_order[v_so.start_rank + v_k] := v_so.ordered_winners[v_k];
      END LOOP;
    END LOOP;

    SELECT coalesce(jsonb_agg(to_jsonb(pid::text) ORDER BY ord), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM (
        SELECT pid, ord
          FROM unnest(v_full_order) WITH ORDINALITY AS t(pid, ord)
         WHERE ord <= v_qualifier_count
      ) q;
  END IF;
  -- ==================== end SHOOTOUT-RESOLVE ========================

  IF jsonb_array_length(v_seeds_jsonb) < v_qualifier_count THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count % exceeds confirmed participants',
      v_qualifier_count USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET ko_config = p_ko_config
    WHERE id = p_tournament_id;

  IF v_bracket_type = 'double_elimination' THEN
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           b.round_number::smallint,
           b.bracket_position::smallint,
           b.bracket_position,
           b.participant_a,
           b.participant_b,
           b.phase,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END
      FROM public._tournament_compute_de_bracket(v_seeds_jsonb, v_with_reset) b;
  ELSE
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           b.round_number::smallint,
           b.bracket_position::smallint,
           b.bracket_position,
           b.participant_a,
           b.participant_b,
           b.phase,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END
      FROM public._tournament_compute_ko_bracket(
             v_seeds_jsonb, v_with_third_place,
             coalesce((SELECT ko_matchup FROM public.tournaments
                         WHERE id = p_tournament_id), 'seed_high_vs_low')) b;
  END IF;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  -- ==================================================================
  -- CONSOLATION-MATERIALISE (E2, ADR-0028 §1.1/§3/§4).
  -- ==================================================================
  IF v_cons_enabled THEN
    -- P6-FIX C11: honour the persisted main_bracket_size (ADR-0028 §5) when set;
    -- fall back to next_pow2(qualifier_count) (== main bracket size) otherwise.
    v_cons_main_size := coalesce((v_cons_cfg ->> 'main_bracket_size')::int, 0);
    IF v_cons_main_size < 2 THEN
      v_cons_main_size := 1;
      WHILE v_cons_main_size < v_qualifier_count LOOP
        v_cons_main_size := v_cons_main_size * 2;
      END LOOP;
    END IF;

    -- direct_count (now persisted by the wire; defensive default 0).
    v_cons_direct_cnt := greatest(0, coalesce((v_cons_cfg ->> 'direct_count')::int, 0));
    -- Direct starters: the top prelim ranks NOT already seeded into the main
    -- bracket (seeds beyond qualifier_count), best-first, capped at direct_count.
    IF v_cons_direct_cnt > 0 AND NOT v_has_pool_phase THEN
      WITH stats AS (
        SELECT p.id AS pid,
               p.registered_at,
               coalesce(sum(
                 CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                      WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                      ELSE 0 END), 0) AS total_points,
               coalesce(sum(
                 CASE WHEN m.participant_a = p.id
                        THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                      WHEN m.participant_b = p.id
                        THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                      ELSE 0 END), 0) AS kubb_diff
          FROM public.tournament_participants p
          LEFT JOIN public.tournament_matches m
            ON m.tournament_id = p.tournament_id
           AND m.phase = 'group'
           AND m.status IN ('finalized','overridden')
           AND (m.participant_a = p.id OR m.participant_b = p.id)
         WHERE p.tournament_id = p_tournament_id
           AND p.registration_status = 'confirmed'
         GROUP BY p.id, p.registered_at
      ),
      ranked AS (
        -- ADR-0035 / §6.2 group-phase chain for the consolation direct starters
        -- (the prelim ranks just below the main-bracket cut): total_points ->
        -- kubb_difference -> stable seed. Same chain as the main seed ranking.
        SELECT pid,
               row_number() OVER (
                 ORDER BY
                   -total_points,
                   -kubb_diff,
                   registered_at ASC,
                   pid ASC
               ) AS rnk
          FROM stats
      )
      SELECT coalesce(jsonb_agg(to_jsonb(pid::text) ORDER BY rnk), '[]'::jsonb)
        INTO v_cons_direct_ids
        FROM ranked
       WHERE rnk > v_qualifier_count
         AND rnk <= v_qualifier_count + v_cons_direct_cnt;
    ELSE
      v_cons_direct_ids := '[]'::jsonb;
    END IF;

    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           c.round_number::smallint,
           c.bracket_position::smallint,
           c.bracket_position,
           c.participant_a,
           c.participant_b,
           c.phase,
           CASE WHEN c.is_bye_pairing THEN 'awaiting_results' ELSE 'scheduled' END,
           CASE WHEN c.is_bye_pairing
                THEN coalesce(c.participant_a, c.participant_b) END,
           1,
           NULL
      FROM public._tournament_compute_cons_bracket(
             v_cons_main_size, v_cons_direct_ids, '[]'::jsonb) c;

    UPDATE public.tournament_matches
      SET status = 'finalized',
          finalized_at = now()
      WHERE tournament_id = p_tournament_id
        AND phase = 'consolation'
        AND winner_participant IS NOT NULL
        AND status = 'awaiting_results';

    SELECT count(*) INTO v_match_count
      FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND phase IN ('ko','third_place','final',
                      'consolation','consolation_third_place');
  END IF;

  -- ADR-0031 A1: the highest KO round_number is the final (final-round
  -- discriminator for the schedule phase below).
  SELECT max(round_number) INTO v_max_round
    FROM public.tournament_matches
   WHERE tournament_id = p_tournament_id
     AND phase IN ('ko','third_place','final',
                   'wb','lb','grand_final','grand_final_reset',
                   'consolation','consolation_third_place');

  FOR v_round IN
    SELECT DISTINCT round_number
      FROM public.tournament_matches
     WHERE tournament_id = p_tournament_id
       AND phase IN ('ko','third_place','final',
                     'wb','lb','grand_final','grand_final_reset',
                     'consolation','consolation_third_place')
     ORDER BY round_number
  LOOP
    PERFORM public._tournament_assign_pitches(p_tournament_id, v_round);

    -- ADR-0031 A1: one schedule row per KO round (phase 'final' for the last
    -- round, else 'ko'); seconds from ko_round_formats[round-1] with fallback.
    PERFORM public._tournament_upsert_round_schedule(
      p_tournament_id, NULL, v_round,
      CASE WHEN v_round = v_max_round THEN 'final' ELSE 'ko' END,
      (public._tournament_schedule_ko_seconds(
         p_tournament_id, v_round, v_round = v_max_round)).match_seconds,
      (public._tournament_schedule_ko_seconds(
         p_tournament_id, v_round, v_round = v_max_round)).break_seconds,
      (public._tournament_schedule_ko_seconds(
         p_tournament_id, v_round, v_round = v_max_round)).tiebreak_after,
      now());

    -- ADR-0031 C1 (E1): one per-pitch publish-notify per KO round, phase
    -- mirroring the schedule row ('final' for the max round, else 'ko').
    -- After pitches + the schedule row exist for this round.
    PERFORM public._tournament_notify_round_per_pitch(
      p_tournament_id, v_round,
      CASE WHEN v_round = v_max_round THEN 'final' ELSE 'ko' END,
      'round_published',
      'Runde ' || v_round || ' veröffentlicht',
      'Turnier "' || coalesce(v_name, '') || '": K.-o.-Runde ' || v_round
        || ' ist da.');
  END LOOP;

  SELECT count(*) INTO v_bye_count
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','final','wb','lb','consolation')
      AND status = 'finalized';

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'ko_phase_started',
      v_caller,
      jsonb_build_object(
        'qualifier_count',          v_qualifier_count,
        'with_third_place_playoff', v_with_third_place,
        'bracket_type',             v_bracket_type,
        'with_bracket_reset',       v_with_reset,
        'consolation_enabled',      v_cons_enabled,
        'match_count',              v_match_count,
        'bye_count',                v_bye_count,
        'pool_phase_present',       v_has_pool_phase,
        'seeds',                    v_seeds_jsonb));

  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_round',
    'Neue Runde',
    'Turnier "' || coalesce(v_name, '') || '": K.-o.-Phase — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'phase', 'ko'));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'match_count',   v_match_count,
    'bye_count',     v_bye_count,
    'pool_phase',    v_has_pool_phase,
    'bracket_type',  v_bracket_type,
    'consolation',   v_cons_enabled);
END;
$function$;

COMMENT ON FUNCTION public.tournament_start_ko_phase(uuid, jsonb) IS
  'Starts the KO phase from a finished preliminary round. ADR-0035 / '
  'vorrunde-ranking-spec §6.2: the three flat-preliminary seed rankings (default '
  'seed, shoot-out resolve order, consolation direct starters) rank '
  'total_points -> kubb_difference -> stable seed (registered_at, id) — no wins, '
  'no Buchholz, no tiebreaker_order gating. The pool path delegates the cut to '
  '_tournament_compute_pool_cut. SECURITY DEFINER.';
