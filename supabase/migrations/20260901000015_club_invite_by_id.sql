-- Club invite by user id (P5 — search-based member adding).
--
-- The club detail screen now invites members through a directory search
-- (friend_search_by_username), which yields user ids — same UX as adding a
-- team player. This adds a `club_invite(club_id, user_id)` RPC carrying the
-- full invite logic, and rewrites `club_invite_by_nickname` to resolve the
-- nickname and delegate (auth.uid() is preserved across the nested
-- SECURITY DEFINER call).

CREATE OR REPLACE FUNCTION public.club_invite(
  p_club_id         uuid,
  p_invitee_user_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_invitation uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.club_memberships m
     WHERE m.club_id = p_club_id
       AND m.user_id = v_caller
       AND m.removed_at IS NULL
       AND (m.roles && ARRAY['owner','admin']::text[])
  ) THEN
    RAISE EXCEPTION 'caller is not a club manager' USING ERRCODE = '42501';
  END IF;

  IF p_invitee_user_id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.club_memberships m
     WHERE m.club_id = p_club_id
       AND m.user_id = p_invitee_user_id
       AND m.removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'invitee already a member' USING ERRCODE = '23505';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.club_invitations i
     WHERE i.club_id = p_club_id
       AND i.invitee_user_id = p_invitee_user_id
       AND i.state = 'pending'
  ) THEN
    RAISE EXCEPTION 'INVITATION_ALREADY_PENDING' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.club_invitations(club_id, invitee_user_id, invited_by)
    VALUES (p_club_id, p_invitee_user_id, v_caller)
    RETURNING id INTO v_invitation;

  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    VALUES (
      p_invitee_user_id,
      'club_invitation',
      'Vereins-Einladung',
      'Du wurdest in einen Verein eingeladen.',
      jsonb_build_object('club_id', p_club_id, 'invitation_id', v_invitation)
    );

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_invited', v_caller,
            jsonb_build_object('invitee_user_id', p_invitee_user_id,
                               'invitation_id', v_invitation));

  RETURN v_invitation;
END;
$$;

REVOKE ALL ON FUNCTION public.club_invite(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.club_invite(uuid, uuid) TO authenticated;


-- Rewrite the nickname variant to resolve then delegate.
CREATE OR REPLACE FUNCTION public.club_invite_by_nickname(
  p_club_id  uuid,
  p_nickname text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_invitee uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_nickname IS NULL OR length(trim(p_nickname)) = 0 THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT user_id INTO v_invitee
    FROM public.user_profiles
   WHERE nickname = trim(p_nickname)::citext;

  IF v_invitee IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  RETURN public.club_invite(p_club_id, v_invitee);
END;
$$;

REVOKE ALL ON FUNCTION public.club_invite_by_nickname(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.club_invite_by_nickname(uuid, text)
  TO authenticated;
