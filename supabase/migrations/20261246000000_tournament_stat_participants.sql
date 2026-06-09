-- P-Ranglisten Punkt 4 — participant directory for the statistics screens.
--
-- The head-to-head statistic (20261245000000_tournament_statistics.sql)
-- compares two STABLE participant ids (COALESCE(team_id, user_id)). To
-- let the UI pick those two sides it needs a self-contained, read-only
-- directory of participants who actually took part in a finalized
-- tournament — deliberately NOT the friend graph (friend_search_by_username
-- excludes the caller and is relationship-scoped), because statistics are
-- public and any two participants must be comparable.
--
-- One row per distinct stable participant id over status='finalized'
-- tournaments, with a resolved display_name and an is_team flag so the UI
-- can show the right avatar/label. Optional case-insensitive substring
-- filter on the name. Mirrors the public spectator-read model (ADR-0023 /
-- ADR-0026): SECURITY DEFINER, granted to anon + authenticated.

CREATE OR REPLACE FUNCTION public.tournament_stat_participants(
  p_query text DEFAULT NULL,
  p_limit int DEFAULT 30
)
RETURNS TABLE (
  participant_id uuid,
  display_name   text,
  is_team        boolean,
  editions       int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  WITH parts AS (
    -- Every participant of a finalized tournament, reduced to its stable id.
    SELECT
      COALESCE(p.team_id, p.user_id) AS pid,
      (p.team_id IS NOT NULL)        AS is_team,
      p.tournament_id
    FROM public.tournament_participants p
    JOIN public.tournaments t
      ON t.id = p.tournament_id AND t.status = 'finalized'
    WHERE COALESCE(p.team_id, p.user_id) IS NOT NULL
  ),
  agg AS (
    SELECT
      pid,
      bool_or(is_team)                       AS is_team,
      COUNT(DISTINCT tournament_id)::int     AS editions
    FROM parts
    GROUP BY pid
  ),
  named AS (
    SELECT
      a.pid AS participant_id,
      COALESCE(tm.display_name, up.nickname, a.pid::text) AS display_name,
      a.is_team,
      a.editions
    FROM agg a
    LEFT JOIN public.teams tm         ON a.is_team     AND tm.id = a.pid
    LEFT JOIN public.user_profiles up ON NOT a.is_team AND up.user_id = a.pid
  )
  SELECT participant_id, display_name, is_team, editions
  FROM named
  WHERE p_query IS NULL
     OR btrim(p_query) = ''
     OR display_name ILIKE '%' || btrim(p_query) || '%'
  ORDER BY editions DESC, display_name ASC, participant_id ASC
  LIMIT greatest(p_limit, 0);
$$;

GRANT EXECUTE ON FUNCTION public.tournament_stat_participants(text, int)
  TO anon, authenticated;

COMMENT ON FUNCTION public.tournament_stat_participants(text, int) IS
  'Directory of STABLE participant ids (COALESCE(team_id, user_id)) that '
  'took part in any finalized tournament, for the head-to-head stat picker. '
  'Resolves display_name (team display_name or user nickname) and an '
  'is_team flag; editions = #finalized tournaments the participant played. '
  'Optional case-insensitive substring filter on the name. Public read.';
