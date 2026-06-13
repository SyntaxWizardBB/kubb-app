-- P7 follow-up: the organizer-team inbox subjects/bodies still said "Verein".
-- Rename the three remaining German strings to "Veranstalterteam".
-- CREATE OR REPLACE on the current (post-rename) bodies; ONLY the user-facing
-- strings change — every table/role/identifier reference is verbatim.

CREATE OR REPLACE FUNCTION public.organizer_team_invite(
  p_club_id uuid, p_invitee_user_id uuid, p_role text DEFAULT 'admin'::text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
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
    SELECT 1 FROM public.team_members m
     WHERE m.organizer_team_id = p_club_id AND m.user_id = v_caller
       AND m.removed_at IS NULL AND (m.roles && ARRAY['owner','admin']::text[])
  ) THEN
    RAISE EXCEPTION 'caller is not a club manager' USING ERRCODE = '42501';
  END IF;
  IF p_invitee_user_id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;
  IF p_role IS NULL OR p_role NOT IN ('owner','admin','referee') THEN
    RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.team_members m
     WHERE m.organizer_team_id = p_club_id AND m.user_id = p_invitee_user_id
       AND m.removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'invitee already a member' USING ERRCODE = '23505';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.club_invitations i
     WHERE i.club_id = p_club_id AND i.invitee_user_id = p_invitee_user_id
       AND i.state = 'pending'
  ) THEN
    RAISE EXCEPTION 'INVITATION_ALREADY_PENDING' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.club_invitations(club_id, invitee_user_id, invited_by, role)
    VALUES (p_club_id, p_invitee_user_id, v_caller, p_role)
    RETURNING id INTO v_invitation;

  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    VALUES (
      p_invitee_user_id,
      'club_invitation',
      'Veranstalterteam-Einladung',
      'Du wurdest in ein Veranstalterteam eingeladen.',
      jsonb_build_object('organizer_team_id', p_club_id, 'invitation_id', v_invitation,
                         'role', p_role)
    );

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_invited', v_caller,
            jsonb_build_object('invitee_user_id', p_invitee_user_id,
                               'invitation_id', v_invitation));
  RETURN v_invitation;
END;
$$;

CREATE OR REPLACE FUNCTION public.organizer_team_remove_member(
  p_club_id uuid, p_member_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_is_owner     boolean;
  v_other_owners int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_organizer_team_manager(p_club_id, v_caller) THEN
    RAISE EXCEPTION 'caller is not a club manager' USING ERRCODE = '42501';
  END IF;
  IF p_member_user_id = v_caller THEN
    RAISE EXCEPTION 'USE_LEAVE' USING ERRCODE = 'P0001';
  END IF;

  SELECT (roles && ARRAY['owner']::text[]) INTO v_is_owner
    FROM public.team_members
   WHERE organizer_team_id = p_club_id AND user_id = p_member_user_id
     AND removed_at IS NULL;
  IF v_is_owner IS NULL THEN
    RAISE EXCEPTION 'member not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_is_owner THEN
    SELECT count(*) INTO v_other_owners
      FROM public.team_members
     WHERE organizer_team_id = p_club_id AND removed_at IS NULL
       AND user_id <> p_member_user_id AND (roles && ARRAY['owner']::text[]);
    IF v_other_owners = 0 THEN
      RAISE EXCEPTION 'LAST_OWNER' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.team_members
     SET removed_at = now(), removed_by = v_caller
   WHERE organizer_team_id = p_club_id AND user_id = p_member_user_id
     AND removed_at IS NULL;

  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    VALUES (p_member_user_id, 'club_member_removed', 'Veranstalterteam-Mitgliedschaft beendet',
            'Du wurdest aus einem Veranstalterteam entfernt.',
            jsonb_build_object('organizer_team_id', p_club_id));

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_removed', v_caller,
            jsonb_build_object('member_user_id', p_member_user_id));
END;
$$;

CREATE OR REPLACE FUNCTION public.organizer_team_request_join(p_club_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth
AS $$
DECLARE
  v_caller  uuid;
  v_request uuid;
  v_name    text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.team_members
     WHERE organizer_team_id = p_club_id AND user_id = v_caller AND removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'ALREADY_MEMBER' USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.club_join_requests
     WHERE club_id = p_club_id AND user_id = v_caller AND state = 'pending'
  ) THEN
    RAISE EXCEPTION 'REQUEST_ALREADY_PENDING' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.club_join_requests(club_id, user_id)
    VALUES (p_club_id, v_caller)
    RETURNING id INTO v_request;

  SELECT nickname INTO v_name FROM public.user_profiles WHERE user_id = v_caller;

  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    SELECT m.user_id, 'club_join_request', 'Beitrittsanfrage',
           COALESCE(v_name, 'Ein Spieler') || ' möchte deinem Veranstalterteam beitreten.',
           jsonb_build_object('organizer_team_id', p_club_id, 'request_id', v_request)
      FROM public.team_members m
     WHERE m.organizer_team_id = p_club_id AND m.removed_at IS NULL
       AND (m.roles && ARRAY['owner','admin']::text[]);

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'join_requested', v_caller,
            jsonb_build_object('request_id', v_request));
  RETURN v_request;
END;
$$;
