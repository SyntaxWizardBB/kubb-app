-- ADR-0031 Phase C / Block C2 — pause/resume notify pgTAP suite.
--
-- Covers (C2-DoD-10):
--   (a) tournament_pause writes a 'paused' row (wire-kind tournament_round,
--       action_payload.kind='paused') per recipient;
--   (b) tournament_resume writes a 'resumed' row per recipient;
--   (c) broadcast recipient set = solo + open team roster, guests/replaced/NULL
--       excluded (same spine as _tournament_notify_participants);
--   (d) idempotency / no-op: a second pause and a resume-without-pause add 0
--       rows; a pause of a non-active tournament adds 0 rows;
--   (e) PII-free payload (only tournament_id, kind — no names/opponents).
--
-- pgTAP is installed transiently inside the BEGIN..ROLLBACK; everything rolls
-- back, nothing is mutated (read-only against the live DB). No db reset.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(20);

-- --------------------------------------------------------------------
-- Fixture (as postgres): one ACTIVE tournament with
--   * a TEAM participant (2 open roster members + 1 replaced slot);
--   * a SOLO participant;
--   * one active (status='running') schedule row so pause/resume have a row to
--     transition;
-- and a SECOND tournament with only a COMPLETED schedule row (non-active) to
-- prove pause is a no-op there.
-- --------------------------------------------------------------------
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION _pr_mk_user(p_uid uuid) RETURNS uuid
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

DO $fixture$
DECLARE
  v_creator   uuid := '66666666-6666-6666-6666-666666666601';
  v_tm_a      uuid := '66666666-6666-6666-6666-666666666602'; -- team member A
  v_tm_b      uuid := '66666666-6666-6666-6666-666666666603'; -- team member B
  v_solo      uuid := '66666666-6666-6666-6666-666666666604'; -- solo player
  v_repl      uuid := '66666666-6666-6666-6666-666666666605'; -- replaced slot
  v_team      uuid := '55555555-5555-5555-5555-555555555501';
  v_tour      uuid := '44444444-4444-4444-4444-444444444401'; -- active tournament
  v_tour2     uuid := '44444444-4444-4444-4444-444444444402'; -- non-active
  v_part_team uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  v_part_solo uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
BEGIN
  PERFORM _pr_mk_user(v_creator);
  PERFORM _pr_mk_user(v_tm_a);
  PERFORM _pr_mk_user(v_tm_b);
  PERFORM _pr_mk_user(v_solo);
  PERFORM _pr_mk_user(v_repl);

  INSERT INTO public.teams(id, display_name, created_by)
    VALUES (v_team, 'PR-Team', v_creator);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES
      (v_tour, v_creator, 'PR-Tour', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800,
                          'break_between_matches_seconds', 300),
       'live', true),
      (v_tour2, v_creator, 'PR-Tour-2', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800,
                          'break_between_matches_seconds', 300),
       'live', true);

  -- Active schedule row (running, not yet paused) for the first tournament.
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds,
      paused_at, paused_accum_seconds)
    VALUES (v_tour, NULL, 1, 'group', 'running',
            now() - interval '400 seconds',
            now() - interval '100 seconds',
            now() + interval '1700 seconds',
            300, 1800, NULL, 0);

  -- Non-active (completed) schedule row for the second tournament -> pause/resume
  -- must be a no-op (terminal guard).
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds,
      paused_at, paused_accum_seconds)
    VALUES (v_tour2, NULL, 1, 'group', 'completed',
            now() - interval '4000 seconds',
            now() - interval '3700 seconds',
            now() - interval '1900 seconds',
            300, 1800, NULL, 0);

  -- Participants of the first tournament: one team participation + one solo.
  INSERT INTO public.tournament_participants(id, tournament_id, team_id, user_id, registration_status)
    VALUES (v_part_team, v_tour, v_team, NULL, 'confirmed');
  INSERT INTO public.tournament_participants(id, tournament_id, user_id, registration_status)
    VALUES (v_part_solo, v_tour, v_solo, 'confirmed');

  -- Roster of the team: 2 open members + 1 replaced slot (must drop out).
  INSERT INTO public.tournament_roster_slots(participant_id, slot_index, member_user_id, guest_player_id)
    VALUES (v_part_team, 1, v_tm_a, NULL),
           (v_part_team, 2, v_tm_b, NULL);
  INSERT INTO public.tournament_roster_slots(participant_id, slot_index, member_user_id, guest_player_id, replaced_at)
    VALUES (v_part_team, 3, v_repl, NULL, now()); -- replaced -> drops out
END;
$fixture$;

-- ====================================================================
-- (a) tournament_pause writes a 'paused' row per recipient.
-- The RPC is SECURITY DEFINER + gated; it must run as the creator (a manager),
-- so each RPC call is wrapped in a DO block that sets the authenticated role +
-- a JWT claim locally. Read-back assertions run as the postgres role (which
-- bypasses the user_inbox_messages owner-read RLS so all recipients' rows are
-- visible) — we re-assert the role before every assertion block.
-- ====================================================================
-- Helper: run an RPC as the manager (authenticated + JWT), then return to
-- postgres so the next assertion reads with RLS bypassed.
DO $pause1$
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '66666666-6666-6666-6666-666666666601',
                      'role', 'authenticated')::text, true);
  PERFORM public.tournament_pause('44444444-4444-4444-4444-444444444401');
END;
$pause1$;
SET LOCAL ROLE postgres;

SELECT pass('(a) tournament_pause ran for a manager (no exception)');

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND (action_payload ->> 'tournament_id') = '44444444-4444-4444-4444-444444444401'
       AND (action_payload ->> 'kind') = 'paused'),
  3,
  '(a) pause writes exactly 3 paused rows (2 team members + 1 solo)');

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '66666666-6666-6666-6666-666666666602'
       AND (action_payload ->> 'kind') = 'paused'),
  1, '(a) team member A has exactly 1 paused row');
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '66666666-6666-6666-6666-666666666604'
       AND (action_payload ->> 'kind') = 'paused'),
  1, '(a) solo player has exactly 1 paused row');

-- wire-kind is tournament_round, sub-event in action_payload.kind.
SELECT is(
  (SELECT DISTINCT kind FROM public.user_inbox_messages
     WHERE (action_payload ->> 'tournament_id') = '44444444-4444-4444-4444-444444444401'
       AND (action_payload ->> 'kind') = 'paused'),
  'tournament_round',
  '(a) wire-kind is tournament_round (sub-event in action_payload.kind)');

-- German subject/body.
SELECT is(
  (SELECT DISTINCT subject FROM public.user_inbox_messages
     WHERE (action_payload ->> 'tournament_id') = '44444444-4444-4444-4444-444444444401'
       AND (action_payload ->> 'kind') = 'paused'),
  'Turnier pausiert', '(a) German subject "Turnier pausiert"');

-- ====================================================================
-- (c) broadcast recipient set: guests / replaced slots excluded.
-- ====================================================================
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '66666666-6666-6666-6666-666666666605' -- replaced slot member
       AND (action_payload ->> 'kind') = 'paused'),
  0, '(c) replaced roster slot member gets NO paused row');

SELECT bag_eq(
  $$SELECT user_id FROM public.user_inbox_messages
      WHERE kind = 'tournament_round'
        AND (action_payload ->> 'tournament_id') = '44444444-4444-4444-4444-444444444401'
        AND (action_payload ->> 'kind') = 'paused'$$,
  $$VALUES ('66666666-6666-6666-6666-666666666602'::uuid),
           ('66666666-6666-6666-6666-666666666603'::uuid),
           ('66666666-6666-6666-6666-666666666604'::uuid)$$,
  '(c) recipients are exactly the 2 open team members + the solo player');

-- ====================================================================
-- (e) PII-free payload: exactly tournament_id, kind; no other key. A broadcast
-- pause/resume carries no per-recipient round/phase/pitch, so the payload is the
-- broadcast-sensible whitelist subset (tournament_id, kind) — no dead NULL keys.
-- ====================================================================
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT jsonb_object_keys(action_payload) k FROM public.user_inbox_messages
       WHERE kind = 'tournament_round'
         AND user_id = '66666666-6666-6666-6666-666666666604'
         AND (action_payload ->> 'kind') = 'paused') t
     WHERE k NOT IN ('tournament_id','kind')),
  0, '(e) paused payload has NO key outside the whitelist (tournament_id, kind)');
SELECT is(
  (SELECT count(DISTINCT k)::int FROM (
     SELECT jsonb_object_keys(action_payload) k FROM public.user_inbox_messages
       WHERE kind = 'tournament_round'
         AND user_id = '66666666-6666-6666-6666-666666666604'
         AND (action_payload ->> 'kind') = 'paused') t),
  2, '(e) paused payload has exactly the 2 whitelist keys (tournament_id, kind)');

-- ====================================================================
-- (d) idempotency: a SECOND pause adds 0 rows (paused_at already set -> the
-- UPDATE changes 0 rows -> the conditional PERFORM does not fire).
-- ====================================================================
DO $pause2$
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '66666666-6666-6666-6666-666666666601',
                      'role', 'authenticated')::text, true);
  PERFORM public.tournament_pause('44444444-4444-4444-4444-444444444401');
END;
$pause2$;
SET LOCAL ROLE postgres;
SELECT pass('(d) a second pause call ran (no-op)');
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND (action_payload ->> 'tournament_id') = '44444444-4444-4444-4444-444444444401'
       AND (action_payload ->> 'kind') = 'paused'),
  3, '(d) second pause adds NO paused row (still 3)');

-- ====================================================================
-- (b) tournament_resume writes a 'resumed' row per recipient.
-- ====================================================================
DO $resume1$
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '66666666-6666-6666-6666-666666666601',
                      'role', 'authenticated')::text, true);
  PERFORM public.tournament_resume('44444444-4444-4444-4444-444444444401');
END;
$resume1$;
SET LOCAL ROLE postgres;
SELECT pass('(b) tournament_resume ran for a manager');

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND (action_payload ->> 'tournament_id') = '44444444-4444-4444-4444-444444444401'
       AND (action_payload ->> 'kind') = 'resumed'),
  3,
  '(b) resume writes exactly 3 resumed rows (one per recipient)');

SELECT is(
  (SELECT DISTINCT subject FROM public.user_inbox_messages
     WHERE (action_payload ->> 'tournament_id') = '44444444-4444-4444-4444-444444444401'
       AND (action_payload ->> 'kind') = 'resumed'),
  'Turnier fortgesetzt', '(b) German subject "Turnier fortgesetzt"');

-- (e) resumed payload is also PII-free (exactly the 2 whitelist keys).
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT jsonb_object_keys(action_payload) k FROM public.user_inbox_messages
       WHERE kind = 'tournament_round'
         AND user_id = '66666666-6666-6666-6666-666666666604'
         AND (action_payload ->> 'kind') = 'resumed') t
     WHERE k NOT IN ('tournament_id','kind')),
  0, '(e) resumed payload has NO key outside the whitelist');

-- ====================================================================
-- (d) idempotency: a resume WITHOUT a prior pause adds 0 rows. We already
-- resumed; a second resume must be a no-op (paused_at IS NULL -> 0 rows).
-- ====================================================================
DO $resume2$
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '66666666-6666-6666-6666-666666666601',
                      'role', 'authenticated')::text, true);
  PERFORM public.tournament_resume('44444444-4444-4444-4444-444444444401');
END;
$resume2$;
SET LOCAL ROLE postgres;
SELECT pass('(d) a second resume (already unpaused) ran (no-op)');
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND (action_payload ->> 'tournament_id') = '44444444-4444-4444-4444-444444444401'
       AND (action_payload ->> 'kind') = 'resumed'),
  3, '(d) resume-without-pause adds NO resumed row (still 3)');

-- ====================================================================
-- (d) pausing a NON-ACTIVE tournament (only a completed schedule row) is a
-- no-op -> 0 paused rows for tour-2.
-- ====================================================================
DO $pause_na$
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', '66666666-6666-6666-6666-666666666601',
                      'role', 'authenticated')::text, true);
  PERFORM public.tournament_pause('44444444-4444-4444-4444-444444444402');
END;
$pause_na$;
SET LOCAL ROLE postgres;
SELECT pass('(d) pausing a non-active tournament ran (no-op)');
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND (action_payload ->> 'tournament_id') = '44444444-4444-4444-4444-444444444402'
       AND (action_payload ->> 'kind') = 'paused'),
  0, '(d) pausing a non-active (completed) tournament writes NO paused row');

SELECT * FROM finish();
ROLLBACK;
