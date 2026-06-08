-- V2-B1 — tournament_update live-edit + safe recompute pgTAP tests.
--
-- Covers the five Definition-of-Done scenarios for the live-editable
-- tournament_update (migration 20261243000000):
--   (i)   metadata edit while LIVE is OK and leaves matches untouched
--   (ii)  future-format edit while LIVE is OK; played matches untouched
--   (iii) structural change on a phase WITH a played match -> STRUCTURE_LOCKED
--   (iv)  structural change on a generated, fully-unplayed phase ->
--         unplayed pairings regenerated, played/finalised matches untouched
--   (v)   finalized tournament stays frozen (TOURNAMENT_LOCKED)
--   (vi)  a non-manager (authenticated, not creator/club-manager) is
--         rejected with SQLSTATE 42501 (manage gate runs first)
--   (vii) the unplayed recompute (iv) is SILENT: it neither spams the
--         participants with a 'Turnier gestartet' inbox message nor emits a
--         fake 'pool_phase_started' audit event (relabelled to
--         'phase_recomputed' instead)
--   (viii) a live FORMAT switch that crosses the phase family (pool <-> ko)
--          on a generated phase is rejected with HINT STRUCTURE_LOCKED
--
-- auth.uid() is switched via SET LOCAL request.jwt.claims, mirroring
-- tournament_ko_rpcs.sql. Each scenario is a SETOF-text function so the
-- pgTAP assertion lines surface as TAP output; called from top-level
-- SELECTs. Wrapped in BEGIN/ROLLBACK.

BEGIN;

SELECT plan(24);

-- ---------------------------------------------------------------------
-- Helpers.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _v2_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
END;
$$;

-- Build a LIVE round_robin_then_ko tournament with n confirmed participants.
-- Status starts 'live' but NO matches are materialised yet. Returns the id.
CREATE OR REPLACE FUNCTION _v2_build(p_creator uuid, p_n int)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_tid uuid := gen_random_uuid();
  v_uid uuid;
  i int;
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
    VALUES (p_creator, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'creator-' || p_creator::text || '@v2.local',
            '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format,
      pool_phase_config, ko_config, bracket_type, ko_matchup,
      tiebreaker_order, status, started_at)
    VALUES (
      v_tid, p_creator, 'V2-Live-' || v_tid::text, 1, 2, 64,
      'round_robin_then_ko', 'ekc', '{"sets_to_win":2,"max_sets":3}'::jsonb,
      jsonb_build_object('group_count', 2, 'qualifiers_per_group', 2,
                         'strategy', 'snake'),
      jsonb_build_object('qualifier_count', 4),
      'single_elimination', 'seed_high_vs_low',
      ARRAY['total_points','wins'], 'live', now());

  FOR i IN 1..p_n LOOP
    v_uid := gen_random_uuid();
    INSERT INTO auth.users (id, instance_id, aud, role, email,
                            encrypted_password, email_confirmed_at,
                            created_at, updated_at)
      VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated',
              'p' || i || '-' || v_tid::text || '@v2.local',
              '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, registered_at)
      VALUES (gen_random_uuid(), v_tid, v_uid, 'confirmed',
              now() - (p_n - i) * interval '1 second');
  END LOOP;

  RETURN v_tid;
END;
$$;

-- Setup payload mirroring what the client passes through p_setup.
CREATE OR REPLACE FUNCTION _v2_setup(p_tid uuid) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'scoring',           scoring,
    'pool_phase_config', pool_phase_config,
    'ko_config',         ko_config,
    'bracket_type',      bracket_type,
    'ko_matchup',        ko_matchup,
    'ko_tiebreak_method', coalesce(ko_tiebreak_method, 'classic_kingtoss_removal'),
    'ko_round_formats',  coalesce(ko_round_formats, '[]'::jsonb))
  FROM public.tournaments WHERE id = p_tid;
$$;

CREATE OR REPLACE FUNCTION _v2_cur_name(p_tid uuid) RETURNS text
LANGUAGE sql AS $$ SELECT display_name FROM public.tournaments WHERE id = p_tid; $$;

-- ---------------------------------------------------------------------
-- (i) Metadata edit while LIVE — OK, matches untouched.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _v2_scenario_i() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
  v_setup   jsonb;
  v_before  int;
  v_after   int;
BEGIN
  v_tid := _v2_build(v_creator, 4);
  PERFORM _v2_as(v_creator);
  PERFORM public.tournament_start_pool_phase(
    v_tid, (SELECT pool_phase_config FROM public.tournaments WHERE id = v_tid));

  SELECT count(*) INTO v_before FROM public.tournament_matches
    WHERE tournament_id = v_tid;

  v_setup := _v2_setup(v_tid)
    || jsonb_build_object('location', 'Bern Stadion',
                          'info_food', 'Bratwurst',
                          'contact_name', 'Lukas');

  PERFORM public.tournament_update(
    v_tid, 'Neuer Name', 1, 2, 64, 'round_robin_then_ko',
    '{"sets_to_win":2,"max_sets":3}'::jsonb,
    ARRAY['total_points','wins'], v_setup);

  SELECT count(*) INTO v_after FROM public.tournament_matches
    WHERE tournament_id = v_tid;

  RETURN NEXT ok(v_before > 0, '(i) group phase generated for metadata test');
  RETURN NEXT is(v_after, v_before, '(i) match count unchanged after metadata edit');
  RETURN NEXT is((SELECT display_name FROM public.tournaments WHERE id = v_tid),
             'Neuer Name', '(i) display_name persisted');
  RETURN NEXT is((SELECT location FROM public.tournaments WHERE id = v_tid),
             'Bern Stadion', '(i) location persisted');
  RETURN NEXT is((SELECT info_food FROM public.tournaments WHERE id = v_tid),
             'Bratwurst', '(i) info_food persisted');
END;
$$;

-- ---------------------------------------------------------------------
-- (ii) Future-format edit while LIVE — OK, played matches untouched.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _v2_scenario_ii() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
  v_setup   jsonb;
  v_before  int;
  v_after   int;
  v_fin_id  uuid;
BEGIN
  v_tid := _v2_build(v_creator, 4);
  PERFORM _v2_as(v_creator);
  PERFORM public.tournament_start_pool_phase(
    v_tid, (SELECT pool_phase_config FROM public.tournaments WHERE id = v_tid));

  UPDATE public.tournament_matches
    SET status = 'finalized', finalized_at = now()
    WHERE tournament_id = v_tid AND phase = 'group'
      AND id = (SELECT id FROM public.tournament_matches
                  WHERE tournament_id = v_tid AND phase = 'group'
                  ORDER BY id LIMIT 1)
    RETURNING id INTO v_fin_id;

  SELECT count(*) INTO v_before FROM public.tournament_matches
    WHERE tournament_id = v_tid;

  v_setup := _v2_setup(v_tid)
    || jsonb_build_object('ko_tiebreak_method', 'mighty_finisher_shootout',
                          'ko_round_formats', '[{"sets_to_win":3,"max_sets":5}]'::jsonb);

  PERFORM public.tournament_update(
    v_tid, _v2_cur_name(v_tid), 1, 2, 64, 'round_robin_then_ko',
    '{"sets_to_win":3,"max_sets":5,"time_limit_seconds":600}'::jsonb,
    ARRAY['total_points','wins'], v_setup);

  SELECT count(*) INTO v_after FROM public.tournament_matches
    WHERE tournament_id = v_tid;

  RETURN NEXT is(v_after, v_before,
             '(ii) future-format edit did not delete/create matches');
  RETURN NEXT is((SELECT status FROM public.tournament_matches WHERE id = v_fin_id),
             'finalized', '(ii) finalized match left untouched');
  RETURN NEXT is((SELECT ko_tiebreak_method FROM public.tournaments WHERE id = v_tid),
             'mighty_finisher_shootout', '(ii) future-format field persisted');
END;
$$;

-- ---------------------------------------------------------------------
-- (iii) Structural change on a phase WITH a played match -> STRUCTURE_LOCKED.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _v2_scenario_iii() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
  v_setup   jsonb;
  v_locked  boolean := false;
  v_hint    text;
BEGIN
  v_tid := _v2_build(v_creator, 4);
  PERFORM _v2_as(v_creator);
  PERFORM public.tournament_start_pool_phase(
    v_tid, (SELECT pool_phase_config FROM public.tournaments WHERE id = v_tid));

  -- One group match is now terminal (played).
  UPDATE public.tournament_matches
    SET status = 'finalized', finalized_at = now()
    WHERE tournament_id = v_tid AND phase = 'group'
      AND id = (SELECT id FROM public.tournament_matches
                  WHERE tournament_id = v_tid AND phase = 'group'
                  ORDER BY id LIMIT 1);

  v_setup := _v2_setup(v_tid)
    || jsonb_build_object('pool_phase_config',
         jsonb_build_object('group_count', 1, 'qualifiers_per_group', 4,
                            'strategy', 'snake'));

  BEGIN
    PERFORM public.tournament_update(
      v_tid, _v2_cur_name(v_tid), 1, 2, 64, 'round_robin_then_ko',
      '{"sets_to_win":2,"max_sets":3}'::jsonb,
      ARRAY['total_points','wins'], v_setup);
  EXCEPTION WHEN OTHERS THEN
    v_locked := true;
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;

  RETURN NEXT ok(v_locked, '(iii) structural change on played phase raised');
  RETURN NEXT is(v_hint, 'STRUCTURE_LOCKED', '(iii) HINT is STRUCTURE_LOCKED');
  RETURN NEXT is((SELECT (pool_phase_config->>'group_count')
                FROM public.tournaments WHERE id = v_tid),
             '2', '(iii) pool_phase_config NOT changed (old value)');
END;
$$;

-- ---------------------------------------------------------------------
-- (iv) Structural change on a generated, fully-UNPLAYED phase ->
--      unplayed pairings regenerated; only scheduled matches replaced.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _v2_scenario_iv() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator   uuid := gen_random_uuid();
  v_tid       uuid;
  v_setup     jsonb;
  v_groups_b  int;
  v_groups_a  int;
BEGIN
  v_tid := _v2_build(v_creator, 4);
  PERFORM _v2_as(v_creator);
  PERFORM public.tournament_start_pool_phase(
    v_tid, (SELECT pool_phase_config FROM public.tournaments WHERE id = v_tid));

  SELECT count(DISTINCT group_label) INTO v_groups_b
    FROM public.tournament_matches WHERE tournament_id = v_tid AND phase='group';

  v_setup := _v2_setup(v_tid)
    || jsonb_build_object('pool_phase_config',
         jsonb_build_object('group_count', 1, 'qualifiers_per_group', 2,
                            'strategy', 'snake'));

  PERFORM public.tournament_update(
    v_tid, _v2_cur_name(v_tid), 1, 2, 64, 'round_robin_then_ko',
    '{"sets_to_win":2,"max_sets":3}'::jsonb,
    ARRAY['total_points','wins'], v_setup);

  SELECT count(DISTINCT group_label) INTO v_groups_a
    FROM public.tournament_matches WHERE tournament_id = v_tid AND phase='group';

  RETURN NEXT is(v_groups_b, 2, '(iv) started with 2 groups');
  RETURN NEXT is(v_groups_a, 1, '(iv) regenerated into 1 group after structural edit');
  RETURN NEXT is((SELECT count(*)::int FROM public.tournament_matches
                WHERE tournament_id = v_tid AND status NOT IN ('scheduled')), 0,
             '(iv) all regenerated group matches scheduled (none played)');
END;
$$;

-- ---------------------------------------------------------------------
-- (v) Finalized tournament stays frozen.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _v2_scenario_v() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
  v_setup   jsonb;
  v_frozen  boolean := false;
  v_hint    text;
BEGIN
  v_tid := _v2_build(v_creator, 4);
  UPDATE public.tournaments SET status = 'finalized', completed_at = now()
    WHERE id = v_tid;
  PERFORM _v2_as(v_creator);
  v_setup := _v2_setup(v_tid) || jsonb_build_object('location', 'Zurich');

  BEGIN
    PERFORM public.tournament_update(
      v_tid, _v2_cur_name(v_tid), 1, 2, 64, 'round_robin_then_ko',
      '{"sets_to_win":2,"max_sets":3}'::jsonb,
      ARRAY['total_points','wins'], v_setup);
  EXCEPTION WHEN OTHERS THEN
    v_frozen := true;
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;

  RETURN NEXT ok(v_frozen, '(v) finalized tournament edit raised');
  RETURN NEXT is(v_hint, 'TOURNAMENT_LOCKED', '(v) HINT is TOURNAMENT_LOCKED');
END;
$$;

-- ---------------------------------------------------------------------
-- (vi) Non-manager (authenticated, not creator / club-manager) -> 42501.
--      The manage gate runs BEFORE any status/structure logic.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _v2_scenario_vi() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_intruder uuid := gen_random_uuid();
  v_tid     uuid;
  v_setup   jsonb;
  v_state   text;
BEGIN
  v_tid := _v2_build(v_creator, 4);
  -- A second, unrelated authenticated user (not creator, no club role).
  INSERT INTO auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
    VALUES (v_intruder, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'intruder-' || v_intruder::text || '@v2.local',
            '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  PERFORM _v2_as(v_intruder);
  v_setup := _v2_setup(v_tid) || jsonb_build_object('location', 'Hacktown');

  BEGIN
    PERFORM public.tournament_update(
      v_tid, _v2_cur_name(v_tid), 1, 2, 64, 'round_robin_then_ko',
      '{"sets_to_win":2,"max_sets":3}'::jsonb,
      ARRAY['total_points','wins'], v_setup);
    v_state := 'no-error';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS v_state = RETURNED_SQLSTATE;
  END;

  RETURN NEXT is(v_state, '42501', '(vi) non-manager rejected with 42501');
  RETURN NEXT is((SELECT location FROM public.tournaments WHERE id = v_tid),
             NULL, '(vi) location NOT changed by unauthorised caller');
END;
$$;

-- ---------------------------------------------------------------------
-- (vii) The unplayed recompute is SILENT: no participant notification,
--       audit event relabelled to 'phase_recomputed' (not a fake start).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _v2_scenario_vii() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator   uuid := gen_random_uuid();
  v_tid       uuid;
  v_setup     jsonb;
  v_inbox_new int;
  v_fake_start int;
  v_recomp    int;
  v_pre_inbox uuid[];
  v_pre_audit uuid[];
BEGIN
  v_tid := _v2_build(v_creator, 4);
  PERFORM _v2_as(v_creator);
  PERFORM public.tournament_start_pool_phase(
    v_tid, (SELECT pool_phase_config FROM public.tournaments WHERE id = v_tid));

  -- Snapshot ids AFTER the legitimate first start so we only count the noise
  -- the recompute would add (defaults stamp now() = txn start, so a timestamp
  -- marker is unreliable inside one transaction — we diff by id).
  SELECT coalesce(array_agg(id), '{}') INTO v_pre_inbox
    FROM public.user_inbox_messages
    WHERE (action_payload->>'tournament_id')::uuid = v_tid;
  SELECT coalesce(array_agg(id), '{}') INTO v_pre_audit
    FROM public.tournament_audit_events WHERE tournament_id = v_tid;

  v_setup := _v2_setup(v_tid)
    || jsonb_build_object('pool_phase_config',
         jsonb_build_object('group_count', 1, 'qualifiers_per_group', 2,
                            'strategy', 'snake'));

  PERFORM public.tournament_update(
    v_tid, _v2_cur_name(v_tid), 1, 2, 64, 'round_robin_then_ko',
    '{"sets_to_win":2,"max_sets":3}'::jsonb,
    ARRAY['total_points','wins'], v_setup);

  SELECT count(*)::int INTO v_inbox_new
    FROM public.user_inbox_messages
    WHERE kind IN ('tournament_started','tournament_round')
      AND (action_payload->>'tournament_id')::uuid = v_tid
      AND NOT (id = ANY (v_pre_inbox));

  SELECT count(*)::int INTO v_fake_start
    FROM public.tournament_audit_events
    WHERE tournament_id = v_tid
      AND kind = 'pool_phase_started'
      AND NOT (id = ANY (v_pre_audit));

  SELECT count(*)::int INTO v_recomp
    FROM public.tournament_audit_events
    WHERE tournament_id = v_tid
      AND kind = 'phase_recomputed'
      AND NOT (id = ANY (v_pre_audit));

  RETURN NEXT is(v_inbox_new, 0,
             '(vii) recompute sent NO participant notifications');
  RETURN NEXT is(v_fake_start, 0,
             '(vii) recompute emitted NO fake pool_phase_started audit event');
  RETURN NEXT ok(v_recomp >= 1,
             '(vii) recompute relabelled audit event to phase_recomputed');
END;
$$;

-- ---------------------------------------------------------------------
-- (viii) Live FORMAT switch crossing the phase family is rejected on a
--        generated phase (pool round_robin_then_ko -> pure single_elimination).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _v2_scenario_viii() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
  v_setup   jsonb;
  v_locked  boolean := false;
  v_hint    text;
BEGIN
  v_tid := _v2_build(v_creator, 4);
  PERFORM _v2_as(v_creator);
  PERFORM public.tournament_start_pool_phase(
    v_tid, (SELECT pool_phase_config FROM public.tournaments WHERE id = v_tid));

  v_setup := _v2_setup(v_tid);

  BEGIN
    PERFORM public.tournament_update(
      v_tid, _v2_cur_name(v_tid), 1, 2, 64, 'single_elimination',
      '{"sets_to_win":2,"max_sets":3}'::jsonb,
      ARRAY['total_points','wins'], v_setup);
  EXCEPTION WHEN OTHERS THEN
    v_locked := true;
    GET STACKED DIAGNOSTICS v_hint = PG_EXCEPTION_HINT;
  END;

  RETURN NEXT ok(v_locked, '(viii) cross-family format switch raised');
  RETURN NEXT is(v_hint, 'STRUCTURE_LOCKED',
             '(viii) HINT is STRUCTURE_LOCKED for cross-family switch');
  RETURN NEXT is((SELECT format FROM public.tournaments WHERE id = v_tid),
             'round_robin_then_ko', '(viii) format NOT changed (old value)');
END;
$$;

-- Run all scenarios (TAP lines surface from these top-level SELECTs).
SELECT _v2_scenario_i();
SELECT _v2_scenario_ii();
SELECT _v2_scenario_iii();
SELECT _v2_scenario_iv();
SELECT _v2_scenario_v();
SELECT _v2_scenario_vi();
SELECT _v2_scenario_vii();
SELECT _v2_scenario_viii();

SELECT finish();
ROLLBACK;
