-- ADR-0039 §6.6 (U10a / T13-T14) — generic round-1 materializer from a stage's
-- config['type_graph'].
--
-- A stage that carries a CUSTOM KO type_graph (KO-8: round 1 = F1..F4) must
-- materialise round 1 = exactly 4 matches (one per round-1 TypeField), seed
-- slotted, with the round-1 per-field format on the stage schedule row. A stage
-- WITHOUT a type_graph (standard single_elim and standard schoch) must keep its
-- existing type-fixed materialisation unchanged.
--
-- pgTAP is installed transiently inside BEGIN..ROLLBACK; nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION _stg_mk_user(p_uid uuid) RETURNS uuid
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
    '8888bbbb-0000-0000-0000-000000000006',
    '8888bbbb-0000-0000-0000-000000000007',
    '8888bbbb-0000-0000-0000-000000000008'
  ]::uuid[];
  v_uid uuid;
  i int;
BEGIN
  PERFORM _stg_mk_user(v_creator);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'U10a-Tour', 1, 2, 16, 'single_elimination', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);

  FOR i IN 1 .. array_length(v_parts, 1) LOOP
    v_uid := _stg_mk_user(v_parts[i]);
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, seed, registration_status)
      VALUES (v_parts[i], v_tour, v_uid, i, 'confirmed');
  END LOOP;

  -- Stage A: a CUSTOM KO-8 type_graph (round 1 = F1..F4) with a distinct
  -- per-round format (time_limit_seconds 900) so the schedule row proves the
  -- per-field format flows through KO timing. The stage's .type column is set
  -- to a non-KO value on purpose: the type_graph branch must NOT consult it.
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'ko8_graph', 'group_phase',
            jsonb_build_object(
              'type_graph', '{
                 "category": "ko",
                 "rounds": [
                   {"round_number": 1,
                    "fields": [
                      {"id": "R1F1", "round_number": 1, "slot": 1},
                      {"id": "R1F2", "round_number": 1, "slot": 2},
                      {"id": "R1F3", "round_number": 1, "slot": 3},
                      {"id": "R1F4", "round_number": 1, "slot": 4}],
                    "match_format": {"sets_to_win": 2, "max_sets": 3, "time_limit_seconds": 900, "tiebreak_enabled": false},
                    "ko_matchup": "seed_high_vs_low",
                    "ko_tiebreak_method": "classic_kingtoss_removal"},
                   {"round_number": 2,
                    "fields": [
                      {"id": "R2F1", "round_number": 2, "slot": 1},
                      {"id": "R2F2", "round_number": 2, "slot": 2}],
                    "match_format": {"sets_to_win": 2, "max_sets": 3, "time_limit_seconds": 900, "tiebreak_enabled": false}},
                   {"round_number": 3,
                    "fields": [{"id": "R3F1", "round_number": 3, "slot": 1}],
                    "match_format": {"sets_to_win": 2, "max_sets": 3, "time_limit_seconds": 900, "tiebreak_enabled": false}}
                 ],
                 "edges": [
                   {"kind": "winner", "from_field_id": "R1F1", "to_field_id": "R2F1"},
                   {"kind": "winner", "from_field_id": "R1F2", "to_field_id": "R2F1"},
                   {"kind": "winner", "from_field_id": "R1F3", "to_field_id": "R2F2"},
                   {"kind": "winner", "from_field_id": "R1F4", "to_field_id": "R2F2"},
                   {"kind": "winner", "from_field_id": "R2F1", "to_field_id": "R3F1"},
                   {"kind": "winner", "from_field_id": "R2F2", "to_field_id": "R3F1"}
                 ]
               }'::jsonb,
              'ko_round_formats', jsonb_build_array(
                jsonb_build_object('time_limit_seconds', 900,
                                   'break_between_matches_seconds', 120))),
            'manual', 'pending');

  -- Stage B: a STANDARD single_elim stage (no type_graph) — must materialise
  -- via the type-fixed CASE, unchanged.
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'ko8_fixed', 'single_elim',
            '{}'::jsonb, 'manual', 'pending');

  -- Stage C: a STANDARD schoch stage (no type_graph) — round-1 seed slide,
  -- unchanged.
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'schoch_fixed', 'schoch',
            '{}'::jsonb, 'manual', 'pending');

  PERFORM public.tournament_generate_stage_matches(v_tour, 'ko8_graph', v_parts);
  PERFORM public.tournament_generate_stage_matches(v_tour, 'ko8_fixed', v_parts);
  PERFORM public.tournament_generate_stage_matches(v_tour, 'schoch_fixed', v_parts);
END;
$fixture$;

-- ── Custom KO type_graph (ko8_graph) ──────────────────────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko8_graph'),
  4,
  'KO-8 type_graph materialises round 1 = 4 matches (the F1..F4 fields)');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko8_graph'
       AND round_number = 1),
  4,
  'all four type_graph matches are round 1');

SELECT is(
  (SELECT array_agg(match_number_in_round::int ORDER BY match_number_in_round)
     FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko8_graph'),
  ARRAY[1,2,3,4],
  'type_graph fields map onto match slots 1..4 (one per TypeField)');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko8_graph'
       AND phase = 'ko'),
  4,
  'a multi-round KO type_graph tags round-1 matches phase ko (not final)');

-- Seed slotting: 8 distinct seeds occupy all eight participant slots, no BYE.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko8_graph'
       AND participant_a IS NOT NULL
       AND participant_b IS NOT NULL),
  4,
  'full field of 8 yields four real (no-BYE) pairings');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko8_graph'
       AND status = 'scheduled'),
  4,
  'all four type_graph round-1 matches are scheduled');

-- Per-field KO timing reached the stage schedule row (900s, not the 1800s
-- prelim format). KO-category type_graph routes through the KO timing arm.
SELECT is(
  (SELECT match_seconds::int FROM public.tournament_round_schedule
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko8_graph'
       AND round_number = 1),
  900,
  'KO type_graph round-1 schedule is timed from the node KO format (900s)');

-- ── Standard single_elim (ko8_fixed) — unchanged type-fixed path ──────────
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko8_fixed'),
  7,
  'standard single_elim over 8 seeds still emits the full 7-match bracket');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko8_fixed'
       AND round_number = 1),
  4,
  'standard single_elim round 1 = 4 matches (type-fixed CASE unchanged)');

-- ── Standard schoch (schoch_fixed) — unchanged seed slide ─────────────────
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'schoch_fixed'),
  4,
  'standard schoch over 8 seeds emits 4 round-1 slide pairs (type-fixed path)');

SELECT is(
  (SELECT match_seconds::int FROM public.tournament_round_schedule
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'schoch_fixed'
       AND round_number = 1),
  1800,
  'standard schoch keeps prelim timing (1800s) — type-fixed path unchanged');

SELECT * FROM finish();
ROLLBACK;
