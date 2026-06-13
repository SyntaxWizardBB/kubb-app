-- ADR-0031 Block B1s — tournament administrable gate + list pgTAP suite.
--
-- Covers (B1s-DoD-12/13):
--   * Gate referee-regression: a caller whose ONLY club role is 'referee'
--     (not owner/admin, not creator) gets tournament_caller_can_manage
--     = true and sees the tournament in tournament_list_administrable; a
--     non-member caller stays false / excluded. (Role consolidation
--     20261280000000 removed 'member'/'guest'; the non-managing case is now
--     "no club membership at all".)
--   * Status filter: draft- and finalized-tournaments do NOT appear in the list.
--   * LEFT-JOIN fallback: an administrable published/live tournament WITHOUT a
--     schedule row appears, schedule-derived fields NULL.
--   * Counts: open_match_count (scheduled|awaiting_results) and
--     disputed_match_count are counted correctly.
--   * EXECUTE-grant for authenticated on tournament_list_administrable(int).
--   * Auth-guard: anon caller -> 42501.
--
-- pgTAP runs inside BEGIN..ROLLBACK; nothing is mutated. Auth context is
-- switched via set_config('request.jwt.claims', ...) like team_rpcs_test.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(14);

-- ---------------------------------------------------------------------
-- Helpers: auth-switch + minimal auth user.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _adm_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _adm_as_anon() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
END;
$$;

CREATE OR REPLACE FUNCTION _adm_mk_user(p_uid uuid) RETURNS uuid
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
-- Fixture (as postgres): one club with a referee; a non-member; a creator;
-- a published club tournament + a live no-schedule tournament + a draft +
-- a finalized one. Plus matches for the counts.
-- ====================================================================
SET LOCAL ROLE postgres;

DO $fixture$
DECLARE
  v_creator  uuid := '33333333-3333-3333-3333-333333333301';
  v_referee  uuid := '33333333-3333-3333-3333-333333333302';
  v_nonmember uuid := '33333333-3333-3333-3333-333333333303';
  v_club     uuid := '44444444-4444-4444-4444-444444444401';
  v_pub      uuid := '55555555-5555-5555-5555-555555555501'; -- published, club, has schedule
  v_live     uuid := '55555555-5555-5555-5555-555555555502'; -- live, club, NO schedule
  v_draft    uuid := '55555555-5555-5555-5555-555555555503'; -- draft, club
  v_final    uuid := '55555555-5555-5555-5555-555555555504'; -- finalized, club
  v_pa       uuid;
  v_pb       uuid;
BEGIN
  PERFORM _adm_mk_user(v_creator);
  PERFORM _adm_mk_user(v_referee);
  PERFORM _adm_mk_user(v_nonmember);

  INSERT INTO public.organizer_teams(id, display_name, created_by)
    VALUES (v_club, 'Adm-Club', v_creator);

  -- referee: ONLY the 'referee' role (no owner/admin).
  INSERT INTO public.team_members(organizer_team_id, user_id, roles)
    VALUES (v_club, v_referee, ARRAY['referee']::text[]);
  -- v_nonmember intentionally gets NO club_memberships row: since the role
  -- consolidation (20261280000000) every club role {owner,admin,referee} can
  -- administer, so the non-managing case is a user without any membership.

  -- Four tournaments, all linked to the club, creator = v_creator.
  INSERT INTO public.tournaments(
      id, created_by, organizer_team_id, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES
      (v_pub,   v_creator, v_club, 'Pub-Sched', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800,
                          'break_between_matches_seconds', 300),
       'published', true),
      (v_live,  v_creator, v_club, 'Live-NoSched', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800,
                          'break_between_matches_seconds', 300),
       'live', true),
      (v_draft, v_creator, v_club, 'Draft', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'draft', false),
      (v_final, v_creator, v_club, 'Finalized', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'finalized', true);

  -- Schedule row for the published tournament only (live stays schedule-less).
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_pub, NULL, 2, 'group', 'running',
            now() - interval '400 seconds',
            now() - interval '100 seconds',
            now() + interval '1700 seconds',
            300, 1800);

  -- Matches on the published tournament for the counts:
  --   2 open (scheduled + awaiting_results), 1 disputed, 1 finalized (ignored).
  INSERT INTO public.tournament_participants(id, tournament_id, user_id, registration_status)
    VALUES (gen_random_uuid(), v_pub, v_referee, 'confirmed') RETURNING id INTO v_pa;
  INSERT INTO public.tournament_participants(id, tournament_id, user_id, registration_status)
    VALUES (gen_random_uuid(), v_pub, v_nonmember, 'confirmed') RETURNING id INTO v_pb;

  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round, participant_a, participant_b, status)
    VALUES
      (v_pub, 1, 1, v_pa, v_pb, 'scheduled'),
      (v_pub, 1, 2, v_pa, v_pb, 'awaiting_results'),
      (v_pub, 1, 3, v_pa, v_pb, 'disputed'),
      (v_pub, 1, 4, v_pa, v_pb, 'finalized');
END;
$fixture$;

-- ====================================================================
-- 1. Gate referee-regression.
-- ====================================================================
SELECT _adm_as('33333333-3333-3333-3333-333333333302'); -- referee
SELECT ok(
  public.tournament_caller_can_manage('55555555-5555-5555-5555-555555555501'),
  'referee-only club role CAN manage the club tournament (gate true)');

SELECT _adm_as('33333333-3333-3333-3333-333333333303'); -- non-member
SELECT ok(
  NOT public.tournament_caller_can_manage('55555555-5555-5555-5555-555555555501'),
  'non-member (mere participant) CANNOT manage (gate false)');

SELECT _adm_as('33333333-3333-3333-3333-333333333301'); -- creator
SELECT ok(
  public.tournament_caller_can_manage('55555555-5555-5555-5555-555555555501'),
  'creator CAN manage (gate true, unchanged branch)');

-- ====================================================================
-- 2. List as referee: sees published + live; NOT draft/finalized.
-- ====================================================================
SELECT _adm_as('33333333-3333-3333-3333-333333333302'); -- referee

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.tournament_list_administrable(50) r
     WHERE (r->>'tournament_id') = '55555555-5555-5555-5555-555555555501'),
  'referee sees the published club tournament in the list');

SELECT ok(
  EXISTS (
    SELECT 1 FROM public.tournament_list_administrable(50) r
     WHERE (r->>'tournament_id') = '55555555-5555-5555-5555-555555555502'),
  'LEFT-JOIN fallback: live tournament WITHOUT a schedule row appears');

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.tournament_list_administrable(50) r
     WHERE (r->>'tournament_id') = '55555555-5555-5555-5555-555555555503'),
  'status filter: draft tournament is excluded from the list');

SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM public.tournament_list_administrable(50) r
     WHERE (r->>'tournament_id') = '55555555-5555-5555-5555-555555555504'),
  'status filter: finalized tournament is excluded from the list');

-- ====================================================================
-- 3. LEFT-JOIN fallback: schedule-derived fields NULL for live no-schedule.
-- ====================================================================
SELECT ok(
  (SELECT (r->'current_round') = 'null'::jsonb
     FROM public.tournament_list_administrable(50) r
    WHERE (r->>'tournament_id') = '55555555-5555-5555-5555-555555555502'),
  'no-schedule tournament: current_round is NULL (LEFT JOIN fallback)');
SELECT ok(
  (SELECT (r->'remaining_seconds') = 'null'::jsonb
     FROM public.tournament_list_administrable(50) r
    WHERE (r->>'tournament_id') = '55555555-5555-5555-5555-555555555502'),
  'no-schedule tournament: remaining_seconds is NULL (LEFT JOIN fallback)');

-- ====================================================================
-- 4. Counts on the published tournament.
-- ====================================================================
SELECT is(
  (SELECT (r->>'open_match_count')::int
     FROM public.tournament_list_administrable(50) r
    WHERE (r->>'tournament_id') = '55555555-5555-5555-5555-555555555501'),
  2, 'open_match_count counts scheduled + awaiting_results (= 2)');
SELECT is(
  (SELECT (r->>'disputed_match_count')::int
     FROM public.tournament_list_administrable(50) r
    WHERE (r->>'tournament_id') = '55555555-5555-5555-5555-555555555501'),
  1, 'disputed_match_count counts disputed (= 1)');
SELECT is(
  (SELECT (r->>'schedule_status')
     FROM public.tournament_list_administrable(50) r
    WHERE (r->>'tournament_id') = '55555555-5555-5555-5555-555555555501'),
  'running', 'schedule_status reflects the active schedule row');

-- ====================================================================
-- 5. Auth-guard: anon caller -> 42501.
-- ====================================================================
SELECT _adm_as_anon();
SELECT throws_ok(
  $$ SELECT * FROM public.tournament_list_administrable(50) $$,
  '42501',
  NULL,
  'anon caller raises 42501 (authentication required)');

-- ====================================================================
-- 6. EXECUTE-grant for authenticated on tournament_list_administrable(int).
-- ====================================================================
SET LOCAL ROLE postgres;
SELECT ok(
  has_function_privilege('authenticated',
    'public.tournament_list_administrable(int)', 'EXECUTE'),
  'EXECUTE on tournament_list_administrable(int) granted to authenticated');

SELECT * FROM finish();
ROLLBACK;
