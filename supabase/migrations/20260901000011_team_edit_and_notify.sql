-- Team editing + league season-window + accept notification.
--
-- 1) team_update: rename / set country (admin-only).
-- 2) team_set_league: change the league, but only inside the transfer window
--    (October–February), checked against the SERVER clock (now()) so a client
--    cannot fake the date by changing the phone time. Outside the window the
--    league is fixed.
-- 3) team_invitation_respond now notifies the inviter via the inbox when the
--    invitee accepts.

-- ---- 1. team_update ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.team_update(
  p_team_id      uuid,
  p_display_name text,
  p_country      text
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
  IF NOT public.is_active_team_member(p_team_id, v_caller) OR NOT EXISTS (
    SELECT 1 FROM public.team_memberships
     WHERE team_id = p_team_id AND user_id = v_caller
       AND removed_at IS NULL AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'NOT_ADMIN' USING ERRCODE = '42501';
  END IF;
  IF p_display_name IS NULL OR length(trim(p_display_name)) NOT BETWEEN 1 AND 60 THEN
    RAISE EXCEPTION 'INVALID_NAME' USING ERRCODE = '22023';
  END IF;
  IF p_country IS NOT NULL AND length(p_country) <> 2 THEN
    RAISE EXCEPTION 'INVALID_COUNTRY' USING ERRCODE = '22023';
  END IF;

  UPDATE public.teams
     SET display_name = trim(p_display_name),
         country      = p_country,
         updated_at   = now()
   WHERE id = p_team_id AND dissolved_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.team_update(uuid, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.team_update(uuid, text, text) TO authenticated;

-- ---- 2. team_set_league ----------------------------------------------
-- Returns true when applied. Raises LEAGUE_LOCKED outside the Oct–Feb window.
CREATE OR REPLACE FUNCTION public.team_set_league(
  p_team_id uuid,
  p_league  text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_month  int;
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
  IF p_league NOT IN ('A', 'B', 'C') THEN
    RAISE EXCEPTION 'INVALID_LEAGUE' USING ERRCODE = '22023';
  END IF;

  -- Server-clock gate: months Oct (10) – Feb (2). Never trust the client.
  v_month := extract(month FROM now())::int;
  IF v_month NOT IN (10, 11, 12, 1, 2) THEN
    RAISE EXCEPTION 'LEAGUE_LOCKED' USING ERRCODE = '22023';
  END IF;

  UPDATE public.teams
     SET league_membership = p_league,
         updated_at        = now()
   WHERE id = p_team_id AND dissolved_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.team_set_league(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.team_set_league(uuid, text) TO authenticated;

-- Helper the client can call to know whether the league window is open right
-- now (so the UI can enable/disable the control without trusting device time).
CREATE OR REPLACE FUNCTION public.team_league_window_open()
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT extract(month FROM now())::int IN (10, 11, 12, 1, 2);
$$;
GRANT EXECUTE ON FUNCTION public.team_league_window_open() TO authenticated;

-- ---- 3. accept notification ------------------------------------------
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
  v_caller   uuid;
  v_inv      public.team_invitations%ROWTYPE;
  v_nickname text;
  v_team     text;
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

    -- Notify the inviter that their invitation was accepted.
    SELECT nickname INTO v_nickname
      FROM public.user_profiles WHERE user_id = v_caller;
    SELECT display_name INTO v_team
      FROM public.teams WHERE id = v_inv.team_id;
    INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
      VALUES (
        v_inv.invited_by,
        'notice',
        'Einladung angenommen',
        coalesce(v_nickname, 'Ein Spieler') || ' ist deinem Team "'
          || coalesce(v_team, '') || '" beigetreten.',
        jsonb_build_object('team_id', v_inv.team_id, 'member_user_id', v_caller)
      );
  ELSE
    INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
      VALUES (v_inv.team_id, 'invitation_declined', v_caller,
              jsonb_build_object('invitation_id', p_invitation_id));
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_invitation_respond(uuid, boolean)
  TO authenticated;
