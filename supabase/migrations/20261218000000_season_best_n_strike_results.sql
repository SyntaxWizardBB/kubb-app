-- Season best-N (Streichresultate), System 1 — Phase C.
--
-- docs/SKV_TOUR_POINTS.md §7: the season ranking counts only the best N
-- tournament results per participant ("Streichresultate"). This adds the
-- per-season N as seasons.counting_results (NULL = count all, no striking)
-- and rewrites the aggregation view v_season_standings to sum only the
-- top-N net-per-tournament results.
--
-- Net-per-tournament first (so an append-only reversal award — a negative
-- final_points row targeting an already-counted tournament, ADR-0025 — nets
-- against its tournament before ranking), then rank tournaments by net points
-- desc and keep the best N (or all when counting_results IS NULL).

ALTER TABLE public.seasons
  ADD COLUMN IF NOT EXISTS counting_results int
    CHECK (counting_results IS NULL OR counting_results >= 1);

COMMENT ON COLUMN public.seasons.counting_results IS
  'Best-N strike-results: number of best tournament results counted per '
  'participant in the season ranking. NULL = count all (no striking). '
  'docs/SKV_TOUR_POINTS.md §7.';

CREATE OR REPLACE VIEW public.v_season_standings AS
WITH per_tournament AS (
  -- Net points per (participant, tournament) so reversals net out first.
  SELECT
    season_id,
    league_id,
    participant_id,
    tournament_id,
    SUM(final_points) AS net_points
  FROM public.season_standings_awards
  GROUP BY 1, 2, 3, 4
),
ranked AS (
  SELECT
    pt.*,
    row_number() OVER (
      PARTITION BY pt.season_id, pt.league_id, pt.participant_id
      ORDER BY pt.net_points DESC, pt.tournament_id
    ) AS rn
  FROM per_tournament pt
)
SELECT
  r.season_id,
  r.league_id,
  r.participant_id,
  SUM(r.net_points)  AS total_points,
  COUNT(*)           AS tournament_count
FROM ranked r
JOIN public.seasons s ON s.id = r.season_id
WHERE s.counting_results IS NULL
   OR r.rn <= s.counting_results
GROUP BY 1, 2, 3;
