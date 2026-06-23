-- Maengel #2 (P1) — tournament_remove_participant pgTAP suite.
--
-- Covers:
--   (a) has_function tournament_remove_participant(uuid, text)
--   (b) EXECUTE grant to authenticated + anon lockout
--   (c) creator removes a confirmed participant => registration_status
--       'withdrawn', exactly 1 'participant_removed' audit with
--       prior_status='confirmed'
--   (d) confirmed P1 + waitlisted P2, P1 removed => P2 confirmed,
--       'waitlist_promoted' audit, 1 'tournament_promoted' inbox to P2
--   (e) waitlisted removed => NO promotion, status 'withdrawn'
--   (f) caller without setup authority (stranger / pure club referee) => 42501
--   (g) status draft => 22023; finalized => 22023
--   (h) confirmed participant who OWNS a finalized match on a LIVE tournament
--       => removal succeeds, the finalized match survives (no cascade delete)
--       with winner/score unchanged, participant lands 'withdrawn'
--   (i) not-found participant => P0002
--   (j) second removal of an already-'withdrawn' participant => 22023
--       (idempotenz guard, RPC Z.72-74)
--
-- Runs inside BEGIN..ROLLBACK; nothing persists. Auth context switched via
-- set_config('request.jwt.claims', ...) like participant_checkin_test.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(26);

-- ---------------------------------------------------------------------
-- Helpers: auth-switch + minimal auth user.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _rp_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _rp_mk_user(p_uid uuid) RETURNS uuid
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
-- Fixture (as postgres): a club with an owner+referee; a creator; a stranger.
--   - live tournament (club-owned) with confirmed P1 and waitlist P2
--   - draft tournament with a confirmed participant (status-gate negative)
--   - finalized tournament with a confirmed participant (status-gate negative)
--   - a SECOND live tournament whose confirmed participant owns a FINALIZED
--     match — removing him exercises the real no-cascade guard (live is inside
--     the status window, so the removal goes through and must NOT cascade-delete
--     the finalized match)
-- ====================================================================
SET LOCAL ROLE postgres;

DO $fixture$
DECLARE
  v_creator   uuid := 'cccccccc-0000-0000-0000-000000000001';
  v_owner     uuid := 'cccccccc-0000-0000-0000-000000000002';
  v_referee   uuid := 'cccccccc-0000-0000-0000-000000000003';
  v_stranger  uuid := 'cccccccc-0000-0000-0000-000000000004';
  v_p2_user   uuid := 'cccccccc-0000-0000-0000-000000000005';
  v_club      uuid := 'dddddddd-0000-0000-0000-000000000001';
  v_live      uuid := 'eeeeeeee-0000-0000-0000-000000000001';
  v_draft     uuid := 'eeeeeeee-0000-0000-0000-000000000002';
  v_final     uuid := 'eeeeeeee-0000-0000-0000-000000000003';
  v_live2     uuid := 'eeeeeeee-0000-0000-0000-000000000004'; -- no-cascade scene
  v_p1        uuid := 'ffffffff-0000-0000-0000-000000000001'; -- confirmed live
  v_p2        uuid := 'ffffffff-0000-0000-0000-000000000002'; -- waitlist live
  v_pd        uuid := 'ffffffff-0000-0000-0000-000000000003'; -- confirmed draft
  v_pf_a      uuid := 'ffffffff-0000-0000-0000-000000000004'; -- confirmed final
  v_pf_b      uuid := 'ffffffff-0000-0000-0000-000000000005'; -- opponent final
  v_match     uuid := 'abababab-0000-0000-0000-000000000001';
  v_pl_a      uuid := 'ffffffff-0000-0000-0000-000000000006'; -- confirmed live2
  v_pl_b      uuid := 'ffffffff-0000-0000-0000-000000000007'; -- opponent live2
  v_match2    uuid := 'abababab-0000-0000-0000-000000000002';
BEGIN
  PERFORM _rp_mk_user(v_creator);
  PERFORM _rp_mk_user(v_owner);
  PERFORM _rp_mk_user(v_referee);
  PERFORM _rp_mk_user(v_stranger);
  PERFORM _rp_mk_user(v_p2_user);

  INSERT INTO public.organizer_teams(id, display_name, created_by)
    VALUES (v_club, 'RP-Club', v_owner);

  INSERT INTO public.team_members(organizer_team_id, user_id, roles)
    VALUES (v_club, v_owner,   ARRAY['owner']::text[]),
           (v_club, v_referee, ARRAY['referee']::text[]);

  INSERT INTO public.tournaments(
      id, created_by, organizer_team_id, display_name, team_size,
      min_participants, max_participants, format, scoring, match_format, status)
    VALUES
      (v_live,  v_creator, v_club, 'RP-Live', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'live'),
      (v_draft, v_creator, v_club, 'RP-Draft', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'draft'),
      (v_final, v_creator, v_club, 'RP-Final', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'finalized'),
      (v_live2, v_creator, v_club, 'RP-Live2', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'live');

  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status, registered_at)
    VALUES
      (v_p1,   v_live,  v_creator, 'confirmed', now() - interval '2 hour'),
      (v_p2,   v_live,  v_p2_user, 'waitlist',  now() - interval '1 hour'),
      (v_pd,   v_draft, v_creator, 'confirmed', now()),
      (v_pf_a, v_final, v_creator, 'confirmed', now()),
      (v_pf_b, v_final, v_p2_user, 'confirmed', now()),
      (v_pl_a, v_live2, v_creator, 'confirmed', now() - interval '3 hour'),
      (v_pl_b, v_live2, v_p2_user, 'confirmed', now() - interval '2 hour');

  -- A FINALIZED match between the two confirmed participants of the finalized
  -- tournament. The seeded row backs the finalized-status gate negative; it is
  -- never actually removed (status=finalized blocks the removal).
  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, status, winner_participant,
      final_score_a, final_score_b, finalized_at)
    VALUES
      (v_match, v_final, 1, 1, v_pf_a, v_pf_b, 'finalized', v_pf_a,
       6, 4, now());

  -- A FINALIZED match on the LIVE second tournament. Live is inside the removal
  -- window, so removing v_pl_a will succeed — and this row MUST survive with its
  -- winner and score untouched (soft status change, never a hard DELETE that the
  -- ON DELETE CASCADE on participant_a/b would turn into a lost finalized match).
  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, status, winner_participant,
      final_score_a, final_score_b, finalized_at)
    VALUES
      (v_match2, v_live2, 1, 1, v_pl_a, v_pl_b, 'finalized', v_pl_a,
       6, 3, now());
END;
$fixture$;

-- ====================================================================
-- (a) has_function.
-- ====================================================================
SELECT has_function('public', 'tournament_remove_participant',
  ARRAY['uuid','text'],
  'tournament_remove_participant(uuid, text) exists');

-- ====================================================================
-- (b) EXECUTE grant to authenticated + anon lockout.
-- ====================================================================
SELECT ok(
  has_function_privilege('authenticated',
    'public.tournament_remove_participant(uuid, text)', 'EXECUTE'),
  'EXECUTE on tournament_remove_participant granted to authenticated');
SELECT ok(
  NOT has_function_privilege('anon',
    'public.tournament_remove_participant(uuid, text)', 'EXECUTE'),
  'anon has NO EXECUTE on tournament_remove_participant');

-- ====================================================================
-- (f) gate-negative: stranger => 42501.
-- ====================================================================
SELECT _rp_as('cccccccc-0000-0000-0000-000000000004'); -- stranger
SELECT throws_ok(
  $$ SELECT public.tournament_remove_participant('ffffffff-0000-0000-0000-000000000001') $$,
  '42501', NULL,
  'stranger without setup authority => 42501');

-- pure club referee also fails the setup gate (referee has no setup authority).
SELECT _rp_as('cccccccc-0000-0000-0000-000000000003'); -- referee
SELECT throws_ok(
  $$ SELECT public.tournament_remove_participant('ffffffff-0000-0000-0000-000000000001') $$,
  '42501', NULL,
  'pure club referee => 42501 (no setup authority)');

-- ====================================================================
-- (g) status gates: draft => 22023, finalized => 22023.
-- ====================================================================
SELECT _rp_as('cccccccc-0000-0000-0000-000000000002'); -- club owner (passes gate)
SELECT throws_ok(
  $$ SELECT public.tournament_remove_participant('ffffffff-0000-0000-0000-000000000003') $$,
  '22023', NULL,
  'removal in draft tournament => 22023');
SELECT throws_ok(
  $$ SELECT public.tournament_remove_participant('ffffffff-0000-0000-0000-000000000004') $$,
  '22023', NULL,
  'removal in finalized tournament => 22023');

-- ====================================================================
-- (i) not-found participant => P0002.
-- ====================================================================
SELECT throws_ok(
  $$ SELECT public.tournament_remove_participant('ffffffff-ffff-ffff-ffff-ffffffffffff') $$,
  'P0002', NULL,
  'non-existent participant => not found (P0002)');

-- ====================================================================
-- (h) REAL no-cascade proof: remove a confirmed participant who OWNS a
-- finalized match on a LIVE tournament. Live is inside the removal window, so
-- the removal goes through (lives_ok). The finalized match must survive with
-- winner and score unchanged — proving the soft status change never triggers
-- the ON DELETE CASCADE on participant_a that a hard DELETE would.
--
-- Sharp oracle: the match2 row references v_pl_a via participant_a (ON DELETE
-- CASCADE). If the RPC ever DELETEd the participant instead of soft-updating,
-- this row would be gone and the count below would be 0 — the assert goes red.
-- ====================================================================
SELECT _rp_as('cccccccc-0000-0000-0000-000000000001'); -- creator (passes gate)
SELECT lives_ok(
  $$ SELECT public.tournament_remove_participant(
       'ffffffff-0000-0000-0000-000000000006', 'no-cascade-scene') $$,
  'creator removes a confirmed participant who owns a finalized live match');

SET LOCAL ROLE postgres;
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE id = 'abababab-0000-0000-0000-000000000002'),
  1, 'finalized live match survives the removal (no cascade delete)');
SELECT is(
  (SELECT winner_participant FROM public.tournament_matches
    WHERE id = 'abababab-0000-0000-0000-000000000002'),
  'ffffffff-0000-0000-0000-000000000006'::uuid,
  'winner_participant unchanged on the surviving finalized match');
SELECT is(
  (SELECT final_score_a::text || '-' || final_score_b::text
     FROM public.tournament_matches
    WHERE id = 'abababab-0000-0000-0000-000000000002'),
  '6-3',
  'final_score unchanged on the surviving finalized match');
SELECT is(
  (SELECT registration_status FROM public.tournament_participants
    WHERE id = 'ffffffff-0000-0000-0000-000000000006'),
  'withdrawn',
  'removed match-owner => withdrawn (soft status, not deleted)');

-- Idempotenz-Guard (RPC Z.72-74): a second removal of an already-'withdrawn'
-- participant raises 22023, the gate runs after the status-window check on a
-- still-live tournament, so it is the prior='withdrawn' branch that fires.
SELECT _rp_as('cccccccc-0000-0000-0000-000000000001'); -- creator (passes gate)
SELECT throws_ok(
  $$ SELECT public.tournament_remove_participant(
       'ffffffff-0000-0000-0000-000000000006') $$,
  '22023', NULL,
  'second removal of an already-withdrawn participant => 22023');

-- ====================================================================
-- (c) happy path: club owner removes confirmed P1 on the LIVE tournament.
-- => registration_status 'withdrawn', exactly 1 'participant_removed' audit
-- with prior_status='confirmed'.
-- ====================================================================
SELECT _rp_as('cccccccc-0000-0000-0000-000000000002'); -- club owner
SELECT lives_ok(
  $$ SELECT public.tournament_remove_participant(
       'ffffffff-0000-0000-0000-000000000001', 'no-show') $$,
  'club owner removes confirmed participant on a live tournament');

SET LOCAL ROLE postgres;
SELECT is(
  (SELECT registration_status FROM public.tournament_participants
    WHERE id = 'ffffffff-0000-0000-0000-000000000001'),
  'withdrawn',
  'removed confirmed participant => registration_status withdrawn');
SELECT isnt(
  (SELECT withdrew_at FROM public.tournament_participants
    WHERE id = 'ffffffff-0000-0000-0000-000000000001'),
  NULL,
  'withdrew_at stamped on removal');
SELECT is(
  (SELECT count(*)::int FROM public.tournament_audit_events
    WHERE kind = 'participant_removed'
      AND (payload->>'participant_id') = 'ffffffff-0000-0000-0000-000000000001'
      AND (payload->>'prior_status')  = 'confirmed'),
  1, 'exactly one participant_removed audit with prior_status=confirmed');

-- ====================================================================
-- (d) promotion: the waitlisted P2 is now promoted to confirmed, with a
-- 'waitlist_promoted' audit and exactly one 'tournament_promoted' inbox.
-- ====================================================================
SELECT is(
  (SELECT registration_status FROM public.tournament_participants
    WHERE id = 'ffffffff-0000-0000-0000-000000000002'),
  'confirmed',
  'oldest waitlisted P2 promoted to confirmed');
SELECT is(
  (SELECT count(*)::int FROM public.tournament_audit_events
    WHERE kind = 'waitlist_promoted'
      AND (payload->>'participant_id') = 'ffffffff-0000-0000-0000-000000000002'
      AND (payload->>'freed_by')       = 'ffffffff-0000-0000-0000-000000000001'),
  1, 'one waitlist_promoted audit linking P2 to the freed slot');
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
    WHERE kind = 'tournament_promoted'
      AND user_id = 'cccccccc-0000-0000-0000-000000000005'),
  1, 'exactly one tournament_promoted inbox message to P2');

-- ====================================================================
-- (e) waitlist removal: removing a waitlisted participant does NOT promote
-- anyone and lands the row in 'withdrawn'. Use the finalized-tournament
-- opponent? No — needs a live waitlist row. Add a fresh live waitlist
-- participant and a confirmed pool so a (non-)promotion is observable.
-- ====================================================================
SET LOCAL ROLE postgres;
DO $extra$
DECLARE
  v_live  uuid := 'eeeeeeee-0000-0000-0000-000000000001';
  v_u     uuid := 'cccccccc-0000-0000-0000-00000000000a';
  v_w     uuid := 'ffffffff-0000-0000-0000-00000000000a'; -- another waitlist
BEGIN
  PERFORM _rp_mk_user(v_u);
  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status, registered_at)
    VALUES (v_w, v_live, v_u, 'waitlist', now());
END;
$extra$;

-- Snapshot confirmed count on the live tournament before the waitlist removal.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_participants
    WHERE tournament_id = 'eeeeeeee-0000-0000-0000-000000000001'
      AND registration_status = 'confirmed'),
  1, 'live tournament has 1 confirmed before waitlist removal (P2 promoted)');

SELECT _rp_as('cccccccc-0000-0000-0000-000000000002'); -- club owner
SELECT lives_ok(
  $$ SELECT public.tournament_remove_participant(
       'ffffffff-0000-0000-0000-00000000000a') $$,
  'club owner removes a waitlisted participant');

SET LOCAL ROLE postgres;
SELECT is(
  (SELECT registration_status FROM public.tournament_participants
    WHERE id = 'ffffffff-0000-0000-0000-00000000000a'),
  'withdrawn',
  'removed waitlist participant => withdrawn');
SELECT is(
  (SELECT count(*)::int FROM public.tournament_participants
    WHERE tournament_id = 'eeeeeeee-0000-0000-0000-000000000001'
      AND registration_status = 'confirmed'),
  1, 'waitlist removal promotes nobody: confirmed count unchanged');

-- ====================================================================
-- no-cascade proof (post): the seeded finalized match still exists with
-- winner/score unchanged after all removals.
-- ====================================================================
SELECT is(
  (SELECT final_score_a::text || '-' || final_score_b::text
     FROM public.tournament_matches
    WHERE id = 'abababab-0000-0000-0000-000000000001'),
  '6-4',
  'finalized match score unchanged (no cascade delete)');

SELECT * FROM finish();
ROLLBACK;
