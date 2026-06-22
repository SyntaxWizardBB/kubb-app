-- §5 Buchholz single source — ranking, shoot-out detector and KO cut agree.
--
-- 20261296000000 split the per-type ranking chain but left the §5 Buchholz at
-- TWO non-identical sites: tournament_stage_ranking (block 1, scoring-aware:
-- classic = set wins, ekc = final score) and _tournament_detect_shootout_groups
-- (ekc-only copy, no classic branch). Worse, tournament_start_ko_phase still
-- ranked its three flat-preliminary seed/cut CTEs by total_points -> kubb_diff
-- with NO format branch. For a flat schoch_then_ko / swiss_then_ko preliminary
-- the detector separated a point-equal pair by Buchholz (so it fired no
-- shoot-out) while the cut ordered the SAME pair by kubb_diff — the
-- kubb_diff-higher player qualified silently even though Buchholz says the
-- other one is ahead. The detector and the cut disagreed.
--
-- This migration collapses the three sites onto ONE §5 Buchholz source,
-- _tournament_schoch_buchholz, and makes the cut format-aware:
--
--   * _tournament_schoch_buchholz (new): scoring-aware total_points (classic =
--     set wins, ekc = final score), §5 Buchholz (opponent total minus the
--     head-to-head subtrahend in the points unit), bye = 16 for schoch/swiss so
--     it feeds opponents' Buchholz. Two scopes: 'stage_node' (a stage-graph
--     node, like tournament_stage_ranking) and 'flat_group' (a flat phase=group
--     preliminary, like the detector and the KO cut). The aggregation is lifted
--     verbatim from tournament_stage_ranking block 1, so the 222-assert Schoch
--     parity golden holds 1:1.
--   * tournament_stage_ranking (schoch/swiss + group_phase non-KO branch) now
--     reads total_points/buchholz from the helper; kubb_diff stays inline. Same
--     signature, same final per-type ORDER BY.
--   * _tournament_detect_shootout_groups schoch/swiss branch now reads the
--     helper instead of its own ekc-only copy — this also makes the detector
--     scoring-aware for classic Schoch (the intended convergence).
--   * tournament_start_ko_phase: the three flat seed/cut CTEs (default seed,
--     shoot-out resolve order, consolation direct starters) now branch on
--     tournaments.format. schoch_then_ko / swiss_then_ko rank
--     total_points -> Buchholz (from the helper, flat_group scope) -> stable
--     seed; every other flat format keeps total_points -> kubb_difference. The
--     straddle gate, the P0001 shoot-out gate, the ON CONFLICT seeding and the
--     consolation materialise are unchanged — only the seed sort keys move.
--
-- ADDITIVE / deploy-safe: CREATE OR REPLACE of the latest definition of each
-- function, same signatures, GRANTs re-issued. No table change, no data
-- migration. Last-writer-wins over 20261296000000.

-- ====================================================================
-- 0. public._tournament_schoch_buchholz — the single §5 Buchholz source.
-- ====================================================================
-- Returns scoring-aware total_points and §5 Buchholz per participant for a
-- preliminary phase. p_scope = 'stage_node' scopes to one stage-graph node
-- (matches on stage_node_id = p_node_id, roster = the node's participants);
-- p_scope = 'flat_group' scopes to a flat phase = 'group' preliminary (roster =
-- the confirmed participants). The schoch/swiss bye (participant_b NULL,
-- finalized, winner = a) is credited 16 in the points unit so it feeds
-- opponents' Buchholz; it only fires when the preliminary is schoch/swiss
-- (stage type for stage_node, tournaments.format for flat_group).
CREATE OR REPLACE FUNCTION public._tournament_schoch_buchholz(
  p_tournament_id uuid,
  p_scoring       text,
  p_scope         text,
  p_node_id       text DEFAULT null
)
RETURNS TABLE(participant_id uuid, total_points int, buchholz int)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
#variable_conflict use_column
DECLARE
  v_scoring  text := coalesce(p_scoring, 'ekc');
  v_byes_on  boolean;
BEGIN
  -- Bye credit applies only to schoch/swiss. Stage scope reads the node type,
  -- flat scope reads the tournament format. group_phase/pool/round_robin never
  -- generate byes, so the guard also keeps their totals bye-free.
  IF p_scope = 'stage_node' THEN
    SELECT s.type IN ('swiss', 'schoch')
      INTO v_byes_on
      FROM public.tournament_stages s
     WHERE s.tournament_id = p_tournament_id
       AND s.node_id       = p_node_id;
  ELSE
    SELECT t.format IN ('schoch', 'swiss', 'schoch_then_ko', 'swiss_then_ko')
      INTO v_byes_on
      FROM public.tournaments t
     WHERE t.id = p_tournament_id;
  END IF;
  v_byes_on := coalesce(v_byes_on, false);

  RETURN QUERY
  WITH roster AS (
    -- stage_node: the node's participants (appear in the node's matches).
    -- flat_group: the confirmed participants.
    SELECT tp.id AS pid
      FROM public.tournament_participants tp
     WHERE (p_scope = 'flat_group'
              AND tp.tournament_id = p_tournament_id
              AND tp.registration_status = 'confirmed')
        OR (p_scope = 'stage_node'
              AND tp.id IN (
                SELECT v.pid
                  FROM public.tournament_matches m
                  CROSS JOIN LATERAL (VALUES (m.participant_a), (m.participant_b)) AS v(pid)
                 WHERE m.tournament_id = p_tournament_id
                   AND m.stage_node_id = p_node_id
                   AND v.pid IS NOT NULL))
  ),
  agreed_sets AS (
    SELECT DISTINCT ON (sp.match_id, sp.set_number)
           sp.match_id,
           sp.set_number,
           sp.set_winner
      FROM public.tournament_set_score_proposals sp
      JOIN public.tournament_matches m
        ON m.id = sp.match_id
       AND sp.consensus_round = m.consensus_round
     WHERE m.tournament_id = p_tournament_id
       AND m.status IN ('finalized', 'overridden')
       AND ((p_scope = 'stage_node' AND m.stage_node_id = p_node_id)
            OR (p_scope = 'flat_group' AND m.phase = 'group'))
     ORDER BY sp.match_id, sp.set_number, sp.submitter_user_id
  ),
  match_sets AS (
    SELECT s.match_id,
           coalesce(count(*) FILTER (WHERE s.set_winner = 'A'), 0) AS sets_a,
           coalesce(count(*) FILTER (WHERE s.set_winner = 'B'), 0) AS sets_b
      FROM agreed_sets s
     GROUP BY s.match_id
  ),
  matches AS (
    SELECT m.id,
           m.participant_a,
           m.participant_b,
           coalesce(m.final_score_a, 0) AS fs_a,
           coalesce(m.final_score_b, 0) AS fs_b,
           coalesce(ms.sets_a, 0)       AS sw_a,
           coalesce(ms.sets_b, 0)       AS sw_b
      FROM public.tournament_matches m
      LEFT JOIN match_sets ms ON ms.match_id = m.id
     WHERE m.tournament_id = p_tournament_id
       AND m.status IN ('finalized', 'overridden')
       AND m.participant_a IS NOT NULL
       AND m.participant_b IS NOT NULL
       AND ((p_scope = 'stage_node' AND m.stage_node_id = p_node_id)
            OR (p_scope = 'flat_group' AND m.phase = 'group'))
  ),
  byes AS (
    SELECT m.participant_a AS pid,
           count(*)::int * 16 AS bye_points
      FROM public.tournament_matches m
     WHERE m.tournament_id = p_tournament_id
       AND m.status IN ('finalized', 'overridden')
       AND m.participant_a IS NOT NULL
       AND m.participant_b IS NULL
       AND m.winner_participant = m.participant_a
       AND v_byes_on
       AND ((p_scope = 'stage_node' AND m.stage_node_id = p_node_id)
            OR (p_scope = 'flat_group' AND m.phase = 'group'))
     GROUP BY m.participant_a
  ),
  match_view AS (
    SELECT m.participant_a AS pid, m.participant_b AS opp,
           m.fs_a AS points_for, m.fs_b AS points_against,
           m.sw_a AS set_wins,   m.sw_b AS set_wins_opp
      FROM matches m
    UNION ALL
    SELECT m.participant_b, m.participant_a,
           m.fs_b, m.fs_a, m.sw_b, m.sw_a
      FROM matches m
  ),
  scoped AS (
    SELECT v.* FROM match_view v
    JOIN roster r1 ON r1.pid = v.pid
    JOIN roster r2 ON r2.pid = v.opp
  ),
  per_part AS (
    SELECT r.pid,
           CASE WHEN v_scoring = 'classic'
                THEN coalesce(sum(v.set_wins),   0)
                ELSE coalesce(sum(v.points_for), 0)
           END
             + coalesce(max(b.bye_points), 0) AS total_points
      FROM roster r
      LEFT JOIN scoped v ON v.pid = r.pid
      LEFT JOIN byes   b ON b.pid = r.pid
     GROUP BY r.pid
  ),
  totals AS (
    SELECT pid, total_points FROM per_part
  ),
  opp_against AS (
    SELECT sc.pid,
           sum(CASE WHEN v_scoring = 'classic' THEN sc.set_wins_opp
                    ELSE sc.points_against END) AS against
      FROM scoped sc
     GROUP BY sc.pid
  )
  SELECT pp.pid,
         pp.total_points::int,
         (coalesce(
            (SELECT sum(t.total_points)
               FROM scoped sc
               JOIN totals t ON t.pid = sc.opp
              WHERE sc.pid = pp.pid),
            0)
          - coalesce(
              (SELECT oa.against FROM opp_against oa WHERE oa.pid = pp.pid),
              0))::int AS buchholz
    FROM per_part pp;
END;
$$;

REVOKE ALL ON FUNCTION public._tournament_schoch_buchholz(uuid, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._tournament_schoch_buchholz(uuid, text, text, text) TO authenticated;

COMMENT ON FUNCTION public._tournament_schoch_buchholz(uuid, text, text, text) IS
  'Single §5 Buchholz source for the Schoch/Swiss preliminary (ADR-0035 / '
  'vorrunde-ranking-spec §5). Scoring-aware total_points (classic = set wins, '
  'ekc = final score) and Buchholz (opponent total minus the head-to-head '
  'subtrahend in the points unit). p_scope = stage_node (one stage-graph node) '
  'or flat_group (a flat phase=group preliminary). schoch/swiss byes credit 16 '
  'so they feed opponents'' Buchholz. Consumed by tournament_stage_ranking, '
  '_tournament_detect_shootout_groups and tournament_start_ko_phase so ranking, '
  'shoot-out detection and the KO cut share ONE Buchholz.';

-- ====================================================================
-- 1. public.tournament_stage_ranking — consumes the helper for the §5 values.
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
    -- Non-KO path. total_points and §5 Buchholz now come from the single
    -- source _tournament_schoch_buchholz (stage_node scope); kubb_diff and the
    -- stable-seed tail (registered_at, id) stay inline. Only the final ORDER BY
    -- is split by stage type (ADR-0035):
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
             sp.basekubbs_knocked_by_b
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
             coalesce(sum(s.basekubbs_knocked_by_b), 0) as kubbs_b
      from agreed_sets s
      group by s.match_id
    ),
    matches as (
      select m.id,
             m.participant_a,
             m.participant_b,
             coalesce(k.kubbs_a, 0)       as k_a,
             coalesce(k.kubbs_b, 0)       as k_b
      from public.tournament_matches m
      left join match_kubbs k on k.match_id = m.id
      where m.tournament_id = p_tournament_id
        and m.stage_node_id = p_node_id
        and m.status in ('finalized', 'overridden')
        and m.participant_a is not null
        and m.participant_b is not null
    ),
    kubb_view as (
      select m.participant_a as pid, m.k_a as k_for, m.k_b as k_against
      from matches m
      union all
      select m.participant_b, m.k_b, m.k_a
      from matches m
    ),
    kubb_scoped as (
      select kv.* from kubb_view kv
      join roster r1 on r1.pid = kv.pid
    ),
    kubb_per_part as (
      select r.pid,
             coalesce(sum(kv.k_for),     0) as kubbs_scored,
             coalesce(sum(kv.k_against), 0) as kubbs_conceded
      from roster r
      left join kubb_scoped kv on kv.pid = r.pid
      group by r.pid
    ),
    sb as (
      select b.participant_id as pid, b.total_points, b.buchholz
      from public._tournament_schoch_buchholz(
             p_tournament_id, v_scoring, 'stage_node', p_node_id) b
    ),
    enriched as (
      select r.pid,
             r.reg,
             coalesce(sb.total_points, 0)                            as total_points,
             (kpp.kubbs_scored - kpp.kubbs_conceded)                 as kubb_diff,
             coalesce(sb.buchholz, 0)                                as buchholz
      from roster r
      left join sb            on sb.pid  = r.pid
      left join kubb_per_part kpp on kpp.pid = r.pid
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
  'Non-KO stages take scoring-aware total_points and §5 Buchholz from the single '
  'source _tournament_schoch_buchholz (stage_node scope) and compute kubb_diff '
  'inline, then ORDER BY a per-type chain (ADR-0035 / vorrunde-ranking-spec '
  '§6.2): schoch/swiss = points -> Buchholz -> stable seed (registered_at, id); '
  'group_phase/pool/round_robin = points -> kubb_difference -> stable seed, with '
  'NO Buchholz in any path. ko_elimination_round = round of the FINAL '
  'elimination (champion -> NULL). Read-only/STABLE. shootout_quali / unknown '
  '-> 0 rows.';

-- ====================================================================
-- 2. public._tournament_detect_shootout_groups — schoch/swiss reads the helper.
-- ====================================================================
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
  v_chain     text[];
  v_n         int;
  v_format    text;
  v_scoring   text;
  v_is_schoch boolean;
BEGIN
  SELECT tiebreaker_order, format, coalesce(scoring, 'ekc')
    INTO v_chain, v_format, v_scoring
    FROM public.tournaments
   WHERE id = p_tournament_id;
  IF v_chain IS NULL THEN
    RAISE EXCEPTION 'tournament not found: %', p_tournament_id
      USING ERRCODE = 'P0002';
  END IF;

  -- Preliminary type drives the tied-key (ADR-0035 / spec §2.1 vs §2.2). Only
  -- schoch/swiss rank by Buchholz; every other flat preliminary keeps the
  -- group-phase chain unchanged.
  v_is_schoch := v_format IN ('schoch_then_ko', 'swiss_then_ko');

  -- q<=0 or q>=N => no qualification-relevant tie possible (no cut line).
  SELECT count(*) INTO v_n
    FROM public.tournament_participants
   WHERE tournament_id = p_tournament_id
     AND registration_status = 'confirmed';

  IF p_qualifier_count <= 0 OR p_qualifier_count >= v_n THEN
    RETURN;  -- empty result set
  END IF;

  IF v_is_schoch THEN
    -- ================================================================
    -- Schoch / Swiss path: total_points -> §5 Buchholz (spec §2.2), both from
    -- the single source _tournament_schoch_buchholz (flat_group scope, the same
    -- aggregation tournament_stage_ranking uses). It is scoring-aware, so the
    -- detector now matches the cut for classic Schoch too. registered_at/pid
    -- come from the participants row as the deterministic ID tail.
    -- ================================================================
    RETURN QUERY
    WITH sb AS (
      SELECT b.participant_id AS pid, b.total_points, b.buchholz
        FROM public._tournament_schoch_buchholz(
               p_tournament_id, v_scoring, 'flat_group', NULL) b
    ),
    base AS (
      SELECT p.id AS pid,
             p.registered_at AS reg,
             coalesce(sb.total_points, 0) AS total_points,
             coalesce(sb.buchholz, 0)     AS buchholz
        FROM public.tournament_participants p
        LEFT JOIN sb ON sb.pid = p.id
       WHERE p.tournament_id      = p_tournament_id
         AND p.registration_status = 'confirmed'
    ),
    ranked AS (
      -- Spec §2.2 Schoch chain. tie_fp and sort share the keys
      -- (total_points, buchholz) so a tied run is a run of equal qualifier-
      -- order rows. registered_at/pid are the deterministic ID tail only.
      SELECT b.pid,
             b.total_points::text || '|' || b.buchholz::text AS tie_fp,
             row_number() OVER (
               ORDER BY
                 -b.total_points,
                 -b.buchholz,
                 b.reg ASC,
                 b.pid ASC
             ) - 1 AS rnk0          -- zero-based rank
        FROM base b
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
             min(rnk0)                    AS first_rank,
             max(rnk0)                    AS last_rank,
             count(*)                     AS cnt,
             array_agg(pid ORDER BY rnk0) AS pids
        FROM runs
       GROUP BY run_id
    )
    SELECT g.first_rank::int AS start_rank,
           g.pids            AS participant_ids
      FROM grouped g
     WHERE g.cnt > 1
       AND g.first_rank <  p_qualifier_count
       AND g.last_rank  >= p_qualifier_count
     ORDER BY g.first_rank;
    RETURN;
  END IF;

  -- ==================================================================
  -- Group-phase path (UNCHANGED from 20261296000000): total_points ->
  -- kubb_difference, NO Buchholz (spec §2.1 / §4). tie_fp and sort share
  -- the keys so a tied run matches the qualifier order (spec §7.1/§7.3).
  -- ==================================================================
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

GRANT EXECUTE ON FUNCTION public._tournament_detect_shootout_groups(uuid, integer) TO authenticated;

COMMENT ON FUNCTION public._tournament_detect_shootout_groups(uuid, integer) IS
  'Detects cut-line shoot-out groups for a flat (non-pool) preliminary. The '
  'tied-key follows the preliminary type (tournaments.format): schoch_then_ko / '
  'swiss_then_ko fingerprint and sort on total_points -> §5 Buchholz from the '
  'single source _tournament_schoch_buchholz (scoring-aware, bye=16 feeds '
  'opponents'' Buchholz); every other flat format keeps total_points -> '
  'kubb_difference with NO Buchholz (§2.1/§4). A shoot-out group is a run of >=2 '
  'rows equal on those keys that straddles the qualification line (spec §3/§7); '
  'cosmetic ties never fire.';

-- ====================================================================
-- 3. public.tournament_start_ko_phase — the three flat seed/cut CTEs are
--    format-aware: schoch/swiss rank points -> Buchholz (helper), else
--    points -> kubb_difference. Everything else (straddle gate, P0001
--    shoot-out gate, ON CONFLICT seeding, consolation materialise) verbatim.
-- ====================================================================
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
  v_format            text;       -- ADR-0035 per-type seed chain
  v_scoring           text;       -- scoring-aware §5 Buchholz
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
         display_name, consolation_bracket, format, coalesce(scoring, 'ekc')
    INTO v_creator, v_bracket_type, v_with_reset, v_name, v_cons_cfg,
         v_format, v_scoring
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
    -- C6: flat-preliminary (no group_label) default seed ranking. ADR-0035:
    -- schoch_then_ko / swiss_then_ko rank total_points -> §5 Buchholz, every
    -- other flat format total_points -> kubb_difference -> stable seed. No wins,
    -- no tiebreaker_order gating; the chain follows from the format. This keeps
    -- the seed order identical to _tournament_detect_shootout_groups and
    -- SHOOTOUT-RESOLVE's v_full_order. registered_at/participant_id are the
    -- deterministic ID-fallback tail, not a separating criterion.
    -- ============================================================
    WITH sb AS (
      -- §5 Buchholz from the single source for the schoch/swiss seed chain.
      SELECT b.participant_id AS pid, b.total_points, b.buchholz
        FROM public._tournament_schoch_buchholz(
               p_tournament_id, v_scoring, 'flat_group', NULL) b
    ),
    stats AS (
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
      -- ADR-0035 per-type seed chain. schoch_then_ko / swiss_then_ko rank
      -- total_points -> Buchholz (matching the cut-line detector); every other
      -- flat format keeps total_points -> kubb_difference. The stable-seed tail
      -- (registered_at, id) is the deterministic ID fallback either way.
      SELECT s.participant_id,
             row_number() OVER (
               ORDER BY
                 CASE WHEN v_format IN ('schoch_then_ko','swiss_then_ko')
                      THEN -coalesce(sb.total_points, 0) ELSE -s.total_points END,
                 CASE WHEN v_format IN ('schoch_then_ko','swiss_then_ko')
                      THEN -coalesce(sb.buchholz, 0)     ELSE -s.kubb_diff   END,
                 s.registered_at ASC,
                 s.participant_id ASC
             ) AS auto_seed
        FROM stats s
        LEFT JOIN sb ON sb.pid = s.participant_id
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
    WITH sb AS (
      SELECT b.participant_id AS pid, b.total_points, b.buchholz
        FROM public._tournament_schoch_buchholz(
               p_tournament_id, v_scoring, 'flat_group', NULL) b
    ),
    stats AS (
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
    -- ADR-0035 per-type base order: schoch_then_ko / swiss_then_ko rank
    -- total_points -> Buchholz, every other flat format total_points ->
    -- kubb_difference. The shoot-out winners overwrite their slots below, so
    -- this base order must match the detector / default-seed order exactly.
    SELECT array_agg(pid ORDER BY rnk)
      INTO v_full_order
      FROM (
        SELECT s.pid,
               row_number() OVER (
                 ORDER BY
                   CASE WHEN v_format IN ('schoch_then_ko','swiss_then_ko')
                        THEN -coalesce(sb.total_points, 0) ELSE -s.total_points END,
                   CASE WHEN v_format IN ('schoch_then_ko','swiss_then_ko')
                        THEN -coalesce(sb.buchholz, 0)     ELSE -s.kubb_diff   END,
                   s.registered_at ASC,
                   s.pid ASC
               ) AS rnk
          FROM stats s
          LEFT JOIN sb ON sb.pid = s.pid
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
      WITH sb AS (
        SELECT b.participant_id AS pid, b.total_points, b.buchholz
          FROM public._tournament_schoch_buchholz(
                 p_tournament_id, v_scoring, 'flat_group', NULL) b
      ),
      stats AS (
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
        -- ADR-0035 per-type chain for the consolation direct starters (the
        -- prelim ranks just below the main-bracket cut). Same chain as the main
        -- seed ranking: schoch_then_ko / swiss_then_ko -> total_points ->
        -- Buchholz, every other flat format -> total_points -> kubb_difference.
        SELECT s.pid,
               row_number() OVER (
                 ORDER BY
                   CASE WHEN v_format IN ('schoch_then_ko','swiss_then_ko')
                        THEN -coalesce(sb.total_points, 0) ELSE -s.total_points END,
                   CASE WHEN v_format IN ('schoch_then_ko','swiss_then_ko')
                        THEN -coalesce(sb.buchholz, 0)     ELSE -s.kubb_diff   END,
                   s.registered_at ASC,
                   s.pid ASC
               ) AS rnk
          FROM stats s
          LEFT JOIN sb ON sb.pid = s.pid
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
  'Starts the KO phase from a finished preliminary round. ADR-0035: the three '
  'flat-preliminary seed rankings (default seed, shoot-out resolve order, '
  'consolation direct starters) branch on tournaments.format. schoch_then_ko / '
  'swiss_then_ko rank total_points -> §5 Buchholz (from the single source '
  '_tournament_schoch_buchholz, so the cut matches the shoot-out detector); '
  'every other flat format ranks total_points -> kubb_difference. Stable seed '
  'tail (registered_at, id), no wins, no tiebreaker_order gating. The pool path '
  'delegates the cut to _tournament_compute_pool_cut. SECURITY DEFINER.';
