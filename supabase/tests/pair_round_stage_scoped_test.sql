-- Stage-scoped tournament_pair_round — ADR-0039 §3 (HIGH-2/3, Server-Seite).
--
-- Migration 20261301000000_pair_round_stage_scoped.sql erweitert
-- tournament_pair_round um einen additiven Parameter p_stage_node_id text
-- DEFAULT NULL. Dieser Test deckt beide Pfade ab:
--
--   * NULL-Pfad (Backward-Compat): ein flaches Swiss-Szenario ohne Stufen.
--     tournament_pair_round(tid, 'swiss_system', pairings) fügt Runde 1 mit
--     stage_node_id NULL ein — byte-identisch zum bisherigen Verhalten.
--   * Stage-scoped-Pfad: eine aktive Schoch-Stufe mit terminaler Runde 1.
--     tournament_pair_round(tid, 'swiss_system', pairings, p_stage_node_id := X)
--     fügt Runde 2 mit stage_node_id = X ein. Geprüft werden ausserdem das
--     runden-scoped Progression-Gate (Runde 1 NICHT terminal -> round_not_complete)
--     und die stage-scoped Validierung (eine Paarung, die nur in einer ANDEREN
--     Stufe vorkam, gilt NICHT als Wiederholung).
--
-- Soll-Werte sind hartkodiert (echtes Oracle). Alles läuft transient in
-- BEGIN..ROLLBACK; nichts wird persistiert.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

-- ---------------------------------------------------------------------
-- Fixture identifiers (flat tournament).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _prs_flat_tid() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5c0d0000-0000-0000-0000-0000000000f1'::uuid $$;
CREATE OR REPLACE FUNCTION _prs_flat_creator() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5c0d0000-0000-0000-0000-0000000000f2'::uuid $$;
CREATE OR REPLACE FUNCTION _prs_flat_p(p_idx int) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('00000000-0000-0000-0f1a-' || lpad(p_idx::text, 12, '0'))::uuid
$$;

-- Stage tournament identifiers.
CREATE OR REPLACE FUNCTION _prs_tid() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5c0d0000-0000-0000-0000-0000000000a1'::uuid $$;
CREATE OR REPLACE FUNCTION _prs_creator() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5c0d0000-0000-0000-0000-0000000000a2'::uuid $$;
CREATE OR REPLACE FUNCTION _prs_p(p_idx int) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('00000000-0000-0000-0a1a-' || lpad(p_idx::text, 12, '0'))::uuid
$$;

-- Pairing-JSON-Builder (wire shape per validate_swiss_pairing: participant_a /
-- participant_b; a NULL b is a bye).
CREATE OR REPLACE FUNCTION _prs_pair(p_pairs uuid[][])
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_arr jsonb := '[]'::jsonb; i int;
BEGIN
  FOR i IN 1 .. array_length(p_pairs, 1) LOOP
    v_arr := v_arr || jsonb_build_array(jsonb_build_object(
      'participant_a', p_pairs[i][1]::text,
      'participant_b', CASE WHEN p_pairs[i][2] IS NULL THEN NULL
                            ELSE p_pairs[i][2]::text END));
  END LOOP;
  RETURN v_arr;
END;
$$;

-- Acts as the given user (authenticated), used right before each RPC call.
CREATE OR REPLACE FUNCTION _prs_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text,
                       'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

-- =====================================================================
-- Fixtures (seeded as postgres so RLS / auth do not block the inserts).
-- =====================================================================
SET LOCAL ROLE postgres;

DO $fixture$
DECLARE
  v_u int;
BEGIN
  -- ---- Flat tournament: 8 confirmed participants, no stage nodes. ----
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (_prs_flat_creator(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated', 'flat-org@prs.local', '',
            now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (_prs_flat_tid(), _prs_flat_creator(), 'Flat Swiss', 1, 4, 16,
            'schoch', 'ekc', '{"format":"best_of_1"}'::jsonb, 'live', true);

  FOR v_u IN 1..8 LOOP
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (('00000000-0000-0000-0f1b-' || lpad(v_u::text, 12, '0'))::uuid,
              '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated', 'fp' || v_u || '@prs.local',
              '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, seed)
      VALUES (_prs_flat_p(v_u), _prs_flat_tid(),
              ('00000000-0000-0000-0f1b-' || lpad(v_u::text, 12, '0'))::uuid,
              'confirmed', v_u);
  END LOOP;

  -- ---- Stage tournament: schoch stage sw1 (active, R=3), plus a second
  --      schoch stage sw2 used only to seed a cross-stage pairing. ----
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (_prs_creator(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated', 'stage-org@prs.local', '',
            now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (_prs_tid(), _prs_creator(), 'Stage Schoch', 1, 2, 32,
            'schoch_then_ko', 'ekc',
            jsonb_build_object('round_time_seconds', 1800), 'live', true);

  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES
      (gen_random_uuid(), _prs_tid(), 'sw1', 'schoch',
         jsonb_build_object('rounds', 3), 'as_routed', 'active'),
      (gen_random_uuid(), _prs_tid(), 'sw2', 'schoch',
         jsonb_build_object('rounds', 3), 'as_routed', 'active');

  FOR v_u IN 1..4 LOOP
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (('00000000-0000-0000-0a1b-' || lpad(v_u::text, 12, '0'))::uuid,
              '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated', 'sp' || v_u || '@prs.local',
              '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, seed)
      VALUES (_prs_p(v_u), _prs_tid(),
              ('00000000-0000-0000-0a1b-' || lpad(v_u::text, 12, '0'))::uuid,
              'confirmed', v_u);
  END LOOP;

  -- sw1 round 1: P1-P3, P2-P4, all finalized (terminal -> next round pairable).
  INSERT INTO public.tournament_matches(
      id, tournament_id, stage_node_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, winner_participant,
      final_score_a, final_score_b, finalized_at)
    VALUES
      (gen_random_uuid(), _prs_tid(), 'sw1', 1, 1, _prs_p(1), _prs_p(3),
         'group', 'finalized', _prs_p(1), 16, 5, now()),
      (gen_random_uuid(), _prs_tid(), 'sw1', 1, 2, _prs_p(2), _prs_p(4),
         'group', 'finalized', _prs_p(2), 16, 5, now());

  -- sw2 round 1: P1-P2 finalized. This pairing exists ONLY in sw2, so a
  -- stage-scoped validate over sw1 must NOT see it as a repeat.
  INSERT INTO public.tournament_matches(
      id, tournament_id, stage_node_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, winner_participant,
      final_score_a, final_score_b, finalized_at)
    VALUES
      (gen_random_uuid(), _prs_tid(), 'sw2', 1, 1, _prs_p(1), _prs_p(2),
         'group', 'finalized', _prs_p(1), 16, 5, now());
END;
$fixture$;

-- =====================================================================
-- A. NULL path — backward compatibility.
-- =====================================================================
SELECT _prs_as(_prs_flat_creator());

SELECT lives_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %L::jsonb) $$,
    _prs_flat_tid(),
    _prs_pair(ARRAY[
      ARRAY[_prs_flat_p(1), _prs_flat_p(2)], ARRAY[_prs_flat_p(3), _prs_flat_p(4)],
      ARRAY[_prs_flat_p(5), _prs_flat_p(6)], ARRAY[_prs_flat_p(7), _prs_flat_p(8)]])),
  'NULL-Pfad: valides 8-Spieler-Pairing wird angenommen');

SET LOCAL ROLE postgres;

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _prs_flat_tid() AND round_number = 1),
  4,
  'NULL-Pfad: genau 4 Matches in Runde 1 eingefügt');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _prs_flat_tid() AND stage_node_id IS NOT NULL),
  0,
  'NULL-Pfad: alle eingefügten Matches haben stage_node_id NULL');

SELECT is(
  (SELECT payload ->> 'stage_node_id' FROM public.tournament_audit_events
    WHERE tournament_id = _prs_flat_tid() AND kind = 'swiss_round_paired'),
  NULL,
  'NULL-Pfad: swiss_round_paired-Audit ohne stage_node_id (flache Form)');

-- =====================================================================
-- B. Stage-scoped path — round-scoped progression gate.
--    sw2 round 1 is terminal, but the new round must be paired on sw1; the
--    gate looks at sw1's highest round (1, terminal) -> pairing is allowed.
--    To prove the negative, voiding one sw1 round-1 match would re-open it,
--    so first test the gate against a NON-terminal stage.
-- =====================================================================

-- B1: round_not_complete when the stage's current round still has an open
--     match. Temporarily set one sw1 match back to scheduled.
SET LOCAL ROLE postgres;
UPDATE public.tournament_matches
   SET status = 'scheduled', winner_participant = NULL, finalized_at = NULL
 WHERE tournament_id = _prs_tid() AND stage_node_id = 'sw1'
   AND match_number_in_round = 2;

SELECT _prs_as(_prs_creator());
SELECT throws_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %L::jsonb, %L) $$,
    _prs_tid(),
    _prs_pair(ARRAY[
      ARRAY[_prs_p(1), _prs_p(2)], ARRAY[_prs_p(3), _prs_p(4)]]),
    'sw1'),
  '22023', NULL,
  'Stage-scoped: nicht-terminale Runde 1 -> round_not_complete');

-- Restore sw1 round 1 to terminal for the happy-path tests.
SET LOCAL ROLE postgres;
UPDATE public.tournament_matches
   SET status = 'finalized', winner_participant = _prs_p(2),
       final_score_a = 16, final_score_b = 5, finalized_at = now()
 WHERE tournament_id = _prs_tid() AND stage_node_id = 'sw1'
   AND match_number_in_round = 2;

-- B2: invalid stage type / inactive stage rejection — a non-existent node.
SELECT _prs_as(_prs_creator());
SELECT throws_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %L::jsonb, %L) $$,
    _prs_tid(),
    _prs_pair(ARRAY[ARRAY[_prs_p(1), _prs_p(2)]]),
    'nope'),
  'P0002', NULL,
  'Stage-scoped: unbekannte Stufe -> stage_not_found');

-- =====================================================================
-- C. Stage-scoped happy path: pair sw1 round 2.
--    P1-P2 played in sw2 (not sw1), so it is a LEGAL pairing for sw1 and
--    must be accepted (stage-scoped repeat check).
-- =====================================================================
SELECT _prs_as(_prs_creator());
SELECT lives_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %L::jsonb, %L) $$,
    _prs_tid(),
    _prs_pair(ARRAY[
      ARRAY[_prs_p(1), _prs_p(2)], ARRAY[_prs_p(3), _prs_p(4)]]),
    'sw1'),
  'Stage-scoped: gültige sw1-Runde-2-Paarung wird angenommen (Cross-Stage-Paarung gilt nicht als Repeat)');

SET LOCAL ROLE postgres;

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _prs_tid() AND stage_node_id = 'sw1'
      AND round_number = 2),
  2,
  'Stage-scoped: 2 Matches in sw1-Runde 2 mit stage_node_id = sw1');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _prs_tid() AND stage_node_id = 'sw2'),
  1,
  'Stage-scoped: sw2 bleibt unverändert (keine fremde Stufe berührt)');

SELECT is(
  (SELECT payload ->> 'stage_node_id' FROM public.tournament_audit_events
    WHERE tournament_id = _prs_tid() AND kind = 'swiss_round_paired'
      AND payload ->> 'round_number' = '2'),
  'sw1',
  'Stage-scoped: swiss_round_paired-Audit trägt stage_node_id = sw1');

-- =====================================================================
-- D. Stage-scoped repeat detection within the SAME stage.
--    P1-P3 already played in sw1 round 1 -> pairing it again is a repeat.
-- =====================================================================

-- Finalize sw1 round 2 so the gate lets round 3 through.
SET LOCAL ROLE postgres;
UPDATE public.tournament_matches
   SET status = 'finalized', winner_participant = participant_a,
       final_score_a = 16, final_score_b = 5, finalized_at = now()
 WHERE tournament_id = _prs_tid() AND stage_node_id = 'sw1'
   AND round_number = 2;

SELECT _prs_as(_prs_creator());
SELECT throws_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %L::jsonb, %L) $$,
    _prs_tid(),
    _prs_pair(ARRAY[
      ARRAY[_prs_p(1), _prs_p(3)], ARRAY[_prs_p(2), _prs_p(4)]]),
    'sw1'),
  '22023', NULL,
  'Stage-scoped: in sw1 bereits gespielte Paarung P1-P3 -> invalid_pairing (Repeat)');

SET LOCAL ROLE postgres;

SELECT * FROM finish();

ROLLBACK;
