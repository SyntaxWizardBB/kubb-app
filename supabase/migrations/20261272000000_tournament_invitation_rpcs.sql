-- Spaßturnier „auf Einladung" — S3: invitation RPCs + register_single gate.
--
-- All RPCs SECURITY DEFINER, search_path = public, auth, GRANT authenticated.
-- The respond/accept path mirrors club_invitation_respond (20260901000013)
-- plus the registration logic of tournament_register_single (Owner-Entscheid:
-- accepted invitees land as 'pending', the creator confirms as usual).


-- ====================================================================
-- 1. tournament_invite_user — invite a player to an invite-only tournament.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_invite_user(
  p_tournament_id uuid,
  p_user_id       uuid
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_invite_only   boolean;
  v_name          text;
  v_invitation    uuid;
  v_old_state     text;
  v_reactivated   boolean := false;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Manage gate (creator OR club owner/admin/organizer).
  IF NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  SELECT invite_only, display_name
    INTO v_invite_only, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;
  IF v_invite_only IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_invite_only IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'tournament is not invite-only' USING ERRCODE = '22023';
  END IF;

  -- Self-invitation forbidden.
  IF p_user_id = v_caller THEN
    RAISE EXCEPTION 'cannot invite yourself' USING ERRCODE = '22023';
  END IF;

  -- Invitee must be an existing user.
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'invitee user not found' USING ERRCODE = '22023';
  END IF;

  -- Upsert: a revoked/declined invitation is re-activated back to 'pending'
  -- with a fresh created_at; a pending/accepted one is a no-op (same id).
  SELECT id, state INTO v_invitation, v_old_state
    FROM public.tournament_invitations
    WHERE tournament_id = p_tournament_id
      AND invitee_user_id = p_user_id
    FOR UPDATE;

  IF v_invitation IS NULL THEN
    INSERT INTO public.tournament_invitations(
        tournament_id, invitee_user_id, invited_by, state)
      VALUES (p_tournament_id, p_user_id, v_caller, 'pending')
      RETURNING id INTO v_invitation;
    v_reactivated := true;
  ELSIF v_old_state IN ('revoked','declined') THEN
    UPDATE public.tournament_invitations
       SET state        = 'pending',
           invited_by   = v_caller,
           created_at   = now(),
           responded_at = NULL
     WHERE id = v_invitation;
    v_reactivated := true;
  ELSE
    -- already 'pending' or 'accepted' -> no-op, return the existing id.
    v_reactivated := false;
  END IF;

  -- Only notify / audit when the invitation is freshly active.
  IF v_reactivated THEN
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
      VALUES (
        p_user_id,
        'tournament_invitation',
        'Turnier-Einladung',
        'Du wurdest zu einem Turnier eingeladen: "'
          || coalesce(v_name, '') || '".',
        jsonb_build_object(
          'tournament_id',   p_tournament_id,
          'invitation_id',   v_invitation,
          'tournament_name', v_name
        )
      );

    INSERT INTO public.tournament_audit_events(
        tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'invitation_sent',
        v_caller,
        jsonb_build_object(
          'invitation_id',   v_invitation,
          'invitee_user_id', p_user_id
        )
      );
  END IF;

  RETURN v_invitation;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_invite_user(uuid, uuid)
  TO authenticated;


-- ====================================================================
-- 2. tournament_revoke_invitation — manager revokes an invitation.
--    Does NOT remove an already-registered participant (kept simple).
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_revoke_invitation(
  p_invitation_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_tournament_id uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT tournament_id INTO v_tournament_id
    FROM public.tournament_invitations
    WHERE id = p_invitation_id
    FOR UPDATE;
  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'invitation not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.tournament_caller_can_manage(v_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.tournament_invitations
     SET state        = 'revoked',
         responded_at = now()
   WHERE id = p_invitation_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'invitation_revoked',
      v_caller,
      jsonb_build_object('invitation_id', p_invitation_id)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_revoke_invitation(uuid)
  TO authenticated;


-- ====================================================================
-- 3. tournament_invitation_respond — invitee accepts/declines.
--    accept mirrors tournament_register_single's capacity/dup logic; the
--    accepted invitee lands as 'pending' (Owner-Entscheid).
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_invitation_respond(
  p_invitation_id uuid,
  p_accept        boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller          uuid;
  v_inv             public.tournament_invitations%ROWTYPE;
  v_status          text;
  v_max             smallint;
  v_active_count    int;
  v_new_status      text;
  v_existing_id     uuid;
  v_existing_status text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_inv FROM public.tournament_invitations
    WHERE id = p_invitation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_inv.invitee_user_id <> v_caller THEN
    RAISE EXCEPTION 'caller is not the invitee' USING ERRCODE = '42501';
  END IF;

  IF v_inv.state <> 'pending' THEN
    RAISE EXCEPTION 'invitation already resolved' USING ERRCODE = 'P0001';
  END IF;

  IF NOT p_accept THEN
    UPDATE public.tournament_invitations
       SET state = 'declined', responded_at = now()
     WHERE id = p_invitation_id;
    RETURN;
  END IF;

  -- ACCEPT: mark accepted, then register the player analogous to
  -- tournament_register_single (status gate, dup-guard, capacity->waitlist).
  UPDATE public.tournament_invitations
     SET state = 'accepted', responded_at = now()
   WHERE id = p_invitation_id;

  -- Lock the tournament row for a stable capacity snapshot.
  SELECT status, max_participants
    INTO v_status, v_max
    FROM public.tournaments
    WHERE id = v_inv.tournament_id
    FOR UPDATE;
  IF v_status <> 'registration_open' THEN
    RAISE EXCEPTION 'registration is not open' USING ERRCODE = '22023';
  END IF;

  -- Dup-guard: an active row (pending/confirmed/waitlist) means already in.
  SELECT id, registration_status
    INTO v_existing_id, v_existing_status
    FROM public.tournament_participants
    WHERE tournament_id = v_inv.tournament_id
      AND user_id = v_caller
    FOR UPDATE;
  IF v_existing_status IN ('pending','confirmed','waitlist') THEN
    RAISE EXCEPTION 'already registered' USING ERRCODE = '23505';
  END IF;

  -- Capacity: count active confirmed/pending participant rows.
  SELECT count(*)::int INTO v_active_count
    FROM public.tournament_participants
    WHERE tournament_id = v_inv.tournament_id
      AND registration_status IN ('pending','confirmed');

  IF v_active_count >= v_max THEN
    v_new_status := 'waitlist';
  ELSE
    -- Owner-Entscheid: accepted invitee lands as 'pending' (creator confirms).
    v_new_status := 'pending';
  END IF;

  IF v_existing_id IS NOT NULL THEN
    -- Reactivate a previously withdrawn/rejected row in place.
    UPDATE public.tournament_participants
      SET registration_status = v_new_status,
          registered_at       = now(),
          responded_at        = now(),
          withdrew_at         = NULL
      WHERE id = v_existing_id;
  ELSE
    INSERT INTO public.tournament_participants(
        tournament_id, user_id, registration_status, responded_at)
      VALUES (v_inv.tournament_id, v_caller, v_new_status, now());
  END IF;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_inv.tournament_id,
      'registration_received',
      v_caller,
      jsonb_build_object(
        'invitation_id', p_invitation_id,
        'via_invitation', true,
        'waitlist',       (v_new_status = 'waitlist')
      )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_invitation_respond(uuid, boolean)
  TO authenticated;


-- ====================================================================
-- 4. tournament_register_single — CREATE OR REPLACE, re-based verbatim from
--    20261201000050 §1. ONLY change: read invite_only in the tournament
--    SELECT and, for invite-only tournaments, require a (pending/accepted)
--    invitation before allowing registration. Non-invite_only is byte-
--    identical to the baseline.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_register_single(
  p_tournament_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller          uuid;
  v_status          text;
  v_max             smallint;
  v_name            text;
  v_invite_only     boolean;
  v_active_count    int;
  v_new_status      text;
  v_auto_waitlist   boolean;
  v_participant_id  uuid;
  v_existing_id     uuid;
  v_existing_status text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Lock the tournament row so the capacity count + insert/update are
  -- evaluated against a stable snapshot. This serialises concurrent
  -- registrations on the same tournament — the (N+1)-th caller blocks until
  -- the prior write commits, then sees the updated count and is routed to
  -- the waitlist deterministically.
  SELECT status, max_participants, display_name, invite_only
    INTO v_status, v_max, v_name, v_invite_only
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status <> 'registration_open' THEN
    RAISE EXCEPTION 'registration is not open' USING ERRCODE = '22023';
  END IF;

  -- INVITE-ONLY GATE: when the tournament is invite-only, the caller must
  -- hold an invitation in state ('pending','accepted'); otherwise refused.
  IF v_invite_only THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.tournament_invitations i
       WHERE i.tournament_id = p_tournament_id
         AND i.invitee_user_id = v_caller
         AND i.state IN ('pending','accepted')
    ) THEN
      RAISE EXCEPTION 'invitation required' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- REACTIVATE-OR-INSERT: there is at most one row per (tournament, user)
  -- (unique index tournament_participants_unique_user). Look it up. An
  -- ACTIVE row (pending/confirmed/waitlist) means the user is already in —
  -- reject with the friendly 'already registered'. A 'withdrawn'/'rejected'
  -- row is eligible for reactivation. Lock the row we may update.
  SELECT id, registration_status
    INTO v_existing_id, v_existing_status
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND user_id = v_caller
    FOR UPDATE;

  IF v_existing_status IN ('pending','confirmed','waitlist') THEN
    RAISE EXCEPTION 'already registered' USING ERRCODE = '23505';
  END IF;

  -- Capacity: count active confirmed participant rows. The new model never
  -- produces 'pending'; legacy 'pending' rows (if any) still count as
  -- occupying a slot, matching the previous behaviour.
  SELECT count(*)::int INTO v_active_count
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status IN ('pending','confirmed');

  IF v_active_count >= v_max THEN
    v_new_status    := 'waitlist';
    v_auto_waitlist := true;
  ELSIF v_invite_only THEN
    -- INVITE-ONLY (Owner-Entscheid): the creator curates an invite-only
    -- Spaßturnier, so a registering invitee lands as 'pending' and the
    -- creator confirms — mirroring the accept-via-inbox path. This is the
    -- ONLY divergence from the open-registration auto-confirm model for
    -- invite_only tournaments; public registration stays 'confirmed' below.
    v_new_status    := 'pending';
    v_auto_waitlist := false;
  ELSE
    -- NEW MODEL: straight into the confirmed pool, no organiser step.
    v_new_status    := 'confirmed';
    v_auto_waitlist := false;
  END IF;

  IF v_existing_id IS NOT NULL THEN
    -- RE-REGISTRATION: reactivate the withdrawn/rejected row in place. Reset
    -- registered_at to now() so a re-joiner queues at the BACK of the
    -- waitlist, and clear withdrew_at.
    UPDATE public.tournament_participants
      SET registration_status = v_new_status,
          registered_at       = now(),
          responded_at        = now(),
          withdrew_at         = NULL
      WHERE id = v_existing_id;
    v_participant_id := v_existing_id;
  ELSE
    INSERT INTO public.tournament_participants(
        tournament_id, user_id, registration_status, responded_at)
      VALUES (p_tournament_id, v_caller, v_new_status, now())
      RETURNING id INTO v_participant_id;
  END IF;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'registration_received',
      v_caller,
      jsonb_build_object(
        'participant_id', v_participant_id,
        'auto_waitlist',  v_auto_waitlist,
        'reactivated',    (v_existing_id IS NOT NULL)
      )
    );

  -- Confirmation / waitlist inbox message to the registrant.
  INSERT INTO public.user_inbox_messages(
      user_id, kind, subject, body, action_payload)
    VALUES (
      v_caller,
      CASE WHEN v_auto_waitlist
           THEN 'tournament_waitlisted'
           ELSE 'tournament_registration_confirmed' END,
      CASE WHEN v_auto_waitlist
           THEN 'Auf der Warteliste'
           ELSE 'Anmeldung bestätigt' END,
      CASE WHEN v_auto_waitlist
           THEN 'Du stehst auf der Warteliste für "'
                || coalesce(v_name, '')
                || '". Wir benachrichtigen dich, sobald du nachrückst.'
           ELSE 'Anmeldung bestätigt für "'
                || coalesce(v_name, '') || '". Du bist dabei!' END,
      jsonb_build_object(
        'tournament_id',  p_tournament_id,
        'participant_id', v_participant_id,
        'waitlist',       v_auto_waitlist
      )
    );

  RETURN jsonb_build_object('participant_id', v_participant_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_register_single(uuid)
  TO authenticated;
