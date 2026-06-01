-- Tournament feature — P6 "TournierStart": in-app go-live notifications.
--
-- When a tournament goes live (tournament_start /
-- tournament_start_pool_phase / tournament_start_ko_phase) and when a new
-- Swiss/Schoch round is materialised (tournament_pair_round), every
-- participant receives an in-app inbox message so the players know their
-- pitch is ready and they may start. This follows the existing in-app
-- inbox pattern (NO push provider, NO Firebase, NO new dependency) used
-- by the team flows (20260901000011_team_edit_and_notify.sql §3) and the
-- admin inbox (20260504000011_mnemonic_admin_inbox.sql §3).
--
-- ====================== AUTHORITATIVE-BODY NOTE =======================
-- The four hooked RPCs each have a LONG chain of CREATE OR REPLACE
-- migrations. This file re-states their CURRENT (latest) bodies VERBATIM
-- and adds ONLY the participant-notify call, marked GO-LIVE-NOTIFY.
-- Latest bodies cross-checked against the on-disk migrations:
--   * tournament_start(uuid)
--       — 20261201000003_tournament_assign_pitches.sql §3
--         (round_robin / swiss-round-1 / hybrid-delegate + PITCH-PLAN).
--   * tournament_start_pool_phase(uuid, jsonb)
--       — 20261201000003 §4 (+ PITCH-PLAN).
--   * tournament_pair_round(uuid, text, jsonb)
--       — 20261201000005_pair_round_progression_gate.sql
--         (PROGRESSION-GATE + PITCH-PLAN, superseding 20261201000003 §5).
--   * tournament_start_ko_phase(uuid, jsonb)
--       — 20261201000003 §6 (single- + double-elimination, per-round
--         PITCH-PLAN loop, superseding 20261101000002 / 20260615000010 /
--         20260601000015).
-- This migration's timestamp (20261201000010) sorts AFTER all of the
-- above, so its definitions win at apply-time. If ANY of those four RPCs
-- is replaced again before this lands, re-base this file onto the newer
-- body (see RISKS).
--
-- ============================ DEPENDENCIES ============================
-- Tables read:
--   * public.tournaments(id, display_name, created_by, status, format,
--                        pool_phase_config, started_at, pitch_plan,
--                        ko_config, bracket_type)
--       — 20260525000001_tournament_schema.sql,
--         20261001000001_tournament_setup_fields.sql (pool_phase_config,
--         pitch_plan), 20260601000010_tournament_ko_phase.sql (ko_config),
--         20261101000001_double_elim_phase.sql (bracket_type).
--   * public.tournament_participants(id, tournament_id, user_id, team_id,
--                        registration_status, registered_at, seed,
--                        group_label)
--       — 20260525000001, 20260615000005 (team_id), 20260615000009
--         (group_label).
--   * public.tournament_roster_slots(participant_id, member_user_id,
--                        replaced_at)
--       — 20260615000005_tournament_team_roster.sql §2.
--   * public.tournament_matches(...) — round / phase / pitch lookups;
--       20260525000001 + KO/pool/DE extensions.
--   * public.tournament_seeding_overrides — 20260601000011.
-- Tables written:
--   * public.user_inbox_messages(user_id, kind, subject, body,
--                        action_payload)
--       — 20260504000011_mnemonic_admin_inbox.sql §3; kind CHECK extended
--         here (§0).
-- Functions called (UNCHANGED, must already exist):
--   * public._tournament_compute_pools(jsonb, jsonb)           — 20260615000009
--   * public._tournament_compute_pool_cut(uuid, text, int)     — 20260615000009
--   * public._tournament_compute_ko_bracket(jsonb, boolean)    — 20260601000014
--   * public._tournament_compute_de_bracket(jsonb, boolean)    — 20261101000002
--   * public._tournament_assign_pitches(uuid, smallint)        — 20261201000003
--   * public.validate_swiss_pairing(uuid, jsonb)               — 20260801000001
-- Function NEW: public._tournament_notify_participants(uuid, text, text,
--   text, jsonb) RETURNS int.
-- =====================================================================


-- ---- 0. Extend the inbox kind CHECK ----------------------------------
-- Mirrors 20260615000004_team_inbox_types.sql: drop + re-add with the two
-- new tournament kinds appended to the full vocabulary.

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
      'tournament_started',
      'tournament_round'
    ));


-- ---- 1. _tournament_notify_participants ------------------------------
-- Fan-out one inbox row per DISTINCT app-user behind the tournament's
-- confirmed participants. Resolution unions solo participant.user_id with
-- every OPEN team roster slot's member_user_id (guests have no app user
-- and drop out). Returns the number of rows inserted. SECURITY DEFINER so
-- the direct INSERT bypasses the (intentionally absent) INSERT policy on
-- user_inbox_messages — same trust path as team_invitation_respond, which
-- already inserts inbox rows directly (20260901000011 §3).

CREATE OR REPLACE FUNCTION public._tournament_notify_participants(
  p_tournament_id uuid,
  p_kind          text,
  p_subject       text,
  p_body          text,
  p_payload       jsonb DEFAULT NULL
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_inserted int := 0;
BEGIN
  IF p_kind NOT IN ('tournament_started', 'tournament_round') THEN
    RAISE EXCEPTION 'invalid tournament inbox kind: %', p_kind
      USING ERRCODE = '22023';
  END IF;

  WITH recipients AS (
    -- Solo participants: the participant row itself carries the user.
    SELECT p.user_id AS user_id
      FROM public.tournament_participants p
     WHERE p.tournament_id = p_tournament_id
       AND p.registration_status = 'confirmed'
       AND p.user_id IS NOT NULL
    UNION
    -- Team participants: every open roster slot's member. Guest slots
    -- (member_user_id NULL) carry no app user and drop out naturally.
    SELECT s.member_user_id AS user_id
      FROM public.tournament_participants p
      JOIN public.tournament_roster_slots s
        ON s.participant_id = p.id
     WHERE p.tournament_id = p_tournament_id
       AND p.registration_status = 'confirmed'
       AND p.team_id IS NOT NULL
       AND s.replaced_at IS NULL
       AND s.member_user_id IS NOT NULL
  ),
  ins AS (
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
    SELECT DISTINCT r.user_id, p_kind, p_subject, p_body, p_payload
      FROM recipients r
      WHERE r.user_id IS NOT NULL
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM ins;

  RETURN v_inserted;
END;
$$;

REVOKE ALL ON FUNCTION public._tournament_notify_participants(uuid, text, text, text, jsonb) FROM public;
-- No role needs direct EXECUTE: the wrapping RPCs are SECURITY DEFINER and
-- call it internally (mirrors admin_inbox_send being service-role only).

COMMENT ON FUNCTION public._tournament_notify_participants(uuid, text, text, text, jsonb) IS
  'Fan-out one user_inbox_messages row per distinct confirmed-participant '
  'user (solo user_id + open team roster member_user_id; guests skipped). '
  'SECURITY DEFINER. Used by tournament go-live / round-publish RPCs. '
  'See 20261201000010_tournament_golive_inbox.sql.';


-- ====================================================================
-- 2. tournament_start — latest body (20261201000003 §3) + GO-LIVE-NOTIFY.
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
  v_name           text;   -- GO-LIVE-NOTIFY
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, format, pool_phase_config, display_name
    INTO v_status, v_format, v_pool_config, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id AND created_by = v_caller
    FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'registration_closed' THEN
    RAISE EXCEPTION 'tournament must be in status registration_closed'
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

    -- tournament_start_pool_phase assigns pitches AND fires the participant
    -- notification itself (see §3), so we do NOT notify again here.
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

    -- PITCH-PLAN: assign pitch_number for round 1 (no-op if plan NULL).
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

    -- GO-LIVE-NOTIFY: tournament is live, fan-out to every participant.
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

    -- PITCH-PLAN: assign pitch_number for this round's matches once the
    -- round is fully inserted (no-op if plan NULL).
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

  -- GO-LIVE-NOTIFY: tournament is live, fan-out to every participant.
  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_started',
    'Turnier gestartet',
    'Turnier "' || coalesce(v_name, '') || '" ist gestartet — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'format', v_format));
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start(uuid) TO authenticated;


-- ====================================================================
-- 3. tournament_start_pool_phase — latest body (20261201000003 §4)
--    + GO-LIVE-NOTIFY.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_start_pool_phase(
  p_tournament_id uuid,
  p_config        jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_creator       uuid;
  v_pools         jsonb;
  v_participants  jsonb;
  v_assignments   int := 0;
  v_match_count   int := 0;
  v_existing      int;
  v_labels        text[];
  v_name          text;   -- GO-LIVE-NOTIFY
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, display_name INTO v_creator, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL OR v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_existing
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase = 'group';
  IF v_existing > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: pool phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(id::text)
                            ORDER BY registered_at ASC, id ASC),
                  '[]'::jsonb)
    INTO v_participants
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status = 'confirmed';

  IF jsonb_array_length(v_participants) < 2 THEN
    RAISE EXCEPTION 'INVALID_POOL_CONFIG: at least 2 confirmed participants required'
      USING ERRCODE = '22023';
  END IF;

  v_pools := public._tournament_compute_pools(v_participants, p_config);

  WITH assignments AS (
    SELECT (elem ->> 'participant_id')::uuid AS pid,
           (elem ->> 'group_label')          AS lbl
      FROM jsonb_array_elements(v_pools) AS elem
  )
  UPDATE public.tournament_participants tp
     SET group_label = a.lbl
    FROM assignments a
   WHERE tp.id = a.pid
     AND tp.tournament_id = p_tournament_id;
  GET DIAGNOSTICS v_assignments = ROW_COUNT;

  SELECT array_agg(DISTINCT (elem ->> 'group_label') ORDER BY (elem ->> 'group_label'))
    INTO v_labels
    FROM jsonb_array_elements(v_pools) AS elem;

  WITH members AS (
    SELECT (elem ->> 'participant_id')::uuid AS pid,
           (elem ->> 'group_label')          AS lbl,
           (elem ->> 'group_position')::int  AS pos
      FROM jsonb_array_elements(v_pools) AS elem
  ),
  pairs AS (
    SELECT m1.lbl, m1.pid AS pid_a, m2.pid AS pid_b,
           m1.pos AS pos_a, m2.pos AS pos_b,
           row_number() OVER (
             PARTITION BY m1.lbl
             ORDER BY m1.pos, m2.pos
           ) AS pair_no
      FROM members m1
      JOIN members m2 ON m1.lbl = m2.lbl AND m1.pos < m2.pos
  )
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b,
      phase, group_label, status, pitch_number)
  SELECT p_tournament_id,
         1::smallint,
         pair_no::smallint,
         pid_a, pid_b,
         'group',
         lbl,
         'scheduled',
         1
    FROM pairs;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  -- PITCH-PLAN: pool round-robin uses round_number = 1 for all groups;
  -- the helper partitions by group_label (no-op if plan NULL).
  PERFORM public._tournament_assign_pitches(p_tournament_id, 1::smallint);

  UPDATE public.tournaments
     SET status     = 'live',
         started_at = coalesce(started_at, now())
   WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'pool_phase_started',
      v_caller,
      jsonb_build_object(
        'group_count',           coalesce(array_length(v_labels, 1), 0),
        'assignments',           v_assignments,
        'match_count',           v_match_count,
        'config',                p_config));

  -- GO-LIVE-NOTIFY: pool phase live, fan-out to every participant.
  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_started',
    'Turnier gestartet',
    'Turnier "' || coalesce(v_name, '') || '" ist gestartet — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'phase', 'pool'));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'group_count',   coalesce(array_length(v_labels, 1), 0),
    'assignments',   v_assignments,
    'match_count',   v_match_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start_pool_phase(uuid, jsonb)
  TO authenticated;


-- ====================================================================
-- 4. tournament_pair_round — latest body (20261201000005, with
--    PROGRESSION-GATE + PITCH-PLAN) + GO-LIVE-NOTIFY (per-round).
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_pair_round(
  p_tournament_id uuid,
  p_strategy      text,
  p_pairings      jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_creator       uuid;
  v_status        text;
  v_next_round    int;
  v_inserted      int := 0;
  v_current_round int;      -- PROGRESSION-GATE
  v_open_count    int;      -- PROGRESSION-GATE
  v_name          text;     -- GO-LIVE-NOTIFY
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, status, display_name INTO v_creator, v_status, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_creator <> v_caller THEN
    RAISE EXCEPTION 'not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'live' THEN
    RAISE EXCEPTION 'tournament must be in status live' USING ERRCODE = '22023';
  END IF;

  -- Backward-compat: non-swiss strategies (or swiss_system without a
  -- pairing payload) keep the original no-op behaviour.
  IF p_strategy IS DISTINCT FROM 'swiss_system' OR p_pairings IS NULL THEN
    RETURN;
  END IF;

  -- ---- PROGRESSION-GATE ------------------------------------------------
  -- Refuse to pair the next round while the CURRENT (latest) round still
  -- has open matches. Terminal = finalized/overridden/voided.
  SELECT max(round_number) INTO v_current_round
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id;

  IF v_current_round IS NOT NULL THEN
    SELECT count(*) INTO v_open_count
      FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND round_number  = v_current_round
        AND status NOT IN ('finalized','overridden','voided');

    IF v_open_count > 0 THEN
      RAISE EXCEPTION
        'round_not_complete: round % still has % open match(es); finalize them before pairing the next round',
        v_current_round, v_open_count
        USING ERRCODE = '22023';
    END IF;
  END IF;
  -- ---- end PROGRESSION-GATE -------------------------------------------

  -- Trust-boundary: validate the client-supplied pairing before any INSERT.
  PERFORM public.validate_swiss_pairing(p_tournament_id, p_pairings);

  SELECT coalesce(max(round_number), 0) + 1
    INTO v_next_round
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id;

  WITH ins AS (
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        participant_a, participant_b, pitch_number, status)
    SELECT
      p_tournament_id,
      v_next_round::smallint,
      (row_number() OVER ())::smallint,
      (elem ->> 'participant_a')::uuid,
      NULLIF(elem ->> 'participant_b','')::uuid,
      1,
      'scheduled'
    FROM jsonb_array_elements(p_pairings) AS elem
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM ins;

  -- PITCH-PLAN: assign pitch_number for the freshly paired round (no-op
  -- if plan NULL).
  PERFORM public._tournament_assign_pitches(p_tournament_id, v_next_round::smallint);

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'swiss_round_paired',
      v_caller,
      jsonb_build_object(
        'round_number', v_next_round,
        'match_count',  v_inserted,
        'strategy',     p_strategy
      )
    );

  -- GO-LIVE-NOTIFY: new round published — notify every participant.
  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_round',
    'Neue Runde',
    'Turnier "' || coalesce(v_name, '') || '": Runde ' || v_next_round
      || ' — dein Platz ist da, leg los!',
    jsonb_build_object(
      'tournament_id', p_tournament_id,
      'round_number',  v_next_round));
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_pair_round(uuid, text, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_pair_round(uuid, text, jsonb) TO authenticated;

COMMENT ON FUNCTION public.tournament_pair_round(uuid, text, jsonb) IS
  'Swiss/Schoch next-round generator. Organizer-only, status=live. Gate: '
  'refuses to pair the next round (ERRCODE 22023, MESSAGE round_not_complete) '
  'while the latest round has any non-terminal match. Validates the '
  'client-supplied pairing, inserts the round, assigns pitches and notifies '
  'every participant via the in-app inbox. No-op for non-swiss strategies.';


-- ====================================================================
-- 5. tournament_start_ko_phase — latest body (20261201000003 §6,
--    single- + double-elimination, per-round PITCH-PLAN) + GO-LIVE-NOTIFY.
--    KO go-live is a NEW round being published, so it uses the
--    'tournament_round' kind ('Neue Runde').
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_start_ko_phase(
  p_tournament_id uuid,
  p_ko_config     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller            uuid;
  v_creator           uuid;
  v_with_third_place  boolean;
  v_qualifier_count   int;
  v_incomplete        uuid[];
  v_ko_exists         int;
  v_has_pool_phase    boolean;
  v_seeds_jsonb       jsonb;
  v_match_count       int := 0;
  v_bye_count         int := 0;
  v_group_label       text;
  v_top_n             int;
  v_cut_result        jsonb;
  v_conflict_ids      jsonb := '[]'::jsonb;
  v_override_ids      uuid[];
  v_pool_count        int;
  v_bracket_type      text;
  v_with_reset        boolean;
  v_round             smallint;   -- PITCH-PLAN loop variable
  v_name              text;       -- GO-LIVE-NOTIFY
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, bracket_type,
         coalesce((ko_config ->> 'with_bracket_reset')::boolean, true),
         display_name
    INTO v_creator, v_bracket_type, v_with_reset, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL OR v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_ko_config IS NULL OR jsonb_typeof(p_ko_config) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: ko_config must be a JSON object'
      USING ERRCODE = '22023';
  END IF;
  v_with_third_place := coalesce(
    (p_ko_config ->> 'with_third_place_playoff')::boolean, false);
  v_qualifier_count := coalesce((p_ko_config ->> 'qualifier_count')::int, 0);
  IF v_qualifier_count < 2 OR v_qualifier_count > 64 THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count must be in [2, 64]'
      USING ERRCODE = '22023';
  END IF;

  IF v_bracket_type = 'double_elimination' THEN
    v_with_reset := coalesce(
      (p_ko_config ->> 'with_bracket_reset')::boolean, v_with_reset);
    IF v_with_third_place THEN
      RAISE EXCEPTION 'INVALID_KO_CONFIG: with_third_place_playoff is not allowed for double_elimination'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  SELECT count(*) INTO v_ko_exists
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','third_place','final',
                    'wb','lb','grand_final','grand_final_reset');
  IF v_ko_exists > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: ko phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  SELECT coalesce(array_agg(id ORDER BY id), ARRAY[]::uuid[])
    INTO v_incomplete
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase = 'group'
      AND status NOT IN ('finalized','overridden','voided');
  IF array_length(v_incomplete, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'PHASE_NOT_COMPLETE: % group match(es) not terminal: %',
      array_length(v_incomplete, 1), v_incomplete
      USING ERRCODE = '22023';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL
  ) INTO v_has_pool_phase;

  IF v_has_pool_phase THEN
    SELECT coalesce(array_agg(participant_id), ARRAY[]::uuid[])
      INTO v_override_ids
      FROM public.tournament_seeding_overrides
     WHERE tournament_id = p_tournament_id;

    SELECT count(DISTINCT group_label) INTO v_pool_count
      FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL;
    v_top_n := greatest(1, ((v_qualifier_count + v_pool_count - 1) / v_pool_count));

    CREATE TEMP TABLE IF NOT EXISTS _tmp_pool_cuts (
      group_label text,
      rank_in_pool int,
      participant_id uuid
    ) ON COMMIT DROP;
    TRUNCATE _tmp_pool_cuts;

    FOR v_group_label IN
      SELECT DISTINCT group_label
        FROM public.tournament_participants
       WHERE tournament_id = p_tournament_id
         AND group_label IS NOT NULL
       ORDER BY 1
    LOOP
      v_cut_result := public._tournament_compute_pool_cut(
        p_tournament_id, v_group_label, v_top_n);

      IF coalesce((v_cut_result ->> 'tie_resolution_needed')::boolean, false) THEN
        v_conflict_ids := v_conflict_ids
          || coalesce(v_cut_result -> 'conflicting_participants', '[]'::jsonb);
      END IF;

      INSERT INTO _tmp_pool_cuts(group_label, rank_in_pool, participant_id)
      SELECT v_group_label,
             (ord)::int,
             (val #>> '{}')::uuid
        FROM jsonb_array_elements(v_cut_result -> 'qualifiers')
             WITH ORDINALITY AS t(val, ord);
    END LOOP;

    IF jsonb_array_length(v_conflict_ids) > 0 THEN
      SELECT coalesce(jsonb_agg(elem ORDER BY elem), '[]'::jsonb)
        INTO v_conflict_ids
        FROM (
          SELECT DISTINCT elem
            FROM jsonb_array_elements_text(v_conflict_ids) AS elem
           WHERE (elem)::uuid <> ALL (v_override_ids)
        ) sub;

      IF jsonb_array_length(v_conflict_ids) > 0 THEN
        RAISE EXCEPTION 'TIEBREAKER_NEEDS_RESOLUTION'
          USING ERRCODE = 'P0001',
                DETAIL = jsonb_build_object(
                  'conflicting_participants', v_conflict_ids)::text;
      END IF;
    END IF;

    WITH labels AS (
      SELECT group_label,
             dense_rank() OVER (ORDER BY group_label) AS label_idx
        FROM (SELECT DISTINCT group_label FROM _tmp_pool_cuts) g
    ),
    base AS (
      SELECT c.participant_id,
             (c.rank_in_pool - 1) * 1000 + l.label_idx AS interleave_seed
        FROM _tmp_pool_cuts c
        JOIN labels l USING (group_label)
    ),
    overrides AS (
      SELECT participant_id, seed_override
        FROM public.tournament_seeding_overrides
       WHERE tournament_id = p_tournament_id
    ),
    combined AS (
      SELECT b.participant_id,
             coalesce(o.seed_override::numeric,
                      b.interleave_seed::numeric + 1000000) AS effective_seed,
             b.interleave_seed
        FROM base b
        LEFT JOIN overrides o USING (participant_id)
    ),
    seeded AS (
      SELECT participant_id,
             row_number() OVER (ORDER BY effective_seed, interleave_seed) AS final_seed
        FROM combined
    )
    SELECT coalesce(jsonb_agg(to_jsonb(participant_id::text) ORDER BY final_seed), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM seeded
     WHERE final_seed <= v_qualifier_count;

  ELSE
    WITH stats AS (
      SELECT p.id AS participant_id,
             p.registered_at,
             coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id THEN m.final_score_a - m.final_score_b
                    WHEN m.participant_b = p.id THEN m.final_score_b - m.final_score_a
                    ELSE 0 END), 0) AS kubb_diff
        FROM public.tournament_participants p
        LEFT JOIN public.tournament_matches m
          ON m.tournament_id = p.tournament_id
         AND m.phase = 'group'
         AND m.status IN ('finalized','overridden')
         AND (m.participant_a = p.id OR m.participant_b = p.id)
       WHERE p.tournament_id = p_tournament_id
         AND p.registration_status = 'confirmed'
       GROUP BY p.id, p.registered_at
    ),
    ranked AS (
      SELECT participant_id,
             row_number() OVER (
               ORDER BY wins DESC, kubb_diff DESC, registered_at ASC, participant_id ASC
             ) AS auto_seed
        FROM stats
    ),
    overrides AS (
      SELECT participant_id, seed_override
        FROM public.tournament_seeding_overrides
       WHERE tournament_id = p_tournament_id
    ),
    combined AS (
      SELECT r.participant_id,
             coalesce(o.seed_override::numeric,
                      r.auto_seed::numeric + 1000) AS effective_seed,
             r.auto_seed
        FROM ranked r
        LEFT JOIN overrides o USING (participant_id)
    ),
    seeded AS (
      SELECT participant_id,
             row_number() OVER (ORDER BY effective_seed, auto_seed) AS final_seed
        FROM combined
    )
    SELECT coalesce(jsonb_agg(to_jsonb(participant_id::text) ORDER BY final_seed), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM seeded
     WHERE final_seed <= v_qualifier_count;
  END IF;

  IF jsonb_array_length(v_seeds_jsonb) < v_qualifier_count THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count % exceeds confirmed participants',
      v_qualifier_count USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET ko_config = p_ko_config
    WHERE id = p_tournament_id;

  IF v_bracket_type = 'double_elimination' THEN
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           b.round_number::smallint,
           b.bracket_position::smallint,
           b.bracket_position,
           b.participant_a,
           b.participant_b,
           b.phase,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END
      FROM public._tournament_compute_de_bracket(v_seeds_jsonb, v_with_reset) b;
  ELSE
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           b.round_number::smallint,
           b.bracket_position::smallint,
           b.bracket_position,
           b.participant_a,
           b.participant_b,
           b.phase,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END
      FROM public._tournament_compute_ko_bracket(v_seeds_jsonb, v_with_third_place) b;
  END IF;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  -- PITCH-PLAN: assign pitch_number for every round just inserted.
  FOR v_round IN
    SELECT DISTINCT round_number
      FROM public.tournament_matches
     WHERE tournament_id = p_tournament_id
       AND phase IN ('ko','third_place','final',
                     'wb','lb','grand_final','grand_final_reset')
     ORDER BY round_number
  LOOP
    PERFORM public._tournament_assign_pitches(p_tournament_id, v_round);
  END LOOP;

  SELECT count(*) INTO v_bye_count
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','final','wb','lb')
      AND status = 'finalized';

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'ko_phase_started',
      v_caller,
      jsonb_build_object(
        'qualifier_count',          v_qualifier_count,
        'with_third_place_playoff', v_with_third_place,
        'bracket_type',             v_bracket_type,
        'with_bracket_reset',       v_with_reset,
        'match_count',              v_match_count,
        'bye_count',                v_bye_count,
        'pool_phase_present',       v_has_pool_phase,
        'seeds',                    v_seeds_jsonb));

  -- GO-LIVE-NOTIFY: KO bracket published — new round for everyone.
  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_round',
    'Neue Runde',
    'Turnier "' || coalesce(v_name, '') || '": K.-o.-Phase — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'phase', 'ko'));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'match_count',   v_match_count,
    'bye_count',     v_bye_count,
    'pool_phase',    v_has_pool_phase,
    'bracket_type',  v_bracket_type);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start_ko_phase(uuid, jsonb)
  TO authenticated;
