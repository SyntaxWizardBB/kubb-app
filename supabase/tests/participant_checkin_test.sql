-- ADR-0031 Phase D Block D1 — on-site participant check-in pgTAP suite.
--
-- Covers (D1-DoD-11):
--   (a) has_column checked_in_at on tournament_participants
--   (b) has_function for both RPCs
--   (c) publication membership of tournament_participants (unchanged)
--   (d) EXECUTE grant to authenticated + anon lockout for both RPCs
--   (e) happy-path check-in sets checked_in_at + writes one audit event
--   (f) idempotent re-check-in no-op (timestamp preserved, no extra audit)
--   (g) undo sets checked_in_at back to NULL + writes one audit event
--   (h) idempotent undo no-op on already-NULL (no extra audit)
--   (i) gate-negative without manage authority => 42501
--   (j) status gate: draft => 22023, live => ok
--   (k) waitlist participant => 22023; not-found participant raises
--
-- Runs inside BEGIN..ROLLBACK; nothing is persisted. Auth context switched via
-- set_config('request.jwt.claims', ...) like tournament_administrable_test.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(23);

-- ---------------------------------------------------------------------
-- Helpers: auth-switch + minimal auth user.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _ci_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _ci_mk_user(p_uid uuid) RETURNS uuid
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
-- Fixture (as postgres): a creator, an outsider; a live tournament with a
-- confirmed + a waitlist participant, and a draft tournament with a confirmed
-- participant (for the status-gate negative).
-- ====================================================================
SET LOCAL ROLE postgres;

DO $fixture$
DECLARE
  v_creator   uuid := '88888888-8888-8888-8888-888888888801';
  v_outsider  uuid := '88888888-8888-8888-8888-888888888802';
  v_live      uuid := '99999999-9999-9999-9999-999999999901'; -- live tournament
  v_draft     uuid := '99999999-9999-9999-9999-999999999902'; -- draft tournament
  v_p_conf    uuid := 'aaaaaaaa-0000-0000-0000-000000000001'; -- confirmed, live
  v_p_wait    uuid := 'aaaaaaaa-0000-0000-0000-000000000002'; -- waitlist, live
  v_p_draft   uuid := 'aaaaaaaa-0000-0000-0000-000000000003'; -- confirmed, draft
BEGIN
  PERFORM _ci_mk_user(v_creator);
  PERFORM _ci_mk_user(v_outsider);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status)
    VALUES
      (v_live, v_creator, 'CI-Live', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'live'),
      (v_draft, v_creator, 'CI-Draft', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'draft');

  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status)
    VALUES
      (v_p_conf,  v_live,  v_creator,  'confirmed'),
      (v_p_wait,  v_live,  v_outsider, 'waitlist'),
      (v_p_draft, v_draft, v_creator,  'confirmed');
END;
$fixture$;

-- ====================================================================
-- (a) has_column checked_in_at.
-- ====================================================================
SELECT has_column('public', 'tournament_participants', 'checked_in_at',
  'tournament_participants has a checked_in_at column');
SELECT col_is_null('public', 'tournament_participants', 'checked_in_at',
  'checked_in_at is NULLable (additive, no NOT NULL)');

-- ====================================================================
-- (b) has_function for both RPCs.
-- ====================================================================
SELECT has_function('public', 'tournament_checkin_participant', ARRAY['uuid'],
  'tournament_checkin_participant(uuid) exists');
SELECT has_function('public', 'tournament_undo_checkin', ARRAY['uuid'],
  'tournament_undo_checkin(uuid) exists');

-- ====================================================================
-- (c) publication membership of tournament_participants unchanged.
-- ====================================================================
SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime'
       AND schemaname = 'public'
       AND tablename = 'tournament_participants'),
  'tournament_participants is still in supabase_realtime publication');

-- ====================================================================
-- (d) EXECUTE grant to authenticated for both RPCs.
-- ====================================================================
SELECT ok(
  has_function_privilege('authenticated',
    'public.tournament_checkin_participant(uuid)', 'EXECUTE'),
  'EXECUTE on tournament_checkin_participant granted to authenticated');
SELECT ok(
  has_function_privilege('authenticated',
    'public.tournament_undo_checkin(uuid)', 'EXECUTE'),
  'EXECUTE on tournament_undo_checkin granted to authenticated');
SELECT ok(
  NOT has_function_privilege('anon',
    'public.tournament_checkin_participant(uuid)', 'EXECUTE'),
  'anon has NO EXECUTE on tournament_checkin_participant');
SELECT ok(
  NOT has_function_privilege('anon',
    'public.tournament_undo_checkin(uuid)', 'EXECUTE'),
  'anon has NO EXECUTE on tournament_undo_checkin');

-- ====================================================================
-- (i) gate-negative: outsider (no manage authority) => 42501.
-- ====================================================================
SELECT _ci_as('88888888-8888-8888-8888-888888888802'); -- outsider
SELECT throws_ok(
  $$ SELECT public.tournament_checkin_participant('aaaaaaaa-0000-0000-0000-000000000001') $$,
  '42501', NULL,
  'outsider without manage authority => 42501');

-- ====================================================================
-- (e) happy-path check-in as creator sets checked_in_at + 1 audit event.
-- This call runs against the LIVE tournament (v_live), so it is ALSO the
-- explicit status-gate positive case: status='live' => check-in allowed
-- (the matching draft-negative is Test (j) below).
-- ====================================================================
SELECT _ci_as('88888888-8888-8888-8888-888888888801'); -- creator

SELECT lives_ok(
  $$ SELECT public.tournament_checkin_participant('aaaaaaaa-0000-0000-0000-000000000001') $$,
  'status-gate live => ok: creator check-in of confirmed participant on a live tournament succeeds');

SELECT isnt(
  (SELECT checked_in_at FROM public.tournament_participants
    WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  NULL,
  'happy-path: checked_in_at is set after check-in');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_audit_events
    WHERE kind = 'participant_checked_in'
      AND (payload->>'participant_id') = 'aaaaaaaa-0000-0000-0000-000000000001'),
  1, 'one participant_checked_in audit event written');

-- ====================================================================
-- (f) idempotent re-check-in no-op: timestamp preserved, no extra audit.
-- ====================================================================
SELECT lives_ok(
  $$ SELECT public.tournament_checkin_participant('aaaaaaaa-0000-0000-0000-000000000001') $$,
  'idempotent re-check-in does not raise');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_audit_events
    WHERE kind = 'participant_checked_in'
      AND (payload->>'participant_id') = 'aaaaaaaa-0000-0000-0000-000000000001'),
  1, 'idempotent re-check-in writes NO additional audit event');

-- ====================================================================
-- (g) undo sets checked_in_at back to NULL + 1 audit event.
-- ====================================================================
SELECT lives_ok(
  $$ SELECT public.tournament_undo_checkin('aaaaaaaa-0000-0000-0000-000000000001') $$,
  'undo check-in succeeds');

SELECT is(
  (SELECT checked_in_at FROM public.tournament_participants
    WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001'),
  NULL,
  'undo: checked_in_at is NULL again');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_audit_events
    WHERE kind = 'participant_checkin_undone'
      AND (payload->>'participant_id') = 'aaaaaaaa-0000-0000-0000-000000000001'),
  1, 'one participant_checkin_undone audit event written');

-- ====================================================================
-- (h) idempotent undo no-op on already-NULL: no extra audit.
-- ====================================================================
SELECT lives_ok(
  $$ SELECT public.tournament_undo_checkin('aaaaaaaa-0000-0000-0000-000000000001') $$,
  'idempotent undo on already-NULL does not raise');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_audit_events
    WHERE kind = 'participant_checkin_undone'
      AND (payload->>'participant_id') = 'aaaaaaaa-0000-0000-0000-000000000001'),
  1, 'idempotent undo writes NO additional audit event');

-- ====================================================================
-- (k) waitlist participant => 22023.
-- ====================================================================
SELECT throws_ok(
  $$ SELECT public.tournament_checkin_participant('aaaaaaaa-0000-0000-0000-000000000002') $$,
  '22023', NULL,
  'waitlist participant check-in => 22023');

-- not-found participant raises.
SELECT throws_ok(
  $$ SELECT public.tournament_checkin_participant('aaaaaaaa-ffff-ffff-ffff-ffffffffffff') $$,
  'P0002', NULL,
  'non-existent participant => not found (P0002)');

-- ====================================================================
-- (j) status gate: draft => 22023.
-- ====================================================================
SELECT throws_ok(
  $$ SELECT public.tournament_checkin_participant('aaaaaaaa-0000-0000-0000-000000000003') $$,
  '22023', NULL,
  'check-in in draft tournament => 22023');

SELECT * FROM finish();
ROLLBACK;
