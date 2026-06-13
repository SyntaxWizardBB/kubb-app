-- ADR-0031 Phase D Block D2 — tournament_get check-in projection pgTAP smoke.
--
-- Covers (D2-DoD-06):
--   (a) after a participant is checked in, tournament_get projects the
--       `checked_in_at` key non-NULL for that participant;
--   (b) a not-yet-checked-in participant projects checked_in_at = NULL (the
--       key is present, value NULL);
--   (c) regression guard against an accidental body swallow: the
--       participants[].display_name projection and the tournament.club_id key
--       remain present / correct.
--
-- D2 is a pure READ projection: it adds no gate and writes nothing. Check-in
-- itself is exercised here only to produce the non-NULL value (the check-in /
-- undo RPC behaviour is covered by participant_checkin_test.sql / D1).
--
-- Runs inside BEGIN..ROLLBACK; nothing is persisted. Auth context switched via
-- set_config('request.jwt.claims', ...) like participant_checkin_test.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- ---------------------------------------------------------------------
-- Helpers: auth-switch + minimal auth user (mirrors the D1 suite).
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _gp_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _gp_mk_user(p_uid uuid) RETURNS uuid
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
-- Fixture (as postgres): a creator who owns a live tournament under a club,
-- with two confirmed participants — one will be checked in, one stays absent.
-- The club is set so tournament.club_id is non-NULL (regression target).
-- ====================================================================
SET LOCAL ROLE postgres;

DO $fixture$
DECLARE
  v_creator uuid := '77777777-7777-7777-7777-777777777701';
  v_club    uuid := '66666666-6666-6666-6666-666666666601';
  v_tour    uuid := '55555555-5555-5555-5555-555555555501'; -- live tournament
  v_p_in    uuid := 'bbbbbbbb-0000-0000-0000-000000000001'; -- will check in
  v_p_out   uuid := 'bbbbbbbb-0000-0000-0000-000000000002'; -- stays absent
BEGIN
  PERFORM _gp_mk_user(v_creator);

  -- user_profiles row gives the projected participant display_name a value.
  INSERT INTO public.user_profiles(user_id, nickname)
    VALUES (v_creator, 'CheckinHero')
    ON CONFLICT (user_id) DO UPDATE SET nickname = EXCLUDED.nickname;

  -- A club so tournament.organizer_team_id is non-NULL (CF5 regression target).
  INSERT INTO public.organizer_teams(id, display_name, created_by)
    VALUES (v_club, 'CI-Club-D2', v_creator)
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, organizer_team_id, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status)
    VALUES
      (v_tour, v_creator, v_club, 'D2-Get-Live', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'live');

  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status)
    VALUES
      (v_p_in,  v_tour, v_creator, 'confirmed'),
      -- second confirmed participant: distinct user so the unique
      -- (tournament_id,user_id) is respected; stays not-checked-in.
      (v_p_out, v_tour, _gp_mk_user('77777777-7777-7777-7777-777777777702'),
       'confirmed');
END;
$fixture$;

-- ====================================================================
-- Act as the creator (manage authority) and check in ONE participant.
-- ====================================================================
SELECT _gp_as('77777777-7777-7777-7777-777777777701');

SELECT lives_ok(
  $$ SELECT public.tournament_checkin_participant('bbbbbbbb-0000-0000-0000-000000000001') $$,
  'fixture: creator checks in participant p_in on the live tournament');

-- ====================================================================
-- (a) tournament_get projects checked_in_at NON-NULL for the checked-in
--     participant.
-- ====================================================================
SELECT isnt(
  (SELECT (part->>'checked_in_at')
     FROM jsonb_array_elements(
            public.tournament_get('55555555-5555-5555-5555-555555555501')
              -> 'participants') AS part
    WHERE (part->>'participant_id') = 'bbbbbbbb-0000-0000-0000-000000000001'),
  NULL,
  'D2-06(a): tournament_get projects checked_in_at NON-NULL for the checked-in participant');

-- key must literally be present in the participant object.
SELECT ok(
  (SELECT (part ? 'checked_in_at')
     FROM jsonb_array_elements(
            public.tournament_get('55555555-5555-5555-5555-555555555501')
              -> 'participants') AS part
    WHERE (part->>'participant_id') = 'bbbbbbbb-0000-0000-0000-000000000001'),
  'D2-04: checked_in_at key is present in the projected participant object');

-- ====================================================================
-- (b) the not-checked-in participant projects checked_in_at = NULL (key
--     present, value NULL).
-- ====================================================================
SELECT is(
  (SELECT (part->>'checked_in_at')
     FROM jsonb_array_elements(
            public.tournament_get('55555555-5555-5555-5555-555555555501')
              -> 'participants') AS part
    WHERE (part->>'participant_id') = 'bbbbbbbb-0000-0000-0000-000000000002'),
  NULL,
  'D2-06(b): not-checked-in participant projects checked_in_at = NULL');

-- ====================================================================
-- (c) regression: participants[].display_name still projected for the
--     checked-in participant (its user has nickname 'CheckinHero').
-- ====================================================================
SELECT is(
  (SELECT (part->>'display_name')
     FROM jsonb_array_elements(
            public.tournament_get('55555555-5555-5555-5555-555555555501')
              -> 'participants') AS part
    WHERE (part->>'participant_id') = 'bbbbbbbb-0000-0000-0000-000000000001'),
  'CheckinHero',
  'D2-06(c): participants[].display_name still projected (no body swallow)');

-- ====================================================================
-- (c) regression: tournament.organizer_team_id key still present + correct.
-- ====================================================================
SELECT ok(
  (public.tournament_get('55555555-5555-5555-5555-555555555501')
     -> 'tournament') ? 'organizer_team_id',
  'D2-06(c): tournament.organizer_team_id key still present in the tournament block');

SELECT is(
  (public.tournament_get('55555555-5555-5555-5555-555555555501')
     -> 'tournament' ->> 'organizer_team_id'),
  '66666666-6666-6666-6666-666666666601',
  'D2-06(c): tournament.organizer_team_id projects the correct club');

SELECT * FROM finish();
ROLLBACK;
