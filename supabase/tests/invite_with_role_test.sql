-- pgTAP tests for the invite-with-role migration (20261282000000).
-- ADR-0032 / docs/plans/permissions-organizer-teams PLAN P3-S.
--
-- Covers:
--   (a) club_invite with p_role='referee' -> invitation row role='referee',
--       inbox action_payload carries the role key, accept via
--       club_invitation_respond -> membership roles = ARRAY['referee'];
--   (b) invalid role ('member') -> SQLSTATE 22023 INVALID_ROLE;
--   (c) default path (2-argument call, no p_role) -> role='admin' ->
--       accept -> membership roles = ARRAY['admin']; the 2-argument call
--       also proves the old club_invite(uuid,uuid) overload is gone
--       (no "function is not unique");
--   (d) pg_proc shape: exactly one club_invite / club_invite_by_nickname,
--       each with 3 args of which 1 is defaulted.
--
-- Everything runs inside BEGIN ... ROLLBACK — no persistent test data.
-- Auth context is switched via request.jwt.claims like in
-- role_consolidation_test.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(15);

-- ---------------------------------------------------------------------
-- Helpers: auth switch + fixture builder.
-- ---------------------------------------------------------------------

-- Act as an authenticated user (RPC caller).
CREATE OR REPLACE FUNCTION _iwr_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

-- Back to superuser for direct seeding/asserts (bypasses RLS again).
CREATE OR REPLACE FUNCTION _iwr_su() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

-- Minimal viable auth.users row (FK requirement for memberships etc.).
CREATE OR REPLACE FUNCTION _iwr_mk_user(p_uid uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
    VALUES (p_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'iwr-' || p_uid::text || '@test.local',
            '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;
  RETURN p_uid;
END;
$$;

-- ---------------------------------------------------------------------
-- Fixture: one club with an owner, plus fresh invitee users.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_owner       uuid := _iwr_mk_user(gen_random_uuid());
  v_ref_invitee uuid := _iwr_mk_user(gen_random_uuid()); -- invited as referee
  v_def_invitee uuid := _iwr_mk_user(gen_random_uuid()); -- default path
  v_bad_invitee uuid := _iwr_mk_user(gen_random_uuid()); -- invalid-role target
  v_club        uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.organizer_teams(id, display_name, created_by)
    VALUES (v_club, 'Invite-Role-Club', v_owner);
  INSERT INTO public.team_members(organizer_team_id, user_id, roles)
    VALUES (v_club, v_owner, ARRAY['owner']::text[]);

  CREATE TEMP TABLE _iwr_ctx ON COMMIT DROP AS
    SELECT v_club AS club, v_owner AS owner,
           v_ref_invitee AS ref_invitee, v_def_invitee AS def_invitee,
           v_bad_invitee AS bad_invitee;
END $$;

-- The context table is read while acting as 'authenticated' (it is owned by
-- postgres), so that role needs an explicit SELECT grant. Temp table + grant
-- vanish with the ROLLBACK.
GRANT SELECT ON _iwr_ctx TO authenticated;

-- ---------------------------------------------------------------------
-- 1-3. Invite with p_role='referee': row + inbox payload carry the role.
-- ---------------------------------------------------------------------

SELECT _iwr_as((SELECT owner FROM _iwr_ctx));

SELECT lives_ok(
  format($$
    SELECT public.organizer_team_invite(%L::uuid, %L::uuid, 'referee')
  $$, (SELECT club FROM _iwr_ctx), (SELECT ref_invitee FROM _iwr_ctx)),
  'organizer_team_invite: p_role = referee succeeds');

SELECT _iwr_su();

SELECT is(
  (SELECT role FROM public.club_invitations
    WHERE club_id = (SELECT club FROM _iwr_ctx)
      AND invitee_user_id = (SELECT ref_invitee FROM _iwr_ctx)),
  'referee',
  'club_invite: invitation row persisted with role = referee');

SELECT is(
  (SELECT action_payload->>'role' FROM public.user_inbox_messages
    WHERE user_id = (SELECT ref_invitee FROM _iwr_ctx)
      AND kind = 'club_invitation'),
  'referee',
  'club_invite: inbox action_payload carries role = referee');

-- ---------------------------------------------------------------------
-- 4+5. Accept -> membership roles = [referee].
-- ---------------------------------------------------------------------

DO $$
BEGIN
  CREATE TEMP TABLE _iwr_inv_ref ON COMMIT DROP AS
    SELECT id AS inv FROM public.club_invitations
     WHERE club_id = (SELECT club FROM _iwr_ctx)
       AND invitee_user_id = (SELECT ref_invitee FROM _iwr_ctx);
END $$;

GRANT SELECT ON _iwr_inv_ref TO authenticated;

SELECT _iwr_as((SELECT ref_invitee FROM _iwr_ctx));

SELECT lives_ok(
  format($$ SELECT public.organizer_team_invitation_respond(%L::uuid, true) $$,
         (SELECT inv FROM _iwr_inv_ref)),
  'organizer_team_invitation_respond: accept of referee invitation succeeds');

SELECT _iwr_su();

SELECT is(
  (SELECT roles FROM public.team_members
    WHERE organizer_team_id = (SELECT club FROM _iwr_ctx)
      AND user_id = (SELECT ref_invitee FROM _iwr_ctx)
      AND removed_at IS NULL),
  ARRAY['referee']::text[],
  'organizer_team_invitation_respond: accept creates membership with roles = [referee]');

-- ---------------------------------------------------------------------
-- 6. Invalid role -> SQLSTATE 22023 INVALID_ROLE.
-- ---------------------------------------------------------------------

SELECT _iwr_as((SELECT owner FROM _iwr_ctx));

SELECT throws_ok(
  format($$
    SELECT public.organizer_team_invite(%L::uuid, %L::uuid, 'member')
  $$, (SELECT club FROM _iwr_ctx), (SELECT bad_invitee FROM _iwr_ctx)),
  '22023', 'INVALID_ROLE',
  'organizer_team_invite: p_role = member -> 22023 INVALID_ROLE');

-- ---------------------------------------------------------------------
-- 7-11. Default path: 2-argument call (also proves the old 2-parameter
-- overload is dropped — would raise "function is not unique" otherwise)
-- -> role = admin -> accept -> membership roles = [admin].
-- ---------------------------------------------------------------------

SELECT lives_ok(
  format($$
    SELECT public.organizer_team_invite(%L::uuid, %L::uuid)
  $$, (SELECT club FROM _iwr_ctx), (SELECT def_invitee FROM _iwr_ctx)),
  'organizer_team_invite: 2-argument default call succeeds (no ambiguous overload)');

SELECT _iwr_su();

SELECT is(
  (SELECT role FROM public.club_invitations
    WHERE club_id = (SELECT club FROM _iwr_ctx)
      AND invitee_user_id = (SELECT def_invitee FROM _iwr_ctx)),
  'admin',
  'club_invite: default path persists role = admin');

SELECT is(
  (SELECT action_payload->>'role' FROM public.user_inbox_messages
    WHERE user_id = (SELECT def_invitee FROM _iwr_ctx)
      AND kind = 'club_invitation'),
  'admin',
  'club_invite: default path inbox action_payload carries role = admin');

DO $$
BEGIN
  CREATE TEMP TABLE _iwr_inv_def ON COMMIT DROP AS
    SELECT id AS inv FROM public.club_invitations
     WHERE club_id = (SELECT club FROM _iwr_ctx)
       AND invitee_user_id = (SELECT def_invitee FROM _iwr_ctx);
END $$;

GRANT SELECT ON _iwr_inv_def TO authenticated;

SELECT _iwr_as((SELECT def_invitee FROM _iwr_ctx));

SELECT lives_ok(
  format($$ SELECT public.organizer_team_invitation_respond(%L::uuid, true) $$,
         (SELECT inv FROM _iwr_inv_def)),
  'organizer_team_invitation_respond: accept of default invitation succeeds');

SELECT _iwr_su();

SELECT is(
  (SELECT roles FROM public.team_members
    WHERE organizer_team_id = (SELECT club FROM _iwr_ctx)
      AND user_id = (SELECT def_invitee FROM _iwr_ctx)
      AND removed_at IS NULL),
  ARRAY['admin']::text[],
  'organizer_team_invitation_respond: accept creates membership with roles = [admin]');

-- ---------------------------------------------------------------------
-- 12-15. pg_proc shape: exactly one definition per invite RPC, with the
-- new 3-parameter signature (1 defaulted) — no ambiguous overloads left.
-- ---------------------------------------------------------------------

SELECT is(
  (SELECT count(*)::int FROM pg_proc
    WHERE proname = 'organizer_team_invite'
      AND pronamespace = 'public'::regnamespace),
  1,
  'pg_proc: exactly one organizer_team_invite definition');

SELECT ok(
  (SELECT pronargs = 3 AND pronargdefaults = 1 FROM pg_proc
    WHERE proname = 'organizer_team_invite'
      AND pronamespace = 'public'::regnamespace),
  'pg_proc: organizer_team_invite has 3 args, 1 defaulted');

SELECT is(
  (SELECT count(*)::int FROM pg_proc
    WHERE proname = 'organizer_team_invite_by_nickname'
      AND pronamespace = 'public'::regnamespace),
  1,
  'pg_proc: exactly one organizer_team_invite_by_nickname definition');

SELECT ok(
  (SELECT pronargs = 3 AND pronargdefaults = 1 FROM pg_proc
    WHERE proname = 'organizer_team_invite_by_nickname'
      AND pronamespace = 'public'::regnamespace),
  'pg_proc: organizer_team_invite_by_nickname has 3 args, 1 defaulted');

SELECT * FROM finish();

ROLLBACK;
