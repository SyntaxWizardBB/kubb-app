-- Add a real (DB-resolved) player to a team directly as a guest-role member.
--
-- Guests are selected from the player directory (same search as friends) — no
-- more free-text placeholder names. A guest joins immediately (no invitation):
-- they carry no permissions (cannot administer the team or register it for
-- tournaments, enforced by the role guard + trigger) and can be picked into a
-- roster. Members, by contrast, keep going through team_invite (admin role on
-- accept).
--
-- Admin-only. Errors: NOT_ADMIN (caller not an admin member),
-- ALREADY_MEMBER (target already in the active pool).

CREATE OR REPLACE FUNCTION public.team_add_guest_member(
  p_team_id        uuid,
  p_member_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.team_memberships
     WHERE team_id = p_team_id AND user_id = v_caller
       AND removed_at IS NULL AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'NOT_ADMIN' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.team_memberships
     WHERE team_id = p_team_id AND user_id = p_member_user_id
       AND removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'ALREADY_MEMBER' USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.team_memberships(team_id, user_id, role)
    VALUES (p_team_id, p_member_user_id, 'guest');
END;
$$;

REVOKE ALL ON FUNCTION public.team_add_guest_member(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.team_add_guest_member(uuid, uuid)
  TO authenticated;
