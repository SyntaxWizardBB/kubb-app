-- W4-T18 (Wave 4c) — cross-tournament check-in target search.
--
-- Adds tournament_search_checkin_targets(p_query text): a fuzzy name search
-- across the participants of every tournament the caller may administer AND
-- that is currently in the on-site check-in phase. It feeds the cross-tournament
-- check-in screen (spec §7 / §9.6): one helper at the gate searches a team or
-- player by name, sees which tournament they registered for, and checks them in
-- via the existing tournament_checkin_participant RPC.
--
-- Scope (spec §7 / §11 "Cross-Check-in Scope geklärt"):
--   * caller-administered: public.tournament_caller_can_administer(t.id) — the
--     same live-intervention gate the check-in RPC sits behind (the deprecated
--     tournament_caller_can_manage is now an alias of it, gate split
--     20261281000000). A foreign / non-manager caller therefore gets nothing.
--   * public.tournaments.public = true.
--   * status in the check-in window: registration_open / registration_closed /
--     live — exactly the window in which tournament_checkin_participant accepts
--     a check-in (20261265000000), so every hit is actually checkable.
--
-- A participant is either a single player (user_id -> user_profiles.nickname)
-- or a team (team_id -> teams.display_name); the searchable name is the same
-- COALESCE(up.nickname, tm.display_name) the tournament_get projection uses
-- (20261266000000). Only confirmed participants are searched (the only ones a
-- check-in can target).
--
-- Fuzzy match: case-insensitive substring via pg_trgm. We add the extension
-- (idempotent) and two GIN trigram indexes on the name columns so the ILIKE
-- '%query%' predicate is index-backed at scale.
--
-- ============================ DEPENDENCIES ============================
--   * public.tournament_caller_can_administer(uuid) (20261281000000) — gate.
--   * public.tournaments(public, status, display_name) (20260525000001 /
--     20260701000002) — scope + projected name.
--   * public.tournament_participants(user_id, team_id, registration_status)
--     (20260525000001 / 20260615000005) — search subjects.
--   * public.user_profiles(user_id, nickname), public.teams(id, display_name)
--     — name sources.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Trigram indexes on the two name columns the search reads. GIN + gin_trgm_ops
-- backs the case-insensitive substring (ILIKE) predicate. IF NOT EXISTS keeps
-- the migration idempotent and avoids clashing with any future name index.
CREATE INDEX IF NOT EXISTS user_profiles_nickname_trgm_idx
  ON public.user_profiles USING gin (nickname gin_trgm_ops);
CREATE INDEX IF NOT EXISTS teams_display_name_trgm_idx
  ON public.teams USING gin (display_name gin_trgm_ops);


CREATE OR REPLACE FUNCTION public.tournament_search_checkin_targets(
  p_query text
)
RETURNS SETOF jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT jsonb_build_object(
           'participant_id',   p.id,
           'display_name',     COALESCE(up.nickname, tm.display_name),
           'tournament_id',    t.id,
           'tournament_name',  t.display_name,
           'checked_in_at',    p.checked_in_at
         )
    FROM public.tournament_participants p
    JOIN public.tournaments t ON t.id = p.tournament_id
    LEFT JOIN public.user_profiles up ON up.user_id = p.user_id
    LEFT JOIN public.teams         tm ON tm.id      = p.team_id
   WHERE auth.uid() IS NOT NULL
     AND p.registration_status = 'confirmed'
     AND t.public = true
     AND t.status IN ('registration_open','registration_closed','live')
     AND public.tournament_caller_can_administer(t.id)
     AND COALESCE(up.nickname, tm.display_name, '') ILIKE '%' || COALESCE(p_query, '') || '%'
   ORDER BY COALESCE(up.nickname, tm.display_name), t.display_name
   LIMIT 50;
$$;

REVOKE ALL ON FUNCTION public.tournament_search_checkin_targets(text)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tournament_search_checkin_targets(text)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_search_checkin_targets(text) IS
  'Cross-tournament check-in target search (spec §7 / §9.6). Fuzzy '
  '(case-insensitive substring, pg_trgm) name search over confirmed '
  'participants of the caller-administered, public tournaments currently in '
  'the check-in window (registration_open|registration_closed|live). Returns '
  'jsonb hits {participant_id, display_name, tournament_id, tournament_name, '
  'checked_in_at}. Gated via tournament_caller_can_administer — a non-manager '
  'gets nothing. Feeds the cross-checkin screen; the actual check-in goes '
  'through tournament_checkin_participant. See '
  '20261320000000_tournament_search_checkin_targets.sql.';
