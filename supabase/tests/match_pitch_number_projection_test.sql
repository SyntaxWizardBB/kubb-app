-- tournament_match_get and tournament_list_matches project the match's
-- pitch_number (column lives on tournament_matches since 20260525000001:67,
-- fed by _tournament_assign_pitches / _from_stage_node).
--
-- Spine mirrors stage_node_group_pitch_assignment_test: a live tournament with
-- a per-group pitch assignment, generate the stage matches, run the assign
-- helper so the matches carry real pitch numbers (3/4 for group A, 7 for group
-- B), then read the two projection RPCs AS THE CREATOR and assert the projected
-- pitch_number equals what the assign helper stamped.
--
-- pgTAP is installed transiently inside BEGIN..ROLLBACK; nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(6);

CREATE OR REPLACE FUNCTION _mpn_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _mpn_as_pg() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

CREATE OR REPLACE FUNCTION _mpn_mk_user(p_uid uuid) RETURNS uuid
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

CREATE OR REPLACE FUNCTION _mpn_creator() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '9999cccc-0000-0000-0000-00000000000a'::uuid $$;
CREATE OR REPLACE FUNCTION _mpn_tid() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '9999aaaa-0000-0000-0000-000000000001'::uuid $$;

DO $fixture$
DECLARE
  v_creator uuid := _mpn_creator();
  v_tour    uuid := _mpn_tid();
  v_parts   uuid[] := ARRAY[
    '9999bbbb-0000-0000-0000-000000000001',
    '9999bbbb-0000-0000-0000-000000000002',
    '9999bbbb-0000-0000-0000-000000000003',
    '9999bbbb-0000-0000-0000-000000000004',
    '9999bbbb-0000-0000-0000-000000000005',
    '9999bbbb-0000-0000-0000-000000000006'
  ]::uuid[];
  v_uid uuid;
  i int;
BEGIN
  PERFORM _mpn_mk_user(v_creator);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'Pitch-Projection-Tour', 1, 2, 16,
            'schoch', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);

  FOR i IN 1 .. array_length(v_parts, 1) LOOP
    v_uid := _mpn_mk_user(v_parts[i]);
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status)
      VALUES (v_parts[i], v_tour, v_uid, 'confirmed');
  END LOOP;

  -- Two snake groups of three, group A on pitches [3,4], group B on pitch [7].
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'pool_pitch', 'group_phase',
            '{"groupCount":2,"qualifierCount":1,"grouping_strategy":"snake",'
            '"group_pitch_assignment":{"A":[3,4],"B":[7]}}'::jsonb,
            'manual', 'pending');

  PERFORM public.tournament_generate_stage_matches(v_tour, 'pool_pitch', v_parts);
  PERFORM public._tournament_assign_pitches_from_stage_node(v_tour, 'pool_pitch');
END;
$fixture$;

-- The assign helper stamped the matches: group A over {3,4}, group B all on 7.
-- The projection assertions read the RPCs as the tournament creator, who passes
-- the SECURITY DEFINER auth + visibility gate on a live tournament.

-- ── tournament_match_get projects pitch_number ───────────────────────────
SELECT _mpn_as(_mpn_creator());

-- A group-A match carries one of its assigned pitches (3 or 4).
SELECT is(
  (public.tournament_match_get((
     SELECT id FROM public.tournament_matches
       WHERE tournament_id = _mpn_tid()
         AND stage_node_id = 'pool_pitch' AND group_label = 'A'
       ORDER BY match_number_in_round LIMIT 1)) ->> 'pitch_number')::int,
  (SELECT pitch_number::int FROM public.tournament_matches
     WHERE tournament_id = _mpn_tid()
       AND stage_node_id = 'pool_pitch' AND group_label = 'A'
     ORDER BY match_number_in_round LIMIT 1),
  'tournament_match_get projects the stamped pitch_number for a group-A match');

-- A group-B match projects pitch 7.
SELECT is(
  (public.tournament_match_get((
     SELECT id FROM public.tournament_matches
       WHERE tournament_id = _mpn_tid()
         AND stage_node_id = 'pool_pitch' AND group_label = 'B'
       ORDER BY match_number_in_round LIMIT 1)) ->> 'pitch_number')::int,
  7,
  'tournament_match_get projects pitch 7 for a group-B match');

-- The projected value is never NULL for an assigned match.
SELECT isnt(
  (public.tournament_match_get((
     SELECT id FROM public.tournament_matches
       WHERE tournament_id = _mpn_tid()
         AND stage_node_id = 'pool_pitch' AND group_label = 'A'
       ORDER BY match_number_in_round LIMIT 1)) ->> 'pitch_number'),
  NULL,
  'tournament_match_get pitch_number is present (not NULL) on an assigned match');

-- ── tournament_list_matches projects pitch_number per row ────────────────
-- Every listed match carries the same pitch_number the table row holds.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_list_matches(_mpn_tid()) j
     JOIN public.tournament_matches m
       ON m.id = (j ->> 'match_id')::uuid
    WHERE (j ->> 'pitch_number') IS DISTINCT FROM m.pitch_number::text),
  0,
  'tournament_list_matches projects each row''s own pitch_number (no mismatch)');

-- Group A spreads over pitches {3,4} in the list projection.
SELECT is(
  (SELECT array_agg(DISTINCT (j ->> 'pitch_number')::int ORDER BY (j ->> 'pitch_number')::int)
     FROM public.tournament_list_matches(_mpn_tid()) j
     JOIN public.tournament_matches m
       ON m.id = (j ->> 'match_id')::uuid
    WHERE m.group_label = 'A'),
  ARRAY[3,4]::int[],
  'tournament_list_matches projects group A over pitches {3,4}');

-- Group B is all on pitch 7 in the list projection.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_list_matches(_mpn_tid()) j
     JOIN public.tournament_matches m
       ON m.id = (j ->> 'match_id')::uuid
    WHERE m.group_label = 'B' AND (j ->> 'pitch_number')::int = 7),
  3,
  'tournament_list_matches projects all three group-B matches on pitch 7');

SELECT _mpn_as_pg();

SELECT * FROM finish();
ROLLBACK;
