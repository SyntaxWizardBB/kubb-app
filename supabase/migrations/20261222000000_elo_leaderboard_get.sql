-- Tournament-ELO leaderboard read RPC (System 2, Phase S2d).
--
-- docs/ELO_RATINGS.md §7: a single GLOBAL leaderboard over players (never
-- teams), every player with >= 1 rated tournament game visible immediately,
-- players with < 10 games flagged as provisional (not hidden). Sort:
-- elo desc -> games desc -> nickname asc. Reads discipline='tournament'
-- only (the personal discipline is private and never leaderboarded).
--
-- SECURITY DEFINER + public grant (analog tournament_ranking_get): the
-- tournament ELO is public; no auth.uid() gate.

CREATE OR REPLACE FUNCTION public.elo_leaderboard_get(p_limit int DEFAULT 100)
RETURNS TABLE(
  rank        int,
  user_id     uuid,
  nickname    text,
  elo         int,
  games       int,
  provisional boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    (row_number() OVER (
      ORDER BY pr.elo DESC, pr.games DESC, COALESCE(up.nickname, '') ASC
    ))::int                  AS rank,
    pr.user_id,
    up.nickname,
    pr.elo,
    pr.games,
    (pr.games < 10)          AS provisional   -- provisional threshold, §3
  FROM public.player_ratings pr
  LEFT JOIN public.user_profiles up ON up.user_id = pr.user_id
  WHERE pr.discipline = 'tournament'
    AND pr.games >= 1
  ORDER BY pr.elo DESC, pr.games DESC, COALESCE(up.nickname, '') ASC
  LIMIT greatest(p_limit, 0);
$$;

GRANT EXECUTE ON FUNCTION public.elo_leaderboard_get(int) TO anon, authenticated;

COMMENT ON FUNCTION public.elo_leaderboard_get(int) IS
  'Global tournament-ELO leaderboard (players with >= 1 game). provisional = '
  'games < 10. Reads discipline=tournament only. docs/ELO_RATINGS.md §7.';
