-- Start-Pfad-Konvergenz für schoch_then_ko — ADR-0039 §4 (M4 Unit 6, Mangel #1).
--
-- Migration 20261302000000_schoch_then_ko_start_stage_path.sql lässt
-- schoch_then_ko (und swiss_then_ko) beim Start KEINEN flachen RR-Pool mehr
-- materialisieren. Stattdessen leitet tournament_start aus Format +
-- pool_phase_config einen 2-Stufen-Graph ab (Schoch-Root + KO) und bootet ihn
-- über tournament_start_stage_graph. Runde 1 entsteht über den swiss/schoch-
-- Zweig von tournament_generate_stage_matches: Seed-Slide, ceil(N/2) Felder,
-- stage_node_id gesetzt — NICHT N*(N-1)/2 RR-Pairs.
--
-- Geprüft wird:
--   1. Start materialisiert die Schoch-Stufe (config['rounds']=R) + KO-Stufe +
--      top_k-Edge; der Hybrid bleibt NICHT im Pool-Pfad.
--   2. Runde 1 = ceil(N/2) Matches mit stage_node_id NOT NULL (Seed-Slide),
--      KEIN voller RR-Pool (N*(N-1)/2). N=5 -> 3, nicht 10.
--   3. Der Loop ist erreichbar: Runde 1 fertig (r=1 < R=3) -> Stufe bleibt
--      'active', ein 'swiss_round_complete'-Signal (kein vorzeitiger Schluss).
--   4. Regression: round_robin_then_ko startet weiterhin als flacher Pool
--      (stage_node_id NULL, N*(N-1)/2 Matches, keine Stufen).
--   5. Regression: single_elimination wird vom Start nicht unterstützt (0A000) —
--      sein Bracket baut tournament_start_ko_phase, nicht tournament_start.
--
-- Soll-Werte hartkodiert. Alles transient in BEGIN..ROLLBACK.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(21);

-- ---------------------------------------------------------------------
-- Auth-actor switching (wie lifecycle_smoke_test): authentifiziert als
-- Creator via JWT-Claims; Fixtures werden als postgres geseedet.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _stsp_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _stsp_as_pg() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

CREATE OR REPLACE FUNCTION _stsp_p(p_t int, p_idx int) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('00000000-0000-' || lpad(p_t::text, 4, '0') || '-0c0d-'
          || lpad(p_idx::text, 12, '0'))::uuid
$$;

-- =====================================================================
-- Fixture: a schoch_then_ko tournament with N=5 confirmed participants,
-- pool_phase_config carrying schoch_rounds=3 (R) + group_count=1, and
-- ko_config qualifier_count=4 (the top_k edge size). Status
-- registration_closed so tournament_start accepts it.
-- =====================================================================
SELECT _stsp_as_pg();

DO $fixture$
DECLARE
  v_tid uuid := '5c0d0000-0000-0000-0000-00000000a001'::uuid;
  v_org uuid := '5c0d0000-0000-0000-0000-00000000b001'::uuid;
  v_u   uuid;
  i     int;
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (v_org, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated', 'org@stsp.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public,
      pool_phase_config, ko_config, ko_matchup)
    VALUES (v_tid, v_org, 'Schoch Start Konvergenz', 1, 2, 32,
            'schoch_then_ko', 'ekc',
            jsonb_build_object('round_time_seconds', 1800),
            'registration_closed', true,
            jsonb_build_object('group_count', 1, 'qualifiers_per_group', 4,
                               'strategy', 'snake', 'schoch_rounds', 3),
            jsonb_build_object('qualifier_count', 4,
                               'with_third_place_playoff', false,
                               'seeding_mode', 'auto'),
            'seed_high_vs_low');

  FOR i IN 1..5 LOOP
    v_u := _stsp_p(1, 100 + i);
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_u, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated', 'p' || i || '@stsp.local',
              '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, registered_at)
      VALUES (_stsp_p(1, i), v_tid, v_u, 'confirmed',
              '2026-06-01 09:00:00+00'::timestamptz + (i || ' seconds')::interval);
  END LOOP;
END;
$fixture$;

-- ---- Start as the creator ----
SELECT _stsp_as('5c0d0000-0000-0000-0000-00000000b001'::uuid);
SELECT lives_ok(
  $$ SELECT public.tournament_start('5c0d0000-0000-0000-0000-00000000a001'::uuid) $$,
  'schoch_then_ko startet ohne Fehler'
);
SELECT _stsp_as_pg();

-- =====================================================================
-- 1. Stage graph was materialised: a schoch root + a KO stage + top_k edge.
-- =====================================================================
SELECT is(
  (SELECT count(*)::int FROM public.tournament_stages
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid),
  2,
  'zwei Stufen angelegt (Schoch-Root + KO)'
);
SELECT is(
  (SELECT type FROM public.tournament_stages
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND node_id = 'vorrunde'),
  'schoch',
  'Root-Stufe ist type schoch'
);
SELECT is(
  (SELECT (config->>'rounds')::int FROM public.tournament_stages
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND node_id = 'vorrunde'),
  3,
  'config[rounds] = R = 3 (aus pool_phase_config.schoch_rounds)'
);
SELECT is(
  (SELECT type FROM public.tournament_stages
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND node_id = 'ko'),
  'single_elim',
  'KO-Stufe ist single_elim (bracket_type single_elimination, Default-Fall)'
);
SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND node_id = 'vorrunde'),
  'active',
  'Schoch-Root ist nach Start active'
);
SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND node_id = 'ko'),
  'pending',
  'KO-Stufe ist pending (wartet auf Vorrunden-Abschluss)'
);
SELECT is(
  (SELECT (selector->>'k')::int FROM public.tournament_stage_edges
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND from_node_id = 'vorrunde' AND to_node_id = 'ko'),
  4,
  'top_k-Edge k = qualifier_count = 4'
);

-- =====================================================================
-- 2. Round 1 is the seed-slide, NOT a flat RR pool. N=5 (odd) ->
-- floor(5/2)=2 paired matches + 1 BYE = ceil(5/2) = 3 round-1 matches,
-- all carrying stage_node_id = 'vorrunde'. A RR pool would be 5*4/2 = 10.
-- =====================================================================
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND round_number = 1),
  3,
  'Runde 1 hat ceil(N/2)=3 Matches (Seed-Slide), NICHT N*(N-1)/2=10 RR-Pool'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND stage_node_id = 'vorrunde'),
  3,
  'alle 3 Runde-1-Matches tragen stage_node_id = vorrunde (Loop-Voraussetzung)'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND stage_node_id IS NULL),
  0,
  'kein Match ohne stage_node_id (kein flacher Pool)'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND round_number = 1 AND participant_b IS NULL AND status = 'finalized'),
  1,
  'genau ein BYE (finalized) bei ungeradem Feld'
);
SELECT is(
  (SELECT status FROM public.tournaments
    WHERE id = '5c0d0000-0000-0000-0000-00000000a001'::uuid),
  'live',
  'Turnier ist live'
);

-- =====================================================================
-- 3. The runtime loop is reachable: finalise round 1 (the two real matches;
-- the BYE is already finalized). r=1 < R=3 -> the schoch runner keeps the
-- stage active and emits one swiss_round_complete instead of closing.
-- =====================================================================
DO $finalise$
DECLARE
  v_tid uuid := '5c0d0000-0000-0000-0000-00000000a001'::uuid;
  r record;
BEGIN
  FOR r IN
    SELECT id, participant_a FROM public.tournament_matches
     WHERE tournament_id = v_tid AND round_number = 1
       AND status = 'scheduled'
  LOOP
    UPDATE public.tournament_matches
       SET status = 'finalized', winner_participant = r.participant_a,
           final_score_a = 16, final_score_b = 7
     WHERE id = r.id;
  END LOOP;
END;
$finalise$;

SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND node_id = 'vorrunde'),
  'active',
  'r1<R: Schoch-Stufe bleibt active (Loop greift, kein vorzeitiger Schluss)'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_audit_events
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND kind = 'swiss_round_complete'),
  1,
  'r1<R: genau ein swiss_round_complete-Signal (Runner-Loop erreichbar)'
);
SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a001'::uuid
      AND node_id = 'ko'),
  'pending',
  'r1<R: KO-Stufe bleibt pending'
);

-- =====================================================================
-- 4. Regression round_robin_then_ko: starts as a flat pool (stage_node_id
-- NULL, N*(N-1)/2 matches), no stages materialised.
-- =====================================================================
SELECT _stsp_as_pg();
DO $rrk$
DECLARE
  v_tid uuid := '5c0d0000-0000-0000-0000-00000000a002'::uuid;
  v_org uuid := '5c0d0000-0000-0000-0000-00000000b001'::uuid;  -- reuse creator
  v_u   uuid;
  i     int;
BEGIN
  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public,
      pool_phase_config, ko_config)
    VALUES (v_tid, v_org, 'RR then KO Regression', 1, 2, 32,
            'round_robin_then_ko', 'ekc',
            jsonb_build_object('round_time_seconds', 1800),
            'registration_closed', true,
            jsonb_build_object('group_count', 1, 'qualifiers_per_group', 4,
                               'strategy', 'snake'),
            jsonb_build_object('qualifier_count', 4,
                               'with_third_place_playoff', false,
                               'seeding_mode', 'auto'));

  FOR i IN 1..5 LOOP
    v_u := _stsp_p(2, 100 + i);
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_u, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated', 'rr' || i || '@stsp.local',
              '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, registered_at)
      VALUES (_stsp_p(2, i), v_tid, v_u, 'confirmed',
              '2026-06-01 09:00:00+00'::timestamptz + (i || ' seconds')::interval);
  END LOOP;
END;
$rrk$;

SELECT _stsp_as('5c0d0000-0000-0000-0000-00000000b001'::uuid);
SELECT lives_ok(
  $$ SELECT public.tournament_start('5c0d0000-0000-0000-0000-00000000a002'::uuid) $$,
  'round_robin_then_ko startet ohne Fehler'
);
SELECT _stsp_as_pg();

SELECT is(
  (SELECT count(*)::int FROM public.tournament_stages
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a002'::uuid),
  0,
  'Regression RR-then-KO: KEINE Stufen materialisiert (Pool-Pfad unverändert)'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a002'::uuid
      AND phase = 'group'),
  10,
  'Regression RR-then-KO: N*(N-1)/2 = 10 RR-Pool-Matches'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = '5c0d0000-0000-0000-0000-00000000a002'::uuid
      AND stage_node_id IS NOT NULL),
  0,
  'Regression RR-then-KO: stage_node_id bleibt NULL (flacher Pool)'
);

-- =====================================================================
-- 5. Regression single_elimination: tournament_start does not materialise it
-- (0A000 — its bracket is built by tournament_start_ko_phase).
-- =====================================================================
SELECT _stsp_as_pg();
DO $se$
DECLARE
  v_tid uuid := '5c0d0000-0000-0000-0000-00000000a003'::uuid;
  v_org uuid := '5c0d0000-0000-0000-0000-00000000b001'::uuid;
BEGIN
  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, v_org, 'Single Elim Regression', 1, 2, 32,
            'single_elimination', 'ekc',
            jsonb_build_object('round_time_seconds', 1800),
            'registration_closed', true);
  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status, registered_at)
    VALUES
      (_stsp_p(3, 1), v_tid, '5c0d0000-0000-0000-0000-00000000b001'::uuid,
         'confirmed', now()),
      (_stsp_p(3, 2), v_tid,
         (SELECT user_id FROM public.tournament_participants
           WHERE id = _stsp_p(1, 1)),
         'confirmed', now() + interval '1 second');
END;
$se$;

SELECT _stsp_as('5c0d0000-0000-0000-0000-00000000b001'::uuid);
SELECT throws_ok(
  $$ SELECT public.tournament_start('5c0d0000-0000-0000-0000-00000000a003'::uuid) $$,
  '0A000',
  'format not yet supported',
  'Regression single_elimination: Start nicht unterstützt (Bracket via KO-Phase)'
);

SELECT * FROM finish();
ROLLBACK;
