-- P6a (ADR-0032) — rename smoke suite for 20261283000000_rename_organizer_teams.
--
-- Asserts the behaviour-neutral rename Verein -> Veranstalterteam:
--   (a) to_regclass: organizer_teams / team_members exist, clubs /
--       club_memberships are gone; out-of-scope tables club_invitations /
--       club_join_requests / club_audit_events and the 1vs1 tables teams /
--       team_memberships are untouched.
--   (b) tournaments.organizer_team_id present, tournaments.club_id absent
--       (plus the column renames on team_members and
--       tournament_stage_graph_templates).
--   (c) pg_policies counts preserved as literals (pre-migration probe:
--       clubs = 1, club_memberships = 1) and 0 policies left on old names.
--   (d) pg_publication_tables has 0 rows for the three renamed tables.
--   (e) pg_proc: zero club_*-named functions left, all 18 renamed pendants
--       exist, 1vs1 team_* functions unchanged (20 names, one def each),
--       deprecated alias tournament_caller_can_manage still present (OE-4).
--   (f) functional smoke: renamed RPCs and the P2 gates are callable
--       without 'relation ... does not exist'.
--
-- pgTAP runs inside BEGIN..ROLLBACK; nothing persists. Auth context is
-- switched via set_config('request.jwt.claims', ...) like gate_split_test.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(32);

-- ---------------------------------------------------------------------
-- Helpers: auth-switch + minimal auth user.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _rot_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _rot_mk_user(p_uid uuid) RETURNS uuid
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
-- (a) to_regclass quartet + out-of-scope tables untouched.
-- ====================================================================
SELECT ok(to_regclass('public.organizer_teams') IS NOT NULL,
  'organizer_teams exists (renamed from clubs)');
SELECT ok(to_regclass('public.team_members') IS NOT NULL,
  'team_members exists (renamed from club_memberships)');
SELECT ok(to_regclass('public.clubs') IS NULL,
  'clubs is gone');
SELECT ok(to_regclass('public.club_memberships') IS NULL,
  'club_memberships is gone');
SELECT ok(to_regclass('public.club_invitations') IS NOT NULL,
  'club_invitations untouched (out of scope)');
SELECT ok(to_regclass('public.club_join_requests') IS NOT NULL,
  'club_join_requests untouched (out of scope)');
SELECT ok(to_regclass('public.club_audit_events') IS NOT NULL,
  'club_audit_events untouched (out of scope)');
SELECT ok(to_regclass('public.teams') IS NOT NULL,
  '1vs1 teams untouched');
SELECT ok(to_regclass('public.team_memberships') IS NOT NULL,
  '1vs1 team_memberships untouched');

-- ====================================================================
-- (b) column renames.
-- ====================================================================
SELECT has_column('public', 'tournaments', 'organizer_team_id',
  'tournaments.organizer_team_id exists');
SELECT hasnt_column('public', 'tournaments', 'club_id',
  'tournaments.club_id is gone');
SELECT has_column('public', 'team_members', 'organizer_team_id',
  'team_members.organizer_team_id exists');
SELECT hasnt_column('public', 'team_members', 'club_id',
  'team_members.club_id is gone');
SELECT has_column('public', 'tournament_stage_graph_templates',
  'organizer_team_id',
  'tournament_stage_graph_templates.organizer_team_id exists');

-- ====================================================================
-- (c) pg_policies counts preserved (pre-migration literals: 1 / 1).
-- ====================================================================
SELECT is((SELECT count(*)::int FROM pg_policies
            WHERE schemaname='public' AND tablename='organizer_teams'),
  1, 'organizer_teams keeps its 1 policy');
SELECT is((SELECT count(*)::int FROM pg_policies
            WHERE schemaname='public' AND tablename='team_members'),
  1, 'team_members keeps its 1 policy');
SELECT is((SELECT count(*)::int FROM pg_policies
            WHERE schemaname='public'
              AND tablename IN ('clubs','club_memberships')),
  0, 'no policies left on the old table names');

-- ====================================================================
-- (d) none of the three renamed tables is in any publication.
-- ====================================================================
SELECT is((SELECT count(*)::int FROM pg_publication_tables
            WHERE tablename IN ('organizer_teams','team_members','tournaments')),
  0, 'organizer_teams/team_members/tournaments are in no publication');

-- ====================================================================
-- (e) pg_proc shape.
-- ====================================================================
SELECT is((SELECT count(*)::int
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public'
              AND (p.proname LIKE 'club\_%'
                OR p.proname IN ('is_active_club_member','is_club_manager'))),
  0, 'no club_* / is_*club* function left');
SELECT is((SELECT count(*)::int
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public'
              AND p.proname = ANY (ARRAY[
                'organizer_team_caller_can_publish',
                'organizer_team_caller_is_organizer',
                'organizer_team_create','organizer_team_founding_code',
                'organizer_team_get','organizer_team_invitation_respond',
                'organizer_team_invite','organizer_team_invite_by_nickname',
                'organizer_team_leave','organizer_team_list_for_caller',
                'organizer_team_list_join_requests',
                'organizer_team_name_available','organizer_team_remove_member',
                'organizer_team_request_join',
                'organizer_team_respond_join_request',
                'organizer_team_set_member_roles',
                'is_active_organizer_team_member',
                'is_organizer_team_manager'])),
  18, 'all 18 renamed pendants exist exactly once');
SELECT is((SELECT count(DISTINCT p.proname)::int
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public'
              AND p.proname = ANY (ARRAY[
                'team_create','team_get','team_update','team_invite',
                'team_invite_by_nickname','team_invitation_respond',
                'team_leave','team_list_for_caller','team_name_available',
                'team_remove_member','team_dissolve','team_add_guest',
                'team_add_guest_member','team_remove_guest',
                'team_set_member_role','team_set_league',
                'team_league_window_open',
                'team_pool_with_tournament_conflicts',
                'is_active_team_member','_team_assert_active_member'])),
  20, '1vs1 team feature functions all still present');
SELECT is((SELECT count(*)::int
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public'
              AND p.proname = 'tournament_caller_can_manage'),
  1, 'deprecated alias tournament_caller_can_manage kept (OE-4)');
SELECT is((SELECT count(*)::int
             FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname='public'
              AND p.prosrc ~* '\mclubs\M|\mclub_memberships\M'),
  0, 'no function body references the dead relations clubs/club_memberships');

-- ====================================================================
-- (f) functional smoke: fixture + renamed RPCs + gates.
-- ====================================================================
SET LOCAL ROLE postgres;

DO $fixture$
DECLARE
  v_owner    uuid := '99999999-9999-9999-9999-999999999901';
  v_referee  uuid := '99999999-9999-9999-9999-999999999902';
  v_team     uuid := 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01';
  v_t        uuid := 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01';
BEGIN
  PERFORM _rot_mk_user(v_owner);
  PERFORM _rot_mk_user(v_referee);

  INSERT INTO public.organizer_teams(id, display_name, created_by)
    VALUES (v_team, 'Rename-Smoke-Team', v_owner);

  INSERT INTO public.team_members(organizer_team_id, user_id, roles)
    VALUES (v_team, v_owner,   ARRAY['owner']::text[]),
           (v_team, v_referee, ARRAY['referee']::text[]);

  INSERT INTO public.tournaments(
      id, created_by, organizer_team_id, display_name, team_size,
      min_participants, max_participants, format, scoring, match_format,
      status, public)
    VALUES
      (v_t, v_owner, v_team, 'Rename-Smoke-T', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800,
                          'break_between_matches_seconds', 300),
       'published', true);
END;
$fixture$;

SELECT _rot_as('99999999-9999-9999-9999-999999999901'); -- owner

SELECT lives_ok(
  $$ SELECT count(*) FROM public.organizer_team_list_for_caller() $$,
  'organizer_team_list_for_caller() is callable (no missing relation)');

SELECT is(
  (SELECT count(*)::int FROM public.organizer_team_list_for_caller()
    WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01'),
  1, 'organizer_team_list_for_caller returns the owner''s team');

SELECT ok(
  (public.organizer_team_get('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01')
     ? 'organizer_team_id'),
  'organizer_team_get projects the renamed organizer_team_id key');

SELECT ok(
  NOT (public.organizer_team_get('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaa01')
     ? 'club_id'),
  'organizer_team_get no longer projects a club_id key');

SELECT ok(
  public.tournament_caller_can_setup('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01'),
  'tournament_caller_can_setup: team owner => true (gate reads team_members)');

SELECT lives_ok(
  $$ SELECT count(*) FROM public.tournament_list_administrable(10) $$,
  'tournament_list_administrable(10) is callable');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_list_administrable(10) j
    WHERE j ->> 'tournament_id' = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01'),
  1, 'tournament_list_administrable lists the team tournament for the owner');

SELECT _rot_as('99999999-9999-9999-9999-999999999902'); -- referee

SELECT ok(
  public.tournament_caller_can_administer('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01'),
  'tournament_caller_can_administer: team referee => true');

SELECT ok(
  NOT public.tournament_caller_can_setup('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbb01'),
  'tournament_caller_can_setup: team referee => false (P2 unchanged)');

SELECT * FROM finish();
ROLLBACK;
