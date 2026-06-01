-- Tournament feature — NEW registration model (organiser-confirmation removed).
--
-- USER DECISION (implement exactly):
--   1. NO organiser confirmation. Registering puts the participant straight
--      into the confirmed pool (registration_status = 'confirmed'), not
--      'pending'. The approve/reject step is no longer REQUIRED to play.
--   2. The registrant (and, for a team, all roster members) receive a
--      CONFIRMATION inbox message ('Anmeldung bestätigt …' / waitlist note).
--   3. Registration is ALWAYS OPEN once published: tournament_publish sets
--      status directly to 'registration_open' (+ published_at). There is no
--      separate manual 'Anmeldung öffnen' step. tournament_start is allowed
--      from 'registration_open' (start implicitly closes registration) as
--      well as 'registration_closed'.
--   4. CAPACITY → WAITLIST: when confirmed participants reach
--      max_participants, further registrations land as 'waitlist' (a
--      'you are on the waitlist' message). One participant row per team
--      counts as one unit toward max_participants.
--   5. DYNAMIC PROMOTION: when a confirmed participant withdraws and a slot
--      opens, the OLDEST waitlisted participant (by registered_at, id) is
--      promoted to 'confirmed' in the same transaction and notified
--      ('Du bist nachgerückt …').
--
-- Each RPC below is RE-STATED from its LATEST on-disk definition and changed
-- ONLY where the new model requires it:
--   * tournament_register_single — latest body 20260525000003 §5
--     (the schema file; never re-stated since). 'pending' -> 'confirmed',
--     confirmation/waitlist inbox message added. Capacity counts only
--     'confirmed' now (no 'pending' state is ever produced).
--   * tournament_register_team — latest body 20261101000003 §1.
--     'pending' -> 'confirmed' for the team unit, confirmation/waitlist
--     fan-out kept (same per-member loop). Capacity already present.
--   * tournament_withdraw — latest body 20260525000003 §6. Adds
--     oldest-waitlist promotion + notify when a CONFIRMED slot is freed.
--   * tournament_publish — latest body 20261201000032 §3. status ->
--     'registration_open' directly (was 'published'); registration_opens_at
--     stamped. Per-tournament manage gate kept verbatim.
--   * tournament_start — latest body 20261201000032 §9. Accepts status IN
--     ('registration_open','registration_closed'). Everything else verbatim.
--
-- ============================ DEPENDENCIES ============================
-- Requires (all earlier on disk):
--   * public.tournaments(id, status, max_participants, created_by, club_id,
--       display_name, format, pool_phase_config, published_at,
--       registration_opens_at) — 20260525000001 + 20261001000001 +
--       20261201000031 (club_id). status CHECK includes 'registration_open',
--       'registration_closed' (20260525000001 l.29-31).
--   * public.tournament_participants(id, tournament_id, user_id, team_id,
--       registration_status, registered_at, responded_at, withdrew_at) —
--       20260525000001 (l.44-55) + 20260615000005 (team_id). status CHECK:
--       'pending','confirmed','rejected','withdrawn','waitlist'
--       (20260525000001 l.48-49).
--   * public.tournament_roster_slots(participant_id, member_user_id,
--       guest_player_id, slot_index, assigned_by) — 20260615000005.
--   * public.tournament_audit_events(tournament_id, kind, actor_user_id,
--       payload) — 20260525000001.
--   * public.user_inbox_messages(user_id, kind, subject, body,
--       action_payload) + CHECK 'user_inbox_messages_kind_check'. LATEST
--       CHECK list = 20261201000010_tournament_golive_inbox.sql §0 (notice,
--       verification_request, system, team_invitation, team_member_removed,
--       team_dissolved, club_invitation, club_member_removed,
--       club_join_request, tournament_started, tournament_round). NOTE:
--       that re-add DROPPED 'tournament_team_registered' (added in
--       20261101000003 §0); §0 below RESTORES it and adds the three new
--       registration kinds. Direct-INSERT-from-SECURITY-DEFINER pattern:
--       team_invitation_respond, 20260901000011 §3.
--   * public.user_profiles(user_id, nickname) — display name in bodies.
--   * public.teams(id, display_name) — 20260615000001.
--   * public.team_memberships(team_id, user_id, removed_at) — 20260615000001.
--   * public.team_guest_players(id, team_id, removed_at) — roster pool check.
--   * public.tournament_caller_can_manage(uuid) — 20261201000031
--       (used by publish/start; kept verbatim).
-- Helpers called UNCHANGED by tournament_start (must already exist):
--   public.tournament_start_pool_phase, public._tournament_assign_pitches,
--   public._tournament_notify_participants.
--
-- ============================ RISK / SCOPE ============================
--   * No registration ever lands as 'pending' again, so the organiser
--     approve/reject RPCs (tournament_confirm_registration /
--     tournament_reject_registration, 20260525000003 §7/§8) become a no-op
--     in practice. They are LEFT AS-IS (still callable on legacy 'pending'
--     rows; harmless). The organiser UI may still show them but has nothing
--     to act on for new registrations — acceptable per the decision.
--   * tournament_open_registration (20261201000032 §4) is now redundant
--     (publish already opens registration). LEFT AS-IS so any existing call
--     site / draft→published→open path keeps working; calling it on an
--     already-'registration_open' tournament is a no-op-to-error per its own
--     status gate (it accepts 'published' or 'registration_closed'). Not a
--     regression — publish no longer produces 'published', but a manually
--     closed tournament can still be reopened with it.
--   * Capacity counts ONLY 'confirmed' rows now (the model produces no
--     'pending'). The FOR UPDATE lock on the tournament row still serialises
--     concurrent registrations so the (N+1)-th caller deterministically
--     waitlists. A team and a solo each occupy exactly one participant row =
--     one unit, matching tournament_list_for_caller's confirmed count.
--   * Promotion in withdraw uses SELECT … FOR UPDATE SKIP LOCKED-free
--     ordering (ORDER BY registered_at, id LIMIT 1) under the same tournament
--     row lock the withdraw already takes via the participant lock chain;
--     since only the participant themselves can withdraw their own row and
--     promotion targets a DIFFERENT row, we add an explicit row lock on the
--     promoted participant to avoid a double-promote race.
-- =====================================================================


-- ---- 0. Inbox kind extension -----------------------------------------
-- Re-state the full CHECK list (latest = 20261201000010 §0), RESTORE the
-- 'tournament_team_registered' kind that the golive re-add stripped, and add
-- the three new registration-confirmation kinds. DROP IF EXISTS keeps this
-- idempotent and order-safe. Unknown kinds render as a plain notice
-- client-side (InboxMessageKind.fromWire default), which is the intended
-- generic-message behaviour for these confirmations.
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
      'club_member_removed',
      'club_join_request',
      'tournament_started',
      'tournament_round',
      'tournament_team_registered',
      'tournament_registration_confirmed',
      'tournament_waitlisted',
      'tournament_promoted'
    ));


-- ====================================================================
-- 1. tournament_register_single — auto-confirm + capacity→waitlist +
--    confirmation inbox message. Re-stated from 20260525000003 §5.
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
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Lock the tournament row so the capacity count + insert are evaluated
  -- against a stable snapshot. This serialises concurrent registrations on
  -- the same tournament — the (N+1)-th caller blocks until the prior INSERT
  -- commits, then sees the updated count and is routed to the waitlist
  -- deterministically.
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

  IF EXISTS (
    SELECT 1 FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND user_id = v_caller
       AND registration_status IN ('pending','confirmed','waitlist')
  ) THEN
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

  INSERT INTO public.tournament_participants(
      tournament_id, user_id, registration_status, responded_at)
    VALUES (p_tournament_id, v_caller, v_new_status, now())
    RETURNING id INTO v_participant_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'registration_received',
      v_caller,
      jsonb_build_object(
        'participant_id', v_participant_id,
        'auto_waitlist',  v_auto_waitlist
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
-- 2. tournament_register_team — auto-confirm + capacity→waitlist +
--    member notification. Re-stated from 20261101000003 §1.
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

  -- Lock the tournament row so the capacity count + insert see a stable
  -- snapshot (same serialisation rationale as tournament_register_single).
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

  INSERT INTO public.tournament_participants(
      tournament_id, team_id, user_id, registration_status, responded_at)
    VALUES (p_tournament_id, p_team_id, v_caller, v_new_status, now())
    RETURNING id INTO v_participant_id;

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
        'auto_waitlist',  v_auto_waitlist
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


-- ====================================================================
-- 3. tournament_withdraw — dynamic promotion of the oldest waitlisted
--    participant when a confirmed slot is freed. Re-stated from
--    20260525000003 §6.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_withdraw(
  p_participant_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_user_id       uuid;
  v_tournament_id uuid;
  v_status        text;
  v_prior         text;
  v_promoted_id   uuid;
  v_promoted_user uuid;
  v_promoted_team uuid;
  v_name          text;
  v_member        uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT p.user_id, p.tournament_id, p.registration_status
    INTO v_user_id, v_tournament_id, v_prior
    FROM public.tournament_participants p
    WHERE p.id = p_participant_id
    FOR UPDATE;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'participant not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_user_id IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'only the participant can withdraw'
      USING ERRCODE = '42501';
  END IF;

  SELECT status, display_name INTO v_status, v_name
    FROM public.tournaments WHERE id = v_tournament_id;
  IF v_status NOT IN ('registration_open','registration_closed','live') THEN
    RAISE EXCEPTION 'withdrawal not allowed in current tournament state'
      USING ERRCODE = '22023';
  END IF;

  IF v_prior = 'withdrawn' THEN
    RAISE EXCEPTION 'already withdrawn' USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournament_participants
    SET registration_status = 'withdrawn',
        withdrew_at         = now()
    WHERE id = p_participant_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'withdrawn',
      v_caller,
      jsonb_build_object(
        'participant_id', p_participant_id,
        'prior_status',   v_prior
      )
    );

  -- DYNAMIC PROMOTION: only a CONFIRMED withdrawal frees a real slot. A
  -- waitlist withdrawal changes nothing for the confirmed pool, so we do
  -- nothing extra. Promote the OLDEST waitlisted participant
  -- (ORDER BY registered_at, id) and lock that row to avoid a double-promote
  -- race with a concurrent withdrawal in the same tournament.
  IF v_prior = 'confirmed' THEN
    SELECT p.id, p.user_id, p.team_id
      INTO v_promoted_id, v_promoted_user, v_promoted_team
      FROM public.tournament_participants p
      WHERE p.tournament_id = v_tournament_id
        AND p.registration_status = 'waitlist'
      ORDER BY p.registered_at, p.id
      LIMIT 1
      FOR UPDATE;

    IF v_promoted_id IS NOT NULL THEN
      UPDATE public.tournament_participants
        SET registration_status = 'confirmed',
            responded_at        = now()
        WHERE id = v_promoted_id;

      INSERT INTO public.tournament_audit_events(
          tournament_id, kind, actor_user_id, payload)
        VALUES (
          v_tournament_id,
          'waitlist_promoted',
          v_caller,
          jsonb_build_object(
            'participant_id',     v_promoted_id,
            'freed_by',           p_participant_id
          )
        );

      -- Notify the promoted unit. For a team participant, fan out to every
      -- registered roster member; for a solo, the participant's user_id.
      IF v_promoted_team IS NOT NULL THEN
        FOR v_member IN
          SELECT DISTINCT s.member_user_id
            FROM public.tournament_roster_slots s
           WHERE s.participant_id = v_promoted_id
             AND s.member_user_id IS NOT NULL
        LOOP
          INSERT INTO public.user_inbox_messages(
              user_id, kind, subject, body, action_payload)
            VALUES (
              v_member,
              'tournament_promoted',
              'Du bist nachgerückt',
              'Ein Platz bei "' || coalesce(v_name, '')
                || '" ist frei geworden — euer Team ist nachgerückt. Ihr seid dabei!',
              jsonb_build_object(
                'tournament_id',  v_tournament_id,
                'participant_id', v_promoted_id
              )
            );
        END LOOP;
      ELSE
        INSERT INTO public.user_inbox_messages(
            user_id, kind, subject, body, action_payload)
          VALUES (
            v_promoted_user,
            'tournament_promoted',
            'Du bist nachgerückt',
            'Ein Platz bei "' || coalesce(v_name, '')
              || '" ist frei geworden — du bist nachgerückt. Du bist dabei!',
            jsonb_build_object(
              'tournament_id',  v_tournament_id,
              'participant_id', v_promoted_id
            )
          );
      END IF;
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_withdraw(uuid) TO authenticated;


-- ====================================================================
-- 4. tournament_publish — open registration immediately. Re-stated from
--    20261201000032 §3; status goes straight to 'registration_open' and
--    registration_opens_at is stamped. Per-tournament manage gate verbatim.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_publish(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_created_by uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'tournament must be in status draft' USING ERRCODE = '22023';
  END IF;

  -- NEW MODEL: publishing opens registration immediately (no separate
  -- manual 'Anmeldung öffnen' step). registration_opens_at is stamped now.
  UPDATE public.tournaments
    SET status                = 'registration_open',
        published_at          = now(),
        registration_opens_at = coalesce(registration_opens_at, now())
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'published', v_caller, '{}'::jsonb);
  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'registration_opened', v_caller, '{}'::jsonb);
END;
$$;


-- ====================================================================
-- 5. tournament_start — allow start from 'registration_open' OR
--    'registration_closed' (start implicitly closes registration).
--    Re-stated from 20261201000032 §9; ONLY the status gate changed.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_start(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller         uuid;
  v_status         text;
  v_format         text;
  v_pool_config    jsonb;
  v_confirmed      int;
  v_slot_count     int;
  v_round_count    int;
  v_match_count    int := 0;
  v_round          int;
  v_i              int;
  v_a_idx          int;
  v_b_idx          int;
  v_a_pid          uuid;
  v_b_pid          uuid;
  v_name           text;
  v_created_by     uuid;   -- PER-TOURNAMENT
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, format, pool_phase_config, display_name, created_by
    INTO v_status, v_format, v_pool_config, v_name, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  -- NEW MODEL: registration is always open once published; starting
  -- implicitly closes it. Accept both open and closed states.
  IF v_status NOT IN ('registration_open','registration_closed') THEN
    RAISE EXCEPTION 'tournament must be in status registration_open or registration_closed'
      USING ERRCODE = '22023';
  END IF;
  IF v_format NOT IN (
       'round_robin','swiss','schoch',
       'round_robin_then_ko','schoch_then_ko','swiss_then_ko') THEN
    RAISE EXCEPTION 'format not yet supported' USING ERRCODE = '0A000';
  END IF;

  -- ---- Hybrid (*_then_ko): delegate the pool phase ------------------
  IF v_format IN ('round_robin_then_ko','schoch_then_ko','swiss_then_ko') THEN
    IF v_pool_config IS NULL OR jsonb_typeof(v_pool_config) <> 'object' THEN
      RAISE EXCEPTION 'pool_phase_config required for hybrid format'
        USING ERRCODE = '22023';
    END IF;

    PERFORM public.tournament_start_pool_phase(p_tournament_id, v_pool_config);

    INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'started',
        v_caller,
        jsonb_build_object('format', v_format, 'phase', 'pool'));
    RETURN;
  END IF;

  -- ---- Non-hybrid formats: confirmed-participant precondition -------
  SELECT count(*) INTO v_confirmed
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status = 'confirmed';

  IF v_confirmed < 2 THEN
    RAISE EXCEPTION 'at least 2 confirmed participants required'
      USING ERRCODE = '22023';
  END IF;

  CREATE TEMP TABLE _tstart_slots (
    slot_idx int PRIMARY KEY,
    participant_id uuid NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _tstart_slots(slot_idx, participant_id)
  SELECT row_number() OVER (ORDER BY p.registered_at, p.id), p.id
    FROM public.tournament_participants p
    WHERE p.tournament_id = p_tournament_id
      AND p.registration_status = 'confirmed';

  UPDATE public.tournament_participants p
    SET seed = s.slot_idx
    FROM _tstart_slots s
    WHERE p.id = s.participant_id;

  -- ---- swiss / schoch: materialise ROUND 1 only ---------------------
  IF v_format IN ('swiss','schoch') THEN
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        participant_a, participant_b, pitch_number, status)
    SELECT
      p_tournament_id,
      1::smallint,
      (((s.slot_idx - 1) / 2) + 1)::smallint,
      s.participant_id,
      part.participant_id,
      1,
      'scheduled'
    FROM _tstart_slots s
    LEFT JOIN _tstart_slots part
      ON part.slot_idx = s.slot_idx + 1
    WHERE (s.slot_idx % 2) = 1;

    GET DIAGNOSTICS v_match_count = ROW_COUNT;

    DROP TABLE _tstart_slots;

    PERFORM public._tournament_assign_pitches(p_tournament_id, 1::smallint);

    UPDATE public.tournaments
      SET status = 'live', started_at = now()
      WHERE id = p_tournament_id;

    INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'started',
        v_caller,
        jsonb_build_object(
          'format',      v_format,
          'round_count', 1,
          'match_count', v_match_count));

    PERFORM public._tournament_notify_participants(
      p_tournament_id,
      'tournament_started',
      'Turnier gestartet',
      'Turnier "' || coalesce(v_name, '') || '" ist gestartet — dein Platz ist da, leg los!',
      jsonb_build_object('tournament_id', p_tournament_id, 'format', v_format));
    RETURN;
  END IF;

  -- ---- round_robin: original circle-rotation materialisation --------
  IF (v_confirmed % 2) = 1 THEN
    v_slot_count := v_confirmed + 1;
    INSERT INTO _tstart_slots(slot_idx, participant_id) VALUES (v_slot_count, NULL);
  ELSE
    v_slot_count := v_confirmed;
  END IF;

  v_round_count := v_slot_count - 1;

  CREATE TEMP TABLE _tstart_ring (
    pos int PRIMARY KEY,
    participant_id uuid NULL
  ) ON COMMIT DROP;

  INSERT INTO _tstart_ring(pos, participant_id)
    SELECT slot_idx, participant_id FROM _tstart_slots;

  FOR v_round IN 1..v_round_count LOOP
    FOR v_i IN 0..((v_slot_count / 2) - 1) LOOP
      v_a_idx := v_i + 1;
      v_b_idx := v_slot_count - v_i;

      SELECT participant_id INTO v_a_pid FROM _tstart_ring WHERE pos = v_a_idx;
      SELECT participant_id INTO v_b_pid FROM _tstart_ring WHERE pos = v_b_idx;

      IF v_a_pid IS NULL AND v_b_pid IS NULL THEN
        CONTINUE;
      END IF;
      IF v_a_pid IS NULL THEN
        v_a_pid := v_b_pid;
        v_b_pid := NULL;
      END IF;

      INSERT INTO public.tournament_matches(
          tournament_id, round_number, match_number_in_round,
          participant_a, participant_b, pitch_number, status)
        VALUES (
          p_tournament_id, v_round::smallint, (v_i + 1)::smallint,
          v_a_pid, v_b_pid, 1, 'scheduled');

      v_match_count := v_match_count + 1;
    END LOOP;

    PERFORM public._tournament_assign_pitches(p_tournament_id, v_round::smallint);

    UPDATE _tstart_ring
      SET pos = CASE
                  WHEN pos = 1 THEN 1
                  WHEN pos = v_slot_count THEN 2
                  ELSE pos + 1
                END;
  END LOOP;

  DROP TABLE _tstart_ring;
  DROP TABLE _tstart_slots;

  UPDATE public.tournaments
    SET status = 'live', started_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'started',
      v_caller,
      jsonb_build_object(
        'format',      v_format,
        'round_count', v_round_count,
        'match_count', v_match_count));

  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_started',
    'Turnier gestartet',
    'Turnier "' || coalesce(v_name, '') || '" ist gestartet — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'format', v_format));
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start(uuid) TO authenticated;
