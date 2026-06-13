-- P9 BUG-2: pgTAP coverage for the name-uniqueness availability RPCs and the
-- clubs unique index added in migration 20261244000000.
--
-- Cases:
--   1. clubs_display_name_unique_idx exists.
--   2. profile_nickname_available: free name → true.
--   3. profile_nickname_available: taken name (other user) → false.
--   4. profile_nickname_available: case/whitespace-insensitive match → false.
--   5. profile_nickname_available: blank → false.
--   6. profile_nickname_available: caller's OWN name excluded → true.
--   7. team_name_available: free → true; taken → false; exclude-self → true.
--   8. club_name_available: free → true; taken → false; exclude-self → true.
--   9. club_create raises 23505 with a clear message on a duplicate name.
--
-- Runs in BEGIN/ROLLBACK so all fixtures are discarded.

BEGIN;

SELECT plan(14);

-- ---- Fixtures ---------------------------------------------------------

CREATE OR REPLACE FUNCTION _nameuniq_seed_user(p_nick text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_uid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'nameuniq-' || v_uid::text || '@test.local',
            '', now(), now(), now());
  INSERT INTO public.user_profiles(user_id, nickname, can_found_clubs)
    VALUES (v_uid, p_nick, true);
  RETURN v_uid;
END;
$$;

CREATE OR REPLACE FUNCTION _nameuniq_as_user(p_uid uuid)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'authenticated', true);
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true);
END;
$$;

DO $$
DECLARE
  v_owner   uuid;
  v_other   uuid;
  v_team_id uuid;
  v_club_id uuid;
BEGIN
  v_owner := _nameuniq_seed_user('OwnerNick');
  v_other := _nameuniq_seed_user('OtherNick');

  INSERT INTO public.teams(display_name, league_membership, created_by)
    VALUES ('Wiesen Kubbler', 'B', v_owner)
    RETURNING id INTO v_team_id;

  INSERT INTO public.organizer_teams(display_name, created_by)
    VALUES ('Meadow Club', v_owner)
    RETURNING id INTO v_club_id;

  CREATE TEMP TABLE _nameuniq_ctx ON COMMIT DROP AS
    SELECT v_owner AS owner_id, v_other AS other_id,
           v_team_id AS team_id, v_club_id AS club_id;
  -- The availability checks run as the `authenticated` role; let it read the
  -- fixture ids (the temp table is owned by the postgres superuser).
  GRANT SELECT ON _nameuniq_ctx TO authenticated;
END $$;

-- ---- 1. Index exists --------------------------------------------------

SELECT ok(
  EXISTS (SELECT 1 FROM pg_indexes
           WHERE schemaname='public'
             AND indexname='clubs_display_name_unique_idx'),
  'clubs_display_name_unique_idx exists');

-- Act as the "owner" user for the availability checks.
SELECT _nameuniq_as_user((SELECT owner_id FROM _nameuniq_ctx));

-- ---- 2..6 profile_nickname_available ---------------------------------

SELECT is(public.profile_nickname_available('BrandNewName'), true,
  'profile: a free nickname is available');

SELECT is(public.profile_nickname_available('OtherNick'), false,
  'profile: another user''s nickname is not available');

SELECT is(public.profile_nickname_available('  othernick  '), false,
  'profile: match is case- and whitespace-insensitive');

SELECT is(public.profile_nickname_available('   '), false,
  'profile: blank is not available');

SELECT is(public.profile_nickname_available('OwnerNick'), true,
  'profile: the caller''s own nickname is excluded (still available)');

-- ---- 7. team_name_available ------------------------------------------

SELECT is(public.team_name_available('Frische Truppe'), true,
  'team: a free name is available');

SELECT is(public.team_name_available('  wiesen kubbler '), false,
  'team: an existing name is not available (ci/ws-insensitive)');

SELECT is(
  public.team_name_available('Wiesen Kubbler',
                             (SELECT team_id FROM _nameuniq_ctx)),
  true,
  'team: excluding the team''s own id makes its name available (rename)');

-- ---- 8. organizer_team_name_available ---------------------------------

SELECT is(public.organizer_team_name_available('Anderer Verein'), true,
  'club: a free name is available');

SELECT is(public.organizer_team_name_available('  MEADOW club '), false,
  'club: an existing name is not available (ci/ws-insensitive)');

SELECT is(
  public.organizer_team_name_available('Meadow Club',
                             (SELECT club_id FROM _nameuniq_ctx)),
  true,
  'club: excluding the club''s own id makes its name available');

-- ---- 9. organizer_team_create raises 23505 on a duplicate name --------

SELECT throws_ok(
  $$ SELECT public.organizer_team_create('meadow club') $$,
  '23505',
  NULL,
  'organizer_team_create: a duplicate name raises ERRCODE 23505');

-- A fresh name still succeeds for an allowed founder.
SELECT lives_ok(
  $$ SELECT public.organizer_team_create('Totally Fresh Club') $$,
  'organizer_team_create: a fresh unique name succeeds');

SELECT * FROM finish();

ROLLBACK;
