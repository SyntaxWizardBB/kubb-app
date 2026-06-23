-- Regression suite for the match-RLS recursion fix
-- (20261310000000_fix_match_rls_recursion.sql).
--
-- Before the fix, match_participants_participant_read read its own table in
-- the USING clause → sqlstate 42P17 'infinite recursion detected in policy'.
-- That recursion propagated to matches reads through matches_participant_read's
-- inline EXISTS on match_participants. The fix routes the participant policy's
-- membership check through the SECURITY DEFINER helper
-- public._is_match_participant, which the function owner evaluates without
-- re-applying RLS — so the recursion is broken.
--
-- What is asserted here (truthful post-migration contract):
--   1. The recursion is gone. A direct match_participants read no longer
--      raises 42P17; it raises 42501 (grant-denied, RPC-only per ADR-0013)
--      — a different, non-recursive failure mode.
--   2. The DEFINER helper itself does NOT recurse and scopes by auth.uid():
--      a participant gets true, a non-participant false, for the same match.
--   3. anon / public EXECUTE on the helper is denied (42501).
--   4. Grant contract: match_participants has NO authenticated SELECT grant
--      (RPC-only); matches HAS one (CDC delivery, PART B).
--   5. matches_participant_read now routes the participant branch through the
--      DEFINER helper, so full visibility is real: a participant reads its
--      match, the creator reads its match, a non-participant non-creator reads
--      zero — and none of them 42501 anymore (the grant is no longer inert).
--
-- pgTAP is available but not pre-installed; CREATE EXTENSION IF NOT EXISTS
-- inside the BEGIN..ROLLBACK keeps the install transient. Role switch via
-- set_config, matching public_rls_test.sql / season_rls.test.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(12);

-- ---------------------------------------------------------------------
-- Helpers: role switches.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _mr_as_user(p_uid uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _mr_as_anon() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
END;
$$;

CREATE OR REPLACE FUNCTION _mr_as_postgres() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
END;
$$;

-- Captures the sqlstate a direct match_participants read raises for the
-- given user. Runs the read inside the helper's own block so the role
-- switch and the read share one statement context.
CREATE OR REPLACE FUNCTION _mr_read_mp_sqlstate(p_uid uuid)
RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_state text := 'OK';
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    PERFORM count(*) FROM public.match_participants;
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;
  PERFORM set_config('role', 'postgres', true);
  RETURN v_state;
END;
$$;

-- Counts the matches a given user can SELECT under RLS as role authenticated.
-- Role switch and read share one statement context, like the sqlstate helper.
CREATE OR REPLACE FUNCTION _mr_visible_matches(p_uid uuid, p_match uuid)
RETURNS int LANGUAGE plpgsql AS $$
DECLARE v_cnt int;
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*)::int INTO v_cnt FROM public.matches WHERE id = p_match;
  PERFORM set_config('role', 'postgres', true);
  RETURN v_cnt;
END;
$$;

-- ---------------------------------------------------------------------
-- Fixture: one match with two in_app participants U (team A) and W
-- (team B). V is a third user who is NOT a participant. Direct-insert as
-- postgres bypasses RLS (pattern from public_rls_test.sql).
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_match uuid := gen_random_uuid();
  v_u uuid := gen_random_uuid();
  v_w uuid := gen_random_uuid();
  v_v uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    SELECT x, '00000000-0000-0000-0000-000000000000',
           'authenticated', 'authenticated',
           'mr-' || x::text || '@test.local', '', now(), now(), now()
    FROM unnest(ARRAY[v_u, v_w, v_v]) AS x;

  INSERT INTO public.matches(id, created_by, format, scoring, status)
    VALUES (v_match, v_u, 'bo1', 'wins', 'active');

  INSERT INTO public.match_teams(match_id, team_id) VALUES
    (v_match, 'A'), (v_match, 'B');

  INSERT INTO public.match_participants(
      match_id, team_id, kind, user_id, invitation_status)
    VALUES
    (v_match, 'A', 'in_app', v_u, 'accepted'),
    (v_match, 'B', 'in_app', v_w, 'accepted');

  CREATE TEMP TABLE _mr_ctx ON COMMIT DROP AS
    SELECT v_match AS match_id, v_u AS u, v_w AS w, v_v AS v;
  GRANT SELECT ON _mr_ctx TO authenticated, anon;
END $$;

-- ---------------------------------------------------------------------
-- 1. Recursion is gone: a match_participants read no longer raises the
--    42P17 'infinite recursion' error. It now grant-denies with 42501
--    (RPC-only surface), which is the correct non-recursive failure mode.
-- ---------------------------------------------------------------------

SELECT isnt(
  _mr_read_mp_sqlstate((SELECT u FROM _mr_ctx)),
  '42P17',
  'match_participants read no longer raises 42P17 (recursion broken)');

SELECT is(
  _mr_read_mp_sqlstate((SELECT u FROM _mr_ctx)),
  '42501',
  'match_participants read now grant-denies (42501, RPC-only per ADR-0013)');

-- ---------------------------------------------------------------------
-- 2. The DEFINER helper does NOT recurse and scopes by auth.uid():
--    participant U → true, non-participant V → false, same match.
-- ---------------------------------------------------------------------

SELECT _mr_as_user((SELECT u FROM _mr_ctx));

SELECT ok(
  public._is_match_participant((SELECT match_id FROM _mr_ctx)),
  'helper returns true for participant U — no recursion');

SELECT _mr_as_user((SELECT v FROM _mr_ctx));

SELECT ok(
  NOT public._is_match_participant((SELECT match_id FROM _mr_ctx)),
  'helper returns false for non-participant V — scoping by auth.uid()');

-- ---------------------------------------------------------------------
-- 3. anon / public EXECUTE on the helper is denied.
-- ---------------------------------------------------------------------

SELECT _mr_as_anon();

SELECT throws_ok(
  'SELECT public._is_match_participant(gen_random_uuid())',
  '42501', NULL,
  'anon EXECUTE on _is_match_participant → 42501 (denied)');

-- ---------------------------------------------------------------------
-- 4. Grant contract: match_participants has NO authenticated SELECT
--    grant (RPC-only, ADR-0013); matches HAS one (CDC delivery, PART B).
-- ---------------------------------------------------------------------

SELECT _mr_as_postgres();

SELECT is(
  (SELECT count(*)::int FROM information_schema.role_table_grants
     WHERE grantee='authenticated' AND table_schema='public'
       AND table_name='match_participants' AND privilege_type='SELECT'),
  0,
  'match_participants has NO authenticated SELECT grant (RPC-only)');

SELECT is(
  (SELECT count(*)::int FROM information_schema.role_table_grants
     WHERE grantee='authenticated' AND table_schema='public'
       AND table_name='matches' AND privilege_type='SELECT'),
  1,
  'matches HAS an authenticated SELECT grant (CDC)');

-- ---------------------------------------------------------------------
-- 5. Helper EXECUTE is granted to authenticated, denied to public/anon
--    at the privilege level (acl check).
-- ---------------------------------------------------------------------

SELECT ok(
  has_function_privilege('authenticated',
    'public._is_match_participant(uuid)', 'EXECUTE'),
  'authenticated has EXECUTE on _is_match_participant');

SELECT ok(
  NOT has_function_privilege('anon',
    'public._is_match_participant(uuid)', 'EXECUTE'),
  'anon has NO EXECUTE on _is_match_participant');

-- ---------------------------------------------------------------------
-- 6. Full visibility is now real (the grant is no longer inert). With the
--    participant branch routed through the DEFINER helper, authenticated
--    matches reads succeed instead of 42501-ing on the match_participants
--    subquery. W is a participant on team B but did NOT create the match —
--    the cleanest proof of the participant branch. U created it. V is
--    neither, so V sees nothing.
-- ---------------------------------------------------------------------

SELECT is(
  _mr_visible_matches((SELECT w FROM _mr_ctx), (SELECT match_id FROM _mr_ctx)),
  1,
  'participant W (not creator) reads its match M — 1 row, no 42501');

SELECT is(
  _mr_visible_matches((SELECT u FROM _mr_ctx), (SELECT match_id FROM _mr_ctx)),
  1,
  'creator U reads its match M — 1 row, no 42501');

SELECT is(
  _mr_visible_matches((SELECT v FROM _mr_ctx), (SELECT match_id FROM _mr_ctx)),
  0,
  'non-participant non-creator V reads 0 rows of match M (no over-exposure)');

SELECT * FROM finish();
ROLLBACK;
