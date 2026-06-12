-- pgTAP tests for the role consolidation migration (20261280000000).
-- ADR-0032 / docs/plans/permissions-organizer-teams PLAN P1-S.
--
-- Covers:
--   (a) club_set_member_roles rejects 'member' and 'organizer' (removed
--       roles) and accepts 'referee';
--   (b) remap behaviour organizer/scorekeeper -> admin via an in-transaction
--       legacy simulation (CHECK temporarily dropped, migration statements
--       re-applied verbatim), incl. audit rows, dedupe, empty fallback and
--       the deliberate absence of a removed_at filter;
--   (c) the narrowed CHECK rejects ARRAY['member'];
--   (d) invitation accept creates a membership with roles = ARRAY['admin']
--       (plus the analogous join-request accept).
--
-- Everything runs inside BEGIN ... ROLLBACK — no persistent test data.
-- Auth context is switched via request.jwt.claims like in team_rpcs_test.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(20);

-- ---------------------------------------------------------------------
-- Helpers: auth switch + fixture builder.
-- ---------------------------------------------------------------------

-- Act as an authenticated user (RPC caller).
CREATE OR REPLACE FUNCTION _rc_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

-- Back to superuser for direct seeding/asserts (bypasses RLS again).
CREATE OR REPLACE FUNCTION _rc_su() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

-- Minimal viable auth.users row (FK requirement for memberships etc.).
CREATE OR REPLACE FUNCTION _rc_mk_user(p_uid uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
    VALUES (p_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'rc-' || p_uid::text || '@test.local',
            '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;
  RETURN p_uid;
END;
$$;

-- ---------------------------------------------------------------------
-- Fixture: one club with an owner and an admin member, plus spare users.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_owner    uuid := _rc_mk_user(gen_random_uuid());
  v_admin    uuid := _rc_mk_user(gen_random_uuid()); -- target of set_member_roles
  v_ref      uuid := _rc_mk_user(gen_random_uuid()); -- direct referee insert
  v_noroles  uuid := _rc_mk_user(gen_random_uuid()); -- insert without roles
  v_member   uuid := _rc_mk_user(gen_random_uuid()); -- insert with ['member']
  v_invitee  uuid := _rc_mk_user(gen_random_uuid());
  v_request  uuid := _rc_mk_user(gen_random_uuid());
  v_club     uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.clubs(id, display_name, created_by)
    VALUES (v_club, 'Konsolidierungs-Club', v_owner);
  INSERT INTO public.club_memberships(club_id, user_id, roles)
    VALUES (v_club, v_owner, ARRAY['owner']::text[]),
           (v_club, v_admin, ARRAY['admin']::text[]);

  CREATE TEMP TABLE _rc_ctx ON COMMIT DROP AS
    SELECT v_club AS club, v_owner AS owner, v_admin AS admin_member,
           v_ref AS ref_user, v_noroles AS noroles_user,
           v_member AS member_user, v_invitee AS invitee,
           v_request AS requester;
END $$;

-- The context table is read while acting as 'authenticated' (it is owned by
-- postgres), so that role needs an explicit SELECT grant. Temp table + grant
-- vanish with the ROLLBACK.
GRANT SELECT ON _rc_ctx TO authenticated;

-- ---------------------------------------------------------------------
-- 1+2. Narrowed CHECK: ['member'] rejected (23514), ['referee'] accepted.
-- ---------------------------------------------------------------------

SELECT throws_ok(
  format($$
    INSERT INTO public.club_memberships(club_id, user_id, roles)
      VALUES (%L::uuid, %L::uuid, ARRAY['member']::text[])
  $$, (SELECT club FROM _rc_ctx), (SELECT member_user FROM _rc_ctx)),
  '23514', NULL,
  'CHECK: roles = [member] is rejected (23514)');

SELECT lives_ok(
  format($$
    INSERT INTO public.club_memberships(club_id, user_id, roles)
      VALUES (%L::uuid, %L::uuid, ARRAY['referee']::text[])
  $$, (SELECT club FROM _rc_ctx), (SELECT ref_user FROM _rc_ctx)),
  'CHECK: roles = [referee] is accepted');

-- ---------------------------------------------------------------------
-- 3+4. DEFAULT dropped: no column default, INSERT without roles fails.
-- ---------------------------------------------------------------------

SELECT ok(
  (SELECT column_default IS NULL
     FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'club_memberships'
      AND column_name = 'roles'),
  'DEFAULT: club_memberships.roles has no default anymore');

SELECT throws_ok(
  format($$
    INSERT INTO public.club_memberships(club_id, user_id)
      VALUES (%L::uuid, %L::uuid)
  $$, (SELECT club FROM _rc_ctx), (SELECT noroles_user FROM _rc_ctx)),
  '23502', NULL,
  'DEFAULT: INSERT without roles fails (NOT NULL, no default)');

-- ---------------------------------------------------------------------
-- 5-8. club_set_member_roles: member/organizer rejected, referee accepted.
-- ---------------------------------------------------------------------

SELECT _rc_as((SELECT owner FROM _rc_ctx));

SELECT throws_ok(
  format($$
    SELECT public.club_set_member_roles(%L::uuid, %L::uuid,
                                        ARRAY['member']::text[])
  $$, (SELECT club FROM _rc_ctx), (SELECT admin_member FROM _rc_ctx)),
  'P0001', 'INVALID_ROLE',
  'club_set_member_roles: [member] -> P0001 INVALID_ROLE');

SELECT throws_ok(
  format($$
    SELECT public.club_set_member_roles(%L::uuid, %L::uuid,
                                        ARRAY['organizer']::text[])
  $$, (SELECT club FROM _rc_ctx), (SELECT admin_member FROM _rc_ctx)),
  'P0001', 'INVALID_ROLE',
  'club_set_member_roles: [organizer] -> P0001 INVALID_ROLE');

SELECT lives_ok(
  format($$
    SELECT public.club_set_member_roles(%L::uuid, %L::uuid,
                                        ARRAY['referee']::text[])
  $$, (SELECT club FROM _rc_ctx), (SELECT admin_member FROM _rc_ctx)),
  'club_set_member_roles: [referee] is accepted');

SELECT _rc_su();

SELECT is(
  (SELECT roles FROM public.club_memberships
    WHERE club_id = (SELECT club FROM _rc_ctx)
      AND user_id = (SELECT admin_member FROM _rc_ctx)
      AND removed_at IS NULL),
  ARRAY['referee']::text[],
  'club_set_member_roles: roles persisted as [referee]');

-- ---------------------------------------------------------------------
-- 9+10. Invitation accept -> membership with roles = [admin].
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_inv uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.club_invitations(id, club_id, invitee_user_id, invited_by)
    VALUES (v_inv, (SELECT club FROM _rc_ctx),
            (SELECT invitee FROM _rc_ctx), (SELECT owner FROM _rc_ctx));
  CREATE TEMP TABLE _rc_inv_ctx ON COMMIT DROP AS SELECT v_inv AS inv;
END $$;

-- Read under role 'authenticated' below -> needs an explicit SELECT grant.
GRANT SELECT ON _rc_inv_ctx TO authenticated;

SELECT _rc_as((SELECT invitee FROM _rc_ctx));

SELECT lives_ok(
  format($$ SELECT public.club_invitation_respond(%L::uuid, true) $$,
         (SELECT inv FROM _rc_inv_ctx)),
  'club_invitation_respond: accept succeeds');

SELECT _rc_su();

SELECT is(
  (SELECT roles FROM public.club_memberships
    WHERE club_id = (SELECT club FROM _rc_ctx)
      AND user_id = (SELECT invitee FROM _rc_ctx)
      AND removed_at IS NULL),
  ARRAY['admin']::text[],
  'club_invitation_respond: accept creates membership with roles = [admin]');

-- ---------------------------------------------------------------------
-- 11+12. Join-request accept -> membership with roles = [admin].
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_req uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.club_join_requests(id, club_id, user_id)
    VALUES (v_req, (SELECT club FROM _rc_ctx), (SELECT requester FROM _rc_ctx));
  CREATE TEMP TABLE _rc_req_ctx ON COMMIT DROP AS SELECT v_req AS req;
END $$;

-- Read under role 'authenticated' below -> needs an explicit SELECT grant.
GRANT SELECT ON _rc_req_ctx TO authenticated;

SELECT _rc_as((SELECT owner FROM _rc_ctx));

SELECT lives_ok(
  format($$ SELECT public.club_respond_join_request(%L::uuid, true) $$,
         (SELECT req FROM _rc_req_ctx)),
  'club_respond_join_request: accept succeeds');

SELECT _rc_su();

SELECT is(
  (SELECT roles FROM public.club_memberships
    WHERE club_id = (SELECT club FROM _rc_ctx)
      AND user_id = (SELECT requester FROM _rc_ctx)
      AND removed_at IS NULL),
  ARRAY['admin']::text[],
  'club_respond_join_request: accept creates membership with roles = [admin]');

-- ---------------------------------------------------------------------
-- 13-20. Legacy remap simulation (in-transaction, rolled back):
-- drop the narrowed CHECK, seed legacy-role rows, re-apply the migration's
-- audit INSERT + remap UPDATE verbatim, and assert the outcome.
-- ---------------------------------------------------------------------

ALTER TABLE public.club_memberships
  DROP CONSTRAINT club_memberships_roles_check;

DO $$
DECLARE
  v_l1 uuid := _rc_mk_user(gen_random_uuid()); -- ['organizer']
  v_l2 uuid := _rc_mk_user(gen_random_uuid()); -- ['member','scorekeeper']
  v_l3 uuid := _rc_mk_user(gen_random_uuid()); -- ['admin','organizer','timemaster'] (dedupe)
  v_l4 uuid := _rc_mk_user(gen_random_uuid()); -- ['owner','organizer']
  v_l5 uuid := _rc_mk_user(gen_random_uuid()); -- soft-deleted ['member']
  v_club uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.clubs(id, display_name, created_by)
    VALUES (v_club, 'Legacy-Club', v_l4);
  INSERT INTO public.club_memberships(club_id, user_id, roles, removed_at)
    VALUES (v_club, v_l1, ARRAY['organizer']::text[], NULL),
           (v_club, v_l2, ARRAY['member','scorekeeper']::text[], NULL),
           (v_club, v_l3, ARRAY['admin','organizer','timemaster']::text[], NULL),
           (v_club, v_l4, ARRAY['owner','organizer']::text[], NULL),
           (v_club, v_l5, ARRAY['member']::text[], now());

  CREATE TEMP TABLE _rc_legacy_ctx ON COMMIT DROP AS
    SELECT v_club AS club, v_l1 AS l1, v_l2 AS l2, v_l3 AS l3,
           v_l4 AS l4, v_l5 AS l5;
END $$;

-- Migration statement 1 (verbatim copy): audit insert before remap.
INSERT INTO public.club_audit_events (club_id, kind, actor_user_id, payload)
SELECT m.club_id,
       'roles_consolidated',
       NULL,
       jsonb_build_object(
         'user_id', m.user_id,
         'roles',   to_jsonb(m.roles)
       )
  FROM public.club_memberships m
 WHERE NOT (m.roles <@ ARRAY['owner','admin','referee']::text[]);

SELECT is(
  (SELECT count(*)::int FROM public.club_audit_events
    WHERE club_id = (SELECT club FROM _rc_legacy_ctx)
      AND kind = 'roles_consolidated'),
  5,
  'remap audit: one roles_consolidated event per affected membership');

SELECT is(
  (SELECT payload->'roles' FROM public.club_audit_events
    WHERE club_id = (SELECT club FROM _rc_legacy_ctx)
      AND kind = 'roles_consolidated'
      AND payload->>'user_id' = (SELECT l1 FROM _rc_legacy_ctx)::text),
  '["organizer"]'::jsonb,
  'remap audit: payload carries the OLD roles array');

-- Migration statement 2 (verbatim copy): remap update before CHECK.
UPDATE public.club_memberships
   SET roles = COALESCE(
         (SELECT array_agg(DISTINCT
                   CASE WHEN r = 'organizer' THEN 'admin' ELSE r END)
            FROM unnest(roles) AS r
           WHERE r IN ('owner', 'admin', 'referee', 'organizer')),
         ARRAY['admin']::text[])
 WHERE NOT (roles <@ ARRAY['owner','admin','referee']::text[]);

SELECT is(
  (SELECT roles FROM public.club_memberships
    WHERE club_id = (SELECT club FROM _rc_legacy_ctx)
      AND user_id = (SELECT l1 FROM _rc_legacy_ctx)),
  ARRAY['admin']::text[],
  'remap: [organizer] -> [admin]');

SELECT is(
  (SELECT roles FROM public.club_memberships
    WHERE club_id = (SELECT club FROM _rc_legacy_ctx)
      AND user_id = (SELECT l2 FROM _rc_legacy_ctx)),
  ARRAY['admin']::text[],
  'remap: [member, scorekeeper] -> stripped empty -> fallback [admin]');

SELECT is(
  (SELECT roles FROM public.club_memberships
    WHERE club_id = (SELECT club FROM _rc_legacy_ctx)
      AND user_id = (SELECT l3 FROM _rc_legacy_ctx)),
  ARRAY['admin']::text[],
  'remap: [admin, organizer, timemaster] -> deduped [admin]');

-- Compare order-insensitively: array_agg(DISTINCT ...) has no guaranteed
-- element order, so sort before asserting.
SELECT is(
  (SELECT (SELECT array_agg(r ORDER BY r) FROM unnest(m.roles) AS r)
     FROM public.club_memberships m
    WHERE m.club_id = (SELECT club FROM _rc_legacy_ctx)
      AND m.user_id = (SELECT l4 FROM _rc_legacy_ctx)),
  ARRAY['admin','owner']::text[],
  'remap: [owner, organizer] -> {admin, owner} (owner kept, organizer mapped)');

SELECT is(
  (SELECT roles FROM public.club_memberships
    WHERE club_id = (SELECT club FROM _rc_legacy_ctx)
      AND user_id = (SELECT l5 FROM _rc_legacy_ctx)),
  ARRAY['admin']::text[],
  'remap: soft-deleted row is remapped too (no removed_at filter)');

SELECT is(
  (SELECT count(*)::int FROM public.club_memberships
    WHERE NOT (roles <@ ARRAY['owner','admin','referee']::text[])),
  0,
  'remap invariant: no row (incl. removed) violates the narrowed role set');

SELECT * FROM finish();

ROLLBACK;
