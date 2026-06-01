-- Tournament feature — allow RE-REGISTRATION after withdraw/reject.
--
-- BUG (found by live e2e): the unconditional unique index
--   tournament_participants_unique_user (tournament_id, user_id)
-- means there is at most ONE participant row per (tournament, user).
-- tournament_register_single / tournament_register_team only blocked
-- re-registration for an ACTIVE row (pending/confirmed/waitlist) and then
-- unconditionally INSERTed — so a user whose row sits in 'withdrawn' or
-- 'rejected' hit a raw 23505 unique-violation and could NEVER rejoin.
--
-- DESIRED: while registration is open, a user who previously withdrew (or
-- was rejected) CAN register again. On re-register we REACTIVATE the
-- existing row (UPDATE) rather than INSERTing a new one:
--   * recompute capacity (confirmed/pending participant rows),
--   * set registration_status to 'confirmed' (below max) or 'waitlist'
--     (at/over max),
--   * reset registered_at = now() so a re-joiner goes to the BACK of the
--     waitlist queue (promotion orders by registered_at, id),
--   * clear withdrew_at,
--   * send the same confirmation / waitlist inbox message.
-- An ACTIVE registration (pending/confirmed/waitlist) is still rejected
-- with the friendly 'already registered' (ERRCODE 23505), never a raw
-- constraint violation.
--
-- Both RPCs are RE-STATED from their LATEST on-disk definition
-- (20261201000040 §1 / §2). The ONLY change is the existence-check /
-- INSERT block, which becomes a "reactivate-or-insert": we look up an
-- existing row for (tournament, user) under the tournament FOR UPDATE
-- lock; if it is active we raise 'already registered'; otherwise we
-- UPDATE it in place (or INSERT when no row exists at all). Capacity
-- logic, the FOR UPDATE lock, audit events, and the inbox messages are
-- kept intact, and none of the 20261201000040 features (auto-confirm,
-- waitlist, member inbox fan-out, capacity = participant rows) regress.
--
-- For the team RPC, reactivation also rebuilds the roster slots for the
-- reactivated participant row (the team may submit a different roster on
-- re-registration), so the per-member inbox fan-out keeps working off the
-- freshly written slots.


-- ====================================================================
-- 1. tournament_register_single — reactivate-or-insert.
--    Re-stated from 20261201000040 §1.
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
  SELECT status, max_participants, display_name
    INTO v_status, v_max, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status <> 'registration_open' THEN
    RAISE EXCEPTION 'registration is not open' USING ERRCODE = '22023';
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


-- ====================================================================
-- 2. tournament_register_team — reactivate-or-insert.
--    Re-stated from 20261201000040 §2.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_register_team(
  p_tournament_id uuid,
  p_team_id       uuid,
  p_roster_json   jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller          uuid;
  v_team_size       smallint;
  v_max             smallint;
  v_status          text;
  v_slot_count      int;
  v_member_count    int;
  v_active_count    int;
  v_new_status      text;
  v_auto_waitlist   boolean;
  v_participant_id  uuid;
  v_slot            jsonb;
  v_team_name       text;
  v_tournament_name text;
  v_registrant_nick text;
  v_member          uuid;
  v_existing_id     uuid;
  v_existing_status text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Caller must be an active pool member of the team (FR-REG-2, BR-29).
  IF NOT EXISTS (
    SELECT 1 FROM public.team_memberships
     WHERE team_id = p_team_id
       AND user_id = v_caller
       AND removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'caller is not an active member of team %', p_team_id
      USING ERRCODE = '42501';
  END IF;

  -- Lock the tournament row so the capacity count + insert/update see a
  -- stable snapshot (same serialisation rationale as
  -- tournament_register_single).
  SELECT status, team_size, max_participants
    INTO v_status, v_team_size, v_max
    FROM public.tournaments WHERE id = p_tournament_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status <> 'registration_open' THEN
    RAISE EXCEPTION 'registration is not open' USING ERRCODE = '22023';
  END IF;

  v_slot_count := jsonb_array_length(p_roster_json);
  IF v_slot_count <> v_team_size THEN
    RAISE EXCEPTION 'roster slot count % does not match tournament team_size %',
      v_slot_count, v_team_size USING ERRCODE = '22023';
  END IF;

  -- FR-REG-12: at least one slot must be a registered member.
  SELECT count(*) INTO v_member_count
    FROM jsonb_array_elements(p_roster_json) AS e
    WHERE (e->>'member_user_id') IS NOT NULL;
  IF v_member_count < 1 THEN
    RAISE EXCEPTION 'roster must contain at least one registered member'
      USING ERRCODE = '22023', HINT = 'MIN_ONE_REGISTERED';
  END IF;

  -- REACTIVATE-OR-INSERT: the participant row is keyed by (tournament,
  -- user_id) via the unique index, where user_id is the registrant (the
  -- caller). An ACTIVE row (pending/confirmed/waitlist) for this caller in
  -- this tournament means the team unit they registered is already in —
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

  -- Capacity: count active confirmed participant rows. Each team
  -- registration is one participant row = one unit toward max_participants,
  -- consistent with how tournament_list_for_caller counts 'confirmed'
  -- participants per tournament. At/over capacity the team is waitlisted.
  SELECT count(*)::int INTO v_active_count
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status IN ('pending','confirmed');

  IF v_active_count >= v_max THEN
    v_new_status    := 'waitlist';
    v_auto_waitlist := true;
  ELSE
    -- NEW MODEL: team goes straight into the confirmed pool.
    v_new_status    := 'confirmed';
    v_auto_waitlist := false;
  END IF;

  IF v_existing_id IS NOT NULL THEN
    -- RE-REGISTRATION: reactivate the withdrawn/rejected participant row in
    -- place. Reset registered_at to now() (BACK of the waitlist queue),
    -- clear withdrew_at, and re-point the row at the (possibly new) team_id.
    UPDATE public.tournament_participants
      SET team_id             = p_team_id,
          registration_status = v_new_status,
          registered_at       = now(),
          responded_at        = now(),
          withdrew_at         = NULL
      WHERE id = v_existing_id;
    v_participant_id := v_existing_id;

    -- Rebuild the roster slots for this participant: the team may have
    -- submitted a different roster on re-registration. Removing the old
    -- slots first keeps the per-member inbox fan-out below accurate.
    DELETE FROM public.tournament_roster_slots
      WHERE participant_id = v_participant_id;
  ELSE
    INSERT INTO public.tournament_participants(
        tournament_id, team_id, user_id, registration_status, responded_at)
      VALUES (p_tournament_id, p_team_id, v_caller, v_new_status, now())
      RETURNING id INTO v_participant_id;
  END IF;

  -- Insert one row per slot. BR-5 / pool-membership / xor-check fire
  -- via constraints + the t1 trigger.
  FOR v_slot IN SELECT * FROM jsonb_array_elements(p_roster_json) LOOP
    -- Pool-membership of the occupant.
    IF (v_slot->>'member_user_id') IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.team_memberships
         WHERE team_id = p_team_id
           AND user_id = (v_slot->>'member_user_id')::uuid
           AND removed_at IS NULL
      ) THEN
        RAISE EXCEPTION 'slot member % is not in team pool',
          v_slot->>'member_user_id' USING ERRCODE = '22023';
      END IF;
    ELSIF (v_slot->>'guest_player_id') IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.team_guest_players
         WHERE id = (v_slot->>'guest_player_id')::uuid
           AND team_id = p_team_id
           AND removed_at IS NULL
      ) THEN
        RAISE EXCEPTION 'slot guest % is not in team pool',
          v_slot->>'guest_player_id' USING ERRCODE = '22023';
      END IF;
    END IF;

    INSERT INTO public.tournament_roster_slots(
        participant_id, slot_index, member_user_id, guest_player_id,
        assigned_by)
      VALUES (
        v_participant_id,
        (v_slot->>'slot_index')::smallint,
        NULLIF(v_slot->>'member_user_id','')::uuid,
        NULLIF(v_slot->>'guest_player_id','')::uuid,
        v_caller);
  END LOOP;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'team_registered',
      v_caller,
      jsonb_build_object(
        'participant_id', v_participant_id,
        'team_id',        p_team_id,
        'roster',         p_roster_json,
        'auto_waitlist',  v_auto_waitlist,
        'reactivated',    (v_existing_id IS NOT NULL)
      ));

  -- --- Member notification ---------------------------------------------
  -- One inbox message per distinct registered roster member, INCLUDING the
  -- caller (the new model promises the registrant a confirmation too).
  -- Guest players have no account and are skipped. 'waitlist' status is
  -- surfaced so members know whether they made the field or the waitlist.
  SELECT display_name INTO v_team_name
    FROM public.teams WHERE id = p_team_id;
  SELECT display_name INTO v_tournament_name
    FROM public.tournaments WHERE id = p_tournament_id;
  SELECT nickname INTO v_registrant_nick
    FROM public.user_profiles WHERE user_id = v_caller;

  FOR v_member IN
    SELECT DISTINCT s.member_user_id
      FROM public.tournament_roster_slots s
     WHERE s.participant_id = v_participant_id
       AND s.member_user_id IS NOT NULL
  LOOP
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
      VALUES (
        v_member,
        CASE WHEN v_auto_waitlist
             THEN 'tournament_waitlisted'
             ELSE 'tournament_registration_confirmed' END,
        CASE WHEN v_auto_waitlist
             THEN 'Auf der Warteliste'
             ELSE 'Anmeldung bestätigt' END,
        coalesce(v_registrant_nick, 'Ein Teammitglied')
          || ' hat das Team "' || coalesce(v_team_name, '')
          || '" für "' || coalesce(v_tournament_name, '')
          || '" angemeldet.'
          || CASE WHEN v_auto_waitlist
                  THEN ' Ihr steht auf der Warteliste — wir benachrichtigen euch,'
                       || ' sobald ihr nachrückt.'
                  ELSE ' Ihr seid dabei!' END,
        jsonb_build_object(
          'tournament_id',  p_tournament_id,
          'participant_id', v_participant_id,
          'team_id',        p_team_id,
          'waitlist',       v_auto_waitlist
        )
      );
  END LOOP;

  RETURN jsonb_build_object(
    'participant_id', v_participant_id,
    'waitlist',       v_auto_waitlist
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_register_team(uuid, uuid, jsonb)
  TO authenticated;
