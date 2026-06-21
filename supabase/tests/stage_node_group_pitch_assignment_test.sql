-- Stage-graph group stages honour the node's group_pitch_assignment.
--
-- _tournament_assign_pitches_from_stage_node reads
-- tournament_stages.config -> 'group_pitch_assignment' (group label -> pitch
-- numbers) and spreads the group's matches over its assigned pitches in a
-- round-robin (ranked by match_number_in_round). No assignment -> the generated
-- placeholder pitch_number = 1 is left untouched.
--
-- pgTAP is installed transiently inside BEGIN..ROLLBACK; nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION _sngpa_mk_user(p_uid uuid) RETURNS uuid
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

DO $fixture$
DECLARE
  v_creator uuid := '88880000-0000-0000-0000-00000000000a';
  v_tour    uuid := '8888aaaa-0000-0000-0000-000000000001';
  v_parts   uuid[] := ARRAY[
    '8888bbbb-0000-0000-0000-000000000001',
    '8888bbbb-0000-0000-0000-000000000002',
    '8888bbbb-0000-0000-0000-000000000003',
    '8888bbbb-0000-0000-0000-000000000004',
    '8888bbbb-0000-0000-0000-000000000005',
    '8888bbbb-0000-0000-0000-000000000006'
  ]::uuid[];
  v_uid uuid;
  i int;
BEGIN
  PERFORM _sngpa_mk_user(v_creator);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'P-pitch-Tour', 1, 2, 16, 'schoch', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);

  FOR i IN 1 .. array_length(v_parts, 1) LOOP
    v_uid := _sngpa_mk_user(v_parts[i]);
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status)
      VALUES (v_parts[i], v_tour, v_uid, 'confirmed');
  END LOOP;

  -- Stage 1: two snake groups of three, with a per-group pitch assignment:
  -- group A served by pitches [3,4], group B by pitch [7].
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'pool_pitch', 'group_phase',
            '{"groupCount":2,"qualifierCount":1,"grouping_strategy":"snake",'
            '"group_pitch_assignment":{"A":[3,4],"B":[7]}}'::jsonb,
            'manual', 'pending');

  -- Stage 2: same two groups, NO group_pitch_assignment -> placeholder kept.
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'pool_noassign', 'group_phase',
            '{"groupCount":2,"qualifierCount":1,"grouping_strategy":"snake"}'::jsonb,
            'manual', 'pending');

  PERFORM public.tournament_generate_stage_matches(v_tour, 'pool_pitch', v_parts);
  PERFORM public.tournament_generate_stage_matches(v_tour, 'pool_noassign', v_parts);

  PERFORM public._tournament_assign_pitches_from_stage_node(v_tour, 'pool_pitch');
  PERFORM public._tournament_assign_pitches_from_stage_node(v_tour, 'pool_noassign');
END;
$fixture$;

-- ── Assigned stage (pool_pitch) ──────────────────────────────────────────
-- Group A (3 matches) over pitches [3,4] round-robin -> {3,4} distinct.
SELECT is(
  (SELECT array_agg(DISTINCT pitch_number ORDER BY pitch_number)
     FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_pitch' AND group_label = 'A'),
  ARRAY[3,4]::smallint[],
  'group A matches land only on its assigned pitches 3 and 4');

-- The round-robin spread: 3 matches over 2 pitches -> 3 appears twice, 4 once.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_pitch' AND group_label = 'A'
       AND pitch_number = 3),
  2,
  'group A: pitch 3 used twice (rn 1 and rn 3)');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_pitch' AND group_label = 'A'
       AND pitch_number = 4),
  1,
  'group A: pitch 4 used once (rn 2)');

-- Group B (3 matches) over a single pitch [7] -> all on 7.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_pitch' AND group_label = 'B'
       AND pitch_number = 7),
  3,
  'group B: all three matches on its single assigned pitch 7');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_pitch'
       AND pitch_number NOT IN (3,4,7)),
  0,
  'no assigned-stage match sits on a pitch outside the assignment');

-- ── No-assignment stage (pool_noassign) — placeholder unchanged ──────────
SELECT is(
  (SELECT count(DISTINCT pitch_number)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_noassign'),
  1,
  'stage without group_pitch_assignment keeps a single placeholder pitch');

SELECT is(
  (SELECT DISTINCT pitch_number::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_noassign'),
  1,
  'that placeholder is the generator default pitch_number = 1 (no-op)');

SELECT * FROM finish();
ROLLBACK;
