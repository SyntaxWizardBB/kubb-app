-- Tournament feature — CF2 / ChangeSpec K04: scoring-mode-aware standings.
--
-- Context. `tournament_pool_standings` (20260801000005) aggregates the
-- per-pool `total_points` straight from `m.final_score_a/_b`. Those columns
-- hold the EKC total (1 point per basekubb + 3 per set win + king bonus),
-- computed by `_tournament_compute_ekc` on the match row. That is correct for
-- EKC tournaments but wrong for `tournaments.scoring = 'classic'`, where only
-- the set win counts: a participant's points must be the number of sets they
-- won, NOT the EKC kubb total. The RPC never read `tournaments.scoring`.
--
-- This migration is ADDITIVE: it CREATE OR REPLACEs the function only — no
-- table change, no data migration, no in-place edit of the old migration
-- file. The EKC path is byte-for-byte unchanged (still sums final_score);
-- only the classic path is new.
--
-- Mirrors the Dart `computeStandings` CF2 change in
-- packages/kubb_domain/lib/src/tournament/standings.dart:
--   * ekc     -> total_points = sum(final_score from this participant's side)
--   * classic -> total_points = sum(sets won by this participant)
-- kubbs_scored / kubbs_conceded are still populated in both modes so the
-- kubb-difference can act as a tiebreak; in classic they do not feed
-- total_points.
--
-- Set wins are derived from `tournament_set_score_proposals.set_winner`
-- ('A' / 'B' / 'none'), reusing the same DISTINCT ON (match_id, set_number)
-- consensus row the existing kubbs aggregation already picks.

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

  -- CF2: default to EKC if the column is somehow null (defensive; the
  -- column is NOT NULL CHECK ('ekc','classic')).
  v_scoring := coalesce(v_scoring, 'ekc');

  -- Caller must be organizer OR a registered participant of the
  -- tournament. Withdrawn rows still count for visibility — they have
  -- legitimate read access to the bracket they were once in.
  SELECT EXISTS (
    SELECT 1 FROM public.tournament_participants p
     WHERE p.tournament_id = p_tournament_id
       AND p.user_id       = v_caller
  ) INTO v_is_member;

  IF v_creator IS DISTINCT FROM v_caller AND NOT v_is_member THEN
    RAISE EXCEPTION 'not authorised' USING ERRCODE = '42501';
  END IF;

  -- ---- 2. Build per-participant stats via CTE pipeline --------------
  --
  -- Identical pipeline to migration 20260801000005, with two additions
  -- for CF2:
  --   * `agreed_sets` also carries `set_winner`.
  --   * `match_kubbs` also exposes per-match set-win counts (sets_a /
  --     sets_b), and `matches` carries them through.
  --   * `match_view` exposes a `set_wins` column per side.
  --   * `per_part.total_points` chooses between the EKC final_score sum
  --     and the classic set-wins sum based on `v_scoring`.

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
    -- Side A perspective.
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
    -- Side B perspective.
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
           -- CF2: point source switches on the tournament scoring mode.
           -- EKC sums the EKC final_score; classic sums the sets won.
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
           (pp.kubbs_scored - pp.kubbs_conceded) AS kubb_diff,
           coalesce(
             (SELECT sum(t.total_points)
                FROM unnest(pp.opponent_ids) AS o(id)
                JOIN totals t ON t.pid = o.id),
             0)                              AS buchholz
      FROM per_part pp
      LEFT JOIN opp_lookup ol ON ol.pid = pp.pid
      LEFT JOIN h2h_lookup hl ON hl.pid = pp.pid
  ),
  ordered AS (
    SELECT e.*,
           row_number() OVER (
             PARTITION BY e.lbl
             ORDER BY
               CASE WHEN 'total_points'    = ANY(v_chain) THEN -e.total_points ELSE 0 END,
               CASE WHEN 'wins'            = ANY(v_chain) THEN -e.wins         ELSE 0 END,
               CASE WHEN 'kubb_difference' = ANY(v_chain) THEN -e.kubb_diff    ELSE 0 END,
               -e.buchholz,
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
  'Per-pool standings snapshot for the M3.3 pool phase. CF2/K04: '
  'total_points respects tournaments.scoring — EKC sums final_score, '
  'classic sums sets won (kubbs only act as a tiebreak). Aggregates '
  'finalized/overridden group matches into the ParticipantStats shape '
  'the client decodes and returns one entry per group_label. Sort '
  'respects tournaments.tiebreaker_order for total_points / wins / '
  'kubb_difference and falls back to (Buchholz desc, kubb_diff desc, '
  'registered_at asc, pid asc). SECURITY DEFINER; visible to organizer '
  'or any registered participant. See ADR-0019 §5.';
