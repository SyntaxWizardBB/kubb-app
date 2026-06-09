-- P-Ranglisten Punkt 4 — Tournament statistics read RPCs.
--
-- Four additive, read-only SECURITY DEFINER functions that power the
-- tournament-statistics screens: series overview (all editions of a
-- series), per-series placement distribution + own performance, and
-- head-to-head between two stable participant ids (teams or users),
-- including a KO-phase split and win probability.
--
-- Only tournaments with status = 'finalized' are ever considered; this
-- matches tournament_ranking_get and the public spectator-read model
-- (ADR-0023 / ADR-0026): finalized tournament data is public, so all
-- functions are granted to anon + authenticated with no auth.uid() guard.
--
-- There is no series_id / slug column on tournaments. A "series" is
-- therefore derived from a normalized display_name via
-- tournament_series_key (see below).
--
-- The STABLE participant id is COALESCE(team_id, user_id) — identical to
-- season_standings_awards.participant_id and tournament_ranking_get.
-- tournament_matches.participant_a / participant_b / winner_participant
-- reference tournament_participants.id and are mapped to the stable id
-- via a join on tournament_participants.
--
-- All functions are read-only (no INSERT/UPDATE/DELETE). Sources:
-- humanPlan/ProjectPlan.txt (MilestoneRanglisten Punkt 4),
-- 20261205000000_tournament_ranking_get.sql (conventions).

-- ---------------------------------------------------------------------------
-- 1. tournament_series_key — normalize a display_name to a stable series key.
-- ---------------------------------------------------------------------------
-- Heuristic (REFINABLE — deliberately coarse, see ProjectPlan note):
--   (a) strip a leading ordinal prefix:   '^\s*\d+\.?\s*'
--   (b) strip a trailing edition token:   UPPERCASE roman numeral OR plain
--       number at the end, '\s+([IVXLCDM]+|\d+)\s*$' (case-sensitive).
--   (c) btrim() + lower().
-- NULL input yields NULL (no error). The function references no tables and
-- is therefore genuinely IMMUTABLE / deterministic.
--
-- Note on (b): a trailing word like 'KUBB' is NOT a pure roman numeral
-- (contains 'K'/'U'/'B' beyond the roman set I/V/X/L/C/D/M), so
-- '5. Havana KUBB' -> 'havana kubb' (the trailing token is kept). Only a
-- token consisting solely of UPPERCASE roman letters (e.g. 'XVIII') is
-- stripped. The match is intentionally case-sensitive: real editions are
-- written uppercase ('II', 'XVIII'), whereas lowercase words made of roman
-- letters (e.g. 'mix', 'civil', 'lid') are common real words and must be
-- preserved ('Cup mix' -> 'cup mix', not 'cup'). REFINABLE.
CREATE OR REPLACE FUNCTION public.tournament_series_key(p_display_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, auth
AS $$
  SELECT CASE
    WHEN p_display_name IS NULL THEN NULL
    ELSE lower(btrim(
      regexp_replace(
        regexp_replace(p_display_name, '^\s*\d+\.?\s*', ''),
        '\s+([IVXLCDM]+|\d+)\s*$', ''
      )
    ))
  END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_series_key(text) TO anon, authenticated;

COMMENT ON FUNCTION public.tournament_series_key(text) IS
  'Normalize a tournament display_name to a stable series key: strip a '
  'leading ordinal prefix and a trailing roman/number edition token, then '
  'btrim + lower. NULL input -> NULL. IMMUTABLE / deterministic. The roman '
  'heuristic is deliberately coarse (REFINABLE); it only strips tokens that '
  'consist solely of UPPERCASE roman letters (e.g. XVIII, case-sensitive), so '
  'words like KUBB or lowercase mix/civil are preserved.';

-- ---------------------------------------------------------------------------
-- 2. tournament_series_list — series overview over finalized tournaments.
-- ---------------------------------------------------------------------------
-- series_label is chosen deterministically as the display_name of the most
-- recently completed edition (ORDER BY completed_at DESC NULLS LAST, then
-- display_name ASC, then id ASC as final tiebreak), so the result is fully
-- reproducible.
CREATE OR REPLACE FUNCTION public.tournament_series_list()
RETURNS TABLE (
  series_key    text,
  series_label  text,
  edition_count int
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  WITH finalized AS (
    SELECT
      t.id,
      t.display_name,
      t.completed_at,
      public.tournament_series_key(t.display_name) AS skey
    FROM public.tournaments t
    WHERE t.status = 'finalized'
  ),
  labeled AS (
    SELECT
      f.skey,
      f.display_name,
      ROW_NUMBER() OVER (
        PARTITION BY f.skey
        ORDER BY f.completed_at DESC NULLS LAST,
                 f.display_name ASC,
                 f.id ASC
      ) AS rn
    FROM finalized f
  )
  SELECT
    f.skey                          AS series_key,
    l.display_name                  AS series_label,
    COUNT(*)::int                   AS edition_count
  FROM finalized f
  JOIN labeled l
    ON l.skey = f.skey AND l.rn = 1
  GROUP BY f.skey, l.display_name
  ORDER BY series_key;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_series_list() TO anon, authenticated;

COMMENT ON FUNCTION public.tournament_series_list() IS
  'List all tournament series derived from finalized tournaments, grouped '
  'by tournament_series_key(display_name). edition_count = number of '
  'finalized editions; series_label = display_name of the most recently '
  'completed edition (deterministic tiebreak). Public read.';

-- ---------------------------------------------------------------------------
-- 3. tournament_series_stats — editions, placement distribution, own perf.
-- ---------------------------------------------------------------------------
-- Definitions (fixed here):
--   * field_size           = number of scored participants of an edition =
--                            COUNT(*) of season_standings_awards rows for the
--                            tournament_id.
--   * winner_participant_id = stable participant_id with placement = 1 for
--                            the edition (NULL if none).
--   * placement_distribution excludes NULL placements (CHECK allows NULL).
--   * participant key is OMITTED entirely when p_participant_id IS NULL.
-- Unknown series key -> { editions: [], placement_distribution: [] }.
CREATE OR REPLACE FUNCTION public.tournament_series_stats(
  p_series_key text,
  p_participant_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  WITH editions AS (
    -- All finalized editions whose normalized name matches the series key.
    SELECT
      t.id AS tournament_id,
      t.display_name,
      t.completed_at
    FROM public.tournaments t
    WHERE t.status = 'finalized'
      AND public.tournament_series_key(t.display_name) = p_series_key
  ),
  edition_rows AS (
    SELECT
      e.tournament_id,
      e.display_name,
      e.completed_at,
      (
        SELECT COUNT(*)
        FROM public.season_standings_awards a
        WHERE a.tournament_id = e.tournament_id
      )::int AS field_size,
      (
        SELECT a.participant_id
        FROM public.season_standings_awards a
        WHERE a.tournament_id = e.tournament_id
          AND a.placement = 1
        LIMIT 1
      ) AS winner_participant_id
    FROM editions e
  ),
  dist AS (
    SELECT a.placement, COUNT(*)::int AS cnt
    FROM public.season_standings_awards a
    JOIN editions e ON e.tournament_id = a.tournament_id
    WHERE a.placement IS NOT NULL
    GROUP BY a.placement
  ),
  part_rows AS (
    SELECT
      a.tournament_id,
      a.placement,
      e.completed_at
    FROM public.season_standings_awards a
    JOIN editions e ON e.tournament_id = a.tournament_id
    WHERE p_participant_id IS NOT NULL
      AND a.participant_id = p_participant_id
      AND a.placement IS NOT NULL
  )
  SELECT
    jsonb_build_object(
      'editions',
      COALESCE((
        SELECT jsonb_agg(
                 jsonb_build_object(
                   'tournament_id', er.tournament_id,
                   'display_name', er.display_name,
                   'completed_at', er.completed_at,
                   'field_size', er.field_size,
                   'winner_participant_id', er.winner_participant_id
                 )
                 ORDER BY er.completed_at ASC NULLS LAST, er.tournament_id ASC
               )
        FROM edition_rows er
      ), '[]'::jsonb),
      'placement_distribution',
      COALESCE((
        SELECT jsonb_agg(
                 jsonb_build_object('placement', d.placement, 'count', d.cnt)
                 ORDER BY d.placement ASC
               )
        FROM dist d
      ), '[]'::jsonb)
    )
    || CASE
         WHEN p_participant_id IS NULL THEN '{}'::jsonb
         ELSE jsonb_build_object(
           'participant',
           jsonb_build_object(
             'placements',
             COALESCE((
               SELECT jsonb_agg(
                        jsonb_build_object(
                          'tournament_id', pr.tournament_id,
                          'placement', pr.placement
                        )
                        ORDER BY pr.completed_at ASC NULLS LAST,
                                 pr.tournament_id ASC
                      )
               FROM part_rows pr
             ), '[]'::jsonb),
             'best_placement', (SELECT MIN(pr.placement) FROM part_rows pr),
             'avg_placement',  (SELECT AVG(pr.placement) FROM part_rows pr),
             'editions_played', (SELECT COUNT(*)::int FROM part_rows pr)
           )
         )
       END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_series_stats(text, uuid) TO anon, authenticated;

COMMENT ON FUNCTION public.tournament_series_stats(text, uuid) IS
  'Statistics for one tournament series (key from tournament_series_key) '
  'over finalized editions: editions (tournament_id, display_name, '
  'completed_at, field_size = #scored participants, winner_participant_id = '
  'stable id with placement 1) and placement_distribution ({placement, '
  'count}, NULL placements excluded). When p_participant_id is given, adds a '
  'participant key (placements, best_placement=MIN, avg_placement=AVG, '
  'editions_played); omitted entirely otherwise. Unknown key -> empty arrays. '
  'Public read.';

-- ---------------------------------------------------------------------------
-- 4. tournament_head_to_head — direct encounters between two stable ids.
-- ---------------------------------------------------------------------------
-- Maps tournament_matches.participant_a / participant_b to the stable id
-- COALESCE(team_id, user_id) via tournament_participants and counts matches
-- whose two resolved sides are exactly {p_a, p_b} (any order). Only
-- finalized tournaments and matches with a winner set are counted. KO =
-- phase in the bracket-phase set (group excluded). a_win_rate = a_wins /
-- total_matches as numeric, 0 when there are no matches. DISTINCT on
-- match.id prevents double counting from the two participant joins.
CREATE OR REPLACE FUNCTION public.tournament_head_to_head(
  p_a uuid,
  p_b uuid
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, auth
AS $$
  WITH resolved AS (
    -- Resolve a/b to stable ids and keep only matches whose unordered pair
    -- equals {p_a, p_b}; require a finalized tournament and a winner set.
    -- Joining tournament_participants pw (not LEFT) is safe because the
    -- winner_participant IS NOT NULL filter is implied by the inner join.
    SELECT
      m.id,
      m.phase,
      COALESCE(pw.team_id, pw.user_id) AS winner_stable_id,
      (m.phase IN ('ko','final','wb','lb','grand_final','grand_final_reset',
                   'consolation','consolation_third_place','third_place'))
        AS is_ko
    FROM public.tournament_matches m
    JOIN public.tournaments t
      ON t.id = m.tournament_id AND t.status = 'finalized'
    JOIN public.tournament_participants pa
      ON pa.id = m.participant_a
    JOIN public.tournament_participants pb
      ON pb.id = m.participant_b
    JOIN public.tournament_participants pw
      ON pw.id = m.winner_participant
    WHERE p_a IS NOT NULL
      AND p_b IS NOT NULL
      AND (
        (COALESCE(pa.team_id, pa.user_id) = p_a
           AND COALESCE(pb.team_id, pb.user_id) = p_b)
        OR (COALESCE(pa.team_id, pa.user_id) = p_b
           AND COALESCE(pb.team_id, pb.user_id) = p_a)
      )
  ),
  deduped AS (
    SELECT DISTINCT id, phase, winner_stable_id, is_ko FROM resolved
  ),
  agg AS (
    SELECT
      COUNT(*)::int AS total_matches,
      COUNT(*) FILTER (WHERE winner_stable_id = p_a)::int AS a_wins,
      COUNT(*) FILTER (WHERE winner_stable_id = p_b)::int AS b_wins,
      COUNT(*) FILTER (WHERE is_ko)::int AS ko_matches,
      COUNT(*) FILTER (WHERE is_ko AND winner_stable_id = p_a)::int AS ko_a_wins,
      COUNT(*) FILTER (WHERE is_ko AND winner_stable_id = p_b)::int AS ko_b_wins
    FROM deduped
  )
  SELECT jsonb_build_object(
    'total_matches', agg.total_matches,
    'a_wins', agg.a_wins,
    'b_wins', agg.b_wins,
    'ko_matches', agg.ko_matches,
    'ko_a_wins', agg.ko_a_wins,
    'ko_b_wins', agg.ko_b_wins,
    'a_win_rate', CASE
      WHEN agg.total_matches = 0 THEN 0::numeric
      ELSE round(agg.a_wins::numeric / agg.total_matches::numeric, 4)
    END
  )
  FROM agg;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_head_to_head(uuid, uuid) TO anon, authenticated;

COMMENT ON FUNCTION public.tournament_head_to_head(uuid, uuid) IS
  'Head-to-head between two STABLE participant ids (COALESCE(team_id, '
  'user_id)) across ALL finalized tournaments. Maps tournament_matches '
  'participant_a/b/winner via tournament_participants; counts matches whose '
  'resolved pair is {p_a,p_b}, with a winner set. Returns total_matches, '
  'a_wins, b_wins, ko_matches, ko_a_wins, ko_b_wins (KO = bracket phases, '
  'group excluded) and a_win_rate (numeric, 0 when no matches). NULL/unknown '
  'ids yield a zero result. Public read.';
