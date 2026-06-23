-- ADR-0039 §4 (Unit 8b E) — stage-scoped KO advance with TWO KO stages.
--
-- Two double_elim KO stages (ko_a, ko_b) live in ONE tournament, each
-- materialised over the SAME four participants via tournament_generate_stage_
-- matches. Finalising a winners-bracket match in stage ko_a must route its
-- winner and loser ONLY inside ko_a's bracket — stage ko_b must stay completely
-- untouched. Before Unit 8b the advance trigger's DE branch aggregated across
-- all phases of the tournament (MAX(round_number) WHERE phase='wb', and the
-- target UPDATEs were not stage-scoped), so the winner would also be written
-- into stage ko_b's wb round 2 and the loser into ko_b's lb — cross-stage
-- corruption. The `AND stage_node_id IS NOT DISTINCT FROM NEW.stage_node_id`
-- scoping closes that.
--
-- DE-4 bracket shape (verified): wb r1 (bp1 = seed1 vs seed4, bp2 = seed3 vs
-- seed2), wb r2 (bp1, the wb final), lb r1 (bp1), lb r2 (bp1), grand_final r1.
-- Finalising ko_a wb r1 bp1 with seed1 winning:
--   * seed1 -> ko_a wb r2 bp1, slot A;
--   * seed4 (loser) -> ko_a lb r1 bp1;
--   * ko_b wb r2 bp1 stays NULL, ko_b lb r1 bp1 stays NULL.
--
-- pgTAP runs transiently inside BEGIN..ROLLBACK; nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION _sst_mk_user(p_uid uuid) RETURNS uuid
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
  PERFORM _sst_mk_user(v_creator);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public,
      bracket_type)
    VALUES (v_tour, v_creator, 'TwoKO-Tour', 1, 2, 16, 'single_elimination', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true, 'double_elimination');

  FOR i IN 1 .. array_length(v_parts, 1) LOOP
    v_uid := _sst_mk_user(v_parts[i]);
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, seed, registration_status)
      VALUES (v_parts[i], v_tour, v_uid, i, 'confirmed');
  END LOOP;

  -- Two double_elim KO stages over the same field. with_reset OFF (explicit).
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES
      (gen_random_uuid(), v_tour, 'ko_a', 'double_elim',
         jsonb_build_object('ko_matchup', 'seed_high_vs_low',
                            'with_reset', false),
         'as_routed', 'active'),
      (gen_random_uuid(), v_tour, 'ko_b', 'double_elim',
         jsonb_build_object('ko_matchup', 'seed_high_vs_low',
                            'with_reset', false),
         'as_routed', 'active');

  PERFORM public.tournament_generate_stage_matches(v_tour, 'ko_a', v_parts);
  PERFORM public.tournament_generate_stage_matches(v_tour, 'ko_b', v_parts);
END;
$fixture$;

-- ---- Both stages materialised independently (wb/lb/grand_final each). ----
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'::uuid
       AND stage_node_id = 'ko_a'
       AND phase IN ('wb','lb','grand_final')),
  6,
  'ko_a materialised the full DE-4 bracket (3 wb + 2 lb + 1 grand_final)'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'::uuid
       AND stage_node_id = 'ko_b'
       AND phase IN ('wb','lb','grand_final')),
  6,
  'ko_b materialised the full DE-4 bracket independently'
);

-- ---- Finalise ko_a wb r1 bp1 (seed1 wins, seed4 loses). ----
DO $fin$
DECLARE
  v_mid uuid;
BEGIN
  SELECT id INTO v_mid FROM public.tournament_matches
    WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'::uuid
      AND stage_node_id = 'ko_a' AND phase = 'wb'
      AND round_number = 1 AND bracket_position = 1;
  UPDATE public.tournament_matches
    SET status = 'finalized',
        winner_participant = '8888bbbb-0000-0000-0000-000000000001'::uuid,
        finalized_at = now()
    WHERE id = v_mid;
END;
$fin$;

-- ---- ko_a routing happened in-stage. ----
SELECT is(
  (SELECT participant_a FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'::uuid
       AND stage_node_id = 'ko_a' AND phase = 'wb'
       AND round_number = 2 AND bracket_position = 1),
  '8888bbbb-0000-0000-0000-000000000001'::uuid,
  'ko_a: wb r1 winner (seed1) advanced into ko_a wb r2 slot A'
);
SELECT ok(
  EXISTS (
    SELECT 1 FROM public.tournament_matches
      WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'::uuid
        AND stage_node_id = 'ko_a' AND phase = 'lb'
        AND round_number = 1
        AND '8888bbbb-0000-0000-0000-000000000004'::uuid
              IN (participant_a, participant_b)),
  'ko_a: wb r1 loser (seed4) dropped into ko_a lb round 1'
);

-- ---- ko_b stays untouched (the whole point of the stage scoping). ----
SELECT is(
  (SELECT participant_a FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'::uuid
       AND stage_node_id = 'ko_b' AND phase = 'wb'
       AND round_number = 2 AND bracket_position = 1),
  NULL::uuid,
  'ko_b: wb r2 slot A is still NULL (no cross-stage winner write)'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '8888aaaa-0000-0000-0000-000000000001'::uuid
       AND stage_node_id = 'ko_b' AND phase = 'lb'
       AND (participant_a IS NOT NULL OR participant_b IS NOT NULL)),
  0,
  'ko_b: lb bracket received no cross-stage loser drop'
);

SELECT * FROM finish();

ROLLBACK;
