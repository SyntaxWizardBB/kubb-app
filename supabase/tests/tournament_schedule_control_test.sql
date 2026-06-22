-- ADR-0031 Block B2s — schedule-control RPC pgTAP suite.
--
-- Covers (B2s-DoD-14):
--   (a) Gate: a club referee / creator is allowed; a non-manager third party
--       gets 42501.
--   (b) pause then resume accumulates the correct paused_accum_seconds and
--       clears paused_at.
--   (c) pause idempotency: a 2nd consecutive pause does not advance paused_at.
--   (d) skip_forward / skip_back state transitions incl. pause-clear.
--   (e) terminal / completed-row guard: a 'completed' row is unchanged by every
--       RPC.
--   (f) tournament_matches rows (incl. a finalised match) unchanged after every
--       RPC (running / finalised matches immune).
--
-- pgTAP runs inside BEGIN..ROLLBACK; nothing is mutated permanently. now() is
-- frozen within the TX (README K7), so pause/resume intervals are deterministic
-- (0 in-TX): we assert the structural invariants (clears, idempotency,
-- transitions, immunity) that hold regardless of wall-clock advance.
-- Auth context is switched via set_config('request.jwt.claims', ...).

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(26);

-- ---------------------------------------------------------------------
-- Helpers: auth-switch + minimal auth user.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _sc_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _sc_mk_user(p_uid uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (p_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'u-' || p_uid::text || '@t.l', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;
  RETURN p_uid;
END;
$$;

-- ====================================================================
-- Fixture (as postgres): one club with a referee + a stranger; a creator; a
-- live club tournament with an ACTIVE ('running') schedule row, a COMPLETED
-- schedule row (terminal guard), and matches incl. a finalised one (immunity).
-- ====================================================================
SET LOCAL ROLE postgres;

DO $fixture$
DECLARE
  v_creator  uuid := '63333333-3333-3333-3333-333333333301';
  v_referee  uuid := '63333333-3333-3333-3333-333333333302';
  v_stranger uuid := '63333333-3333-3333-3333-333333333303';
  v_club     uuid := '64444444-4444-4444-4444-444444444401';
  v_tour     uuid := '65555555-5555-5555-5555-555555555501';
  v_pa       uuid;
  v_pb       uuid;
BEGIN
  PERFORM _sc_mk_user(v_creator);
  PERFORM _sc_mk_user(v_referee);
  PERFORM _sc_mk_user(v_stranger);

  INSERT INTO public.organizer_teams(id, display_name, created_by)
    VALUES (v_club, 'SC-Club', v_creator);

  -- referee: ONLY the 'referee' role (manager via K4); stranger: no membership.
  INSERT INTO public.team_members(organizer_team_id, user_id, roles)
    VALUES (v_club, v_referee, ARRAY['referee']::text[]);

  INSERT INTO public.tournaments(
      id, created_by, organizer_team_id, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES
      (v_tour, v_creator, v_club, 'SC-Live', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800,
                          'break_between_matches_seconds', 300),
       'live', true);

  -- ACTIVE round (round 2): status 'running', break 300, match 1800.
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds,
      paused_at, paused_accum_seconds)
    VALUES (v_tour, NULL, 2, 'group', 'running',
            now() - interval '400 seconds',
            now() - interval '100 seconds',
            now() + interval '1700 seconds',
            300, 1800, NULL, 0);

  -- TERMINAL round (round 1): status 'completed' — must stay unchanged.
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds,
      paused_at, paused_accum_seconds)
    VALUES (v_tour, NULL, 1, 'group', 'completed',
            now() - interval '4000 seconds',
            now() - interval '3700 seconds',
            now() - interval '1900 seconds',
            300, 1800, NULL, 0);

  -- Matches incl. a finalised (terminal) one — must stay byte-for-byte immune.
  INSERT INTO public.tournament_participants(id, tournament_id, user_id, registration_status)
    VALUES (gen_random_uuid(), v_tour, v_referee, 'confirmed') RETURNING id INTO v_pa;
  INSERT INTO public.tournament_participants(id, tournament_id, user_id, registration_status)
    VALUES (gen_random_uuid(), v_tour, v_stranger, 'confirmed') RETURNING id INTO v_pb;

  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round, participant_a, participant_b, status)
    VALUES
      (v_tour, 2, 1, v_pa, v_pb, 'scheduled'),
      (v_tour, 1, 1, v_pa, v_pb, 'finalized');
END;
$fixture$;

-- Snapshot tournament_matches so we can assert byte-for-byte immunity later.
CREATE TEMP TABLE _sc_matches_before AS
  SELECT * FROM public.tournament_matches
   WHERE tournament_id = '65555555-5555-5555-5555-555555555501';

-- Snapshot the completed (terminal) schedule row for the terminal guard.
CREATE TEMP TABLE _sc_completed_before AS
  SELECT * FROM public.tournament_round_schedule
   WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
     AND status = 'completed';

-- ====================================================================
-- (a) Gate: non-manager stranger -> 42501 on every RPC.
-- ====================================================================
SELECT _sc_as('63333333-3333-3333-3333-333333333303'); -- stranger

SELECT throws_ok(
  $$ SELECT public.tournament_pause('65555555-5555-5555-5555-555555555501') $$,
  '42501', NULL, 'pause: non-manager stranger raises 42501');
SELECT throws_ok(
  $$ SELECT public.tournament_resume('65555555-5555-5555-5555-555555555501') $$,
  '42501', NULL, 'resume: non-manager stranger raises 42501');
SELECT throws_ok(
  $$ SELECT public.tournament_skip_forward('65555555-5555-5555-5555-555555555501') $$,
  '42501', NULL, 'skip_forward: non-manager stranger raises 42501');
SELECT throws_ok(
  $$ SELECT public.tournament_skip_back('65555555-5555-5555-5555-555555555501') $$,
  '42501', NULL, 'skip_back: non-manager stranger raises 42501');

-- Gate: creator and referee are allowed (no throw).
SELECT _sc_as('63333333-3333-3333-3333-333333333301'); -- creator
SELECT lives_ok(
  $$ SELECT public.tournament_pause('65555555-5555-5555-5555-555555555501') $$,
  'pause: creator is allowed (no throw)');

SELECT _sc_as('63333333-3333-3333-3333-333333333302'); -- referee
SELECT lives_ok(
  $$ SELECT public.tournament_resume('65555555-5555-5555-5555-555555555501') $$,
  'resume: referee (K4) is allowed (no throw)');

-- ====================================================================
-- (b) pause then resume: paused_at set, then cleared; accum stays sane.
--     now() is frozen in-TX so the interval is 0; assert structural invariants.
-- ====================================================================
SELECT _sc_as('63333333-3333-3333-3333-333333333302'); -- referee

-- Clean slate on the active row.
SET LOCAL ROLE postgres;
UPDATE public.tournament_round_schedule
   SET paused_at = NULL, paused_accum_seconds = 0
 WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
   AND status = 'running';
SELECT _sc_as('63333333-3333-3333-3333-333333333302');

SELECT public.tournament_pause('65555555-5555-5555-5555-555555555501');
-- Verifikations-Reads laufen direkt auf der Tabelle — als postgres, da der
-- Caller-Kontext oben 'referee' war (Direkt-Read trifft sonst die tournaments-
-- RLS-Subquery → 42501). Vor dem nächsten RPC zurück auf referee.
SET LOCAL ROLE postgres;
SELECT ok(
  (SELECT paused_at IS NOT NULL FROM public.tournament_round_schedule
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND status = 'running'),
  'pause: paused_at is set on the active row');

SELECT _sc_as('63333333-3333-3333-3333-333333333302');
SELECT public.tournament_resume('65555555-5555-5555-5555-555555555501');
SET LOCAL ROLE postgres;
SELECT ok(
  (SELECT paused_at IS NULL FROM public.tournament_round_schedule
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND status = 'running'),
  'resume: paused_at is cleared on the active row');
SELECT ok(
  (SELECT paused_accum_seconds >= 0 FROM public.tournament_round_schedule
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND status = 'running'),
  'resume: paused_accum_seconds stays non-negative (no garbage)');

-- resume when not paused is a no-op (idempotent): accum unchanged.
-- Capture accum, call resume again (paused_at is NULL now), re-read, compare.
CREATE TEMP TABLE _sc_accum_before_resume AS
  SELECT paused_accum_seconds AS v FROM public.tournament_round_schedule
   WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
     AND status = 'running';
SELECT _sc_as('63333333-3333-3333-3333-333333333302');
SELECT public.tournament_resume('65555555-5555-5555-5555-555555555501');
SET LOCAL ROLE postgres;
SELECT is(
  (SELECT paused_accum_seconds FROM public.tournament_round_schedule
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND status = 'running'),
  (SELECT v FROM _sc_accum_before_resume),
  'resume idempotency: a resume while not paused does not change accum');

-- ====================================================================
-- (b2) resume accumulation arithmetic with a NON-ZERO delta.
--      now() is frozen in-TX, so we cannot let real time pass; instead we
--      manually back-date paused_at to now() - 30s on the active row (as
--      postgres), then resume and assert paused_accum_seconds grew by ~30
--      (>= 29 to allow for boundary rounding). This proves the formula
--      paused_accum_seconds += EXTRACT(EPOCH FROM now()-paused_at)::int with a
--      real positive interval, hardening B2s-08 beyond the frozen-now() case.
-- ====================================================================
SET LOCAL ROLE postgres;
UPDATE public.tournament_round_schedule
   SET paused_at = now() - interval '30 seconds', paused_accum_seconds = 0
 WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
   AND status = 'running';
SELECT _sc_as('63333333-3333-3333-3333-333333333302');

SELECT public.tournament_resume('65555555-5555-5555-5555-555555555501');
SET LOCAL ROLE postgres;
SELECT cmp_ok(
  (SELECT paused_accum_seconds FROM public.tournament_round_schedule
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND status = 'running'),
  '>=', 29,
  'resume: accumulates ~30s when paused_at is now()-30s (positive-delta formula)');

-- ====================================================================
-- (c) pause idempotency: a 2nd consecutive pause does not advance paused_at.
-- ====================================================================
SET LOCAL ROLE postgres;
UPDATE public.tournament_round_schedule
   SET paused_at = NULL, paused_accum_seconds = 0
 WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
   AND status = 'running';
SELECT _sc_as('63333333-3333-3333-3333-333333333302');

SELECT public.tournament_pause('65555555-5555-5555-5555-555555555501');

-- Capture paused_at, pause again, assert paused_at is unchanged (idempotent).
-- Snapshot-Read als postgres (Caller war referee), dann zurück für den RPC.
SET LOCAL ROLE postgres;
CREATE TEMP TABLE _sc_paused_before AS
  SELECT paused_at AS v FROM public.tournament_round_schedule
   WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
     AND status = 'running';
SELECT _sc_as('63333333-3333-3333-3333-333333333302');
SELECT public.tournament_pause('65555555-5555-5555-5555-555555555501');
SET LOCAL ROLE postgres;
SELECT is(
  (SELECT paused_at FROM public.tournament_round_schedule
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND status = 'running'),
  (SELECT v FROM _sc_paused_before),
  'pause idempotency: a 2nd consecutive pause does not advance paused_at');

-- ====================================================================
-- (d) skip_forward / skip_back state transitions incl. pause-clear.
-- ====================================================================
-- Prime a paused active row, then skip_forward -> running + pause cleared.
SET LOCAL ROLE postgres;
UPDATE public.tournament_round_schedule
   SET status = 'call', paused_at = now(), paused_accum_seconds = 42
 WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
   AND round_number = 2;
SELECT _sc_as('63333333-3333-3333-3333-333333333302');

SELECT public.tournament_skip_forward('65555555-5555-5555-5555-555555555501');
-- Verifikations-Reads als postgres (Caller war referee).
SET LOCAL ROLE postgres;
SELECT is(
  (SELECT status FROM public.tournament_round_schedule
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND round_number = 2),
  'running', 'skip_forward: active row transitions to running');
SELECT ok(
  (SELECT paused_at IS NULL AND paused_accum_seconds = 0
     FROM public.tournament_round_schedule
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND round_number = 2),
  'skip_forward: pause state cleared (paused_at NULL, accum 0)');
SELECT ok(
  (SELECT ends_at = starts_at + make_interval(secs => match_seconds)
     FROM public.tournament_round_schedule
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND round_number = 2),
  'skip_forward: ends_at = starts_at + match_seconds');

-- skip_back -> status 'call', starts_at = now()+break, pause cleared.
SET LOCAL ROLE postgres;
UPDATE public.tournament_round_schedule
   SET paused_at = now(), paused_accum_seconds = 17
 WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
   AND round_number = 2;
SELECT _sc_as('63333333-3333-3333-3333-333333333302');

SELECT public.tournament_skip_back('65555555-5555-5555-5555-555555555501');
-- Verifikations-Reads als postgres (Caller war referee).
SET LOCAL ROLE postgres;
SELECT is(
  (SELECT status FROM public.tournament_round_schedule
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND round_number = 2),
  'call', 'skip_back: active row returns to call (re-call the window)');
SELECT ok(
  (SELECT paused_at IS NULL AND paused_accum_seconds = 0
     FROM public.tournament_round_schedule
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND round_number = 2),
  'skip_back: pause state cleared (paused_at NULL, accum 0)');
SELECT ok(
  (SELECT ends_at = starts_at + make_interval(secs => match_seconds)
     FROM public.tournament_round_schedule
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND round_number = 2),
  'skip_back: ends_at = starts_at + match_seconds (window re-called)');

-- ====================================================================
-- (e) terminal / completed-row guard: the 'completed' row is unchanged by
--     every RPC.
-- ====================================================================
SELECT _sc_as('63333333-3333-3333-3333-333333333302');
SELECT public.tournament_pause('65555555-5555-5555-5555-555555555501');
SELECT public.tournament_resume('65555555-5555-5555-5555-555555555501');
SELECT public.tournament_skip_forward('65555555-5555-5555-5555-555555555501');
SELECT public.tournament_skip_back('65555555-5555-5555-5555-555555555501');

-- Back to postgres to read the postgres-owned temp snapshots.
SET LOCAL ROLE postgres;
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT * FROM public.tournament_round_schedule
      WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
        AND status = 'completed'
     EXCEPT
     SELECT * FROM _sc_completed_before) d),
  0, 'terminal guard: the completed schedule row is unchanged by all RPCs');

-- ====================================================================
-- (f) tournament_matches (incl. the finalised match) unchanged after all RPCs.
-- ====================================================================
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT * FROM public.tournament_matches
      WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
     EXCEPT
     SELECT * FROM _sc_matches_before) d),
  0, 'immunity: no tournament_matches row diverges from the pre-RPC snapshot');
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT * FROM _sc_matches_before
     EXCEPT
     SELECT * FROM public.tournament_matches
      WHERE tournament_id = '65555555-5555-5555-5555-555555555501') d),
  0, 'immunity: no tournament_matches row was removed/changed by the RPCs');
SELECT is(
  (SELECT status FROM public.tournament_matches
    WHERE tournament_id = '65555555-5555-5555-5555-555555555501'
      AND round_number = 1 AND match_number_in_round = 1),
  'finalized', 'immunity: the finalised match keeps status = finalized');

-- ====================================================================
-- EXECUTE grants for authenticated on all four RPCs.
-- ====================================================================
SET LOCAL ROLE postgres;
SELECT ok(
  has_function_privilege('authenticated', 'public.tournament_pause(uuid)', 'EXECUTE'),
  'EXECUTE on tournament_pause(uuid) granted to authenticated');
SELECT ok(
  has_function_privilege('authenticated', 'public.tournament_resume(uuid)', 'EXECUTE'),
  'EXECUTE on tournament_resume(uuid) granted to authenticated');
SELECT ok(
  has_function_privilege('authenticated', 'public.tournament_skip_forward(uuid)', 'EXECUTE'),
  'EXECUTE on tournament_skip_forward(uuid) granted to authenticated');
SELECT ok(
  has_function_privilege('authenticated', 'public.tournament_skip_back(uuid)', 'EXECUTE'),
  'EXECUTE on tournament_skip_back(uuid) granted to authenticated');

SELECT * FROM finish();
ROLLBACK;
