-- Tournament feature — M3.3 pool-phase: `tournament_pool_standings` RPC.
--
-- The Flutter client (TournamentRepository.getPoolStandings, see
-- lib/features/tournament/data/tournament_repository.dart) calls this RPC
-- to render the pool-standings screen. The RPC itself was never
-- materialised — only the per-group `_tournament_compute_pool_cut`
-- helper exists (20260615000009_tournament_pool_phase.sql), which only
-- returns qualifier ids, not the full per-participant statistics the UI
-- needs. Without this function the screen surfaces a runtime PostgREST
-- 404. This migration closes that gap.
--
-- Return shape (matches the `ParticipantStats` value object in
-- packages/kubb_domain/lib/src/tournament/tiebreaker.dart and the
-- `PoolGroupStandings` envelope the repository decodes):
--
--   { "groups": [
--       { "group_label": "A",
--         "stats": [
--           { "participant_id":                  "<uuid>",
--             "total_points":                    <int>,
--             "wins":                            <int>,
--             "kubbs_scored":                    <int>,
--             "kubbs_conceded":                  <int>,
--             "opponent_ids":                    ["<uuid>", ...],
--             "opponent_total_points_lookup":    { "<uuid>": <int>, ... },
--             "head_to_head_lookup":             { "<uuid>": <int>, ... } },
--           ...
--         ] },
--       ...
--   ] }
--
-- Data sources:
--   * `tournament_participants` (group_label, registration_status)  —
--     roster + group membership written by `tournament_start_pool_phase`.
--   * `tournament_matches` filtered to (phase='group', status IN
--     ('finalized','overridden')) — round-robin matches with their
--     agreed final_score_a/_b and winner_participant.
--   * `tournament_set_score_proposals` filtered to the match's current
--     `consensus_round` — provides per-set basekubbs_knocked_by_a/_b
--     which we sum to derive kubbs_scored / kubbs_conceded. Both
--     submitter rows agree by the time the match is finalised, so we
--     pick one deterministic row per (match_id, set_number) via
--     `DISTINCT ON (submitter_user_id ASC)`.
--
-- Tiebreaker ordering:
--   `tournaments.tiebreaker_order` declares the chain (text[], default
--   ['total_points','buchholz_minus_h2h','direct_comparison','wins']).
--   This RPC implements the same three criteria the existing
--   `_tournament_compute_pool_cut` helper supports — `total_points`,
--   `wins`, `kubb_difference` — gated on chain membership, then falls
--   back to a deterministic stable tail (Buchholz desc → kubb_diff desc
--   → participant_id asc). Criteria not yet wired here
--   (`buchholz_minus_h2h`, `medianBuchholz`, `direct_comparison`,
--   `random`) currently flow through the deterministic tail; the
--   client-side `TiebreakerChain` re-sorts when richer lookups are
--   needed (see `TournamentPoolStandingsScreen`). A followup patch can
--   align the SQL order with the full chain once the corresponding
--   helper exists.

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
  v_result     jsonb;
BEGIN
  -- ---- 1. Authentication + visibility gate ---------------------------
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, tiebreaker_order
    INTO v_creator, v_chain
    FROM public.tournaments
   WHERE id = p_tournament_id;
  IF v_creator IS NULL AND v_chain IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;

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
  -- The CTE pipeline mirrors the Dart `computeStandings` accumulator in
  -- packages/kubb_domain/lib/src/tournament/standings.dart:
  --
  --   * `roster`         — confirmed participants WITH a group_label.
  --   * `agreed_sets`    — one row per (match_id, set_number) with the
  --     consensus basekubbs values; both submitter sides are identical
  --     in finalized rows, so we pick the lowest-uuid submitter
  --     deterministically.
  --   * `match_kubbs`    — per-match sums of basekubbs_knocked_by_a/_b.
  --   * `match_view`     — joins `tournament_matches` with `match_kubbs`
  --     and exposes the row twice (once from A's perspective, once
  --     from B's) so the participant-side aggregation can sum without
  --     CASE bloat.
  --   * `per_part`       — total_points / wins / kubbs_scored /
  --     kubbs_conceded plus the opponent_ids array.
  --   * `opp_lookup`     — opponent_id → opponent.total_points map.
  --   * `h2h_lookup`     — opponent_id → +1 (win) / -1 (loss) sum from
  --     this participant's perspective. Aggregated across multiple
  --     matches against the same opponent (group_label can host
  --     repeats in some configs even though the default round-robin
  --     does not).
  --   * `enriched`       — joins back `per_part` with the two lookups.
  --   * `ordered`        — chain-gated sort key per the comments above.
  --
  -- The final SELECT folds `ordered` into the `{ groups: [...] }`
  -- envelope grouped by `group_label`.

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
    -- DISTINCT ON keeps a single deterministic row per set even if
    -- both submitter rows are present (the standard case post-
    -- finalisation). `submitter_user_id ASC` is stable across the two
    -- consensus participants.
    SELECT DISTINCT ON (sp.match_id, sp.set_number)
           sp.match_id,
           sp.set_number,
           sp.basekubbs_knocked_by_a,
           sp.basekubbs_knocked_by_b
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
           coalesce(sum(s.basekubbs_knocked_by_b), 0) AS kubbs_b
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
           coalesce(k.kubbs_b, 0)       AS k_b
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
           m.k_b,
           m.k_a,
           CASE WHEN m.winner_participant = m.participant_b THEN 1
                WHEN m.winner_participant IS NULL          THEN 0
                ELSE -1 END,
           CASE WHEN m.winner_participant = m.participant_b THEN 1
                ELSE 0 END
      FROM matches m
  ),
  -- Only keep rows whose participant + opponent are both confirmed
  -- members of this tournament's pool roster (defensive — drops
  -- withdrawn/rejected ghosts).
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
           coalesce(sum(v.points_for),     0) AS total_points,
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
    -- One row per (participant, opponent_id) with the opponent's
    -- current total_points. Aggregated to a jsonb object below.
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
           -- Buchholz from this participant's perspective: sum of
           -- opponents' total_points. Used as a deterministic
           -- secondary key when the configured chain doesn't
           -- separate a tie within this RPC's supported criteria.
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
               -- Chain-gated criteria (mirrors _tournament_compute_pool_cut).
               CASE WHEN 'total_points'    = ANY(v_chain) THEN -e.total_points ELSE 0 END,
               CASE WHEN 'wins'            = ANY(v_chain) THEN -e.wins         ELSE 0 END,
               CASE WHEN 'kubb_difference' = ANY(v_chain) THEN -e.kubb_diff    ELSE 0 END,
               -- Deterministic tail. Buchholz desc gives a sensible
               -- default secondary; kubb_diff desc breaks remaining
               -- ties; participant_id asc guarantees stability.
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
  'Per-pool standings snapshot for the M3.3 pool phase. Aggregates '
  'finalized/overridden group matches into the ParticipantStats shape '
  'the client decodes (total_points, wins, kubbs_scored/conceded, '
  'opponent_ids, opponent_total_points_lookup, head_to_head_lookup) '
  'and returns one entry per group_label. Sort respects '
  'tournaments.tiebreaker_order for total_points / wins / '
  'kubb_difference and falls back to (Buchholz desc, kubb_diff desc, '
  'registered_at asc, pid asc) so the ordering is deterministic. '
  'SECURITY DEFINER; visible to organizer or any registered '
  'participant. See ADR-0019 §5.';
