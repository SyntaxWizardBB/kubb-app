-- tournament_reactivate + aborted-edit pgTAP tests.
--
-- Covers:
--   (i)   abort snapshots the prior status into pre_abort_status and
--         tournament_reactivate restores it, clearing completed_at + the
--         snapshot, and writes a 'reactivated' audit event
--   (ii)  reactivate on a non-aborted tournament is rejected (22023)
--   (iii) a non-manager caller is rejected by the setup gate (42501)
--   (iv)  an old aborted row WITHOUT pre_abort_status falls back to 'draft'
--   (v)   tournament_update on an aborted tournament leaves the aborted state
--         (status restored, completed_at cleared) and persists the edit
--
-- auth.uid() is switched via request.jwt.claims, mirroring the live-edit test.
-- Wrapped in BEGIN/ROLLBACK; nothing is mutated.

BEGIN;

SELECT plan(12);

CREATE OR REPLACE FUNCTION _ra_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
END;
$$;

-- Build a draft tournament with a creator + n confirmed participants. Returns
-- the id. Status starts 'draft'; callers move it where they need it.
CREATE OR REPLACE FUNCTION _ra_build(p_creator uuid, p_n int)
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
            'creator-' || p_creator::text || '@ra.local',
            '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format,
      pool_phase_config, ko_config, bracket_type, ko_matchup,
      tiebreaker_order, status)
    VALUES (
      v_tid, p_creator, 'RA-' || v_tid::text, 1, 2, 64,
      'round_robin_then_ko', 'ekc', '{"sets_to_win":2,"max_sets":3}'::jsonb,
      jsonb_build_object('group_count', 2, 'qualifiers_per_group', 2,
                         'strategy', 'snake'),
      jsonb_build_object('qualifier_count', 4),
      'single_elimination', 'seed_high_vs_low',
      ARRAY['total_points','wins'], 'draft');

  FOR i IN 1..p_n LOOP
    v_uid := gen_random_uuid();
    INSERT INTO auth.users (id, instance_id, aud, role, email,
                            encrypted_password, email_confirmed_at,
                            created_at, updated_at)
      VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated',
              'p' || i || '-' || v_tid::text || '@ra.local',
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

CREATE OR REPLACE FUNCTION _ra_setup(p_tid uuid) RETURNS jsonb
LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'scoring',            scoring,
    'pool_phase_config',  pool_phase_config,
    'ko_config',          ko_config,
    'bracket_type',       bracket_type,
    'ko_matchup',         ko_matchup,
    'ko_tiebreak_method', coalesce(ko_tiebreak_method, 'classic_kingtoss_removal'),
    'ko_round_formats',   coalesce(ko_round_formats, '[]'::jsonb))
  FROM public.tournaments WHERE id = p_tid;
$$;

-- ---------------------------------------------------------------------
-- (i) abort -> pre_abort_status snapshot -> reactivate restores it.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _ra_scenario_restore() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
BEGIN
  v_tid := _ra_build(v_creator, 4);
  PERFORM _ra_as(v_creator);
  -- Drive into registration_open via publish (IST open-registration model).
  PERFORM public.tournament_publish(v_tid);

  PERFORM public.tournament_abort(v_tid);
  RETURN NEXT is((SELECT status FROM public.tournaments WHERE id = v_tid),
             'aborted', '(i) abort flips status to aborted');
  RETURN NEXT is((SELECT pre_abort_status FROM public.tournaments WHERE id = v_tid),
             'registration_open', '(i) abort snapshots the prior status');

  PERFORM public.tournament_reactivate(v_tid);
  RETURN NEXT is((SELECT status FROM public.tournaments WHERE id = v_tid),
             'registration_open', '(i) reactivate restores the pre-abort status');
  RETURN NEXT ok((SELECT completed_at IS NULL FROM public.tournaments WHERE id = v_tid),
             '(i) reactivate clears completed_at');
  RETURN NEXT ok((SELECT pre_abort_status IS NULL FROM public.tournaments WHERE id = v_tid),
             '(i) reactivate clears the snapshot');
  RETURN NEXT ok(EXISTS (SELECT 1 FROM public.tournament_audit_events
                  WHERE tournament_id = v_tid AND kind = 'reactivated'),
             '(i) reactivate writes a reactivated audit event');
END;
$$;

-- ---------------------------------------------------------------------
-- (ii) reactivate on a non-aborted tournament -> 22023.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _ra_scenario_not_aborted() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
BEGIN
  v_tid := _ra_build(v_creator, 4);
  PERFORM _ra_as(v_creator);
  BEGIN
    PERFORM public.tournament_reactivate(v_tid);
    RETURN NEXT fail('(ii) reactivate of a draft should raise');
  EXCEPTION WHEN sqlstate '22023' THEN
    RETURN NEXT pass('(ii) reactivate of a non-aborted tournament raises 22023');
  END;
END;
$$;

-- ---------------------------------------------------------------------
-- (iii) reactivate by a non-manager -> 42501 (setup gate).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _ra_scenario_gate() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_other   uuid := gen_random_uuid();
  v_tid     uuid;
BEGIN
  v_tid := _ra_build(v_creator, 4);
  INSERT INTO auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
    VALUES (v_other, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'other-' || v_other::text || '@ra.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  PERFORM _ra_as(v_creator);
  PERFORM public.tournament_abort(v_tid);

  PERFORM _ra_as(v_other);
  BEGIN
    PERFORM public.tournament_reactivate(v_tid);
    RETURN NEXT fail('(iii) reactivate by a non-manager should raise');
  EXCEPTION WHEN sqlstate '42501' THEN
    RETURN NEXT pass('(iii) reactivate by a non-manager raises 42501');
  END;
END;
$$;

-- ---------------------------------------------------------------------
-- (iv) aborted row without pre_abort_status -> falls back to draft.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _ra_scenario_legacy_fallback() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
BEGIN
  v_tid := _ra_build(v_creator, 4);
  -- Simulate an old aborted row: aborted with a NULL snapshot.
  UPDATE public.tournaments
    SET status = 'aborted', completed_at = now(), pre_abort_status = NULL
    WHERE id = v_tid;

  PERFORM _ra_as(v_creator);
  PERFORM public.tournament_reactivate(v_tid);
  RETURN NEXT is((SELECT status FROM public.tournaments WHERE id = v_tid),
             'draft', '(iv) legacy aborted row reactivates to draft');
END;
$$;

-- ---------------------------------------------------------------------
-- (v) tournament_update on an aborted tournament leaves the aborted state.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _ra_scenario_edit_aborted() RETURNS SETOF text
LANGUAGE plpgsql AS $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid     uuid;
  v_setup   jsonb;
BEGIN
  v_tid := _ra_build(v_creator, 4);
  PERFORM _ra_as(v_creator);
  PERFORM public.tournament_publish(v_tid);
  PERFORM public.tournament_abort(v_tid);

  v_setup := _ra_setup(v_tid)
    || jsonb_build_object('location', 'Thun');

  PERFORM public.tournament_update(
    v_tid, 'Editiert nach Abbruch', 1, 2, 64, 'round_robin_then_ko',
    '{"sets_to_win":2,"max_sets":3}'::jsonb,
    ARRAY['total_points','wins'], v_setup);

  RETURN NEXT is((SELECT status FROM public.tournaments WHERE id = v_tid),
             'registration_open', '(v) editing an aborted tournament restores its status');
  RETURN NEXT ok((SELECT completed_at IS NULL FROM public.tournaments WHERE id = v_tid),
             '(v) editing an aborted tournament clears completed_at');
  RETURN NEXT is((SELECT display_name FROM public.tournaments WHERE id = v_tid),
             'Editiert nach Abbruch', '(v) the edit persisted');
END;
$$;

SELECT _ra_scenario_restore();
SELECT _ra_scenario_not_aborted();
SELECT _ra_scenario_gate();
SELECT _ra_scenario_legacy_fallback();
SELECT _ra_scenario_edit_aborted();

SELECT * FROM finish();
ROLLBACK;
