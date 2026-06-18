-- ADR-0033 §4 P5.3a — stage POOL nodes honour multi-group config.
--
-- tournament_generate_stage_matches must, for a pool/round_robin stage:
--   * group_count > 1 → split the seeded field into group_count groups via
--     _tournament_compute_pools and emit intra-group round-robin pairs tagged
--     with group_label;
--   * group_count <= 1 (or absent) → keep the original single flat group
--     (group_label NULL), behaviour-stable.
--
-- pgTAP is installed transiently inside BEGIN..ROLLBACK; nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION _spmg_mk_user(p_uid uuid) RETURNS uuid
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
  v_creator uuid := '77770000-0000-0000-0000-00000000000a';
  v_tour    uuid := '7777aaaa-0000-0000-0000-000000000001';
  v_parts   uuid[] := ARRAY[
    '7777bbbb-0000-0000-0000-000000000001',
    '7777bbbb-0000-0000-0000-000000000002',
    '7777bbbb-0000-0000-0000-000000000003',
    '7777bbbb-0000-0000-0000-000000000004',
    '7777bbbb-0000-0000-0000-000000000005',
    '7777bbbb-0000-0000-0000-000000000006'
  ]::uuid[];
  v_uid uuid;
  i int;
BEGIN
  PERFORM _spmg_mk_user(v_creator);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'P5.3a-Tour', 1, 2, 16, 'swiss', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);

  -- 6 confirmed solo participants. Each participant id doubles as its user id
  -- (a fresh auth user per participant).
  FOR i IN 1 .. array_length(v_parts, 1) LOOP
    v_uid := _spmg_mk_user(v_parts[i]);
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status)
      VALUES (v_parts[i], v_tour, v_uid, 'confirmed');
  END LOOP;

  -- Stage 1: pool with group_count = 2 (snake) → two groups of three.
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'pool_g2', 'pool',
            '{"groupCount":2,"qualifierCount":1,"grouping_strategy":"snake"}'::jsonb,
            'manual', 'pending');

  -- Stage 2: pool with NO group_count → single flat group (group_label NULL).
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'pool_flat', 'pool',
            '{}'::jsonb, 'manual', 'pending');

  PERFORM public.tournament_generate_stage_matches(v_tour, 'pool_g2', v_parts);
  PERFORM public.tournament_generate_stage_matches(v_tour, 'pool_flat', v_parts);
END;
$fixture$;

-- ── Multi-group stage (pool_g2) ──────────────────────────────────────────
SELECT is(
  (SELECT count(DISTINCT group_label)::int FROM public.tournament_matches
     WHERE tournament_id = '7777aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_g2'),
  2,
  'group_count=2 produces exactly two distinct group_labels');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '7777aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_g2' AND group_label = 'A'),
  3,
  'group A (3 players) has 3 round-robin matches');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '7777aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_g2'),
  6,
  'two groups of three => 6 group matches total');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '7777aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_g2'
       AND (phase <> 'group' OR round_number <> 1)),
  0,
  'all multi-group matches are round 1, phase group');

-- ── Single flat group (pool_flat) — behaviour-stable ─────────────────────
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '7777aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_flat' AND group_label IS NOT NULL),
  0,
  'single flat group keeps group_label NULL (no behaviour change)');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = '7777aaaa-0000-0000-0000-000000000001'
       AND stage_node_id = 'pool_flat'),
  15,
  'flat group over 6 participants => C(6,2)=15 round-robin matches');

SELECT * FROM finish();
ROLLBACK;
