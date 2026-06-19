-- ADR-0033 §4 / ADR-0034 §1 P5.3b — KO matchup is consumed at round-1 pairing.
--
--   * _tournament_compute_ko_bracket(seeds, third_place, matchup):
--       'seed_high_vs_low' (default) => standard order (1-N, 2-(N-1), ...)
--       'one_vs_two'                 => adjacent seeds (1-2, 3-4, ...)
--     bracket_position is identical in both; only the participants differ.
--   * a stage single_elim node with config ko_matchup='one_vs_two' generates
--     adjacent round-1 matches end-to-end.
--
-- pgTAP runs inside BEGIN..ROLLBACK; nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(5);

SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION _kmc_mk_user(p_uid uuid) RETURNS uuid
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

-- ── Helper: seeds 1..4 ───────────────────────────────────────────────────
-- standard => round 1: (seed1, seed4), (seed2, seed3)
SELECT is(
  (SELECT array_agg(participant_a::text || '/' || participant_b::text
                    ORDER BY bracket_position)
     FROM public._tournament_compute_ko_bracket(
       to_jsonb(ARRAY[
         '00000000-0000-0000-0000-000000000001',
         '00000000-0000-0000-0000-000000000002',
         '00000000-0000-0000-0000-000000000003',
         '00000000-0000-0000-0000-000000000004']::text[]),
       false, 'seed_high_vs_low')
     WHERE round_number = 1),
  ARRAY[
    '00000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000003/00000000-0000-0000-0000-000000000002'],
  'seed_high_vs_low keeps standard order (bp1=1-4, bp2=3-2) — unchanged');

-- one_vs_two => round 1: (seed1, seed2), (seed3, seed4)
SELECT is(
  (SELECT array_agg(participant_a::text || '/' || participant_b::text
                    ORDER BY bracket_position)
     FROM public._tournament_compute_ko_bracket(
       to_jsonb(ARRAY[
         '00000000-0000-0000-0000-000000000001',
         '00000000-0000-0000-0000-000000000002',
         '00000000-0000-0000-0000-000000000003',
         '00000000-0000-0000-0000-000000000004']::text[]),
       false, 'one_vs_two')
     WHERE round_number = 1),
  ARRAY[
    '00000000-0000-0000-0000-000000000001/00000000-0000-0000-0000-000000000002',
    '00000000-0000-0000-0000-000000000003/00000000-0000-0000-0000-000000000004'],
  'one_vs_two pairs adjacent seeds 1-2 and 3-4 in round 1');

-- bracket_position is identical regardless of matchup (advance logic intact).
SELECT is(
  (SELECT array_agg(DISTINCT bracket_position ORDER BY bracket_position)
     FROM public._tournament_compute_ko_bracket(
       to_jsonb(ARRAY[
         '00000000-0000-0000-0000-000000000001',
         '00000000-0000-0000-0000-000000000002',
         '00000000-0000-0000-0000-000000000003',
         '00000000-0000-0000-0000-000000000004']::text[]),
       false, 'one_vs_two')
     WHERE round_number = 1),
  ARRAY[1, 2],
  'one_vs_two keeps bracket_position 1..size/2 (advance slots unchanged)');

-- ── End-to-end: stage single_elim node with config ko_matchup='one_vs_two' ──
DO $fixture$
DECLARE
  v_creator uuid := '88880000-0000-0000-0000-00000000000a';
  v_tour    uuid := '8888aaaa-0000-0000-0000-000000000001';
  v_parts   uuid[] := ARRAY[
    '8888bbbb-0000-0000-0000-000000000001',
    '8888bbbb-0000-0000-0000-000000000002',
    '8888bbbb-0000-0000-0000-000000000003',
    '8888bbbb-0000-0000-0000-000000000004'
  ]::uuid[];
  i int;
BEGIN
  PERFORM _kmc_mk_user(v_creator);
  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'P5.3b-Tour', 1, 2, 16, 'swiss', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);
  FOR i IN 1 .. array_length(v_parts, 1) LOOP
    PERFORM _kmc_mk_user(v_parts[i]);
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status)
      VALUES (v_parts[i], v_tour, v_parts[i], 'confirmed');
  END LOOP;
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'cup', 'single_elim',
            '{"ko_matchup":"one_vs_two"}'::jsonb, 'manual', 'pending');
  PERFORM public.tournament_generate_stage_matches(v_tour, 'cup', v_parts);
END;
$fixture$;

-- The two round-1 matches must be the adjacent pairs (seed order = v_parts).
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'cup' AND round_number = 1),
  2,
  'stage single_elim over 4 => 2 round-1 matches');

SELECT is(
  (SELECT bool_and(ok) FROM (
     SELECT (participant_a = '8888bbbb-0000-0000-0000-000000000001'
             AND participant_b = '8888bbbb-0000-0000-0000-000000000002') AS ok
       FROM public.tournament_matches
      WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
        AND stage_node_id = 'cup' AND round_number = 1 AND bracket_position = 1
   ) s),
  true,
  'stage one_vs_two: bracket_position 1 is seed1 vs seed2 (adjacent)');

SELECT * FROM finish();
ROLLBACK;
