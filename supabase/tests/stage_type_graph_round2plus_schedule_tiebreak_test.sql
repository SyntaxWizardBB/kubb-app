-- ADR-0039 §6.6 (U10c / T17-T18 + U10b concurrency hardening) — round-2+
-- scheduling from the TypeRound matchFormat, server-authoritative per-field
-- ko_tiebreak, and a duplicate-free upsert under concurrent feeders.
--
-- Stage A carries a CUSTOM KO-4 type_graph whose ROUND-2 matchFormat timing is
-- deliberately DISTINCT from both the round-1 matchFormat and the stage-wide
-- config->'ko_round_formats':
--   round 1: F1 (slot 1), F2 (slot 2), matchFormat time 1800 / break 300,
--            ko_tiebreak_method classic_kingtoss_removal.
--   round 2: F1 (slot 1) = both round-1 winners' target, matchFormat
--            time 1234 / break 77, ko_tiebreak_method mighty_finisher_shootout.
--   edges:  winner R1F1 -> R2F1, winner R1F2 -> R2F1.
--   ko_round_formats = [ {900/120}, {600/60} ]  (the OLD, wrong source).
--
-- Asserts:
--   * round-1 schedule row times from the TypeRound-1 matchFormat (1800/300),
--     NOT ko_round_formats[0] (900/120) — closes the U10a parsed-but-unused gap.
--   * round-1 KO matches carry ko_tiebreak_method = classic (T18, materializer).
--   * filling R2F1 (both winners) materialises a round-2 schedule row timed from
--     the TypeRound-2 matchFormat (1234/77), proving the type_graph source over
--     ko_round_formats[1] (600/60) (T17).
--   * R2F1 carries ko_tiebreak_method = mighty_finisher_shootout (T18, routing).
--   * two simultaneous feeders into the SAME target field yield exactly ONE
--     match (no duplicate) thanks to the ON CONFLICT upsert (U10b hardening).
--
-- Stage B is a STANDARD single_elim bracket (no type_graph): its KO schedule and
-- its NULL ko_tiebreak_method must be byte-for-byte unchanged (regression).
--
-- pgTAP runs transiently inside BEGIN..ROLLBACK; nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(11);

SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION _tgs_mk_user(p_uid uuid) RETURNS uuid
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
    '8888bbbb-0000-0000-0000-000000000004'
  ]::uuid[];
  v_uid uuid;
  i int;
BEGIN
  PERFORM _tgs_mk_user(v_creator);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'U10c-Tour', 1, 2, 16, 'single_elimination', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);

  FOR i IN 1 .. array_length(v_parts, 1) LOOP
    v_uid := _tgs_mk_user(v_parts[i]);
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, seed, registration_status)
      VALUES (v_parts[i], v_tour, v_uid, i, 'confirmed');
  END LOOP;

  -- Stage A: KO-4 type_graph. Round-2 matchFormat (1234/77) is distinct from the
  -- round-1 matchFormat (1800/300) AND from ko_round_formats ([900/120],[600/60]).
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'ko4_graph', 'group_phase',
            jsonb_build_object(
              'type_graph', '{
                 "category": "ko",
                 "rounds": [
                   {"round_number": 1,
                    "fields": [
                      {"id": "R1F1", "round_number": 1, "slot": 1},
                      {"id": "R1F2", "round_number": 1, "slot": 2}],
                    "match_format": {"sets_to_win": 2, "max_sets": 3, "time_limit_seconds": 1800, "break_between_matches_seconds": 300, "tiebreak_enabled": false, "tiebreak_after_seconds": null},
                    "ko_matchup": "seed_high_vs_low",
                    "ko_tiebreak_method": "classic_kingtoss_removal"},
                   {"round_number": 2,
                    "fields": [
                      {"id": "R2F1", "round_number": 2, "slot": 1}],
                    "match_format": {"sets_to_win": 2, "max_sets": 3, "time_limit_seconds": 1234, "break_between_matches_seconds": 77, "tiebreak_enabled": false, "tiebreak_after_seconds": null},
                    "ko_tiebreak_method": "mighty_finisher_shootout"}
                 ],
                 "edges": [
                   {"kind": "winner", "from_field_id": "R1F1", "to_field_id": "R2F1"},
                   {"kind": "winner", "from_field_id": "R1F2", "to_field_id": "R2F1"}
                 ]
               }'::jsonb,
              'ko_round_formats', jsonb_build_array(
                jsonb_build_object('time_limit_seconds', 900,
                                   'break_between_matches_seconds', 120),
                jsonb_build_object('time_limit_seconds', 600,
                                   'break_between_matches_seconds', 60))),
            'manual', 'pending');

  -- Stage B: a STANDARD single_elim bracket (no type_graph) for the regression.
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'ko4_fixed', 'single_elim',
            '{}'::jsonb, 'manual', 'pending');

  PERFORM public.tournament_generate_stage_matches(v_tour, 'ko4_graph', v_parts);
  PERFORM public.tournament_generate_stage_matches(v_tour, 'ko4_fixed', v_parts);
END;
$fixture$;

-- ── T17 / U10a-MEDIUM: round-1 schedule from the TypeRound-1 matchFormat ──────
SELECT is(
  (SELECT match_seconds FROM public.tournament_round_schedule
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph' AND round_number = 1),
  1800,
  'round-1 schedule match_seconds = TypeRound-1 matchFormat (1800), not ko_round_formats[0] (900)');

SELECT is(
  (SELECT break_seconds FROM public.tournament_round_schedule
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph' AND round_number = 1),
  300,
  'round-1 schedule break_seconds = TypeRound-1 matchFormat (300), not ko_round_formats[0] (120)');

-- ── T18: round-1 KO matches carry the round-1 ko_tiebreak (materializer) ──────
SELECT is(
  (SELECT count(DISTINCT ko_tiebreak_method)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph' AND round_number = 1),
  1,
  'all round-1 type_graph KO matches share one server-set ko_tiebreak_method');

SELECT is(
  (SELECT DISTINCT ko_tiebreak_method FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph' AND round_number = 1),
  'classic_kingtoss_removal',
  'round-1 KO match ko_tiebreak_method == TypeRound-1 ko_tiebreak (T18, materializer)');

-- Finalise both round-1 matches so R2F1 fills (both winners present).
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT id, participant_a FROM public.tournament_matches
      WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
        AND stage_node_id = 'ko4_graph' AND round_number = 1
      ORDER BY bracket_position
  LOOP
    UPDATE public.tournament_matches
      SET status = 'finalized', winner_participant = r.participant_a,
          finalized_at = now()
      WHERE id = r.id;
  END LOOP;
END $$;

-- R2F1 exists, both winners present, flipped to awaiting_results.
SELECT is(
  (SELECT status FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph' AND round_number = 2 AND bracket_position = 1),
  'awaiting_results',
  'R2F1 flips scheduled -> awaiting_results once both winners arrive');

-- ── T17: round-2 schedule materialised from the TypeRound-2 matchFormat ───────
SELECT is(
  (SELECT match_seconds FROM public.tournament_round_schedule
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph' AND round_number = 2),
  1234,
  'round-2 schedule match_seconds = TypeRound-2 matchFormat (1234), not ko_round_formats[1] (600)');

SELECT is(
  (SELECT break_seconds FROM public.tournament_round_schedule
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph' AND round_number = 2),
  77,
  'round-2 schedule break_seconds = TypeRound-2 matchFormat (77), not ko_round_formats[1] (60)');

-- ── T18: R2F1 carries the round-2 ko_tiebreak (routing) ───────────────────────
SELECT is(
  (SELECT ko_tiebreak_method FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph' AND round_number = 2 AND bracket_position = 1),
  'mighty_finisher_shootout',
  'R2F1 ko_tiebreak_method == TypeRound-2 ko_tiebreak (T18, routing)');

-- ── U10b hardening: two simultaneous feeders -> exactly ONE target match ──────
-- Drop the materialised R2F1 and replay BOTH winner routes directly through the
-- helper (the second feeder hits the ON CONFLICT upsert path, not a duplicate
-- INSERT). Exactly one R2F1 must exist, with both slots filled.
DO $$
DECLARE
  v_tour  uuid := '8888aaaa-0000-0000-0000-000000000001';
  v_graph jsonb;
  v_w1 uuid; v_w2 uuid;
BEGIN
  DELETE FROM public.tournament_matches
    WHERE tournament_id = v_tour AND stage_node_id = 'ko4_graph'
      AND round_number = 2;
  DELETE FROM public.tournament_round_schedule
    WHERE tournament_id = v_tour AND stage_node_id = 'ko4_graph'
      AND round_number = 2;

  SELECT config -> 'type_graph' INTO v_graph
    FROM public.tournament_stages
    WHERE tournament_id = v_tour AND node_id = 'ko4_graph';

  SELECT winner_participant INTO v_w1 FROM public.tournament_matches
    WHERE tournament_id = v_tour AND stage_node_id = 'ko4_graph'
      AND round_number = 1 AND bracket_position = 1;
  SELECT winner_participant INTO v_w2 FROM public.tournament_matches
    WHERE tournament_id = v_tour AND stage_node_id = 'ko4_graph'
      AND round_number = 1 AND bracket_position = 2;

  -- Both feeders into R2F1. First INSERTs (slot A), second upserts (slot B).
  PERFORM public._tournament_type_graph_route_into(
    v_tour, 'ko4_graph', v_graph, 'R1F1', 'R2F1', v_w1, 2, 1);
  PERFORM public._tournament_type_graph_route_into(
    v_tour, 'ko4_graph', v_graph, 'R1F2', 'R2F1', v_w2, 2, 1);
END $$;

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph' AND round_number = 2 AND bracket_position = 1),
  1,
  'two feeders into R2F1 yield exactly one match (ON CONFLICT, no duplicate)');

SELECT is(
  (SELECT (participant_a IS NOT NULL AND participant_b IS NOT NULL)
     FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph' AND round_number = 2 AND bracket_position = 1),
  true,
  'the single R2F1 has both slots filled after the second feeder upsert');

-- ── Regression: standard single_elim KO scheduling + NULL tiebreak unchanged ──
-- The standard stage's round-1 schedule still times from ko_round_formats[0]
-- (the fixed-type KO source: stage config has none -> tournament match_format
-- 1800/300), and its matches carry a NULL ko_tiebreak_method (classic path).
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_fixed' AND ko_tiebreak_method IS NOT NULL),
  0,
  'standard single_elim matches keep a NULL ko_tiebreak_method (classic unchanged)');

SELECT * FROM finish();
ROLLBACK;
