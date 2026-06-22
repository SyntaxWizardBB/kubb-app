-- ADR-0039 §6.6 (U10b / T15-T16) — winner-advance + loser-route along a stage
-- type_graph's field edges.
--
-- Stage A carries a CUSTOM KO-4 type_graph:
--   round 1: F1 (slot 1), F2 (slot 2)
--   round 2: F1 (slot 1) = winners' target, F2 (slot 2) = Neben-Cup (side-cup)
--   edges:  winner R1F1 -> R2F1, winner R1F2 -> R2F1 (both winners into R2F1),
--           loser  R1F1 -> R2F2 (F1's loser into the side-cup),
--           R1F2 has NO loser edge -> its loser drops out.
-- Finalising R1F1 then R1F2 must:
--   * land R1F1's winner in R2F1.participant_a (edge rank 1 -> A),
--   * land R1F2's winner in R2F1.participant_b (edge rank 2 -> B),
--   * flip R2F1 scheduled -> awaiting_results once both winners are present,
--   * route R1F1's loser into the side-cup R2F2 (slot A),
--   * drop R1F2's loser (no routing — R2F2 keeps a single occupant).
--
-- Stage B is a STANDARD single_elim bracket (no type_graph): its advance must be
-- byte-for-byte unchanged (semifinal winner lands in the final, regression).
--
-- pgTAP runs transiently inside BEGIN..ROLLBACK; nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(10);

SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION _tgr_mk_user(p_uid uuid) RETURNS uuid
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
  v_creator uuid := '99990000-0000-0000-0000-00000000000a';
  v_tour    uuid := '9999aaaa-0000-0000-0000-000000000001';
  v_parts   uuid[] := ARRAY[
    '9999bbbb-0000-0000-0000-000000000001',
    '9999bbbb-0000-0000-0000-000000000002',
    '9999bbbb-0000-0000-0000-000000000003',
    '9999bbbb-0000-0000-0000-000000000004'
  ]::uuid[];
  v_uid uuid;
  i int;
BEGIN
  PERFORM _tgr_mk_user(v_creator);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'U10b-Tour', 1, 2, 16, 'single_elimination', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);

  FOR i IN 1 .. array_length(v_parts, 1) LOOP
    v_uid := _tgr_mk_user(v_parts[i]);
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, seed, registration_status)
      VALUES (v_parts[i], v_tour, v_uid, i, 'confirmed');
  END LOOP;

  -- Stage A: a CUSTOM KO-4 type_graph with a Neben-Cup loser route.
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
                    "match_format": {"sets_to_win": 2, "max_sets": 3, "time_limit_seconds": 900, "tiebreak_enabled": false},
                    "ko_matchup": "seed_high_vs_low"},
                   {"round_number": 2,
                    "fields": [
                      {"id": "R2F1", "round_number": 2, "slot": 1},
                      {"id": "R2F2", "round_number": 2, "slot": 2}],
                    "match_format": {"sets_to_win": 2, "max_sets": 3, "time_limit_seconds": 900, "tiebreak_enabled": false}}
                 ],
                 "edges": [
                   {"kind": "winner", "from_field_id": "R1F1", "to_field_id": "R2F1"},
                   {"kind": "winner", "from_field_id": "R1F2", "to_field_id": "R2F1"},
                   {"kind": "loser",  "from_field_id": "R1F1", "to_field_id": "R2F2"}
                 ]
               }'::jsonb,
              'ko_round_formats', jsonb_build_array(
                jsonb_build_object('time_limit_seconds', 900,
                                   'break_between_matches_seconds', 120))),
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

-- Sanity: the type_graph stage materialised exactly round 1 = 2 matches.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph'),
  2,
  'KO-4 type_graph materialises round 1 = 2 matches before any advance');

-- Finalise R1F1 (bracket_position 1): winner = its participant_a, loser = b.
DO $$
DECLARE
  v_a uuid; v_b uuid;
BEGIN
  SELECT participant_a, participant_b INTO v_a, v_b
    FROM public.tournament_matches
    WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
      AND stage_node_id = 'ko4_graph'
      AND round_number = 1 AND bracket_position = 1;
  UPDATE public.tournament_matches
    SET status = 'finalized', winner_participant = v_a, finalized_at = now()
    WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
      AND stage_node_id = 'ko4_graph'
      AND round_number = 1 AND bracket_position = 1;
END $$;

-- After R1F1: R2F1 exists (first WinnerEdge feeder), winner in A, status scheduled.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph'
       AND round_number = 2 AND bracket_position = 1),
  1,
  'first WinnerEdge feeder upserts the target match R2F1');

SELECT is(
  (SELECT participant_a FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph'
       AND round_number = 2 AND bracket_position = 1),
  (SELECT winner_participant FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph'
       AND round_number = 1 AND bracket_position = 1),
  'R1F1 winner lands in R2F1.participant_a (edge rank 1 -> A)');

SELECT is(
  (SELECT status FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph'
       AND round_number = 2 AND bracket_position = 1),
  'scheduled',
  'R2F1 stays scheduled while only one winner is present');

-- R1F1's loser routed into the side-cup R2F2 (LoserEdge), slot A.
SELECT is(
  (SELECT participant_a FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph'
       AND round_number = 2 AND bracket_position = 2),
  (SELECT participant_b FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph'
       AND round_number = 1 AND bracket_position = 1),
  'R1F1 loser routed into the Neben-Cup R2F2 via the LoserEdge');

-- Finalise R1F2 (bracket_position 2): winner = participant_a, loser = b (drops).
DO $$
DECLARE
  v_a uuid;
BEGIN
  SELECT participant_a INTO v_a
    FROM public.tournament_matches
    WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
      AND stage_node_id = 'ko4_graph'
      AND round_number = 1 AND bracket_position = 2;
  UPDATE public.tournament_matches
    SET status = 'finalized', winner_participant = v_a, finalized_at = now()
    WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
      AND stage_node_id = 'ko4_graph'
      AND round_number = 1 AND bracket_position = 2;
END $$;

-- After R1F2: second WinnerEdge feeder fills R2F1.participant_b.
SELECT is(
  (SELECT participant_b FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph'
       AND round_number = 2 AND bracket_position = 1),
  (SELECT winner_participant FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph'
       AND round_number = 1 AND bracket_position = 2),
  'R1F2 winner lands in R2F1.participant_b (edge rank 2 -> B)');

-- Both winners present -> R2F1 promoted scheduled -> awaiting_results.
SELECT is(
  (SELECT status FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph'
       AND round_number = 2 AND bracket_position = 1),
  'awaiting_results',
  'R2F1 flips scheduled -> awaiting_results once both winners are present');

-- R1F2 has no LoserEdge: its loser must NOT enter the side-cup (drops out).
-- R2F2 keeps a single occupant (only R1F1's loser, in slot A; B stays null).
SELECT is(
  (SELECT participant_b FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_graph'
       AND round_number = 2 AND bracket_position = 2),
  NULL::uuid,
  'R1F2 loser drops out (no LoserEdge) — side-cup R2F2.participant_b stays empty');

-- ── Regression: standard single_elim advance unchanged ────────────────────
-- Finalise the standard stage's first round-1 match (bracket_position 1). Its
-- winner must land in the round-2 (final) match participant_a, byte-identical.
DO $$
DECLARE
  v_a uuid;
BEGIN
  SELECT participant_a INTO v_a
    FROM public.tournament_matches
    WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
      AND stage_node_id = 'ko4_fixed'
      AND round_number = 1 AND bracket_position = 1;
  UPDATE public.tournament_matches
    SET status = 'finalized', winner_participant = v_a, finalized_at = now()
    WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
      AND stage_node_id = 'ko4_fixed'
      AND round_number = 1 AND bracket_position = 1;
END $$;

SELECT is(
  (SELECT participant_a FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_fixed'
       AND round_number = 2 AND bracket_position = 1),
  (SELECT winner_participant FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_fixed'
       AND round_number = 1 AND bracket_position = 1),
  'standard single_elim: round-1 winner (pos 1) advances into the final A-slot');

-- The standard stage never grew a side-cup field (no type_graph edges at play):
-- round 2 still has exactly the one pre-materialised bracket match.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'ko4_fixed'
       AND round_number = 2),
  1,
  'standard single_elim round 2 is the lone pre-materialised match (no upsert)');

SELECT * FROM finish();
ROLLBACK;
