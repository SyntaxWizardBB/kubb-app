-- W4-T09/T10 — tournament_adjust_round_time RPC pgTAP suite (spec
-- organizer-cockpit-dashboard-spec.md §6 / §9.5, ADR-0031 timer extension).
--
-- tournament_adjust_round_time(p_tournament_id uuid, p_delta_seconds int)
-- additively adjusts the LIVE round's length: a positive delta lengthens, a
-- negative delta shortens the active (non-terminal) schedule row. The write is
-- additive on match_seconds AND ends_at (so the Restzeit-Formel and the CDC
-- push agree); the result is clamped to >= 0 (a delta that would drive
-- match_seconds negative pins it at 0). It is gated by
-- tournament_caller_can_administer (a non-administrator gets 42501) and never
-- touches the terminal ('completed') row or tournament_matches.
--
-- Covers:
--   (a) Gate: an administrator (creator / club referee) is allowed; a stranger
--       gets 42501.
--   (b) Positive delta lengthens match_seconds AND pushes ends_at by the same
--       amount.
--   (c) Negative delta shortens both symmetrically.
--   (d) Clamp: a delta below -match_seconds pins match_seconds at 0 (never
--       negative) and ends_at = starts_at.
--   (e) Terminal guard: a 'completed' schedule row is unchanged.
--   (f) Immunity: tournament_matches (incl. a finalised match) is unchanged.
--   (g) EXECUTE granted to authenticated.
--
-- pgTAP runs inside BEGIN..ROLLBACK; now() is frozen in-TX (README K7), so we
-- assert the structural additive invariants that hold regardless of wall clock.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

-- ---------------------------------------------------------------------
-- Helpers: auth-switch + minimal auth user.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _art_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _art_mk_user(p_uid uuid) RETURNS uuid
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
-- Fixture: one club with a referee + a stranger; a creator; a live club
-- tournament with an ACTIVE ('running') schedule row (match 1800), a COMPLETED
-- schedule row (terminal guard), and matches incl. a finalised one (immunity).
-- ====================================================================
SET LOCAL ROLE postgres;

DO $fixture$
DECLARE
  v_creator  uuid := '73333333-3333-3333-3333-333333333301';
  v_referee  uuid := '73333333-3333-3333-3333-333333333302';
  v_stranger uuid := '73333333-3333-3333-3333-333333333303';
  v_club     uuid := '74444444-4444-4444-4444-444444444401';
  v_tour     uuid := '75555555-5555-5555-5555-555555555501';
  v_pa       uuid;
  v_pb       uuid;
BEGIN
  PERFORM _art_mk_user(v_creator);
  PERFORM _art_mk_user(v_referee);
  PERFORM _art_mk_user(v_stranger);

  INSERT INTO public.organizer_teams(id, display_name, created_by)
    VALUES (v_club, 'ART-Club', v_creator);

  INSERT INTO public.team_members(organizer_team_id, user_id, roles)
    VALUES (v_club, v_referee, ARRAY['referee']::text[]);

  INSERT INTO public.tournaments(
      id, created_by, organizer_team_id, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES
      (v_tour, v_creator, v_club, 'ART-Live', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800,
                          'break_between_matches_seconds', 300),
       'live', true);

  -- ACTIVE round (round 2): status 'running', match 1800, ends_at = starts + 1800.
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

-- Snapshot tournament_matches + the completed row for the guards.
CREATE TEMP TABLE _art_matches_before AS
  SELECT * FROM public.tournament_matches
   WHERE tournament_id = '75555555-5555-5555-5555-555555555501';
CREATE TEMP TABLE _art_completed_before AS
  SELECT * FROM public.tournament_round_schedule
   WHERE tournament_id = '75555555-5555-5555-5555-555555555501'
     AND status = 'completed';

-- ====================================================================
-- (a) Gate: non-administrator stranger -> 42501; administrators allowed.
-- ====================================================================
SELECT _art_as('73333333-3333-3333-3333-333333333303'); -- stranger
SELECT throws_ok(
  $$ SELECT public.tournament_adjust_round_time(
       '75555555-5555-5555-5555-555555555501', 60) $$,
  '42501', NULL, 'adjust: non-administrator stranger raises 42501');

SELECT _art_as('73333333-3333-3333-3333-333333333301'); -- creator
SELECT lives_ok(
  $$ SELECT public.tournament_adjust_round_time(
       '75555555-5555-5555-5555-555555555501', 0) $$,
  'adjust: creator (administrator) is allowed (no throw)');

SELECT _art_as('73333333-3333-3333-3333-333333333302'); -- referee (K4)
SELECT lives_ok(
  $$ SELECT public.tournament_adjust_round_time(
       '75555555-5555-5555-5555-555555555501', 0) $$,
  'adjust: club referee (administrator) is allowed (no throw)');

-- ====================================================================
-- (b) Positive delta: +60 lengthens match_seconds AND ends_at by 60.
-- ====================================================================
SET LOCAL ROLE postgres;
UPDATE public.tournament_round_schedule
   SET match_seconds = 1800, ends_at = starts_at + interval '1800 seconds'
 WHERE tournament_id = '75555555-5555-5555-5555-555555555501'
   AND status = 'running';
SELECT _art_as('73333333-3333-3333-3333-333333333302');

SELECT public.tournament_adjust_round_time(
  '75555555-5555-5555-5555-555555555501', 60);
SET LOCAL ROLE postgres;
SELECT is(
  (SELECT match_seconds FROM public.tournament_round_schedule
    WHERE tournament_id = '75555555-5555-5555-5555-555555555501'
      AND status = 'running'),
  1860, 'positive delta: match_seconds += 60');
SELECT ok(
  (SELECT ends_at = starts_at + make_interval(secs => match_seconds)
     FROM public.tournament_round_schedule
    WHERE tournament_id = '75555555-5555-5555-5555-555555555501'
      AND status = 'running'),
  'positive delta: ends_at stays starts_at + match_seconds (pushed by 60)');

-- ====================================================================
-- (c) Negative delta: -300 shortens match_seconds AND ends_at by 300.
-- ====================================================================
SET LOCAL ROLE postgres;
UPDATE public.tournament_round_schedule
   SET match_seconds = 1800, ends_at = starts_at + interval '1800 seconds'
 WHERE tournament_id = '75555555-5555-5555-5555-555555555501'
   AND status = 'running';
SELECT _art_as('73333333-3333-3333-3333-333333333302');

SELECT public.tournament_adjust_round_time(
  '75555555-5555-5555-5555-555555555501', -300);
SET LOCAL ROLE postgres;
SELECT is(
  (SELECT match_seconds FROM public.tournament_round_schedule
    WHERE tournament_id = '75555555-5555-5555-5555-555555555501'
      AND status = 'running'),
  1500, 'negative delta: match_seconds -= 300');
SELECT ok(
  (SELECT ends_at = starts_at + make_interval(secs => match_seconds)
     FROM public.tournament_round_schedule
    WHERE tournament_id = '75555555-5555-5555-5555-555555555501'
      AND status = 'running'),
  'negative delta: ends_at stays starts_at + match_seconds (pulled by 300)');

-- ====================================================================
-- (d) Clamp: a delta below -match_seconds pins match_seconds at 0 (never
--     negative); ends_at collapses to starts_at.
-- ====================================================================
SET LOCAL ROLE postgres;
UPDATE public.tournament_round_schedule
   SET match_seconds = 1800, ends_at = starts_at + interval '1800 seconds'
 WHERE tournament_id = '75555555-5555-5555-5555-555555555501'
   AND status = 'running';
SELECT _art_as('73333333-3333-3333-3333-333333333302');

SELECT public.tournament_adjust_round_time(
  '75555555-5555-5555-5555-555555555501', -100000);
SET LOCAL ROLE postgres;
SELECT is(
  (SELECT match_seconds FROM public.tournament_round_schedule
    WHERE tournament_id = '75555555-5555-5555-5555-555555555501'
      AND status = 'running'),
  0, 'clamp: an over-large negative delta pins match_seconds at 0 (never < 0)');
SELECT ok(
  (SELECT ends_at = starts_at
     FROM public.tournament_round_schedule
    WHERE tournament_id = '75555555-5555-5555-5555-555555555501'
      AND status = 'running'),
  'clamp: ends_at collapses to starts_at when clamped to 0');

-- ====================================================================
-- (e) Terminal guard + (f) match immunity after a batch of adjustments.
-- ====================================================================
SELECT _art_as('73333333-3333-3333-3333-333333333302');
SELECT public.tournament_adjust_round_time(
  '75555555-5555-5555-5555-555555555501', 120);
SELECT public.tournament_adjust_round_time(
  '75555555-5555-5555-5555-555555555501', -60);

SET LOCAL ROLE postgres;
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT * FROM public.tournament_round_schedule
      WHERE tournament_id = '75555555-5555-5555-5555-555555555501'
        AND status = 'completed'
     EXCEPT
     SELECT * FROM _art_completed_before) d),
  0, 'terminal guard: the completed schedule row is unchanged by adjust');
SELECT is(
  (SELECT count(*)::int FROM (
     (SELECT * FROM public.tournament_matches
       WHERE tournament_id = '75555555-5555-5555-5555-555555555501'
      EXCEPT
      SELECT * FROM _art_matches_before)
     UNION ALL
     (SELECT * FROM _art_matches_before
      EXCEPT
      SELECT * FROM public.tournament_matches
       WHERE tournament_id = '75555555-5555-5555-5555-555555555501')) d),
  0, 'immunity: no tournament_matches row diverges from the pre-RPC snapshot');

-- ====================================================================
-- (g) EXECUTE grant for authenticated.
-- ====================================================================
SET LOCAL ROLE postgres;
SELECT ok(
  has_function_privilege('authenticated',
    'public.tournament_adjust_round_time(uuid, integer)', 'EXECUTE'),
  'EXECUTE on tournament_adjust_round_time(uuid, int) granted to authenticated');

SELECT * FROM finish();
ROLLBACK;
