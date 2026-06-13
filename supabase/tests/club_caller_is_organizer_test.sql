-- pgTAP tests for organizer_team_caller_is_organizer() (migration
-- 20261282500000, renamed from club_caller_is_organizer in 20261283000000).
-- ADR-0032 / docs/plans/permissions-organizer-teams PLAN P4-S.
--
-- Covers the three PLAN cases:
--   (1) user with user_profiles.can_found_clubs = true and NO membership
--       -> true;
--   (2) user without can_found_clubs but with an active membership
--       roles = ['referee'] -> true;
--   (3) outsider (no can_found_clubs, only a removed membership) -> false.
--
-- Everything runs inside BEGIN ... ROLLBACK — no persistent test data.
-- Auth context is switched via request.jwt.claims like in team_rpcs_test.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(3);

-- ---------------------------------------------------------------------
-- Helpers: auth switch + fixture builder.
-- ---------------------------------------------------------------------

-- Act as an authenticated user (function caller).
CREATE OR REPLACE FUNCTION _cio_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

-- Back to superuser for direct seeding (bypasses RLS again).
CREATE OR REPLACE FUNCTION _cio_su() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

-- Minimal viable auth.users row (FK requirement for profiles/memberships).
CREATE OR REPLACE FUNCTION _cio_mk_user(p_uid uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
    VALUES (p_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'cio-' || p_uid::text || '@test.local',
            '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;
  RETURN p_uid;
END;
$$;

-- ---------------------------------------------------------------------
-- Fixture: deterministic user ids (no ctx table needed) + one club.
--   founder  — can_found_clubs = true, no membership at all
--   referee  — can_found_clubs = false, active membership ['referee']
--   outsider — can_found_clubs = false, only a REMOVED membership ['admin']
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_founder  uuid := _cio_mk_user('00000000-0000-4000-8000-0000000c1001');
  v_referee  uuid := _cio_mk_user('00000000-0000-4000-8000-0000000c1002');
  v_outsider uuid := _cio_mk_user('00000000-0000-4000-8000-0000000c1003');
  v_club     uuid := gen_random_uuid();
BEGIN
  -- Profiles: upsert because a signup trigger may have created rows already.
  INSERT INTO public.user_profiles(user_id, can_found_clubs)
    VALUES (v_founder, true), (v_referee, false), (v_outsider, false)
    ON CONFLICT (user_id) DO UPDATE SET can_found_clubs = EXCLUDED.can_found_clubs;

  INSERT INTO public.organizer_teams(id, display_name, created_by)
    VALUES (v_club, 'Organizer-Gate-Club', v_referee);

  -- Active referee-only membership.
  INSERT INTO public.team_members(organizer_team_id, user_id, roles)
    VALUES (v_club, v_referee, ARRAY['referee']::text[]);

  -- Removed membership for the outsider (must NOT count as organizer).
  INSERT INTO public.team_members(organizer_team_id, user_id, roles,
                                      removed_at, removed_by)
    VALUES (v_club, v_outsider, ARRAY['admin']::text[], now(), v_referee);
END $$;

-- ---------------------------------------------------------------------
-- 1. can_found_clubs user without any membership -> true.
-- ---------------------------------------------------------------------

SELECT _cio_as('00000000-0000-4000-8000-0000000c1001');

SELECT is(
  public.organizer_team_caller_is_organizer(),
  true,
  'can_found_clubs user without membership is an organizer');

-- ---------------------------------------------------------------------
-- 2. referee-only active membership, no can_found_clubs -> true.
-- ---------------------------------------------------------------------

SELECT _cio_as('00000000-0000-4000-8000-0000000c1002');

SELECT is(
  public.organizer_team_caller_is_organizer(),
  true,
  'active referee-only member is an organizer');

-- ---------------------------------------------------------------------
-- 3. outsider: no can_found_clubs, only removed membership -> false.
-- ---------------------------------------------------------------------

SELECT _cio_as('00000000-0000-4000-8000-0000000c1003');

SELECT is(
  public.organizer_team_caller_is_organizer(),
  false,
  'outsider (removed membership, no flag) is NOT an organizer');

SELECT _cio_su();

SELECT * FROM finish();
ROLLBACK;
