-- P2-S (ADR-0032) — gate split pgTAP suite.
--
-- Covers (P2-S DoD-9):
--   (a) Truth table of both gates for creator / owner / admin / referee /
--       non-member:
--         tournament_caller_can_setup:      T / T / T / F / F
--         tournament_caller_can_administer: T / T / T / T / F
--   (b) referee CAN call an admin RPC (tournament_pause; gate-first, body is
--       an idempotent no-op without schedule rows) while a non-member gets
--       42501 on the same RPC.
--   (c) referee gets 42501 on a setup RPC (tournament_update) AND on
--       tournament_start (locked decision OE-2: start = setup, a referee
--       does not start a tournament).
--   (d) deprecated alias: tournament_caller_can_manage delegates to
--       _can_administer (referee => true).
--   Plus EXECUTE grants for authenticated on both new gates.
--
-- pgTAP runs inside BEGIN..ROLLBACK; nothing persists. Auth context is
-- switched via set_config('request.jwt.claims', ...) like
-- tournament_administrable_test.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

-- ---------------------------------------------------------------------
-- Helpers: auth-switch + minimal auth user.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _gs_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _gs_mk_user(p_uid uuid) RETURNS uuid
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
-- Fixture (as postgres): one club with an owner, an admin and a referee;
-- a tournament creator who is NOT a club member; an outsider with no
-- membership at all; one published club tournament.
-- ====================================================================
SET LOCAL ROLE postgres;

DO $fixture$
DECLARE
  v_creator  uuid := '66666666-6666-6666-6666-666666666601';
  v_owner    uuid := '66666666-6666-6666-6666-666666666602';
  v_admin    uuid := '66666666-6666-6666-6666-666666666603';
  v_referee  uuid := '66666666-6666-6666-6666-666666666604';
  v_outsider uuid := '66666666-6666-6666-6666-666666666605';
  v_club     uuid := '77777777-7777-7777-7777-777777777701';
  v_t        uuid := '88888888-8888-8888-8888-888888888801';
BEGIN
  PERFORM _gs_mk_user(v_creator);
  PERFORM _gs_mk_user(v_owner);
  PERFORM _gs_mk_user(v_admin);
  PERFORM _gs_mk_user(v_referee);
  PERFORM _gs_mk_user(v_outsider);

  INSERT INTO public.organizer_teams(id, display_name, created_by)
    VALUES (v_club, 'GateSplit-Club', v_owner);

  INSERT INTO public.team_members(organizer_team_id, user_id, roles)
    VALUES (v_club, v_owner,   ARRAY['owner']::text[]),
           (v_club, v_admin,   ARRAY['admin']::text[]),
           (v_club, v_referee, ARRAY['referee']::text[]);

  INSERT INTO public.tournaments(
      id, created_by, organizer_team_id, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES
      (v_t, v_creator, v_club, 'GateSplit-T', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800,
                          'break_between_matches_seconds', 300),
       'published', true);
END;
$fixture$;

-- ====================================================================
-- (a) Truth table — tournament_caller_can_setup: T / T / T / F / F.
-- ====================================================================
SELECT _gs_as('66666666-6666-6666-6666-666666666601'); -- creator
SELECT ok(
  public.tournament_caller_can_setup('88888888-8888-8888-8888-888888888801'),
  'can_setup: creator => true');

SELECT _gs_as('66666666-6666-6666-6666-666666666602'); -- owner
SELECT ok(
  public.tournament_caller_can_setup('88888888-8888-8888-8888-888888888801'),
  'can_setup: club owner => true');

SELECT _gs_as('66666666-6666-6666-6666-666666666603'); -- admin
SELECT ok(
  public.tournament_caller_can_setup('88888888-8888-8888-8888-888888888801'),
  'can_setup: club admin => true');

SELECT _gs_as('66666666-6666-6666-6666-666666666604'); -- referee
SELECT ok(
  NOT public.tournament_caller_can_setup('88888888-8888-8888-8888-888888888801'),
  'can_setup: club referee => FALSE (referee has no setup authority)');

SELECT _gs_as('66666666-6666-6666-6666-666666666605'); -- outsider
SELECT ok(
  NOT public.tournament_caller_can_setup('88888888-8888-8888-8888-888888888801'),
  'can_setup: non-member => FALSE');

-- ====================================================================
-- (a) Truth table — tournament_caller_can_administer: T / T / T / T / F.
-- ====================================================================
SELECT _gs_as('66666666-6666-6666-6666-666666666601'); -- creator
SELECT ok(
  public.tournament_caller_can_administer('88888888-8888-8888-8888-888888888801'),
  'can_administer: creator => true');

SELECT _gs_as('66666666-6666-6666-6666-666666666602'); -- owner
SELECT ok(
  public.tournament_caller_can_administer('88888888-8888-8888-8888-888888888801'),
  'can_administer: club owner => true');

SELECT _gs_as('66666666-6666-6666-6666-666666666603'); -- admin
SELECT ok(
  public.tournament_caller_can_administer('88888888-8888-8888-8888-888888888801'),
  'can_administer: club admin => true');

SELECT _gs_as('66666666-6666-6666-6666-666666666604'); -- referee
SELECT ok(
  public.tournament_caller_can_administer('88888888-8888-8888-8888-888888888801'),
  'can_administer: club referee => TRUE (live intervention allowed)');

SELECT _gs_as('66666666-6666-6666-6666-666666666605'); -- outsider
SELECT ok(
  NOT public.tournament_caller_can_administer('88888888-8888-8888-8888-888888888801'),
  'can_administer: non-member => FALSE');

-- ====================================================================
-- (d) Deprecated alias delegates to can_administer (referee => true).
-- ====================================================================
SELECT _gs_as('66666666-6666-6666-6666-666666666604'); -- referee
SELECT ok(
  public.tournament_caller_can_manage('88888888-8888-8888-8888-888888888801'),
  'alias can_manage: referee => true (administer semantics)');

-- ====================================================================
-- (b) referee CAN call an admin RPC; a non-member cannot.
-- tournament_pause checks the gate first and is an idempotent no-op
-- without active schedule rows, so success == gate passed.
-- ====================================================================
SELECT _gs_as('66666666-6666-6666-6666-666666666604'); -- referee
SELECT lives_ok(
  $$ SELECT public.tournament_pause('88888888-8888-8888-8888-888888888801') $$,
  'admin RPC: referee may call tournament_pause (no 42501)');

SELECT _gs_as('66666666-6666-6666-6666-666666666605'); -- outsider
SELECT throws_ok(
  $$ SELECT public.tournament_pause('88888888-8888-8888-8888-888888888801') $$,
  '42501',
  NULL,
  'admin RPC: non-member gets 42501 on tournament_pause');

-- ====================================================================
-- (c) referee gets 42501 on setup RPCs: tournament_update AND
-- tournament_start (locked decision OE-2).
-- ====================================================================
SELECT _gs_as('66666666-6666-6666-6666-666666666604'); -- referee
SELECT throws_ok(
  $$ SELECT public.tournament_update(
       '88888888-8888-8888-8888-888888888801',
       'GateSplit-T2', 1, 2, 16, 'swiss', NULL, NULL) $$,
  '42501',
  NULL,
  'setup RPC: referee gets 42501 on tournament_update');

SELECT throws_ok(
  $$ SELECT public.tournament_start('88888888-8888-8888-8888-888888888801') $$,
  '42501',
  NULL,
  'setup RPC: referee gets 42501 on tournament_start (OE-2: start = setup)');

-- ====================================================================
-- EXECUTE grants for authenticated on both new gates.
-- ====================================================================
SET LOCAL ROLE postgres;
SELECT ok(
  has_function_privilege('authenticated',
    'public.tournament_caller_can_setup(uuid)', 'EXECUTE'),
  'EXECUTE on tournament_caller_can_setup(uuid) granted to authenticated');
SELECT ok(
  has_function_privilege('authenticated',
    'public.tournament_caller_can_administer(uuid)', 'EXECUTE'),
  'EXECUTE on tournament_caller_can_administer(uuid) granted to authenticated');

SELECT * FROM finish();
ROLLBACK;
