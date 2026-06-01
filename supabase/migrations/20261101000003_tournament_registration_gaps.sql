-- P6 "Tournieranmeldung" — server-side registration gaps.
--
-- Closes two server gaps from docs/P6_GAP_ANALYSIS.md:
--   (3) WAITLIST for TEAM registrations: tournament_register_team did no
--       capacity check, so team tournaments could over-fill past
--       tournaments.max_participants. The single-registration RPC already
--       routes the (N+1)-th caller to 'waitlist'; this brings team
--       registration in line with the same rule.
--   (4) MEMBER NOTIFICATION: every roster member of a team registration now
--       receives an inbox message so they all see they are registered.
--       Previously only a 'team_registered' audit event was written and the
--       non-registrant roster members had no surface telling them.
--
-- Both RPCs are re-created with CREATE OR REPLACE; their signatures are
-- unchanged, so existing GRANTs and client call sites keep working. A new
-- inbox `kind` ('tournament_team_registered') is added to the
-- user_inbox_messages CHECK constraint.
--
-- ---- Dependencies (verified by reading) -------------------------------
--  * public.tournament_register_team(uuid, uuid, jsonb)
--      — original def: 20260615000006_tournament_team_rpcs.sql (l.24-142).
--  * public.tournaments(status, team_size, max_participants)
--      — 20260525000001_tournament_schema.sql (l.13-39); max_participants
--        is NOT NULL (l.19), so the '>= v_max' comparison is always defined.
--  * public.tournament_participants(registration_status CHECK includes
--    'waitlist','pending','confirmed','withdrawn','rejected')
--      — 20260525000001_tournament_schema.sql (l.48-49).
--  * Single-registration waitlist precedent (count of pending+confirmed
--    >= max_participants -> 'waitlist', audit 'auto_waitlist'):
--      — tournament_register_single, 20260525000003_..._rpcs.sql (l.325-405).
--  * public.tournament_roster_slots(participant_id, member_user_id, ...)
--      — 20260615000005_tournament_team_roster.sql; populated by the team
--        RPC's slot loop (20260615000006, l.114-123).
--  * public.team_memberships(team_id, user_id, removed_at, role)
--      — 20260615000001_team_schema.sql (l.33-46).
--  * public.user_inbox_messages(user_id, kind, subject, body,
--    action_payload) + kind CHECK constraint name
--    'user_inbox_messages_kind_check'
--      — table: 20260504000011_mnemonic_admin_inbox.sql (l.83-99);
--        latest CHECK list: 20260901000016_club_membership_ops.sql
--        (l.67-75) = notice, verification_request, system, team_invitation,
--        team_member_removed, team_dissolved, club_invitation,
--        club_member_removed, club_join_request. The inbox-insert pattern
--        (direct INSERT into user_inbox_messages from a SECURITY DEFINER
--        RPC) follows team_invitation_respond,
--        20260901000011_team_edit_and_notify.sql (l.162-170).
--  * public.user_profiles(user_id, nickname) — used for the registrant's
--    display name in the notification body (same source as l.158-159 of
--    20260901000011).
--  * public.teams(display_name) — 20260615000001_team_schema.sql (l.16-18).
--  * public.tournaments(display_name) — for the message body.
-- -----------------------------------------------------------------------


-- ---- 0. Inbox kind extension -----------------------------------------
-- Re-declare the full CHECK list (latest = 20260901000016) plus the new
-- tournament kind. DROP IF EXISTS keeps this idempotent and order-safe.
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
      'tournament_team_registered'
    ));


-- ---- 1. tournament_register_team (waitlist + member notification) ----
--
-- Changes vs. 20260615000006:
--   * Capacity check mirroring tournament_register_single: count
--     pending+confirmed participants under the FOR UPDATE row lock; if
--     >= max_participants the new team lands as 'waitlist' instead of
--     'pending'. Behaviour below capacity is unchanged.
--   * After inserting the roster, fan out one inbox message per distinct
--     roster member_user_id (excluding the caller, who already gets the
--     RPC result) so all members see they are registered.
-- Everything else (membership gate, slot-count == team_size, MIN_ONE,
-- pool-membership checks, audit event) is preserved verbatim.

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
  v_caller         uuid;
  v_team_size      smallint;
  v_max            smallint;
  v_status         text;
  v_slot_count     int;
  v_member_count   int;
  v_active_count   int;
  v_new_status     text;
  v_auto_waitlist  boolean;
  v_participant_id uuid;
  v_slot           jsonb;
  v_team_name      text;
  v_tournament_name text;
  v_registrant_nick text;
  v_member         uuid;
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

  -- Capacity: count active (pending+confirmed) participant rows. Each team
  -- registration is one participant row, consistent with how
  -- tournament_list_for_caller counts 'confirmed' participants per
  -- tournament. At/over capacity the team is waitlisted.
  SELECT count(*)::int INTO v_active_count
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status IN ('pending','confirmed');

  IF v_active_count >= v_max THEN
    v_new_status    := 'waitlist';
    v_auto_waitlist := true;
  ELSE
    v_new_status    := 'pending';
    v_auto_waitlist := false;
  END IF;

  INSERT INTO public.tournament_participants(
      tournament_id, team_id, user_id, registration_status)
    VALUES (p_tournament_id, p_team_id, v_caller, v_new_status)
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

  -- --- Member notification (gap 4) -------------------------------------
  -- One inbox message per distinct registered roster member, excluding the
  -- caller (who gets the RPC result directly). Guest players have no
  -- account, so they are skipped. 'waitlist' status is surfaced in the body
  -- so members know whether they made the field or the waitlist.
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
       AND s.member_user_id <> v_caller
  LOOP
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
      VALUES (
        v_member,
        'tournament_team_registered',
        CASE WHEN v_auto_waitlist
             THEN 'Auf der Warteliste'
             ELSE 'Für Turnier angemeldet' END,
        coalesce(v_registrant_nick, 'Ein Teammitglied')
          || ' hat das Team "' || coalesce(v_team_name, '')
          || '" für "' || coalesce(v_tournament_name, '')
          || '" angemeldet.'
          || CASE WHEN v_auto_waitlist
                  THEN ' Ihr steht auf der Warteliste.'
                  ELSE '' END,
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
