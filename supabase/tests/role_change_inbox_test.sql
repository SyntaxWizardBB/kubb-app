-- pgTAP: organizer_team_set_member_roles emits a 'club_role_changed' inbox
-- row to the affected member (ADR-0032 P7), and does NOT notify on a
-- self-change. Runs entirely inside BEGIN .. ROLLBACK.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;
SELECT plan(4);

-- Auth helpers ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION _rci_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END; $$;

CREATE OR REPLACE FUNCTION _rci_su() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END; $$;

CREATE OR REPLACE FUNCTION _rci_mk_user(p_uid uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
    VALUES (p_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'rci-' || p_uid::text || '@test.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;
  RETURN p_uid;
END; $$;

-- Fixture: one team, an owner (caller) and an admin member (target) ----------
DO $$
DECLARE
  v_owner  uuid := _rci_mk_user(gen_random_uuid());
  v_member uuid := _rci_mk_user(gen_random_uuid());
  v_team   uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.organizer_teams(id, display_name, created_by)
    VALUES (v_team, 'P7-Team', v_owner);
  INSERT INTO public.team_members(organizer_team_id, user_id, roles)
    VALUES (v_team, v_owner, ARRAY['owner']::text[]),
           (v_team, v_member, ARRAY['admin']::text[]);
  CREATE TEMP TABLE _rci_ctx ON COMMIT DROP AS
    SELECT v_team AS team, v_owner AS owner, v_member AS member;
END $$;
GRANT SELECT ON _rci_ctx TO authenticated;

-- 1) Owner promotes the member to referee -> one inbox row for the member ----
SELECT _rci_as((SELECT owner FROM _rci_ctx));
SELECT lives_ok(
  $$ SELECT public.organizer_team_set_member_roles(
       (SELECT team FROM _rci_ctx),
       (SELECT member FROM _rci_ctx),
       ARRAY['referee']::text[]) $$,
  'owner may change a member role');

SELECT _rci_su();
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE user_id = (SELECT member FROM _rci_ctx)
       AND kind = 'club_role_changed'),
  1, 'member received exactly one club_role_changed inbox row');

SELECT is(
  (SELECT action_payload->>'organizer_team_id' FROM public.user_inbox_messages
     WHERE user_id = (SELECT member FROM _rci_ctx)
       AND kind = 'club_role_changed'),
  (SELECT team::text FROM _rci_ctx),
  'inbox payload carries the organizer_team_id (PII-free)');

-- 2) Owner changes their OWN roles -> no self-notification -------------------
SELECT _rci_as((SELECT owner FROM _rci_ctx));
SELECT public.organizer_team_set_member_roles(
  (SELECT team FROM _rci_ctx),
  (SELECT owner FROM _rci_ctx),
  ARRAY['owner','admin']::text[]);

SELECT _rci_su();
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE user_id = (SELECT owner FROM _rci_ctx)
       AND kind = 'club_role_changed'),
  0, 'a self role-change does not notify the caller');

SELECT finish();
ROLLBACK;
