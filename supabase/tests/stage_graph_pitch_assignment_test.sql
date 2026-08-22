-- Regression guard for the pitch plan on the stage-graph route.
--
-- Before 20261337000000 a schoch/swiss tournament reached 'live' through
-- tournament_start_stage_graph, which returned before either of
-- tournament_start's _tournament_assign_pitches calls. Every first-round match
-- kept the inserted default of pitch 1, whatever the organiser had configured.
-- Rounds 2+ were fine (tournament_pair_round assigns), and so was the
-- group phase (tournament_start_pool_phase assigns).
--
-- Eight players on a plan of pitches 5..12 must therefore end up on four
-- distinct pitches inside that range, not four times pitch 1.
--
-- pgTAP is installed transiently inside the BEGIN..ROLLBACK; nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(4);

DO $fixture$
DECLARE
  v_org  uuid := '00000000-0000-4000-9000-000000000001';
  v_pid  uuid;
  v_tid  uuid;
  i      int;
BEGIN
  FOR i IN 0..8 LOOP
    v_pid := CASE WHEN i = 0 THEN v_org
                  ELSE ('00000000-0000-4000-9000-0000000001' ||
                        lpad(i::text, 2, '0'))::uuid END;
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_pid, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated',
              'pitch' || i || '@tts.local', '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.user_profiles(user_id, can_found_clubs)
      VALUES (v_pid, i = 0)
      ON CONFLICT (user_id) DO UPDATE SET can_found_clubs = EXCLUDED.can_found_clubs;
  END LOOP;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_org::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);

  v_tid := (public.tournament_create(
      'Pitch plan guard', 1, 2, 8, 'swiss_then_ko',
      jsonb_build_object(
        'max_sets', 2, 'sets_to_win', 2, 'basekubbs_per_side', 5,
        'round_time_seconds', 1800, 'break_between_matches_seconds', 300),
      ARRAY['total_points', 'wins', 'kubb_difference'],
      jsonb_build_object(
        'ko_type', 'single_out',
        'scoring', 'ekc',
        'ko_config', jsonb_build_object(
          'seeding_mode', 'auto', 'qualifier_count', 4,
          'with_third_place_playoff', false),
        'ko_matchup', 'seed_high_vs_low',
        'bracket_type', 'single_elimination',
        'vorrunde_type', 'schoch',
        'pool_phase_config', jsonb_build_object(
          'strategy', 'seeded', 'group_count', 1,
          'schoch_rounds', 3, 'qualifiers_per_group', 4),
        'ko_tiebreak_method', 'classic_kingtoss_removal',
        'pitch_plan', jsonb_build_object(
          'mode', 'range', 'range_from', 5, 'range_to', 12,
          'sort_strategy', 'top_seeds_low_numbers'))
    ) ->> 'tournament_id')::uuid;

  PERFORM public.tournament_publish(v_tid);

  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);

  FOR i IN 1..8 LOOP
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, registered_at)
      VALUES (gen_random_uuid(), v_tid,
              ('00000000-0000-4000-9000-0000000001' ||
               lpad(i::text, 2, '0'))::uuid,
              'confirmed', now() + (i || ' seconds')::interval);
  END LOOP;

  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', v_org::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);

  PERFORM public.tournament_close_registration(v_tid);
  PERFORM public.tournament_start(v_tid);

  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);

  CREATE TEMP TABLE _pitch_guard AS
    SELECT m.pitch_number
      FROM public.tournament_matches m
      JOIN public.tournaments t ON t.id = m.tournament_id
     WHERE t.display_name = 'Pitch plan guard'
       AND m.round_number = 1;
END
$fixture$;

SELECT is((SELECT count(*)::int FROM _pitch_guard), 4,
  'eight players pair into four first-round matches');

SELECT is((SELECT count(DISTINCT pitch_number)::int FROM _pitch_guard), 4,
  'each match gets its own pitch, not all of them pitch 1');

SELECT ok((SELECT bool_and(pitch_number BETWEEN 5 AND 12) FROM _pitch_guard),
  'every pitch comes from the configured range 5..12');

SELECT is((SELECT min(pitch_number)::int FROM _pitch_guard), 5,
  'assignment starts at the low end of the range');

SELECT * FROM finish();
ROLLBACK;
