-- Server-Idempotenz-Tests fuer `tournament_propose_set_score` (TASK-M4.3-T3).
--
-- Merge-Gate fuer M4.3 (R-M4.3-1): verifiziert das Verhalten der mit
-- Migration `20260701000003_score_rpc_idempotency.sql` eingefuehrten
-- 6-Parameter-Variante (Lamport-Counter + Device-Id) sowie das
-- weiterhin gueltige UPSERT-Verhalten der 4-Parameter-Legacy-Variante.
--
-- Pflicht-Cases (tasks.md §M4.3-T3):
--   1. Erster Submit lamport=5/device='dev-A' → Row mit lamport_counter=5.
--   2. Zweiter identischer Submit → kein neuer Row (Partial-UNIQUE-DEDUP).
--   3. Legacy-4-Param-Pfad ohne Lamport → Rows skalieren mit set_index.
--   4. Submits lamport=5 + lamport=6 (gleicher Slot, gleiches Device)
--      → eine Row, in-place ersetzt, lamport=6 persistiert (DSCORE-30).
--   5. Submits lamport=5 dev-A + lamport=5 dev-B (gleicher Slot)
--      → eine Row, in-place ersetzt, device='dev-B' persistiert.
--
-- Cases 4/5 erzwingen REPLACE-Semantik: derselbe Submitter hat pro
-- Versuch (consensus_round) und Set genau eine aktuelle Eingabe
-- (unique_slot). Ein Outbox-Flush mit neuem Lamport ersetzt die alte,
-- statt mit 23505 auf unique_slot zu kollidieren.
--
-- Pattern: Auth-Switch via `set_config('request.jwt.claims', ...)` plus
-- `set_config('role','authenticated', ...)` analog `tournament_ko_rpcs.sql`.

BEGIN;

SELECT plan(9);

-- ---------------------------------------------------------------------
-- Helpers: Auth-Switch + Fixture-Seed.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _t3_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _t3_as_postgres() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

-- Seedet Creator-User, Turnier mit einem `confirmed`-Participant und ein
-- `scheduled`-Match. Match-Status ist Whitelist-konform (vgl.
-- `_tournament_validate_set_proposal`), `consensus_round` startet auf
-- dem Default 1. `participant_b` bleibt NULL (nullable Spalte) — die
-- Validierungs-Helper schauen nur auf status/consensus_round/score.
CREATE OR REPLACE FUNCTION _t3_seed_match(OUT match_id uuid, OUT user_id uuid)
LANGUAGE plpgsql AS $$
DECLARE
  v_tid uuid := gen_random_uuid();
  v_pa  uuid := gen_random_uuid();
BEGIN
  user_id  := gen_random_uuid();
  match_id := gen_random_uuid();

  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    VALUES (user_id, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'idem-' || user_id::text || '@test.local',
            '', now(), now(), now());

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status)
    VALUES (v_tid, user_id, 'Idempotency-Test-' || v_tid::text, 1, 2, 16,
            'round_robin', 'ekc', '{"format":"best_of_3"}'::jsonb,
            'live');

  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status)
    VALUES (v_pa, v_tid, user_id, 'confirmed');

  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, status)
    VALUES (match_id, v_tid, 1, 1, v_pa, 'scheduled');
END;
$$;

-- Convenience: zaehlt Proposal-Rows fuer ein Match (alle Sets/Rounds).
CREATE OR REPLACE FUNCTION _t3_count(p_match uuid) RETURNS int
LANGUAGE sql AS $$
  SELECT count(*)::int FROM public.tournament_set_score_proposals
    WHERE match_id = p_match;
$$;

-- ---------------------------------------------------------------------
-- Case 1: Idempotenter Erst-Submit landet als Row mit lamport_counter=5.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_match uuid;
  v_user  uuid;
BEGIN
  SELECT s.match_id, s.user_id INTO v_match, v_user FROM _t3_seed_match() s;
  PERFORM _t3_as(v_user);
  PERFORM public.tournament_propose_set_score(
    v_match, 1, 1,
    '{"basekubbs_a":6,"basekubbs_b":3,"winner":"A"}'::jsonb,
    5, 'dev-A');
  PERFORM _t3_as_postgres();

  CREATE TEMP TABLE _t3_ctx1 ON COMMIT DROP AS
    SELECT v_match AS match_id, v_user AS user_id;
END $$;

SELECT is(_t3_count((SELECT match_id FROM _t3_ctx1)),
         1,
         'Case 1: erster idempotenter Submit erzeugt genau eine Row');

SELECT is(
  (SELECT lamport_counter FROM public.tournament_set_score_proposals
     WHERE match_id = (SELECT match_id FROM _t3_ctx1)),
  5,
  'Case 1: lamport_counter wurde mit 5 persistiert');

-- ---------------------------------------------------------------------
-- Case 2: Re-Submit mit identischem Tupel → No-Op via Partial-UNIQUE.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_ctx record;
BEGIN
  SELECT * INTO v_ctx FROM _t3_ctx1;
  PERFORM _t3_as(v_ctx.user_id);
  PERFORM public.tournament_propose_set_score(
    v_ctx.match_id, 1, 1,
    '{"basekubbs_a":6,"basekubbs_b":3,"winner":"A"}'::jsonb,
    5, 'dev-A');
  PERFORM _t3_as_postgres();
END $$;

SELECT is(_t3_count((SELECT match_id FROM _t3_ctx1)),
         1,
         'Case 2: identischer Re-Submit erzeugt keinen neuen Row');

-- ---------------------------------------------------------------------
-- Case 3: Legacy-4-Param-Variante schreibt pro distinctem (set_index)
--         eine Row (Partial-UNIQUE greift nicht ohne Lamport).
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_match uuid;
  v_user  uuid;
BEGIN
  SELECT s.match_id, s.user_id INTO v_match, v_user FROM _t3_seed_match() s;
  PERFORM _t3_as(v_user);
  -- 4-Argument-Overload → Legacy-UPSERT-Pfad (kein lamport_counter).
  PERFORM public.tournament_propose_set_score(
    v_match, 1, 1,
    '{"basekubbs_a":6,"basekubbs_b":4,"winner":"A"}'::jsonb);
  PERFORM public.tournament_propose_set_score(
    v_match, 1, 2,
    '{"basekubbs_a":3,"basekubbs_b":6,"winner":"B"}'::jsonb);
  PERFORM _t3_as_postgres();

  CREATE TEMP TABLE _t3_ctx3 ON COMMIT DROP AS
    SELECT v_match AS match_id;
END $$;

SELECT is(
  (SELECT count(*)::int FROM public.tournament_set_score_proposals
     WHERE match_id = (SELECT match_id FROM _t3_ctx3)
       AND lamport_counter IS NULL),
  2,
  'Case 3: Legacy-Pfad schreibt zwei Rows mit lamport_counter IS NULL');

-- ---------------------------------------------------------------------
-- Case 4: Zwei Submits selber Slot, selbes Device, gebumpter Lamport
--         (Outbox-Flush nach korrigierter Eingabe) → eine Row, in-place
--         ersetzt. unique_slot bleibt total, der neue Lamport gewinnt.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_match uuid;
  v_user  uuid;
BEGIN
  SELECT s.match_id, s.user_id INTO v_match, v_user FROM _t3_seed_match() s;
  PERFORM _t3_as(v_user);
  PERFORM public.tournament_propose_set_score(
    v_match, 1, 1,
    '{"basekubbs_a":6,"basekubbs_b":2,"winner":"A"}'::jsonb,
    5, 'dev-A');
  PERFORM public.tournament_propose_set_score(
    v_match, 1, 1,
    '{"basekubbs_a":6,"basekubbs_b":5,"winner":"A"}'::jsonb,
    6, 'dev-A');
  PERFORM _t3_as_postgres();

  CREATE TEMP TABLE _t3_ctx4 ON COMMIT DROP AS
    SELECT v_match AS match_id;
END $$;

SELECT is(_t3_count((SELECT match_id FROM _t3_ctx4)),
         1,
         'Case 4: gebumpter Lamport ersetzt in-place, eine Row');

SELECT is(
  (SELECT lamport_counter FROM public.tournament_set_score_proposals
     WHERE match_id = (SELECT match_id FROM _t3_ctx4)),
  6,
  'Case 4: der neuere Lamport-Counter 6 wurde persistiert');

-- ---------------------------------------------------------------------
-- Case 5: Gleicher Lamport, gewechseltes Device, selber Slot → eine Row,
--         in-place ersetzt, das zuletzt gesehene Device gewinnt.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_match uuid;
  v_user  uuid;
BEGIN
  SELECT s.match_id, s.user_id INTO v_match, v_user FROM _t3_seed_match() s;
  PERFORM _t3_as(v_user);
  PERFORM public.tournament_propose_set_score(
    v_match, 1, 1,
    '{"basekubbs_a":6,"basekubbs_b":2,"winner":"A"}'::jsonb,
    5, 'dev-A');
  PERFORM public.tournament_propose_set_score(
    v_match, 1, 1,
    '{"basekubbs_a":6,"basekubbs_b":4,"winner":"A"}'::jsonb,
    5, 'dev-B');
  PERFORM _t3_as_postgres();

  CREATE TEMP TABLE _t3_ctx5 ON COMMIT DROP AS
    SELECT v_match AS match_id;
END $$;

SELECT is(
  (SELECT device_id FROM public.tournament_set_score_proposals
     WHERE match_id = (SELECT match_id FROM _t3_ctx5)),
  'dev-B',
  'Case 5: bei einer Row gewinnt das zuletzt gesehene Device dev-B');

-- ---------------------------------------------------------------------
-- Case 6: Identischer Replay (gleicher Lamport + Device) ist ein echtes
--         No-Op — der WHERE-Guard unterdrückt das UPDATE, proposed_at
--         bleibt unverändert (kein Row-Churn bei Netz-Retry).
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_match uuid;
  v_user  uuid;
  v_first timestamptz;
BEGIN
  SELECT s.match_id, s.user_id INTO v_match, v_user FROM _t3_seed_match() s;
  PERFORM _t3_as(v_user);
  PERFORM public.tournament_propose_set_score(
    v_match, 1, 1,
    '{"basekubbs_a":6,"basekubbs_b":3,"winner":"A"}'::jsonb,
    5, 'dev-A');
  SELECT proposed_at INTO v_first
    FROM public.tournament_set_score_proposals WHERE match_id = v_match;
  PERFORM pg_sleep(0.01);
  PERFORM public.tournament_propose_set_score(
    v_match, 1, 1,
    '{"basekubbs_a":6,"basekubbs_b":3,"winner":"A"}'::jsonb,
    5, 'dev-A');
  PERFORM _t3_as_postgres();

  CREATE TEMP TABLE _t3_ctx6 ON COMMIT DROP AS
    SELECT v_match AS match_id, v_first AS first_proposed_at;
END $$;

SELECT is(
  (SELECT proposed_at FROM public.tournament_set_score_proposals
     WHERE match_id = (SELECT match_id FROM _t3_ctx6)),
  (SELECT first_proposed_at FROM _t3_ctx6),
  'Case 6: identischer Replay lässt proposed_at unverändert (No-Op)');

-- ---------------------------------------------------------------------
-- Case 7: Echter Konflikt zweier Submitter im selben Versuch/Set bleibt
--         zwei Rows — der Konsens-Vergleich (ADR-0007) liest weiter eine
--         kanonische Zeile pro Seite. Replace darf das nicht stilllegen.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_match uuid;
  v_user_a uuid;
  v_user_b uuid := gen_random_uuid();
BEGIN
  SELECT s.match_id, s.user_id INTO v_match, v_user_a FROM _t3_seed_match() s;
  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    VALUES (v_user_b, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'idem-b-' || v_user_b::text || '@test.local',
            '', now(), now(), now());

  PERFORM _t3_as(v_user_a);
  PERFORM public.tournament_propose_set_score(
    v_match, 1, 1,
    '{"basekubbs_a":6,"basekubbs_b":2,"winner":"A"}'::jsonb,
    5, 'dev-A');
  PERFORM _t3_as(v_user_b);
  PERFORM public.tournament_propose_set_score(
    v_match, 1, 1,
    '{"basekubbs_a":2,"basekubbs_b":6,"winner":"B"}'::jsonb,
    7, 'dev-B');
  PERFORM _t3_as_postgres();

  CREATE TEMP TABLE _t3_ctx7 ON COMMIT DROP AS
    SELECT v_match AS match_id;
END $$;

SELECT is(_t3_count((SELECT match_id FROM _t3_ctx7)),
         2,
         'Case 7: zwei verschiedene Submitter behalten je eine eigene Row');

SELECT * FROM finish();

ROLLBACK;
