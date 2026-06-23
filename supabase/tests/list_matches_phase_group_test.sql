-- tournament_list_matches projects each match's phase and group_label.
-- Both columns live on tournament_matches: `phase` since 20260601000010
-- (DEFAULT 'group', CHECK group/ko/third_place/final) and `group_label`
-- since 20260615000009 (pool-phase group, NULL outside the group phase).
--
-- The live "Übersicht" tab labels group-phase matches "Gruppe A · Runde 1"
-- (spec §5.2), so the list RPC must carry both per row. Spine mirrors
-- match_pitch_number_projection_test: a live tournament with stage matches
-- generated and stamped into two snake groups (A/B), then read the list RPC
-- AS THE CREATOR and assert phase + group_label match the table rows.
--
-- pgTAP is installed transiently inside BEGIN..ROLLBACK; nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(5);

CREATE OR REPLACE FUNCTION _lpg_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _lpg_as_pg() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

CREATE OR REPLACE FUNCTION _lpg_mk_user(p_uid uuid) RETURNS uuid
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

CREATE OR REPLACE FUNCTION _lpg_creator() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '8888cccc-0000-0000-0000-00000000000a'::uuid $$;
CREATE OR REPLACE FUNCTION _lpg_tid() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '8888aaaa-0000-0000-0000-000000000001'::uuid $$;

DO $fixture$
DECLARE
  v_creator uuid := _lpg_creator();
  v_tour    uuid := _lpg_tid();
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
  PERFORM _lpg_mk_user(v_creator);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'Phase-Group-Label-Tour', 1, 2, 16,
            'schoch', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);

  FOR i IN 1 .. array_length(v_parts, 1) LOOP
    v_uid := _lpg_mk_user(v_parts[i]);
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status)
      VALUES (v_parts[i], v_tour, v_uid, 'confirmed');
  END LOOP;

  -- Two snake groups of three (A/B). The group_phase materializer stamps
  -- group_label per match and the row keeps the default phase 'group'.
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'pool_pg', 'group_phase',
            '{"groupCount":2,"qualifierCount":1,"grouping_strategy":"snake"}'::jsonb,
            'manual', 'pending');

  PERFORM public.tournament_generate_stage_matches(v_tour, 'pool_pg', v_parts);
END;
$fixture$;

-- Read the list RPC as the tournament creator, who passes the SECURITY DEFINER
-- auth + visibility gate on a live tournament.
SELECT _lpg_as(_lpg_creator());

-- Every listed match projects its own phase (no mismatch against the row).
SELECT is(
  (SELECT count(*)::int FROM public.tournament_list_matches(_lpg_tid()) j
     JOIN public.tournament_matches m
       ON m.id = (j ->> 'match_id')::uuid
    WHERE (j ->> 'phase') IS DISTINCT FROM m.phase),
  0,
  'tournament_list_matches projects each row''s own phase (no mismatch)');

-- Every listed match projects its own group_label (NULL-safe comparison).
SELECT is(
  (SELECT count(*)::int FROM public.tournament_list_matches(_lpg_tid()) j
     JOIN public.tournament_matches m
       ON m.id = (j ->> 'match_id')::uuid
    WHERE (j ->> 'group_label') IS DISTINCT FROM m.group_label),
  0,
  'tournament_list_matches projects each row''s own group_label (no mismatch)');

-- The group-phase matches all carry phase = 'group'.
SELECT is(
  (SELECT array_agg(DISTINCT (j ->> 'phase'))
     FROM public.tournament_list_matches(_lpg_tid()) j),
  ARRAY['group']::text[],
  'tournament_list_matches projects phase = group for the group-phase matches');

-- Both groups A and B surface as group_label in the projection.
SELECT is(
  (SELECT array_agg(DISTINCT (j ->> 'group_label') ORDER BY (j ->> 'group_label'))
     FROM public.tournament_list_matches(_lpg_tid()) j),
  ARRAY['A','B']::text[],
  'tournament_list_matches projects both group labels A and B');

-- Group A has the same match count in the projection as the table holds.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_list_matches(_lpg_tid()) j
    WHERE (j ->> 'group_label') = 'A'),
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = _lpg_tid() AND group_label = 'A'),
  'tournament_list_matches projects all group-A matches with their label');

SELECT _lpg_as_pg();

SELECT * FROM finish();
ROLLBACK;
