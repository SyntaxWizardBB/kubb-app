-- W4-T17 (Wave 4c) — cross-tournament check-in search pgTAP suite.
--
-- Covers tournament_search_checkin_targets(p_query text):
--   (a) has_function + grant shape (authenticated yes, anon no)
--   (b) manager finds a single-player hit (nickname) in an own, public,
--       check-in-phase tournament
--   (c) manager finds a team hit (teams.display_name) in the same scope
--   (d) hit carries the tournament id + name + participant id + name
--   (e) tournaments NOT in the check-in phase (draft / finalized) are excluded
--   (f) non-public tournaments are excluded even when manageable
--   (g) tournaments the caller cannot administer are excluded
--   (h) a non-manager / outsider caller gets an empty result
--   (i) the query is fuzzy (substring / trigram), case-insensitive
--
-- Runs inside BEGIN..ROLLBACK; nothing is persisted. Auth context switched via
-- set_config('request.jwt.claims', ...) like participant_checkin_test.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(13);

-- ---------------------------------------------------------------------
-- Helpers: auth-switch + minimal auth user.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _sct_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _sct_mk_user(p_uid uuid) RETURNS uuid
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
-- Fixture (as postgres): a manager who created two tournaments in the
-- check-in phase (registration_closed + live), plus a draft one and a
-- private one. A single-player participant (nickname 'Stefan Brunner')
-- and a team participant (teams.display_name 'Holzwurm Bern'). A second,
-- unrelated tournament created by an outsider holds a same-named player
-- that must never leak into the manager's results.
-- ====================================================================
SET LOCAL ROLE postgres;

DO $fixture$
DECLARE
  v_manager  uuid := '12121212-1212-1212-1212-121212121201';
  v_player   uuid := '12121212-1212-1212-1212-121212121202'; -- single player
  v_outsider uuid := '12121212-1212-1212-1212-121212121203'; -- creator of v_t_other
  v_stranger uuid := '12121212-1212-1212-1212-121212121204'; -- manages nothing
  v_t_closed uuid := '13131313-1313-1313-1313-131313131301'; -- registration_closed, public
  v_t_live   uuid := '13131313-1313-1313-1313-131313131302'; -- live, public
  v_t_draft  uuid := '13131313-1313-1313-1313-131313131303'; -- draft, public
  v_t_priv   uuid := '13131313-1313-1313-1313-131313131304'; -- live, NOT public
  v_t_other  uuid := '13131313-1313-1313-1313-131313131305'; -- live, public, foreign creator
  v_team     uuid := '14141414-1414-1414-1414-141414141401';
  v_p_player uuid := 'cccccccc-0000-0000-0000-000000000001'; -- player in t_closed
  v_p_team   uuid := 'cccccccc-0000-0000-0000-000000000002'; -- team in t_live
  v_p_draft  uuid := 'cccccccc-0000-0000-0000-000000000003'; -- player in t_draft
  v_p_priv   uuid := 'cccccccc-0000-0000-0000-000000000004'; -- player in t_priv
  v_p_other  uuid := 'cccccccc-0000-0000-0000-000000000005'; -- player in t_other
BEGIN
  PERFORM _sct_mk_user(v_manager);
  PERFORM _sct_mk_user(v_player);
  PERFORM _sct_mk_user(v_outsider);
  PERFORM _sct_mk_user(v_stranger);

  INSERT INTO public.user_profiles(user_id, nickname)
    VALUES (v_player, 'Stefan Brunner')
    ON CONFLICT (user_id) DO UPDATE SET nickname = EXCLUDED.nickname;

  INSERT INTO public.teams(id, display_name, created_by)
    VALUES (v_team, 'Holzwurm Bern', v_manager)
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES
      (v_t_closed, v_manager, 'Frühlingscup', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'registration_closed', true),
      (v_t_live, v_manager, 'Sommercup', 2, 2, 16, 'round_robin', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'live', true),
      (v_t_draft, v_manager, 'Herbstcup', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'draft', true),
      (v_t_priv, v_manager, 'Privatcup', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'live', false),
      (v_t_other, v_outsider, 'Fremdcup', 1, 2, 16, 'swiss', 'ekc',
       jsonb_build_object('round_time_seconds', 1800), 'live', true);

  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, team_id, registration_status)
    VALUES
      (v_p_player, v_t_closed, v_player,  NULL,   'confirmed'),
      (v_p_team,   v_t_live,   NULL,      v_team, 'confirmed'),
      (v_p_draft,  v_t_draft,  v_player,  NULL,   'confirmed'),
      (v_p_priv,   v_t_priv,   v_player,  NULL,   'confirmed'),
      (v_p_other,  v_t_other,  v_player,  NULL,   'confirmed');
END;
$fixture$;

-- ====================================================================
-- (a) has_function + grant shape.
-- ====================================================================
SELECT has_function('public', 'tournament_search_checkin_targets', ARRAY['text'],
  'tournament_search_checkin_targets(text) exists');
SELECT ok(
  has_function_privilege('authenticated',
    'public.tournament_search_checkin_targets(text)', 'EXECUTE'),
  'EXECUTE granted to authenticated');
SELECT ok(
  NOT has_function_privilege('anon',
    'public.tournament_search_checkin_targets(text)', 'EXECUTE'),
  'anon has NO EXECUTE');

-- ====================================================================
-- (b) manager finds a single-player hit by nickname.
-- ====================================================================
SELECT _sct_as('12121212-1212-1212-1212-121212121201'); -- manager

SELECT is(
  (SELECT count(*)::int
     FROM public.tournament_search_checkin_targets('Brunner') r
    WHERE (r->>'participant_id') = 'cccccccc-0000-0000-0000-000000000001'),
  1, 'manager finds the single-player hit by nickname substring');

-- ====================================================================
-- (c) manager finds the team hit by teams.display_name.
-- ====================================================================
SELECT is(
  (SELECT count(*)::int
     FROM public.tournament_search_checkin_targets('Holzwurm') r
    WHERE (r->>'participant_id') = 'cccccccc-0000-0000-0000-000000000002'),
  1, 'manager finds the team hit by team display_name substring');

-- ====================================================================
-- (d) hit projects tournament id + name + participant id + name.
-- ====================================================================
SELECT is(
  (SELECT r->>'tournament_id'
     FROM public.tournament_search_checkin_targets('Brunner') r
    WHERE (r->>'participant_id') = 'cccccccc-0000-0000-0000-000000000001'),
  '13131313-1313-1313-1313-131313131301',
  'hit carries the correct tournament_id');
SELECT is(
  (SELECT r->>'tournament_name'
     FROM public.tournament_search_checkin_targets('Brunner') r
    WHERE (r->>'participant_id') = 'cccccccc-0000-0000-0000-000000000001'),
  'Frühlingscup',
  'hit carries the tournament display_name');
SELECT is(
  (SELECT r->>'display_name'
     FROM public.tournament_search_checkin_targets('Brunner') r
    WHERE (r->>'participant_id') = 'cccccccc-0000-0000-0000-000000000001'),
  'Stefan Brunner',
  'hit carries the participant display_name');

-- ====================================================================
-- (e) draft tournament hit excluded (not in the check-in phase).
-- ====================================================================
SELECT is(
  (SELECT count(*)::int
     FROM public.tournament_search_checkin_targets('Brunner') r
    WHERE (r->>'participant_id') = 'cccccccc-0000-0000-0000-000000000003'),
  0, 'draft-tournament participant is excluded (not check-in phase)');

-- ====================================================================
-- (f) non-public tournament hit excluded.
-- ====================================================================
SELECT is(
  (SELECT count(*)::int
     FROM public.tournament_search_checkin_targets('Brunner') r
    WHERE (r->>'participant_id') = 'cccccccc-0000-0000-0000-000000000004'),
  0, 'private-tournament participant is excluded (public = false)');

-- ====================================================================
-- (g) foreign tournament (caller cannot administer) excluded.
-- ====================================================================
SELECT is(
  (SELECT count(*)::int
     FROM public.tournament_search_checkin_targets('Brunner') r
    WHERE (r->>'participant_id') = 'cccccccc-0000-0000-0000-000000000005'),
  0, 'foreign-tournament participant is excluded (no administer authority)');

-- ====================================================================
-- (h) stranger caller (manages nothing) gets an empty result.
-- ====================================================================
SELECT _sct_as('12121212-1212-1212-1212-121212121204'); -- stranger
SELECT is(
  (SELECT count(*)::int
     FROM public.tournament_search_checkin_targets('Brunner') r),
  0, 'stranger (no manage authority anywhere) gets an empty result');

-- ====================================================================
-- (i) fuzzy + case-insensitive: lowercase substring still matches.
-- ====================================================================
SELECT _sct_as('12121212-1212-1212-1212-121212121201'); -- manager
SELECT is(
  (SELECT count(*)::int
     FROM public.tournament_search_checkin_targets('stefan') r
    WHERE (r->>'participant_id') = 'cccccccc-0000-0000-0000-000000000001'),
  1, 'search is case-insensitive (lowercase substring matches)');

SELECT * FROM finish();
ROLLBACK;
