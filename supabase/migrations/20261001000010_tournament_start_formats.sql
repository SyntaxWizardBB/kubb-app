-- Tournament feature — P6: tournament_start routing across all formats.
--
-- The M1 tournament_start (20260525000002_tournament_lifecycle_rpcs.sql)
-- materialised only the round_robin circle-rotation schedule and raised
-- ERRCODE 0A000 ('format not yet supported') for every other format.
-- P6 unlocked the remaining formats in the setup wizard, so this
-- migration CREATE OR REPLACEs tournament_start to route by the
-- tournaments.format value while preserving the M1 preconditions, the
-- status->live transition, started_at and the 'started' audit event.
--
-- Routing:
--   round_robin
--       Unchanged — the original circle-rotation materialisation,
--       inlined verbatim below.
--   swiss | schoch
--       Materialise ROUND 1 only. The swiss pairing RPC
--       (tournament_pair_round, 20260801000001_pair_round_swiss.sql)
--       requires a CLIENT-supplied p_pairings payload and prior matches
--       to pair later rounds, so it cannot seed round 1 itself. Round 1
--       is therefore the initial seeded pairing: confirmed participants
--       ordered by registration, paired adjacently (seed 1 vs 2,
--       3 vs 4, ...); an odd roster gives the last seed a bye
--       (participant_b NULL). Later rounds are paired by the client via
--       tournament_pair_round once these matches are finalized. schoch
--       is EKC-Schoch == live-score Swiss (P6_RULES_DECISIONS §G), so it
--       shares the swiss round-1 seeding path exactly.
--   round_robin_then_ko | schoch_then_ko | swiss_then_ko
--       Delegate the POOL phase to the existing
--       tournament_start_pool_phase(uuid, jsonb)
--       (20260615000009_tournament_pool_phase.sql), passing
--       tournaments.pool_phase_config (persisted at create-time by
--       20261001000001_tournament_setup_fields.sql). That sub-function
--       performs its own FOR UPDATE lock (re-entrant within this txn),
--       its own >=2 confirmed check, sets status='live' + started_at and
--       writes a 'pool_phase_started' audit event; this wrapper adds the
--       uniform 'started' event afterwards. The KO bracket is built later
--       by tournament_start_ko_phase once the group phase is complete.
--
-- ============================ DEPENDENCIES ============================
-- Functions called:
--   * public.tournament_start_pool_phase(uuid, jsonb)
--       — source: 20260615000009_tournament_pool_phase.sql §4.
--         Reads p_config in the shape _tournament_compute_pools accepts:
--         { group_count, qualifiers_per_group, strategy, random_seed? }.
-- Tables / columns read:
--   * public.tournaments(id, created_by, status, format,
--                         pool_phase_config, started_at)
--       — id/created_by/status/format: 20260525000001_tournament_schema.sql
--       — pool_phase_config:            20261001000001_tournament_setup_fields.sql §5c
--       — started_at:                   20260525000001_tournament_schema.sql
--   * public.tournament_participants(id, tournament_id,
--                                    registration_status, registered_at,
--                                    seed)
--       — 20260525000001_tournament_schema.sql
-- Tables / columns written:
--   * public.tournament_participants.seed
--       — set to the 1-based slot index (round_robin + swiss/schoch).
--   * public.tournament_matches(tournament_id, round_number,
--       match_number_in_round, participant_a, participant_b,
--       pitch_number, status)
--       — 20260525000001_tournament_schema.sql; `phase` defaults to
--         'group' (20260601000010_tournament_ko_phase.sql §1) which is
--         correct for round_robin and the swiss/schoch round-1 rows.
--   * public.tournaments(status, started_at)
--   * public.tournament_audit_events(tournament_id, kind, actor_user_id,
--       payload) — 'started'
--       — 20260525000001_tournament_schema.sql.
-- Format vocabulary cross-checked against the CHECK in
--   public.tournament_create (20260525000002_tournament_lifecycle_rpcs.sql):
--   round_robin, single_elimination, round_robin_then_ko, schoch, swiss,
--   schoch_then_ko, swiss_then_ko.
-- =====================================================================


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
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, format, pool_phase_config
    INTO v_status, v_format, v_pool_config
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
    -- single_elimination has no group/round-1 schedule to materialise at
    -- start; its bracket is built by tournament_start_ko_phase. Anything
    -- else is genuinely unsupported.
    RAISE EXCEPTION 'format not yet supported' USING ERRCODE = '0A000';
  END IF;

  -- ---- Hybrid (*_then_ko): delegate the pool phase ------------------
  -- tournament_start_pool_phase does its own confirmed>=2 check, its own
  -- FOR UPDATE (re-entrant within this txn), sets status='live' +
  -- started_at and emits a 'pool_phase_started' audit event. We only
  -- guard the config here and add the uniform 'started' event after.
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

  -- Materialise confirmed participants into a temp slot table, indexed
  -- 1..v_confirmed in registered_at order. seed = slot index (P6 has no
  -- pre-seeding at start; seed is purely the registration order).
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
  -- Initial seeded pairing: adjacent seeds (1v2, 3v4, ...). An odd
  -- roster gives the highest remaining seed a bye (participant_b NULL).
  -- Later rounds are paired by the client via tournament_pair_round.
  IF v_format IN ('swiss','schoch') THEN
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        participant_a, participant_b, pitch_number, status)
    SELECT
      p_tournament_id,
      1::smallint,
      (((s.slot_idx - 1) / 2) + 1)::smallint,    -- 1,1,2,2,3,3,...
      s.participant_id,                            -- odd slot = participant_a
      part.participant_id,                         -- even slot = participant_b (NULL on bye)
      1,
      'scheduled'
    FROM _tstart_slots s
    LEFT JOIN _tstart_slots part
      ON part.slot_idx = s.slot_idx + 1
    WHERE (s.slot_idx % 2) = 1;                    -- one row per pair, anchored on odd slot

    GET DIAGNOSTICS v_match_count = ROW_COUNT;

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
          'round_count', 1,
          'match_count', v_match_count));
    RETURN;
  END IF;

  -- ---- round_robin: original circle-rotation materialisation --------
  -- Pad to an even number of slots with a virtual NULL bye slot.
  IF (v_confirmed % 2) = 1 THEN
    v_slot_count := v_confirmed + 1;
    INSERT INTO _tstart_slots(slot_idx, participant_id) VALUES (v_slot_count, NULL);
  ELSE
    v_slot_count := v_confirmed;
  END IF;

  v_round_count := v_slot_count - 1;

  -- Working ring used by the rotation. The slot at position 1 stays
  -- fixed; positions 2..v_slot_count rotate clockwise after each round.
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

      -- Normalise so participant_a is always the real participant; bye
      -- matches store NULL in participant_b. Skip the pairing entirely
      -- if both slots are NULL (cannot happen since we pad at most one).
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

    -- Rotate: keep pos 1 fixed, move last into pos 2, shift the rest
    -- down by one. Implemented by re-numbering positions in-place.
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
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start(uuid) TO authenticated;
