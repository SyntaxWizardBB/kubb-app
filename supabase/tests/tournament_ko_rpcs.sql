-- KO-Phase RPC- und Trigger-Integrationstests (M2.2-T6).
--
-- Deckt die vier KO-Mutationspfade ab:
--   * `tournament_set_seeding`                 (Migration 20260601000012)
--   * `tournament_organizer_override_pairing`  (Migration 20260601000013)
--   * `tournament_start_ko_phase`              (Migration 20260601000015)
--   * `tournament_advance_ko_winner`-Trigger   (Migration 20260601000016)
--
-- Setup: jeweils ein Mini-Turnier mit 4 confirmed-Teilnehmern und
-- finalisierten Group-Matches, ausreichend fuer Bracket-Aufbau (2
-- Halbfinale + 1 Final, optional Third-Place). UUIDs zero-padded
-- analog `bracket_parity.sql`. `auth.uid()` wird via
-- `SET LOCAL request.jwt.claims` auf den jeweiligen Test-Actor
-- umgeschaltet (Supabase-Standard, vgl. pgtap-feasibility.md §Option A).

BEGIN;

SELECT plan(16);

-- ---------------------------------------------------------------------
-- Helpers: Auth-Switch via JWT-Claim + Fixture-Builder.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _t6_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
END;
$$;

CREATE OR REPLACE FUNCTION _t6_as_anon() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
END;
$$;

-- Build a tournament with `n` confirmed participants + a creator user.
-- Returns the tournament_id. Participants are accessible via
-- `_t6_participant(tournament_id, idx)`.
CREATE OR REPLACE FUNCTION _t6_build_tournament(
  p_creator uuid, p_n int, p_with_third_place boolean)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_tid uuid := gen_random_uuid();
  v_uid uuid;
  i int;
BEGIN
  -- Creator-User in auth.users (FK-Pflicht; minimal viable shape).
  INSERT INTO auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
    VALUES (p_creator, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'creator-' || p_creator::text || '@test.local',
            '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format,
      ko_config, status)
    VALUES (
      v_tid, p_creator, 'T6-Test-' || v_tid::text, 1, 2, 64,
      'round_robin_then_ko', 'ekc', '{"format":"best_of_1"}'::jsonb,
      jsonb_build_object('with_third_place_playoff', p_with_third_place,
                         'qualifier_count', p_n),
      'live');

  FOR i IN 1..p_n LOOP
    v_uid := ('00000000-0000-0000-0001-' || lpad(i::text, 12, '0'))::uuid;
    INSERT INTO auth.users (id, instance_id, aud, role, email,
                            encrypted_password, email_confirmed_at,
                            created_at, updated_at)
      VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated',
              'p' || i || '-' || v_tid::text || '@test.local',
              '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, registered_at)
      VALUES (
        ('00000000-0000-0000-0002-' ||
           lpad((i + (abs(hashtext(v_tid::text)) % 1000) * 100)::text, 12, '0'))::uuid,
        v_tid, v_uid, 'confirmed', now() - (p_n - i) * interval '1 second');
  END LOOP;

  RETURN v_tid;
END;
$$;

CREATE OR REPLACE FUNCTION _t6_participant(p_tid uuid, p_idx int)
RETURNS uuid LANGUAGE sql AS $$
  SELECT p.id FROM public.tournament_participants p
    WHERE p.tournament_id = p_tid
    ORDER BY p.registered_at ASC, p.id ASC
    OFFSET p_idx - 1 LIMIT 1;
$$;

-- ---------------------------------------------------------------------
-- 1. tournament_set_seeding — 4 Cases.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_other   uuid := gen_random_uuid();
  v_tid     uuid;
  v_p1      uuid;
  v_p2      uuid;
BEGIN
  v_tid := _t6_build_tournament(v_creator, 4, false);
  v_p1  := _t6_participant(v_tid, 1);
  v_p2  := _t6_participant(v_tid, 2);

  -- Ablage in Temp-Tabelle, damit Folge-Tests Zugriff haben.
  CREATE TEMP TABLE _t6_seed_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_other AS other,
           v_tid AS tid, v_p1 AS p1, v_p2 AS p2;

  -- Foreign user fuer 403-Case auch in auth.users anlegen.
  INSERT INTO auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
    VALUES (v_other, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'other-' || v_other::text || '@test.local',
            '', now(), now(), now());
END $$;

-- Case 1.1: Happy-Path Upsert legt zwei Override-Rows an.
DO $$
DECLARE
  v_ctx record;
BEGIN
  SELECT * INTO v_ctx FROM _t6_seed_ctx;
  PERFORM _t6_as(v_ctx.creator);
  PERFORM public.tournament_set_seeding(
    v_ctx.tid,
    jsonb_build_object(v_ctx.p1::text, 1, v_ctx.p2::text, 2));
END $$;

SELECT is(
  (SELECT count(*)::int FROM public.tournament_seeding_overrides
    WHERE tournament_id = (SELECT tid FROM _t6_seed_ctx)),
  2,
  'set_seeding: Happy-Path schreibt zwei Overrides');

-- Case 1.2: Nicht-Veranstalter → ERRCODE 42501.
SELECT _t6_as((SELECT other FROM _t6_seed_ctx));
SELECT throws_ok(
  format($$
    SELECT public.tournament_set_seeding(
      %L::uuid,
      jsonb_build_object(%L::text, 1))
  $$, (SELECT tid FROM _t6_seed_ctx), (SELECT p1 FROM _t6_seed_ctx)),
  '42501', NULL,
  'set_seeding: Nicht-Veranstalter wird mit 42501 abgewiesen');

-- Case 1.3: INVALID_PARTICIPANT bei fremder participant_id.
SELECT _t6_as((SELECT creator FROM _t6_seed_ctx));
SELECT throws_ok(
  format($$
    SELECT public.tournament_set_seeding(
      %L::uuid,
      jsonb_build_object('00000000-0000-0000-9999-999999999999', 1))
  $$, (SELECT tid FROM _t6_seed_ctx)),
  'P0001', 'INVALID_PARTICIPANT: 1 key(s) not part of this tournament',
  'set_seeding: fremde participant_id → P0001 INVALID_PARTICIPANT');

-- Case 1.4: DUPLICATE_SEED beim gleichen Seed-Wert.
SELECT throws_ok(
  format($$
    SELECT public.tournament_set_seeding(
      %L::uuid,
      jsonb_build_object(%L::text, 3, %L::text, 3))
  $$, (SELECT tid FROM _t6_seed_ctx),
       (SELECT p1 FROM _t6_seed_ctx),
       (SELECT p2 FROM _t6_seed_ctx)),
  'P0001', 'DUPLICATE_SEED: same seed assigned to multiple participants',
  'set_seeding: doppelter Seed-Wert → P0001 DUPLICATE_SEED');

-- ---------------------------------------------------------------------
-- 2. tournament_organizer_override_pairing — 4 Cases.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
  v_p1      uuid;
  v_p2      uuid;
  v_p3      uuid;
  v_p4      uuid;
  v_m1      uuid := gen_random_uuid();
  v_m2      uuid := gen_random_uuid();
BEGIN
  v_tid := _t6_build_tournament(v_creator, 4, false);
  v_p1  := _t6_participant(v_tid, 1);
  v_p2  := _t6_participant(v_tid, 2);
  v_p3  := _t6_participant(v_tid, 3);
  v_p4  := _t6_participant(v_tid, 4);

  -- Zwei scheduled KO-Matches in derselben Runde (Halbfinale).
  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      bracket_position, participant_a, participant_b,
      phase, status)
    VALUES
      (v_m1, v_tid, 1, 1, 1, v_p1, v_p2, 'ko', 'scheduled'),
      (v_m2, v_tid, 1, 2, 2, v_p3, v_p4, 'ko', 'scheduled');

  CREATE TEMP TABLE _t6_ovr_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_tid AS tid,
           v_p1 AS p1, v_p2 AS p2, v_p3 AS p3, v_p4 AS p4,
           v_m1 AS m1, v_m2 AS m2;
END $$;

-- Case 2.1: Happy-Path Tausch (p1 ↔ p3 zwischen den beiden Halbfinalen).
DO $$
DECLARE
  v_ctx record;
BEGIN
  SELECT * INTO v_ctx FROM _t6_ovr_ctx;
  PERFORM _t6_as(v_ctx.creator);
  -- Schritt 1: m1 von (p1, p2) auf (p3, p2) — p1 muss vorher aus m2.
  UPDATE public.tournament_matches
    SET participant_a = v_ctx.p1, participant_b = v_ctx.p4
    WHERE id = v_ctx.m2;
  PERFORM public.tournament_organizer_override_pairing(
    v_ctx.m1, v_ctx.p3, v_ctx.p2, 'Spielerwunsch: Tausch m1 ↔ m2');
END $$;

SELECT is(
  (SELECT participant_a FROM public.tournament_matches
    WHERE id = (SELECT m1 FROM _t6_ovr_ctx)),
  (SELECT p3 FROM _t6_ovr_ctx),
  'override_pairing: Happy-Path setzt neue participant_a (p3)');

SELECT is(
  (SELECT participant_b FROM public.tournament_matches
    WHERE id = (SELECT m1 FROM _t6_ovr_ctx)),
  (SELECT p2 FROM _t6_ovr_ctx),
  'override_pairing: Happy-Path setzt neue participant_b (p2)');

-- Case 2.2: MISSING_REASON bei NULL.
SELECT _t6_as((SELECT creator FROM _t6_ovr_ctx));
SELECT throws_ok(
  format($$
    SELECT public.tournament_organizer_override_pairing(
      %L::uuid, %L::uuid, %L::uuid, NULL)
  $$, (SELECT m1 FROM _t6_ovr_ctx),
       (SELECT p1 FROM _t6_ovr_ctx),
       (SELECT p4 FROM _t6_ovr_ctx)),
  '22023', 'MISSING_REASON: override reason must be 1..500 chars',
  'override_pairing: NULL reason → 22023 MISSING_REASON');

-- Case 2.3: MATCH_ALREADY_STARTED bei status='awaiting_results'.
DO $$
BEGIN
  UPDATE public.tournament_matches
    SET status = 'awaiting_results'
    WHERE id = (SELECT m2 FROM _t6_ovr_ctx);
END $$;

SELECT throws_ok(
  format($$
    SELECT public.tournament_organizer_override_pairing(
      %L::uuid, %L::uuid, %L::uuid, 'Grund')
  $$, (SELECT m2 FROM _t6_ovr_ctx),
       (SELECT p1 FROM _t6_ovr_ctx),
       (SELECT p3 FROM _t6_ovr_ctx)),
  '22023', 'MATCH_ALREADY_STARTED: match status is awaiting_results, expected scheduled',
  'override_pairing: bereits gestartet → 22023 MATCH_ALREADY_STARTED');

-- Case 2.4: PARTICIPANT_CONFLICT — Teilnehmer bereits in anderer
-- Runden-Paarung. m2 enthaelt (p1, p4); Versuch m1 auf (p1, p3) zu
-- aendern muss scheitern.
DO $$
BEGIN
  UPDATE public.tournament_matches
    SET status = 'scheduled' WHERE id = (SELECT m2 FROM _t6_ovr_ctx);
END $$;

SELECT throws_ok(
  format($$
    SELECT public.tournament_organizer_override_pairing(
      %L::uuid, %L::uuid, %L::uuid, 'Konfliktversuch')
  $$, (SELECT m1 FROM _t6_ovr_ctx),
       (SELECT p1 FROM _t6_ovr_ctx),
       (SELECT p3 FROM _t6_ovr_ctx)),
  '22023', 'PARTICIPANT_CONFLICT: participant already paired in round 1',
  'override_pairing: gepaarter Spieler → 22023 PARTICIPANT_CONFLICT');

-- ---------------------------------------------------------------------
-- 3. tournament_start_ko_phase — 3 Cases.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
BEGIN
  v_tid := _t6_build_tournament(v_creator, 4, true);
  CREATE TEMP TABLE _t6_start_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_tid AS tid;
END $$;

-- Case 3.1: Happy-Path mit 4 Teilnehmern + Third-Place
--           → 2 Halbfinale + 1 Final + 1 Third-Place = 4 Matches.
DO $$
DECLARE
  v_ctx record;
BEGIN
  SELECT * INTO v_ctx FROM _t6_start_ctx;
  PERFORM _t6_as(v_ctx.creator);
  PERFORM public.tournament_start_ko_phase(
    v_ctx.tid,
    jsonb_build_object(
      'qualifier_count', 4,
      'with_third_place_playoff', true));
END $$;

SELECT results_eq(
  $$
    SELECT phase, count(*)::int
      FROM public.tournament_matches
     WHERE tournament_id = (SELECT tid FROM _t6_start_ctx)
     GROUP BY phase
     ORDER BY phase;
  $$,
  $$
    VALUES ('final', 1), ('ko', 2), ('third_place', 1)
  $$,
  'start_ko_phase: n=4 erzeugt 2 Halbfinale + 1 Final + 1 Third-Place');

-- Case 3.2: ALREADY_STARTED → ERRCODE 40001 (Idempotency).
SELECT throws_ok(
  format($$
    SELECT public.tournament_start_ko_phase(
      %L::uuid,
      jsonb_build_object('qualifier_count', 4,
                         'with_third_place_playoff', true))
  $$, (SELECT tid FROM _t6_start_ctx)),
  '40001', 'ALREADY_STARTED: ko phase already initialised',
  'start_ko_phase: zweiter Aufruf → 40001 ALREADY_STARTED (Idempotency)');

-- Case 3.3: PHASE_NOT_COMPLETE bei einem disputed Group-Match.
DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
  v_p1      uuid;
  v_p2      uuid;
BEGIN
  v_tid := _t6_build_tournament(v_creator, 4, false);
  v_p1  := _t6_participant(v_tid, 1);
  v_p2  := _t6_participant(v_tid, 2);
  -- Ein offenes Group-Match blockiert die Phase-Transition.
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status)
    VALUES (v_tid, 1, 1, v_p1, v_p2, 'group', 'disputed');
  CREATE TEMP TABLE _t6_start_blk_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_tid AS tid;
END $$;

SELECT _t6_as((SELECT creator FROM _t6_start_blk_ctx));
SELECT throws_ok(
  format($$
    SELECT public.tournament_start_ko_phase(
      %L::uuid,
      jsonb_build_object('qualifier_count', 4,
                         'with_third_place_playoff', false))
  $$, (SELECT tid FROM _t6_start_blk_ctx)),
  '22023', NULL,
  'start_ko_phase: disputed Group-Match → 22023 PHASE_NOT_COMPLETE');

-- ---------------------------------------------------------------------
-- 4. tournament_advance_ko_winner-Trigger — 4 Cases.
-- ---------------------------------------------------------------------

-- Setup: frisches Turnier mit 4 confirmed Teilnehmern, KO-Phase bereits
-- via RPC gestartet (Third-Place aktiv). Damit existieren:
--   round 1, bracket_position 1 / phase=ko        → Halbfinale 1
--   round 1, bracket_position 2 / phase=ko        → Halbfinale 2
--   round 2, bracket_position 1 / phase=final     → Finale
--   round 2, bracket_position 1 / phase=third_place

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
  v_sf1     uuid;
  v_sf2     uuid;
  v_sf1_a   uuid;
  v_sf1_b   uuid;
  v_sf2_a   uuid;
BEGIN
  v_tid := _t6_build_tournament(v_creator, 4, true);
  PERFORM _t6_as(v_creator);
  PERFORM public.tournament_start_ko_phase(
    v_tid, jsonb_build_object('qualifier_count', 4,
                              'with_third_place_playoff', true));

  -- IDs der beiden Halbfinale auslesen.
  SELECT id, participant_a, participant_b INTO v_sf1, v_sf1_a, v_sf1_b
    FROM public.tournament_matches
    WHERE tournament_id = v_tid AND phase = 'ko'
      AND round_number = 1 AND bracket_position = 1;
  SELECT id, participant_a INTO v_sf2, v_sf2_a
    FROM public.tournament_matches
    WHERE tournament_id = v_tid AND phase = 'ko'
      AND round_number = 1 AND bracket_position = 2;

  CREATE TEMP TABLE _t6_trig_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_tid AS tid,
           v_sf1 AS sf1, v_sf2 AS sf2,
           v_sf1_a AS sf1_a, v_sf1_b AS sf1_b,
           v_sf2_a AS sf2_a;
END $$;

-- Case 4.1: Halbfinal-Sieger landet im Final-Slot participant_a (sf1
-- ist bracket_position=1 → ungerade → Sieger nach participant_a).
DO $$
DECLARE
  v_ctx record;
BEGIN
  SELECT * INTO v_ctx FROM _t6_trig_ctx;
  UPDATE public.tournament_matches
    SET status = 'finalized',
        winner_participant = v_ctx.sf1_a,
        final_score_a = 6, final_score_b = 3,
        finalized_at = now()
    WHERE id = v_ctx.sf1;
END $$;

SELECT is(
  (SELECT participant_a FROM public.tournament_matches
    WHERE tournament_id = (SELECT tid FROM _t6_trig_ctx)
      AND phase = 'final'),
  (SELECT sf1_a FROM _t6_trig_ctx),
  'advance_ko_winner: Halbfinal-Sieger (sf1, pos=1) landet in Final.participant_a');

-- Case 4.2: Halbfinal-Verlierer landet im Third-Place-Slot
-- participant_a (gleiches Slot-Mapping wie 4.1).
SELECT is(
  (SELECT participant_a FROM public.tournament_matches
    WHERE tournament_id = (SELECT tid FROM _t6_trig_ctx)
      AND phase = 'third_place'),
  (SELECT sf1_b FROM _t6_trig_ctx),
  'advance_ko_winner: Halbfinal-Verlierer landet in Third-Place.participant_a (with_third_place=true)');

-- Case 4.3: Walkover-Pfad — sf2 wird via reines
-- `winner_participant`-Setzen (kein final_score) finalisiert.
-- Trigger muss trotzdem propagieren (Forfeit-Kompatibilitaet).
DO $$
DECLARE
  v_ctx record;
BEGIN
  SELECT * INTO v_ctx FROM _t6_trig_ctx;
  UPDATE public.tournament_matches
    SET status = 'finalized',
        winner_participant = v_ctx.sf2_a,
        finalized_at = now()
    WHERE id = v_ctx.sf2;
END $$;

SELECT is(
  (SELECT participant_b FROM public.tournament_matches
    WHERE tournament_id = (SELECT tid FROM _t6_trig_ctx)
      AND phase = 'final'),
  (SELECT sf2_a FROM _t6_trig_ctx),
  'advance_ko_winner: Walkover (winner ohne Score) propagiert in Final.participant_b');

-- Case 4.4: Final-Status wurde durch beidseitiges Fuellen auf
-- `awaiting_results` promoted (vorher `scheduled`).
SELECT is(
  (SELECT status FROM public.tournament_matches
    WHERE tournament_id = (SELECT tid FROM _t6_trig_ctx)
      AND phase = 'final'),
  'awaiting_results',
  'advance_ko_winner: Folge-Match scheduled → awaiting_results bei vollen Slots');

SELECT * FROM finish();

ROLLBACK;
