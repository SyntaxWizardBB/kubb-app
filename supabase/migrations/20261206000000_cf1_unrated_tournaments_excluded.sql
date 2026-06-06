-- CF1 (Wizard-Rework comment K02) — unrated "Spasstournier" tournaments
-- must never produce or appear in any ranking / season points surface.
--
-- Background: the wizard marks a tournament as wertungsfrei
-- ("Spasstournier – ohne Wertung") by leaving tournaments.club_id NULL;
-- such a tournament also always carries an empty league_categories array
-- (the Dart draft, tournament_config_draft.dart, emits
-- league_categories = '{}' whenever club_id is null). The single,
-- canonical "rated" criterion therefore is:
--
--     a tournament is RATED  <=>  tournaments.club_id IS NOT NULL
--
-- This migration is purely additive (CREATE OR REPLACE only, no schema
-- edits, no destructive ops) and applies the rated criterion at ONE
-- place — the SQL helper public.tournament_is_rated(uuid) — which is then
-- reused by:
--   (1) the season standings view  public.v_season_standings, and
--   (2) the all-time ranking RPC    public.tournament_ranking_get(text),
--       covering buckets A / B / C and the EINZEL (singles) bucket.
--
-- Bucket-by-bucket reasoning:
--   * A / B / C : already filter league_categories @> ARRAY[bucket]. A
--                 Spasstournier has an empty league_categories array, so
--                 it can never match — it is already excluded. The
--                 rated() guard is added anyway so the criterion is
--                 expressed identically in every bucket (defence in
--                 depth; survives any future change that would let an
--                 unrated tournament carry categories).
--   * EINZEL    : previously filtered ONLY team_size = 1 + status =
--                 'finalized'. THIS WAS THE GAP — a team_size = 1
--                 Spasstournier (club_id NULL) would have counted in the
--                 singles leaderboard. The rated() guard closes it.
--
-- season_get(p_season_id) reads through v_season_standings, so guarding
-- the view also fixes the season-standings surface without touching the
-- RPC itself. (A Spasstournier could only ever reach a season via an
-- explicit league_admin season_tournaments link; the view guard makes
-- the exclusion unconditional regardless.)
--
-- The award-creation path is NOT changed here: awards are written by the
-- league-admin INSERT path on season_standings_awards, which is only ever
-- driven for rated/league tournaments. Excluding unrated tournaments at
-- the read/aggregation layer is the authoritative, single-source guard;
-- even if a stray unrated award were ever inserted, it can no longer
-- surface in any of the three weightings.


-- ---- 1. Canonical "rated" criterion (single source of truth) ---------

CREATE OR REPLACE FUNCTION public.tournament_is_rated(p_tournament_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  -- A tournament is rated (league-/ranking-relevant) exactly when it has
  -- an organizing club. "Spasstournier – ohne Wertung" leaves club_id
  -- NULL and is therefore never rated. league_categories is intentionally
  -- NOT part of the criterion: the EINZEL bucket has no categories yet is
  -- still rated whenever a club is present.
  SELECT EXISTS (
    SELECT 1
      FROM public.tournaments t
     WHERE t.id = p_tournament_id
       AND t.club_id IS NOT NULL
  );
$$;

GRANT EXECUTE ON FUNCTION public.tournament_is_rated(uuid) TO anon, authenticated;

COMMENT ON FUNCTION public.tournament_is_rated(uuid) IS
  'CF1 single-source rated criterion: TRUE iff tournaments.club_id IS '
  'NOT NULL. Unrated "Spasstournier – ohne Wertung" (club_id NULL) is '
  'excluded from all points / ranking / season weightings.';


-- ---- 2. Season standings view — exclude unrated tournaments ----------
--
-- Identical aggregation to migration 20260801000002, with one added
-- WHERE clause that drops awards belonging to unrated tournaments.

CREATE OR REPLACE VIEW public.v_season_standings AS
SELECT
  season_id,
  league_id,
  participant_id,
  SUM(final_points)              AS total_points,
  COUNT(DISTINCT tournament_id)  AS tournament_count
FROM public.season_standings_awards a
WHERE public.tournament_is_rated(a.tournament_id)
GROUP BY 1, 2, 3;

COMMENT ON VIEW public.v_season_standings IS
  'Public-readable season standings aggregate. Visibility is gated '
  'through the underlying season_standings_awards RLS (status IN '
  '(open, closed)). CF1: awards of unrated tournaments '
  '(tournament_is_rated = false) are excluded.';


-- ---- 3. All-time ranking RPC — exclude unrated in EVERY bucket -------
--
-- Signature unchanged. Only the valid_awards CTE gains the rated() guard;
-- everything else (aggregation, naming, sort, grants) is preserved
-- verbatim from migration 20261205000000.

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
    --
    -- CF1: every bucket additionally requires the tournament to be rated
    -- (public.tournament_is_rated -> club_id IS NOT NULL). For A/B/C this
    -- is already implied by the non-empty league_categories match, but is
    -- stated explicitly for a uniform, future-proof criterion. For EINZEL
    -- it is the substantive guard that keeps unrated singles
    -- "Spasstournier" tournaments out of the leaderboard.
    SELECT
      a.participant_id,
      a.tournament_id,
      a.final_points
    FROM public.season_standings_awards a
    JOIN public.tournaments t
      ON t.id = a.tournament_id
    WHERE t.status = 'finalized'
      AND public.tournament_is_rated(t.id)
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
  'double-counting. CF1: every bucket excludes unrated tournaments '
  '(tournament_is_rated = false / club_id IS NULL). total_points = '
  'SUM(final_points), tournament_count = COUNT(DISTINCT tournament_id); '
  'sort total_points DESC, tournament_count DESC, display_name ASC. '
  'Public read (anon + authenticated), analog season_get / '
  'spectator-read.';
