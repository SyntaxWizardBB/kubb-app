-- Club (Verein) feature — P5 RPCs.
--
-- SECURITY DEFINER mutations for the club tables (companion to
-- 20260901000012_club_schema.sql). Each guards on auth.uid() and raises
-- ERRCODE 42501 when the caller is missing auth or management rights.
-- Founding is gated by a single global code (club_founding_code).
--
-- Inbox notifications for invitations write kind='club_invitation' — added to
-- the user_inbox_messages kind CHECK at the bottom of this file.


-- ---- 0. Inbox kind extension -----------------------------------------

ALTER TABLE public.user_inbox_messages
  DROP CONSTRAINT IF EXISTS user_inbox_messages_kind_check;

ALTER TABLE public.user_inbox_messages
  ADD CONSTRAINT user_inbox_messages_kind_check
    CHECK (kind IN (
      'notice',
      'verification_request',
      'system',
      'team_invitation',
      'team_member_removed',
      'team_dissolved',
      'club_invitation',
      'club_member_removed'
    ));


-- ---- 1. Global founding code -----------------------------------------
--
-- Single shared code (format XXXX-XXXX) that unlocks club founding, mirroring
-- an early-access code. Centralised in one function so it is trivial to rotate.
-- Comparison is case-insensitive and trim-tolerant in club_create.

CREATE OR REPLACE FUNCTION public.club_founding_code()
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$ SELECT 'KUBB-2026'::text $$;


-- ---- 2. club_create ---------------------------------------------------

CREATE OR REPLACE FUNCTION public.club_create(
  p_display_name text,
  p_code         text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller  uuid;
  v_club_id uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF p_code IS NULL
     OR upper(trim(p_code)) <> public.club_founding_code() THEN
    RAISE EXCEPTION 'INVALID_FOUNDING_CODE' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.clubs(display_name, created_by)
    VALUES (p_display_name, v_caller)
    RETURNING id INTO v_club_id;

  -- Founder owns the club.
  INSERT INTO public.club_memberships(club_id, user_id, roles)
    VALUES (v_club_id, v_caller, ARRAY['owner']::text[]);

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (v_club_id, 'club_created', v_caller,
            jsonb_build_object('display_name', p_display_name));

  RETURN v_club_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.club_create(text, text) TO authenticated;


-- ---- 3. club_list_for_caller -----------------------------------------

CREATE OR REPLACE FUNCTION public.club_list_for_caller()
RETURNS SETOF public.clubs
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

  RETURN QUERY
    SELECT c.*
      FROM public.clubs c
      JOIN public.club_memberships m ON m.club_id = c.id
     WHERE m.user_id = v_caller
       AND m.removed_at IS NULL
     ORDER BY c.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.club_list_for_caller() TO authenticated;


-- ---- 4. club_get ------------------------------------------------------

CREATE OR REPLACE FUNCTION public.club_get(p_club_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_club   public.clubs%ROWTYPE;
  v_members jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_club FROM public.clubs WHERE id = p_club_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'club not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'membership_id', m.id,
           'user_id',       m.user_id,
           'display_name',  p.nickname,
           'roles',         to_jsonb(m.roles),
           'joined_at',     m.joined_at
         ) ORDER BY m.joined_at), '[]'::jsonb)
    INTO v_members
    FROM public.club_memberships m
    LEFT JOIN public.user_profiles p ON p.user_id = m.user_id
   WHERE m.club_id = p_club_id AND m.removed_at IS NULL;

  RETURN jsonb_build_object(
    'club_id',      v_club.id,
    'display_name', v_club.display_name,
    'created_by',   v_club.created_by,
    'dissolved_at', v_club.dissolved_at,
    'created_at',   v_club.created_at,
    'updated_at',   v_club.updated_at,
    'members',      v_members
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.club_get(uuid) TO authenticated;


-- ---- 5. club_invite_by_nickname --------------------------------------
--
-- Only an owner/admin may invite. Resolves the unique citext nickname to a
-- user id, guards against double-membership and duplicate pending invites,
-- then writes the invitation, an inbox message and an audit row.

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
  v_caller     uuid;
  v_invitee    uuid;
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

  IF p_nickname IS NULL OR length(trim(p_nickname)) = 0 THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT user_id INTO v_invitee
    FROM public.user_profiles
   WHERE nickname = trim(p_nickname)::citext;

  IF v_invitee IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.club_memberships m
     WHERE m.club_id = p_club_id
       AND m.user_id = v_invitee
       AND m.removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'invitee already a member' USING ERRCODE = '23505';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.club_invitations i
     WHERE i.club_id = p_club_id
       AND i.invitee_user_id = v_invitee
       AND i.state = 'pending'
  ) THEN
    RAISE EXCEPTION 'INVITATION_ALREADY_PENDING' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.club_invitations(club_id, invitee_user_id, invited_by)
    VALUES (p_club_id, v_invitee, v_caller)
    RETURNING id INTO v_invitation;

  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    VALUES (
      v_invitee,
      'club_invitation',
      'Vereins-Einladung',
      'Du wurdest in einen Verein eingeladen.',
      jsonb_build_object('club_id', p_club_id, 'invitation_id', v_invitation)
    );

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_invited', v_caller,
            jsonb_build_object('invitee_user_id', v_invitee,
                               'invitation_id', v_invitation));

  RETURN v_invitation;
END;
$$;

REVOKE ALL ON FUNCTION public.club_invite_by_nickname(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.club_invite_by_nickname(uuid, text)
  TO authenticated;


-- ---- 6. club_invitation_respond --------------------------------------

CREATE OR REPLACE FUNCTION public.club_invitation_respond(
  p_invitation_id uuid,
  p_accept        boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_inv    public.club_invitations%ROWTYPE;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_inv FROM public.club_invitations WHERE id = p_invitation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_inv.invitee_user_id <> v_caller THEN
    RAISE EXCEPTION 'caller is not the invitee' USING ERRCODE = '42501';
  END IF;

  IF v_inv.state <> 'pending' THEN
    RAISE EXCEPTION 'invitation already resolved' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.club_invitations
     SET state        = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
         responded_at = now()
   WHERE id = p_invitation_id;

  IF p_accept THEN
    INSERT INTO public.club_memberships(club_id, user_id, roles)
      VALUES (v_inv.club_id, v_caller, ARRAY['member']::text[])
      ON CONFLICT DO NOTHING;

    INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
      VALUES (v_inv.club_id, 'invitation_accepted', v_caller,
              jsonb_build_object('invitation_id', p_invitation_id));
  ELSE
    INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
      VALUES (v_inv.club_id, 'invitation_declined', v_caller,
              jsonb_build_object('invitation_id', p_invitation_id));
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.club_invitation_respond(uuid, boolean)
  TO authenticated;


-- ---- 7. club_set_member_roles ----------------------------------------
--
-- Owner/admin assigns the full role set for a member. Validates the roles are
-- a non-empty subset of the allowed set, and refuses to drop the last owner so
-- a club always keeps an administrator.

CREATE OR REPLACE FUNCTION public.club_set_member_roles(
  p_club_id        uuid,
  p_member_user_id uuid,
  p_roles          text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_was_owner    boolean;
  v_will_owner   boolean;
  v_other_owners int;
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

  IF p_roles IS NULL OR array_length(p_roles, 1) IS NULL THEN
    RAISE EXCEPTION 'EMPTY_ROLES' USING ERRCODE = 'P0001';
  END IF;
  IF NOT (p_roles <@ ARRAY[
            'owner','admin','member','referee','timemaster',
            'organizer','scorekeeper','treasurer']::text[]) THEN
    RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = 'P0001';
  END IF;

  SELECT (roles && ARRAY['owner']::text[]) INTO v_was_owner
    FROM public.club_memberships
   WHERE club_id = p_club_id AND user_id = p_member_user_id
     AND removed_at IS NULL;
  IF v_was_owner IS NULL THEN
    RAISE EXCEPTION 'member not found' USING ERRCODE = 'P0002';
  END IF;

  v_will_owner := p_roles && ARRAY['owner']::text[];

  -- Block demoting the final owner.
  IF v_was_owner AND NOT v_will_owner THEN
    SELECT count(*) INTO v_other_owners
      FROM public.club_memberships
     WHERE club_id = p_club_id
       AND removed_at IS NULL
       AND user_id <> p_member_user_id
       AND (roles && ARRAY['owner']::text[]);
    IF v_other_owners = 0 THEN
      RAISE EXCEPTION 'LAST_OWNER' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.club_memberships
     SET roles = p_roles
   WHERE club_id = p_club_id AND user_id = p_member_user_id
     AND removed_at IS NULL;

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_roles_set', v_caller,
            jsonb_build_object('member_user_id', p_member_user_id,
                               'roles', to_jsonb(p_roles)));
END;
$$;

REVOKE ALL ON FUNCTION public.club_set_member_roles(uuid, uuid, text[]) FROM public;
GRANT EXECUTE ON FUNCTION public.club_set_member_roles(uuid, uuid, text[])
  TO authenticated;
