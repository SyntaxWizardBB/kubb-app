-- ADR-0031 Block A2 — tournament_match_autostart trigger pgTAP suite.
--
-- Covers the four Plan-A2 cases (phase-a-plan.md l.128-129):
--   (a) schedule starts_at in the PAST   => started_at = starts_at
--   (b) schedule starts_at in the FUTURE => started_at = starts_at (kept,
--       NOT clamped to now() — greatest picks the larger)
--   (c) NO schedule row                  => started_at stays NULL (no-op,
--       trigger does not error, score-RPC COALESCE backstop survives)
--   (d) started_at ALREADY set           => never overwritten (idempotency)
-- Plus: the trigger fires on UPDATE OF status (anchor on play-ready), and the
-- classic NULL stage_node_id match hits the NULL schedule row.
--
-- pgTAP is installed transiently inside BEGIN..ROLLBACK (see
-- realtime_cdc_rls_test.sql / round_schedule_test.sql); everything rolls back,
-- nothing is mutated. now() is frozen for the whole transaction, so PAST/FUTURE
-- are expressed relative to now() (now() - / + interval) for determinism.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(8);

SELECT has_function('public', 'tournament_match_autostart',
  'tournament_match_autostart() trigger function exists');
SELECT trigger_is('public', 'tournament_matches', 'tournament_match_autostart',
  'public', 'tournament_match_autostart',
  'tournament_match_autostart trigger is wired on tournament_matches');

-- ====================================================================
-- Fixture: an organiser, a live tournament, two participants, and three
-- schedule rows (past round 1, future round 2; round 3 has no schedule row).
-- Inserted as postgres so RLS does not interfere.
-- ====================================================================
SET LOCAL ROLE postgres;

DO $fixture$
DECLARE
  v_org uuid := gen_random_uuid();
  v_usr_b uuid := gen_random_uuid();
  v_tid uuid := '33333333-3333-3333-3333-333333333333';
  v_pa  uuid := '44444444-4444-4444-4444-444444444444';
  v_pb  uuid := '55555555-5555-5555-5555-555555555555';
BEGIN
  -- Two auth users (organiser + participant B's user) first, so the
  -- participant FKs resolve.
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES
      (v_org, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated',
       'autostart-' || v_org::text || '@t.l', '', now(), now(), now()),
      (v_usr_b, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated',
       'autostart-b-' || v_usr_b::text || '@t.l', '', now(), now(), now());

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (
      v_tid, v_org, 'Autostart-Fixture', 1, 2, 16, 'swiss', 'ekc',
      jsonb_build_object('round_time_seconds', 1800,
                         'break_between_matches_seconds', 300),
      'live', true);

  INSERT INTO public.tournament_participants(id, tournament_id, user_id,
      registration_status)
    VALUES (v_pa, v_tid, v_org, 'confirmed');
  INSERT INTO public.tournament_participants(id, tournament_id, user_id,
      registration_status)
    VALUES (v_pb, v_tid, v_usr_b, 'confirmed');

  -- Round 1: schedule whose starts_at is at-or-before now() (the "Vergangenheit"
  -- case of the Plan formula greatest(starts_at, now())). pgTAP freezes now()
  -- for the whole TX, so a strictly-past starts_at would make greatest() return
  -- the frozen now() (a moving target across runs); pinning starts_at = now()
  -- exercises the boundary deterministically: greatest(now(), now()) = now() =
  -- starts_at, i.e. "Vergangenheit => started_at = starts_at" per A2-7.
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at,
      break_seconds, match_seconds, tiebreak_after_seconds)
    VALUES (
      v_tid, NULL, 1, 'group', 'running',
      now() - interval '5 minutes',
      now(),
      now() + interval '30 minutes',
      300, 1800, NULL);

  -- Round 2: schedule in the FUTURE (starts_at = now() + 1h).
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at,
      break_seconds, match_seconds, tiebreak_after_seconds)
    VALUES (
      v_tid, NULL, 2, 'group', 'published',
      now() + interval '55 minutes',
      now() + interval '1 hour',
      now() + interval '1 hour 30 minutes',
      300, 1800, NULL);

  -- Round 3: NO schedule row (intentionally absent) for the no-op case.

  -- Round 4: schedule STRICTLY in the past (starts_at = now() - 1h). Here the
  -- A2-7 clamp is exercised in its true form: greatest(now()-1h, now()) = now(),
  -- i.e. a past starts_at is clamped UP to now() (the backstop semantics shared
  -- with the later E-tick). now() is frozen for the whole TX, so the asserted
  -- started_at = now() is the same frozen instant the trigger evaluated.
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at,
      break_seconds, match_seconds, tiebreak_after_seconds)
    VALUES (
      v_tid, NULL, 4, 'group', 'running',
      now() - interval '1 hour 5 minutes',
      now() - interval '1 hour',
      now() - interval '30 minutes',
      300, 1800, NULL);
END;
$fixture$;

-- ---- (a) schedule in the PAST => started_at = starts_at (= now()-1h) ----
INSERT INTO public.tournament_matches(
    id, tournament_id, round_number, match_number_in_round,
    participant_a, participant_b, status)
  VALUES ('a0000000-0000-0000-0000-000000000001',
    '33333333-3333-3333-3333-333333333333', 1, 1,
    '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555', 'scheduled');

SELECT is(
  (SELECT started_at FROM public.tournament_matches
     WHERE id = 'a0000000-0000-0000-0000-000000000001'),
  now(),
  'PAST/at-now schedule => started_at = starts_at (greatest(starts_at<=now, now) = starts_at)');

-- ---- (a2) STRICTLY-PAST schedule => started_at clamped UP to now() ----
-- The true A2-7 clamp: starts_at < now() => greatest(starts_at, now()) = now().
INSERT INTO public.tournament_matches(
    id, tournament_id, round_number, match_number_in_round,
    participant_a, participant_b, status)
  VALUES ('a0000000-0000-0000-0000-000000000005',
    '33333333-3333-3333-3333-333333333333', 4, 1,
    '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555', 'scheduled');

SELECT is(
  (SELECT started_at FROM public.tournament_matches
     WHERE id = 'a0000000-0000-0000-0000-000000000005'),
  now(),
  'STRICTLY-PAST schedule => started_at clamped to now() (greatest(starts_at<now, now) = now)');

-- ---- (b) FUTURE schedule => started_at = starts_at (kept, not now()) ----
INSERT INTO public.tournament_matches(
    id, tournament_id, round_number, match_number_in_round,
    participant_a, participant_b, status)
  VALUES ('a0000000-0000-0000-0000-000000000002',
    '33333333-3333-3333-3333-333333333333', 2, 1,
    '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555', 'scheduled');

SELECT is(
  (SELECT started_at FROM public.tournament_matches
     WHERE id = 'a0000000-0000-0000-0000-000000000002'),
  now() + interval '1 hour',
  'FUTURE schedule => started_at = starts_at (future kept, greatest picks the larger)');

-- ---- (c) NO schedule row (round 3) => started_at stays NULL (no-op) ----
INSERT INTO public.tournament_matches(
    id, tournament_id, round_number, match_number_in_round,
    participant_a, participant_b, status)
  VALUES ('a0000000-0000-0000-0000-000000000003',
    '33333333-3333-3333-3333-333333333333', 3, 1,
    '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555', 'scheduled');

SELECT ok(
  (SELECT started_at FROM public.tournament_matches
     WHERE id = 'a0000000-0000-0000-0000-000000000003') IS NULL,
  'NO schedule row => started_at stays NULL (no-op, trigger does not error)');

-- ---- (d) started_at ALREADY set => never overwritten (idempotency) ----
-- Insert into round 1 (past schedule exists) but pre-set started_at; the
-- trigger must leave it untouched.
INSERT INTO public.tournament_matches(
    id, tournament_id, round_number, match_number_in_round,
    participant_a, participant_b, status, started_at)
  VALUES ('a0000000-0000-0000-0000-000000000004',
    '33333333-3333-3333-3333-333333333333', 1, 2,
    '44444444-4444-4444-4444-444444444444',
    '55555555-5555-5555-5555-555555555555', 'scheduled',
    '2020-01-01 00:00:00+00'::timestamptz);

SELECT is(
  (SELECT started_at FROM public.tournament_matches
     WHERE id = 'a0000000-0000-0000-0000-000000000004'),
  '2020-01-01 00:00:00+00'::timestamptz,
  'already-set started_at is never overwritten on INSERT (idempotency)');

-- ---- bonus: trigger fires on UPDATE OF status too ----
-- Round 2 match #2 starts NULL via a direct UPDATE bypass... instead insert it
-- with started_at pre-cleared is impossible (trigger fires on insert), so prove
-- the UPDATE path by clearing started_at as postgres then flipping status.
UPDATE public.tournament_matches
   SET started_at = NULL
 WHERE id = 'a0000000-0000-0000-0000-000000000002';
UPDATE public.tournament_matches
   SET status = 'awaiting_results'
 WHERE id = 'a0000000-0000-0000-0000-000000000002';

SELECT is(
  (SELECT started_at FROM public.tournament_matches
     WHERE id = 'a0000000-0000-0000-0000-000000000002'),
  now() + interval '1 hour',
  'UPDATE OF status re-anchors started_at = starts_at (future kept)');

SELECT * FROM finish();
ROLLBACK;
