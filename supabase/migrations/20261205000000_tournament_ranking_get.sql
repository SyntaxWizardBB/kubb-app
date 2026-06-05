-- P8-Hub-B1 — All-time tournament ranking read RPC.
--
-- Provides the all-time leaderboards for the new Tournament-Hub
-- ranking screen, split into four buckets: Liga A, Liga B, Liga C and
-- Einzel (singles). All buckets aggregate ONLY awards of tournaments
-- with status = 'finalized' across the whole history (no season filter,
-- no league_factor).
--
-- Bucket semantics:
--   * 'A' / 'B' / 'C' : team tournaments (tournaments.team_size > 1)
--     whose tournaments.league_categories array contains the requested
--     category. A tournament tagged with both {'A','B'} therefore feeds
--     the 'A' AND the 'B' leaderboard. participant_id references a team
--     (teams.id); display_name resolves to teams.display_name.
--   * 'EINZEL'        : singles tournaments (tournaments.team_size = 1).
--     Own bucket, never double-counted with A/B/C. participant_id
--     references a user (auth.users.id); display_name resolves to
--     user_profiles.nickname.
--
-- Aggregation semantics are identical to the Dart-side
-- SeasonStandingsAggregator (packages/kubb_domain/lib/src/season/
-- season_standings.dart):
--   * total_points     = SUM(season_standings_awards.final_points)
--                        per participant_id. Reversal / negative awards
--                        reduce total_points naturally.
--   * tournament_count = COUNT(DISTINCT tournament_id) of the valid
--                        awards. A reversal targets an already counted
--                        tournament_id and therefore does NOT inflate
--                        the participation count.
--   * Sort order       = total_points DESC, tournament_count DESC,
--                        display_name ASC. rank is the dense 1-based
--                        position following this ordering.
--
-- The RPC is read-only, runs SECURITY DEFINER with a fixed
-- search_path (analog public_tournament_get / season_get), and is
-- granted to anon + authenticated: the leaderboards are public, derived
-- only from finalized (public) tournament data — no auth.uid() guard
-- (analog spectator-read ADR-0023 / ADR-0026).
--
-- Sources: docs/adr/0025-m5-season-aggregation.md, ADR-0023, ADR-0026,
-- packages/kubb_domain/lib/src/season/season_standings.dart.

CREATE OR REPLACE FUNCTION public.tournament_ranking_get(p_bucket text)
RETURNS TABLE (
  participant_id   uuid,
  display_name     text,
  total_points     numeric,
  tournament_count bigint,
  rank             bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- Defined behaviour for an invalid bucket: return an empty result set
  -- rather than raising, so the UI can render a uniform "no data" state.
  IF p_bucket IS NULL OR p_bucket NOT IN ('A', 'B', 'C', 'EINZEL') THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH valid_awards AS (
    -- Awards joined to their tournament. The bucket filter lives here:
    -- awards do not carry team_size / league_categories themselves, so
    -- visibility is derived via the tournaments join. Only finalized
    -- tournaments are ever considered.
    SELECT
      a.participant_id,
      a.tournament_id,
      a.final_points
    FROM public.season_standings_awards a
    JOIN public.tournaments t
      ON t.id = a.tournament_id
    WHERE t.status = 'finalized'
      AND (
        (p_bucket = 'EINZEL' AND t.team_size = 1)
        OR (
          p_bucket IN ('A', 'B', 'C')
          AND t.team_size > 1
          AND t.league_categories @> ARRAY[p_bucket]
        )
      )
  ),
  aggregated AS (
    SELECT
      va.participant_id,
      SUM(va.final_points)              AS total_points,
      COUNT(DISTINCT va.tournament_id)  AS tournament_count
    FROM valid_awards va
    GROUP BY va.participant_id
  ),
  named AS (
    SELECT
      ag.participant_id,
      -- For team buckets the participant_id is a team id; for the
      -- singles bucket it is a user id. Resolve the appropriate name
      -- and fall back to the raw id only if no name row exists.
      CASE
        WHEN p_bucket = 'EINZEL'
          THEN COALESCE(up.nickname::text, ag.participant_id::text)
        ELSE COALESCE(tm.display_name, ag.participant_id::text)
      END                               AS display_name,
      ag.total_points,
      ag.tournament_count
    FROM aggregated ag
    LEFT JOIN public.teams tm
      ON p_bucket IN ('A', 'B', 'C') AND tm.id = ag.participant_id
    LEFT JOIN public.user_profiles up
      ON p_bucket = 'EINZEL' AND up.user_id = ag.participant_id
  )
  SELECT
    n.participant_id,
    n.display_name,
    n.total_points,
    n.tournament_count,
    ROW_NUMBER() OVER (
      ORDER BY n.total_points DESC,
               n.tournament_count DESC,
               n.display_name ASC
    ) AS rank
  FROM named n
  ORDER BY rank;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_ranking_get(text) TO anon, authenticated;

COMMENT ON FUNCTION public.tournament_ranking_get(text) IS
  'All-time tournament leaderboard for the Tournament-Hub ranking '
  'screen. p_bucket IN (A, B, C, EINZEL); invalid bucket yields an '
  'empty set. Aggregates season_standings_awards.final_points across '
  'ALL finalized tournaments (no season filter): buckets A/B/C cover '
  'team tournaments (team_size > 1) whose league_categories contain the '
  'category; EINZEL covers singles tournaments (team_size = 1) without '
  'double-counting. total_points = SUM(final_points), tournament_count '
  '= COUNT(DISTINCT tournament_id); sort total_points DESC, '
  'tournament_count DESC, display_name ASC. Public read (anon + '
  'authenticated), analog season_get / spectator-read.';
