-- Team feature — M3 RPCs (part A: create, list, get, invite, respond).
--
-- Mutations on the team tables flow exclusively through SECURITY DEFINER
-- functions; RLS on the underlying tables permits SELECT only (see the
-- companion schema migration 20260615000001_team_schema.sql). Each
-- function guards on auth.uid() and raises ERRCODE 42501 when the caller
-- is not authenticated or lacks the required pool membership.
--
-- Inbox notifications for invitations write to user_inbox_messages with
-- kind='team_invitation'. That string is a hard-coded contract with the
-- inbox-types migration that extends the kind CHECK (TASK-M3.1-T6).
--
-- See docs/plans/m3-teams-pools-roster/architecture.md §3.2 and §3.5,
-- ADR-0018, and docs/plans/m3-teams-pools-roster/tasks.md T4.


-- ---- 1. team_create ---------------------------------------------------

CREATE OR REPLACE FUNCTION public.team_create(
  p_display_name      text,
  p_league_membership text,
  p_logo_url          text DEFAULT NULL,
  p_country           text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller  uuid;
  v_team_id uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.teams(display_name, league_membership, logo_url, country, created_by)
    VALUES (p_display_name, COALESCE(p_league_membership, 'B'), p_logo_url, p_country, v_caller)
    RETURNING id INTO v_team_id;

  INSERT INTO public.team_memberships(team_id, user_id)
    VALUES (v_team_id, v_caller);

  INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
    VALUES (v_team_id, 'team_created', v_caller,
            jsonb_build_object('display_name', p_display_name));

  RETURN v_team_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_create(text, text, text, text) TO authenticated;


-- ---- 2. team_list_for_caller -----------------------------------------

CREATE OR REPLACE FUNCTION public.team_list_for_caller()
RETURNS SETOF public.teams
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
    SELECT t.*
      FROM public.teams t
      JOIN public.team_memberships m ON m.team_id = t.id
     WHERE m.user_id = v_caller
       AND m.removed_at IS NULL
     ORDER BY t.created_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_list_for_caller() TO authenticated;


-- ---- 3. team_get ------------------------------------------------------

CREATE OR REPLACE FUNCTION public.team_get(p_team_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_team   public.teams%ROWTYPE;
  v_pool   jsonb;
  v_guests jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_team FROM public.teams WHERE id = p_team_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'team not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'membership_id', m.id,
           'user_id',       m.user_id,
           'joined_at',     m.joined_at
         ) ORDER BY m.joined_at), '[]'::jsonb)
    INTO v_pool
    FROM public.team_memberships m
   WHERE m.team_id = p_team_id AND m.removed_at IS NULL;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'guest_id',     g.id,
           'display_name', g.display_name,
           'added_at',     g.added_at
         ) ORDER BY g.added_at), '[]'::jsonb)
    INTO v_guests
    FROM public.team_guest_players g
   WHERE g.team_id = p_team_id AND g.removed_at IS NULL;

  RETURN jsonb_build_object(
    'team_id',           v_team.id,
    'display_name',      v_team.display_name,
    'league_membership', v_team.league_membership,
    'logo_url',          v_team.logo_url,
    'country',           v_team.country,
    'home_club_id',      v_team.home_club_id,
    'created_by',        v_team.created_by,
    'dissolved_at',      v_team.dissolved_at,
    'created_at',        v_team.created_at,
    'updated_at',        v_team.updated_at,
    'pool',              v_pool,
    'guests',            v_guests
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_get(uuid) TO authenticated;


-- ---- 4. team_invite ---------------------------------------------------

CREATE OR REPLACE FUNCTION public.team_invite(
  p_team_id         uuid,
  p_invitee_user_id uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller      uuid;
  v_invitation  uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.team_memberships m
     WHERE m.team_id = p_team_id
       AND m.user_id = v_caller
       AND m.removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'caller is not a pool member' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.team_memberships m
     WHERE m.team_id = p_team_id
       AND m.user_id = p_invitee_user_id
       AND m.removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'invitee already a member' USING ERRCODE = '23505';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.team_invitations i
     WHERE i.team_id = p_team_id
       AND i.invitee_user_id = p_invitee_user_id
       AND i.state = 'pending'
  ) THEN
    RAISE EXCEPTION 'INVITATION_ALREADY_PENDING' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.team_invitations(team_id, invitee_user_id, invited_by)
    VALUES (p_team_id, p_invitee_user_id, v_caller)
    RETURNING id INTO v_invitation;

  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    VALUES (
      p_invitee_user_id,
      'team_invitation',
      'Team-Einladung',
      'Du wurdest in ein Team eingeladen.',
      jsonb_build_object('team_id', p_team_id, 'invitation_id', v_invitation)
    );

  INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
    VALUES (p_team_id, 'member_invited', v_caller,
            jsonb_build_object('invitee_user_id', p_invitee_user_id,
                               'invitation_id', v_invitation));

  RETURN v_invitation;
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_invite(uuid, uuid) TO authenticated;


-- ---- 5. team_invitation_respond --------------------------------------

CREATE OR REPLACE FUNCTION public.team_invitation_respond(
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
  v_inv    public.team_invitations%ROWTYPE;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_inv FROM public.team_invitations WHERE id = p_invitation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_inv.invitee_user_id <> v_caller THEN
    RAISE EXCEPTION 'caller is not the invitee' USING ERRCODE = '42501';
  END IF;

  IF v_inv.state <> 'pending' THEN
    RAISE EXCEPTION 'invitation already resolved' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.team_invitations
     SET state        = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
         responded_at = now()
   WHERE id = p_invitation_id;

  IF p_accept THEN
    INSERT INTO public.team_memberships(team_id, user_id)
      VALUES (v_inv.team_id, v_caller)
      ON CONFLICT DO NOTHING;

    INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
      VALUES (v_inv.team_id, 'invitation_accepted', v_caller,
              jsonb_build_object('invitation_id', p_invitation_id));
  ELSE
    INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
      VALUES (v_inv.team_id, 'invitation_declined', v_caller,
              jsonb_build_object('invitation_id', p_invitation_id));
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_invitation_respond(uuid, boolean) TO authenticated;
