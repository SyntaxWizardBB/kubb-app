-- ADR-0033 §4 / ADR-0034 §3 P5.3c — stage KO round 1 honours per-node format.
--
-- A KO-typed stage node times its round-1 schedule from
-- config->'ko_round_formats'[0]; a non-KO (pool) node keeps prelim timing.
--
-- pgTAP runs inside BEGIN..ROLLBACK; nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(3);

SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION _skrf_mk_user(p_uid uuid) RETURNS uuid
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
  i int;
BEGIN
  PERFORM _skrf_mk_user(v_creator);
  -- Prelim match_format: 1800 s round, 300 s break.
  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'P5.3c-Tour', 1, 2, 16, 'swiss', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);
  FOR i IN 1 .. array_length(v_parts, 1) LOOP
    PERFORM _skrf_mk_user(v_parts[i]);
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status)
      VALUES (v_parts[i], v_tour, v_parts[i], 'confirmed');
  END LOOP;

  -- KO node: per-round format[0] = 1234 s round, 77 s break.
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'cup', 'single_elim',
            jsonb_build_object('ko_round_formats', jsonb_build_array(
              jsonb_build_object(
                'sets_to_win', 2, 'max_sets', 3,
                'time_limit_seconds', 1234,
                'break_between_matches_seconds', 77))),
            'manual', 'pending');

  -- Pool node: no per-round format → prelim timing.
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'grp', 'pool',
            '{}'::jsonb, 'manual', 'pending');

  PERFORM public.tournament_generate_stage_matches(v_tour, 'cup', v_parts);
  PERFORM public.tournament_generate_stage_matches(v_tour, 'grp', v_parts);
END;
$fixture$;

SELECT is(
  (SELECT match_seconds FROM public.tournament_round_schedule
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'cup' AND round_number = 1),
  1234,
  'KO stage round-1 match_seconds comes from node config (1234), not prelim');

SELECT is(
  (SELECT break_seconds FROM public.tournament_round_schedule
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'cup' AND round_number = 1),
  77,
  'KO stage round-1 break_seconds comes from node config (77)');

SELECT is(
  (SELECT match_seconds FROM public.tournament_round_schedule
     WHERE tournament_id = '9999aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'grp' AND round_number = 1),
  1800,
  'non-KO (pool) stage keeps prelim timing (1800) — unchanged');

SELECT * FROM finish();
ROLLBACK;
