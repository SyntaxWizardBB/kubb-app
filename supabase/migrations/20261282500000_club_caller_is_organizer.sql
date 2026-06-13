-- P4-S (docs/plans/permissions-organizer-teams PLAN, ADR-0032):
-- organizer gate helper for the home screen organizer tile (P4-C).
--
-- club_caller_is_organizer() returns true exactly when the caller either
--   (a) holds the global user_profiles.can_found_clubs flag (early-access
--       organizer code), or
--   (b) has at least one ACTIVE club membership (removed_at IS NULL, same
--       activity pattern as is_active_club_member) whose roles array
--       overlaps ARRAY['owner','admin','referee'] (the consolidated role
--       set from P1, && operator).
--
-- Pattern follows is_active_club_member (20260901000012_club_schema.sql):
-- SECURITY DEFINER so it reads user_profiles / club_memberships without
-- re-triggering RLS, STABLE, pinned search_path. auth.uid()-based — no
-- parameters; callable by authenticated users only.

CREATE FUNCTION public.club_caller_is_organizer()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles
     WHERE user_id = auth.uid()
       AND can_found_clubs = true
  )
  OR EXISTS (
    SELECT 1 FROM public.club_memberships
     WHERE user_id = auth.uid()
       AND removed_at IS NULL
       AND roles && ARRAY['owner','admin','referee']::text[]
  );
$$;

COMMENT ON FUNCTION public.club_caller_is_organizer() IS
  'True when the caller may act as an organizer: user_profiles.can_found_clubs '
  'or an active club membership with a role overlapping {owner,admin,referee}. '
  'P4-S of the organizer-teams plan (ADR-0032).';

REVOKE ALL ON FUNCTION public.club_caller_is_organizer() FROM public;
GRANT EXECUTE ON FUNCTION public.club_caller_is_organizer()
  TO authenticated;
