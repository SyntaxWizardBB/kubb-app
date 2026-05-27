-- Trust-Boundary-Tests fuer `tournament_pair_round` Swiss-Dispatch
-- (TASK-M5.2-T9, R-M5.2-2). Validierungs-Funktion
-- `validate_swiss_pairing(p_tournament_id, p_pairings jsonb)` aus T8
-- muss die vier Misuse-Vektoren ablehnen: fehlender Teilnehmer,
-- Doppel-Zuordnung, Repeat (Pairing existierte in Vorrunde) und
-- Bye-Konflikt (Spieler hatte bereits Bye).

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

-- Seedet ein Swiss-Turnier mit 8 confirmed Participants. Exponiert
-- `_pair_ctx(tournament_id, organizer_uid)` + `_pair_ctx_participants
-- (seed, participant_id, user_id)` als TEMP-Tables. `_pid(seed)` ist
-- ein Lookup-Shortcut fuer die nachfolgenden Pairing-Konstrukte.
CREATE OR REPLACE FUNCTION _pair_seed_tournament(p_status text DEFAULT 'live')
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_tid uuid := gen_random_uuid();
  v_org uuid := gen_random_uuid();
  v_uid uuid; v_pid uuid; i int;
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (v_org, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'org-' || v_org::text || '@t.l', '', now(), now(), now());

  INSERT INTO public.tournaments(id, created_by, display_name, team_size,
      min_participants, max_participants, format, scoring, match_format,
      status, public)
    VALUES (v_tid, v_org, 'Swiss-T9', 1, 4, 16, 'swiss_system', 'ekc',
            '{"format":"best_of_1"}'::jsonb, p_status, true);

  CREATE TEMP TABLE IF NOT EXISTS _pair_ctx_participants(
    seed int, participant_id uuid, user_id uuid) ON COMMIT DROP;

  FOR i IN 1..8 LOOP
    v_uid := gen_random_uuid(); v_pid := gen_random_uuid();
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated',
              'p' || i || '-' || v_uid::text || '@t.l',
              '', now(), now(), now());
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status)
      VALUES (v_pid, v_tid, v_uid, 'confirmed');
    INSERT INTO _pair_ctx_participants VALUES (i, v_pid, v_uid);
  END LOOP;

  CREATE TEMP TABLE IF NOT EXISTS _pair_ctx ON COMMIT DROP AS
    SELECT v_tid AS tournament_id, v_org AS organizer_uid;
  RETURN v_tid;
END;
$$;

CREATE OR REPLACE FUNCTION _pid(p_seed int) RETURNS uuid
LANGUAGE sql AS $$
  SELECT participant_id FROM _pair_ctx_participants WHERE seed = p_seed
$$;

-- Pairing-JSON-Builder. Format konform zur T8-Spec:
-- `[{"round": N, "a": <uuid>, "b": <uuid> | null}, ...]`.
CREATE OR REPLACE FUNCTION _pair_json(p_round int, p_pairs uuid[][])
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_arr jsonb := '[]'::jsonb; i int;
BEGIN
  FOR i IN 1..array_length(p_pairs, 1) LOOP
    v_arr := v_arr || jsonb_build_array(jsonb_build_object(
      'round', p_round, 'a', p_pairs[i][1]::text,
      'b', CASE WHEN p_pairs[i][2] IS NULL THEN NULL
                ELSE p_pairs[i][2]::text END));
  END LOOP;
  RETURN v_arr;
END;
$$;

DO $$ BEGIN PERFORM _pair_seed_tournament('live'); END $$;

-- 1. Valid Pairing (alle 8 Spieler, 4 Pairs, Runde 1) → Matches inserted.
SELECT _pair_as((SELECT organizer_uid FROM _pair_ctx));

SELECT lives_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 1, %L::jsonb) $$,
    (SELECT tournament_id FROM _pair_ctx),
    _pair_json(1, ARRAY[
      ARRAY[_pid(1), _pid(2)], ARRAY[_pid(3), _pid(4)],
      ARRAY[_pid(5), _pid(6)], ARRAY[_pid(7), _pid(8)]])),
  'tournament_pair_round: valides 8-Spieler-Pairing → Matches inserted');

-- 2. Fehlender Teilnehmer (Seed 8 fehlt) → invalid_pairing.
SELECT throws_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 2, %L::jsonb) $$,
    (SELECT tournament_id FROM _pair_ctx),
    _pair_json(2, ARRAY[
      ARRAY[_pid(1), _pid(2)], ARRAY[_pid(3), _pid(4)],
      ARRAY[_pid(5), _pid(6)], ARRAY[_pid(7), NULL::uuid]])),
  'P0001', 'invalid_pairing',
  'tournament_pair_round: fehlender Teilnehmer → invalid_pairing');

-- 3. Doppel-Zuordnung (Seed 1 in zwei Pairings) → invalid_pairing.
SELECT throws_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 2, %L::jsonb) $$,
    (SELECT tournament_id FROM _pair_ctx),
    _pair_json(2, ARRAY[
      ARRAY[_pid(1), _pid(2)], ARRAY[_pid(1), _pid(4)],
      ARRAY[_pid(5), _pid(6)], ARRAY[_pid(7), _pid(8)]])),
  'P0001', 'invalid_pairing',
  'tournament_pair_round: Doppel-Zuordnung → invalid_pairing');

-- 4. Repeat (Pairing 1-2 existierte in Runde 1) → invalid_pairing.
SELECT throws_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 2, %L::jsonb) $$,
    (SELECT tournament_id FROM _pair_ctx),
    _pair_json(2, ARRAY[
      ARRAY[_pid(1), _pid(2)], ARRAY[_pid(3), _pid(5)],
      ARRAY[_pid(4), _pid(6)], ARRAY[_pid(7), _pid(8)]])),
  'P0001', 'invalid_pairing',
  'tournament_pair_round: Repeat-Pairing → invalid_pairing');

-- 5. Bye-Konflikt: Seed 9 hinzu (ungerade Teilnehmerzahl); Seed 9 hatte
--    in Runde 3 bereits Bye; Runde 4 vergibt erneut Bye an Seed 9
--    → invalid_pairing (FR-PAIR-5: max. 1 Bye pro Spieler).
DO $$
DECLARE
  v_tid uuid := (SELECT tournament_id FROM _pair_ctx);
  v_uid uuid := gen_random_uuid();
  v_p9  uuid := gen_random_uuid();
BEGIN
  PERFORM set_config('role', 'postgres', true);
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'p9-' || v_uid::text || '@t.l', '', now(), now(), now());
  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status)
    VALUES (v_p9, v_tid, v_uid, 'confirmed');
  INSERT INTO _pair_ctx_participants VALUES (9, v_p9, v_uid);
  INSERT INTO public.tournament_matches(id, tournament_id, round_number,
      match_number_in_round, participant_a, participant_b, status)
    VALUES (gen_random_uuid(), v_tid, 3, 1, v_p9, NULL, 'finalized');
  PERFORM set_config('role', 'authenticated', true);
END $$;

SELECT _pair_as((SELECT organizer_uid FROM _pair_ctx));

SELECT throws_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 4, %L::jsonb) $$,
    (SELECT tournament_id FROM _pair_ctx),
    _pair_json(4, ARRAY[
      ARRAY[_pid(1), _pid(3)], ARRAY[_pid(2), _pid(4)],
      ARRAY[_pid(5), _pid(6)], ARRAY[_pid(7), _pid(8)],
      ARRAY[_pid(9), NULL::uuid]])),
  'P0001', 'invalid_pairing',
  'tournament_pair_round: Bye-Konflikt (Seed 9 hatte bereits Bye) → invalid_pairing');

SELECT * FROM finish();

ROLLBACK;
