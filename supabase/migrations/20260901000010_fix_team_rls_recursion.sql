-- Fix infinite recursion in team RLS.
--
-- `team_memberships_pool_read` referenced team_memberships inside its own
-- USING clause. Any read of team_memberships under RLS re-applied the policy
-- endlessly → "infinite recursion detected in policy for relation
-- team_memberships". This fired for every direct PostgREST read whose policy
-- subqueries team_memberships — notably the team_invitations read behind the
-- invitation screen — so invitations could neither be listed nor accepted
-- (the client just hit an error). SECURITY DEFINER RPCs (team_create etc.)
-- bypass RLS, which is why creating teams worked while invitations did not.
--
-- Fix: move the membership predicate into a SECURITY DEFINER helper that reads
-- team_memberships without RLS, and use it from the affected policies.

CREATE OR REPLACE FUNCTION public.is_active_team_member(
  p_team_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.team_memberships
     WHERE team_id = p_team_id
       AND user_id = p_user_id
       AND removed_at IS NULL
  );
$$;

REVOKE ALL ON FUNCTION public.is_active_team_member(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.is_active_team_member(uuid, uuid)
  TO authenticated, anon;

DROP POLICY IF EXISTS team_memberships_pool_read ON public.team_memberships;
CREATE POLICY team_memberships_pool_read
  ON public.team_memberships FOR SELECT
  USING (public.is_active_team_member(team_memberships.team_id, auth.uid()));

DROP POLICY IF EXISTS team_guest_players_pool_read ON public.team_guest_players;
CREATE POLICY team_guest_players_pool_read
  ON public.team_guest_players FOR SELECT
  USING (public.is_active_team_member(team_guest_players.team_id, auth.uid()));

DROP POLICY IF EXISTS team_invitations_invitee_or_pool_read
  ON public.team_invitations;
CREATE POLICY team_invitations_invitee_or_pool_read
  ON public.team_invitations FOR SELECT
  USING (
    invitee_user_id = auth.uid()
    OR public.is_active_team_member(team_invitations.team_id, auth.uid())
  );
