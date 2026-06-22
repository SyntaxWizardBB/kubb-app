-- Trust-Boundary-Tests fuer `tournament_pair_round` Swiss-Dispatch
-- (TASK-M5.2-T9, R-M5.2-2). Die Validierungs-Funktion
-- `validate_swiss_pairing` (Migration 20260801000001, stage-scoped
-- erweitert in 20261301000000) muss die vier Misuse-Vektoren ablehnen:
-- fehlender Teilnehmer, Doppel-Zuordnung, Repeat (Pairing existierte in
-- einer Vorrunde) und Bye-Konflikt (Spieler hatte bereits ein Bye).
--
-- Live-Vertrag (siehe Migration):
--   tournament_pair_round(p_tournament_id uuid, p_strategy text,
--                         p_pairings jsonb, p_stage_node_id text DEFAULT NULL)
--   * p_strategy muss 'swiss_system' sein, sonst No-op.
--   * Wire-Shape: [{"participant_a": <uuid>, "participant_b": <uuid>|null}].
--     participant_b NULL markiert ein Bye.
--   * Die Rundennummer wird serverseitig aus max(round_number)+1 abgeleitet.
--   * Verletzungen werfen ERRCODE 22023 mit MESSAGE-Prefix 'invalid_pairing'.
--
-- Jeder Misuse-Vektor läuft gegen ein FRISCHES Swiss-Turnier ohne
-- Vorrunde: damit ist die erste Paarung die Runde 1, das runden-scoped
-- Progression-Gate (max(round_number) IS NULL) greift nicht, und die
-- Validierung ist allein verantwortlich für den Fehler. Der Bye-Konflikt
-- braucht eine finalisierte (terminale) Bye-Vorrunde — die zählt fürs
-- Gate als abgeschlossen, sodass die zweite Paarung die Validierung
-- erreicht. Stage-scoped Pfad + Repeat-innerhalb-Stufe sind in
-- pair_round_stage_scoped_test.sql abgedeckt.

BEGIN;

SELECT plan(5);

CREATE OR REPLACE FUNCTION _pair_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text,
                       'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

-- Deterministische Teilnehmer-uuid: ein Tag pro Turnier, Seed als Suffix.
-- Damit braucht der Lookup keine TEMP-Tabelle und _pid ist eine reine
-- Funktion (Pattern aus pair_round_stage_scoped_test.sql).
CREATE OR REPLACE FUNCTION _pid(p_tag text, p_seed int) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('00000000-0000-0000-' || p_tag || '-' || lpad(p_seed::text, 12, '0'))::uuid
$$;

-- Seedet ein frisches live-Swiss-Turnier mit p_n confirmed Participants.
-- Turnier-id und Organizer-id sind aus dem Tag abgeleitet (eindeutig je
-- Misuse-Vektor). Läuft als postgres, damit RLS/Auth die Seeds nicht
-- blockieren.
CREATE OR REPLACE FUNCTION _pair_seed(p_tag text, p_n int) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_tid uuid := ('00000000-0000-0000-' || p_tag || '-0000000000a1')::uuid;
  v_org uuid := ('00000000-0000-0000-' || p_tag || '-0000000000a2')::uuid;
  v_uid uuid; i int;
BEGIN
  PERFORM set_config('role', 'postgres', true);

  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (v_org, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'org-' || p_tag || '@t.l', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(id, created_by, display_name, team_size,
      min_participants, max_participants, format, scoring, match_format,
      status, public)
    VALUES (v_tid, v_org, 'Swiss-' || p_tag, 1, 4, 16, 'swiss', 'ekc',
            '{"format":"best_of_1"}'::jsonb, 'live', true);

  FOR i IN 1..p_n LOOP
    v_uid := ('00000000-0000-0000-' || p_tag || '-' || lpad((900 + i)::text, 12, '0'))::uuid;
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated',
              'p' || i || '-' || p_tag || '@t.l', '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status)
      VALUES (_pid(p_tag, i), v_tid, v_uid, 'confirmed');
  END LOOP;

  RETURN v_tid;
END;
$$;

-- Pairing-JSON-Builder konform zur Live-Wire-Spec:
-- [{"participant_a": <uuid>, "participant_b": <uuid>|null}, ...].
CREATE OR REPLACE FUNCTION _pair_json(p_pairs uuid[][])
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_arr jsonb := '[]'::jsonb; i int;
BEGIN
  FOR i IN 1..array_length(p_pairs, 1) LOOP
    v_arr := v_arr || jsonb_build_array(jsonb_build_object(
      'participant_a', p_pairs[i][1]::text,
      'participant_b', CASE WHEN p_pairs[i][2] IS NULL THEN NULL
                           ELSE p_pairs[i][2]::text END));
  END LOOP;
  RETURN v_arr;
END;
$$;

-- Seeds: ein frisches Turnier pro Misuse-Vektor.
DO $$
BEGIN
  PERFORM _pair_seed('1111', 8);  -- valides Pairing
  PERFORM _pair_seed('2222', 8);  -- fehlender Teilnehmer
  PERFORM _pair_seed('3333', 8);  -- Doppel-Zuordnung
  PERFORM _pair_seed('4444', 8);  -- Repeat
  PERFORM _pair_seed('5555', 9);  -- Bye-Konflikt (ungerade Teilnehmerzahl)
END $$;

-- 1. Valides 8-Spieler-Pairing (4 Pairs, Runde 1) → Matches inserted.
SELECT _pair_as(('00000000-0000-0000-1111-0000000000a2')::uuid);

SELECT lives_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %L::jsonb) $$,
    ('00000000-0000-0000-1111-0000000000a1')::uuid,
    _pair_json(ARRAY[
      ARRAY[_pid('1111', 1), _pid('1111', 2)], ARRAY[_pid('1111', 3), _pid('1111', 4)],
      ARRAY[_pid('1111', 5), _pid('1111', 6)], ARRAY[_pid('1111', 7), _pid('1111', 8)]])),
  'tournament_pair_round: valides 8-Spieler-Pairing → Matches inserted');

-- 2. Fehlender Teilnehmer: nur 7 reale Spieler gepaart, der achte Slot
--    nennt eine nicht-confirmte uuid → invalid_pairing.
SELECT _pair_as(('00000000-0000-0000-2222-0000000000a2')::uuid);

SELECT throws_like(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %L::jsonb) $$,
    ('00000000-0000-0000-2222-0000000000a1')::uuid,
    _pair_json(ARRAY[
      ARRAY[_pid('2222', 1), _pid('2222', 2)], ARRAY[_pid('2222', 3), _pid('2222', 4)],
      ARRAY[_pid('2222', 5), _pid('2222', 6)], ARRAY[_pid('2222', 7), gen_random_uuid()]])),
  'invalid_pairing%',
  'tournament_pair_round: fehlender/unbekannter Teilnehmer → invalid_pairing');

-- 3. Doppel-Zuordnung (Seed 1 in zwei Pairings) → invalid_pairing.
SELECT _pair_as(('00000000-0000-0000-3333-0000000000a2')::uuid);

SELECT throws_like(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %L::jsonb) $$,
    ('00000000-0000-0000-3333-0000000000a1')::uuid,
    _pair_json(ARRAY[
      ARRAY[_pid('3333', 1), _pid('3333', 2)], ARRAY[_pid('3333', 1), _pid('3333', 4)],
      ARRAY[_pid('3333', 5), _pid('3333', 6)], ARRAY[_pid('3333', 7), _pid('3333', 8)]])),
  'invalid_pairing%',
  'tournament_pair_round: Doppel-Zuordnung → invalid_pairing');

-- 4. Repeat: eine in Runde 1 gespielte Paarung (1-2) erneut anbieten.
--    Runde 1 wird terminal geseedet, damit das Progression-Gate die
--    zweite Paarung durchlässt und die Repeat-Prüfung greift.
DO $$
DECLARE v_tid uuid := ('00000000-0000-0000-4444-0000000000a1')::uuid;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.tournament_matches(id, tournament_id, round_number,
      match_number_in_round, participant_a, participant_b, status, finalized_at)
    VALUES
      (gen_random_uuid(), v_tid, 1, 1, _pid('4444', 1), _pid('4444', 2), 'finalized', now()),
      (gen_random_uuid(), v_tid, 1, 2, _pid('4444', 3), _pid('4444', 4), 'finalized', now()),
      (gen_random_uuid(), v_tid, 1, 3, _pid('4444', 5), _pid('4444', 6), 'finalized', now()),
      (gen_random_uuid(), v_tid, 1, 4, _pid('4444', 7), _pid('4444', 8), 'finalized', now());
END $$;

SELECT _pair_as(('00000000-0000-0000-4444-0000000000a2')::uuid);

SELECT throws_like(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %L::jsonb) $$,
    ('00000000-0000-0000-4444-0000000000a1')::uuid,
    _pair_json(ARRAY[
      ARRAY[_pid('4444', 1), _pid('4444', 2)], ARRAY[_pid('4444', 3), _pid('4444', 5)],
      ARRAY[_pid('4444', 4), _pid('4444', 6)], ARRAY[_pid('4444', 7), _pid('4444', 8)]])),
  'invalid_pairing%',
  'tournament_pair_round: Repeat-Pairing (1-2 aus Runde 1) → invalid_pairing');

-- 5. Bye-Konflikt: Seed 9 hatte in einer terminalen Vorrunde bereits ein
--    Bye; eine neue Paarung vergibt erneut ein Bye an Seed 9
--    → invalid_pairing (FR-PAIR-5: max. 1 Bye pro Spieler).
DO $$
DECLARE v_tid uuid := ('00000000-0000-0000-5555-0000000000a1')::uuid;
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO public.tournament_matches(id, tournament_id, round_number,
      match_number_in_round, participant_a, participant_b, status, finalized_at)
    VALUES
      (gen_random_uuid(), v_tid, 1, 1, _pid('5555', 1), _pid('5555', 2), 'finalized', now()),
      (gen_random_uuid(), v_tid, 1, 2, _pid('5555', 3), _pid('5555', 4), 'finalized', now()),
      (gen_random_uuid(), v_tid, 1, 3, _pid('5555', 5), _pid('5555', 6), 'finalized', now()),
      (gen_random_uuid(), v_tid, 1, 4, _pid('5555', 7), _pid('5555', 8), 'finalized', now()),
      (gen_random_uuid(), v_tid, 1, 5, _pid('5555', 9), NULL, 'finalized', now());
END $$;

SELECT _pair_as(('00000000-0000-0000-5555-0000000000a2')::uuid);

SELECT throws_like(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %L::jsonb) $$,
    ('00000000-0000-0000-5555-0000000000a1')::uuid,
    _pair_json(ARRAY[
      ARRAY[_pid('5555', 1), _pid('5555', 3)], ARRAY[_pid('5555', 2), _pid('5555', 4)],
      ARRAY[_pid('5555', 5), _pid('5555', 6)], ARRAY[_pid('5555', 7), _pid('5555', 8)],
      ARRAY[_pid('5555', 9), NULL::uuid]])),
  'invalid_pairing%',
  'tournament_pair_round: Bye-Konflikt (Seed 9 hatte bereits Bye) → invalid_pairing');

SELECT * FROM finish();

ROLLBACK;
