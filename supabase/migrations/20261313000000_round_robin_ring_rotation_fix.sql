-- round_robin ring-rotation collision + NULL-bye fix — ADR-0039 (M4 follow-up).
--
-- Two defects in the round_robin branch of tournament_start (last body
-- 20261308000000):
--
--   1. RING-ROTATION COLLISION. The circle rotation was a single bulk UPDATE
--      `SET pos = CASE WHEN pos=1 THEN 1 WHEN pos=v_slot_count THEN 2
--      ELSE pos+1 END`. Postgres checks the PRIMARY KEY immediately (not
--      deferred), row by row, so the in-place +1 shift collides transiently
--      with an as-yet-unmoved neighbour for every slot_count >= 3
--      (_tstart_ring_pkey, 23505). Replaced by a two-phase shift that first
--      moves every target out of the occupied keyspace [1..slot_count] into
--      the disjoint [slot_count+1..2*slot_count], then pulls them back. Same
--      standard circle rotation (anchor pos=1 fixed, last -> pos=2, rest +1),
--      no transient collision.
--
--   2. NOT-NULL BYE. On the odd-N path the bye is inserted as a NULL
--      participant_id into _tstart_slots, but that column was declared NOT
--      NULL -> not_null_violation. _tstart_ring.participant_id was already
--      nullable and the bye handling in the match loop is correct; only the
--      _tstart_slots column needed widening. Dropped its NOT NULL.
--
-- Everything else is a verbatim CREATE OR REPLACE of the 20261308000000
-- tournament_start body: the schoch_then_ko / swiss_then_ko stage-graph path,
-- round_robin_then_ko pool delegation, swiss/schoch round-1 materialisation,
-- SECURITY DEFINER, SET search_path, GRANT EXECUTE — all unchanged.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.tournament_start(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller         uuid;
  v_status         text;
  v_format         text;
  v_pool_config    jsonb;
  v_ko_config      jsonb;
  v_ko_matchup     text;
  v_confirmed      int;
  v_slot_count     int;
  v_round_count    int;
  v_match_count    int := 0;
  v_round          int;
  v_i              int;
  v_a_idx          int;
  v_b_idx          int;
  v_a_pid          uuid;
  v_b_pid          uuid;
  v_name           text;
  v_created_by     uuid;   -- PER-TOURNAMENT
  -- Auto-derive (schoch_then_ko / swiss_then_ko -> stage graph):
  v_stage_count    int;
  v_rounds         int;
  v_qualifiers     int;
  v_ko_type        text;
  v_third_place    boolean;   -- ko_config.with_third_place_playoff (single_elim)
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, format, pool_phase_config, ko_config, ko_matchup,
         display_name, created_by
    INTO v_status, v_format, v_pool_config, v_ko_config, v_ko_matchup,
         v_name, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the organizer_team_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  -- NEW MODEL: registration is always open once published; starting
  -- implicitly closes it. Accept both open and closed states.
  IF v_status NOT IN ('registration_open','registration_closed') THEN
    RAISE EXCEPTION 'tournament must be in status registration_open or registration_closed'
      USING ERRCODE = '22023';
  END IF;
  IF v_format NOT IN (
       'round_robin','swiss','schoch',
       'round_robin_then_ko','schoch_then_ko','swiss_then_ko') THEN
    RAISE EXCEPTION 'format not yet supported' USING ERRCODE = '0A000';
  END IF;

  -- ---- schoch_then_ko / swiss_then_ko: converge on the stage-graph path ----
  -- ADR-0039 §4: round 1 is the schoch seed-slide (via the stage generator),
  -- not a flat RR pool. Auto-derive a 2-stage graph from the persisted config
  -- when no stages exist yet, then boot it through tournament_start_stage_graph
  -- (which runs the swiss/schoch round-1 generation with stage_node_id set, so
  -- the runtime loop U3-U5 takes over for the later rounds).
  IF v_format IN ('schoch_then_ko','swiss_then_ko') THEN
    IF v_pool_config IS NULL OR jsonb_typeof(v_pool_config) <> 'object' THEN
      RAISE EXCEPTION 'pool_phase_config required for hybrid format'
        USING ERRCODE = '22023';
    END IF;

    SELECT count(*) INTO v_stage_count
      FROM public.tournament_stages
      WHERE tournament_id = p_tournament_id;

    IF v_stage_count = 0 THEN
      -- R = schoch_rounds (positive int, else conservative 1). The runner reads
      -- this as the Schoch round target (20261300000000).
      v_rounds := nullif(v_pool_config ->> 'schoch_rounds', '')::int;
      IF v_rounds IS NULL OR v_rounds < 1 THEN
        v_rounds := 1;
      END IF;

      -- KO field size = ko_config.qualifier_count (else 2). Drives the top_k edge.
      v_qualifiers := nullif(v_ko_config ->> 'qualifier_count', '')::int;
      IF v_qualifiers IS NULL OR v_qualifiers < 1 THEN
        v_qualifiers := 2;
      END IF;

      -- KO type stays single_elim. double_elim / consolation AFTER schoch are
      -- underspecified (seeding into wb/lb, early_ko_losers routing over the
      -- stage graph) and remain an owner decision — ADR-0039 marks the KO-type
      -- refinement as a later unit. The auto-route only owns single_elim today.
      v_ko_type := 'single_elim';

      -- ko_config-aware: a single_elim KO honours with_third_place_playoff. The
      -- generator emits a third_place match from this stage config (the advance
      -- trigger already mirrors the semifinal losers into it). Defaults false,
      -- so a tournament without the flag keeps the byte-stable (no 3rd-place)
      -- bracket of 20261302 (T19 + schoch_then_ko_start_path stay green).
      v_third_place := coalesce(
        (v_ko_config ->> 'with_third_place_playoff')::boolean, false);

      INSERT INTO public.tournament_stages(
          tournament_id, node_id, type, config, seeding, status)
        VALUES
          (p_tournament_id, 'vorrunde', 'schoch',
             jsonb_build_object('rounds', v_rounds),
             'as_routed', 'pending'),
          (p_tournament_id, 'ko', v_ko_type,
             jsonb_build_object('ko_matchup',
                                coalesce(v_ko_matchup, 'seed_high_vs_low'),
                                'with_third_place', v_third_place),
             'from_prev_ranking', 'pending');

      INSERT INTO public.tournament_stage_edges(
          tournament_id, from_node_id, to_node_id, selector, seeding_in)
        VALUES (
          p_tournament_id, 'vorrunde', 'ko',
          jsonb_build_object('kind', 'top_k', 'k', v_qualifiers),
          'reseed_by_source_rank');
    END IF;

    -- Boot the (derived or pre-existing) stage graph. Round 1 of the schoch
    -- root is built by the swiss/schoch branch of
    -- tournament_generate_stage_matches: ceil(N/2) matches, stage_node_id set.
    PERFORM public.tournament_start_stage_graph(p_tournament_id);

    INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'started',
        v_caller,
        jsonb_build_object('format', v_format, 'phase', 'stage_graph'));
    RETURN;
  END IF;

  -- ---- round_robin_then_ko: delegate the pool phase (UNCHANGED) ------------
  IF v_format = 'round_robin_then_ko' THEN
    IF v_pool_config IS NULL OR jsonb_typeof(v_pool_config) <> 'object' THEN
      RAISE EXCEPTION 'pool_phase_config required for hybrid format'
        USING ERRCODE = '22023';
    END IF;

    PERFORM public.tournament_start_pool_phase(p_tournament_id, v_pool_config);

    INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'started',
        v_caller,
        jsonb_build_object('format', v_format, 'phase', 'pool'));
    RETURN;
  END IF;

  -- ---- Non-hybrid formats: confirmed-participant precondition -------
  SELECT count(*) INTO v_confirmed
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status = 'confirmed';

  IF v_confirmed < 2 THEN
    RAISE EXCEPTION 'at least 2 confirmed participants required'
      USING ERRCODE = '22023';
  END IF;

  CREATE TEMP TABLE _tstart_slots (
    slot_idx int PRIMARY KEY,
    participant_id uuid
  ) ON COMMIT DROP;

  INSERT INTO _tstart_slots(slot_idx, participant_id)
  SELECT row_number() OVER (ORDER BY p.registered_at, p.id), p.id
    FROM public.tournament_participants p
    WHERE p.tournament_id = p_tournament_id
      AND p.registration_status = 'confirmed';

  UPDATE public.tournament_participants p
    SET seed = s.slot_idx
    FROM _tstart_slots s
    WHERE p.id = s.participant_id;

  -- ---- swiss / schoch: materialise ROUND 1 only ---------------------
  IF v_format IN ('swiss','schoch') THEN
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        participant_a, participant_b, pitch_number, status)
    SELECT
      p_tournament_id,
      1::smallint,
      (((s.slot_idx - 1) / 2) + 1)::smallint,
      s.participant_id,
      part.participant_id,
      1,
      'scheduled'
    FROM _tstart_slots s
    LEFT JOIN _tstart_slots part
      ON part.slot_idx = s.slot_idx + 1
    WHERE (s.slot_idx % 2) = 1;

    GET DIAGNOSTICS v_match_count = ROW_COUNT;

    DROP TABLE _tstart_slots;

    PERFORM public._tournament_assign_pitches(p_tournament_id, 1::smallint);

    UPDATE public.tournaments
      SET status = 'live', started_at = now()
      WHERE id = p_tournament_id;

    -- ADR-0031 A1: materialise the active round 1 schedule (phase 'group').
    PERFORM public._tournament_upsert_round_schedule(
      p_tournament_id, NULL, 1, 'group',
      (public._tournament_schedule_prelim_seconds(p_tournament_id)).match_seconds,
      (public._tournament_schedule_prelim_seconds(p_tournament_id)).break_seconds,
      NULL, now());

    -- ADR-0031 C1 (E1): per-pitch publish-notify of round 1 (phase 'group').
    -- After pitches + schedule exist; starts_at resolved inside the helper.
    PERFORM public._tournament_notify_round_per_pitch(
      p_tournament_id, 1, 'group', 'round_published',
      'Runde 1 veröffentlicht',
      'Turnier "' || coalesce(v_name, '') || '": Runde 1 ist da.');

    INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'started',
        v_caller,
        jsonb_build_object(
          'format',      v_format,
          'round_count', 1,
          'match_count', v_match_count));

    PERFORM public._tournament_notify_participants(
      p_tournament_id,
      'tournament_started',
      'Turnier gestartet',
      'Turnier "' || coalesce(v_name, '') || '" ist gestartet — dein Platz ist da, leg los!',
      jsonb_build_object('tournament_id', p_tournament_id, 'format', v_format));
    RETURN;
  END IF;

  -- ---- round_robin: original circle-rotation materialisation --------
  IF (v_confirmed % 2) = 1 THEN
    v_slot_count := v_confirmed + 1;
    INSERT INTO _tstart_slots(slot_idx, participant_id) VALUES (v_slot_count, NULL);
  ELSE
    v_slot_count := v_confirmed;
  END IF;

  v_round_count := v_slot_count - 1;

  CREATE TEMP TABLE _tstart_ring (
    pos int PRIMARY KEY,
    participant_id uuid NULL
  ) ON COMMIT DROP;

  INSERT INTO _tstart_ring(pos, participant_id)
    SELECT slot_idx, participant_id FROM _tstart_slots;

  FOR v_round IN 1..v_round_count LOOP
    FOR v_i IN 0..((v_slot_count / 2) - 1) LOOP
      v_a_idx := v_i + 1;
      v_b_idx := v_slot_count - v_i;

      SELECT participant_id INTO v_a_pid FROM _tstart_ring WHERE pos = v_a_idx;
      SELECT participant_id INTO v_b_pid FROM _tstart_ring WHERE pos = v_b_idx;

      IF v_a_pid IS NULL AND v_b_pid IS NULL THEN
        CONTINUE;
      END IF;
      IF v_a_pid IS NULL THEN
        v_a_pid := v_b_pid;
        v_b_pid := NULL;
      END IF;

      INSERT INTO public.tournament_matches(
          tournament_id, round_number, match_number_in_round,
          participant_a, participant_b, pitch_number, status)
        VALUES (
          p_tournament_id, v_round::smallint, (v_i + 1)::smallint,
          v_a_pid, v_b_pid, 1, 'scheduled');

      v_match_count := v_match_count + 1;
    END LOOP;

    PERFORM public._tournament_assign_pitches(p_tournament_id, v_round::smallint);

    -- ADR-0031 A1 (OE-2): only the active round 1 gets a schedule row.
    IF v_round = 1 THEN
      PERFORM public._tournament_upsert_round_schedule(
        p_tournament_id, NULL, 1, 'group',
        (public._tournament_schedule_prelim_seconds(p_tournament_id)).match_seconds,
        (public._tournament_schedule_prelim_seconds(p_tournament_id)).break_seconds,
        NULL, now());

      -- ADR-0031 C1 (E1): per-pitch publish-notify of the active round 1
      -- (phase 'group'). After pitches + schedule exist for round 1.
      PERFORM public._tournament_notify_round_per_pitch(
        p_tournament_id, 1, 'group', 'round_published',
        'Runde 1 veröffentlicht',
        'Turnier "' || coalesce(v_name, '') || '": Runde 1 ist da.');
    END IF;

    -- Standard circle rotation in two phases to avoid the transient
    -- _tstart_ring_pkey collision (Postgres checks the PK per row, not at
    -- statement end). Phase 1 lifts every target out of [1..slot_count] into
    -- the disjoint [slot_count+1..2*slot_count]; phase 2 pulls them back.
    UPDATE _tstart_ring
      SET pos = CASE
                  WHEN pos = 1 THEN 1
                  WHEN pos = v_slot_count THEN 2
                  ELSE pos + 1
                END + v_slot_count;
    UPDATE _tstart_ring
      SET pos = pos - v_slot_count;
  END LOOP;

  DROP TABLE _tstart_ring;
  DROP TABLE _tstart_slots;

  UPDATE public.tournaments
    SET status = 'live', started_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'started',
      v_caller,
      jsonb_build_object(
        'format',      v_format,
        'round_count', v_round_count,
        'match_count', v_match_count));

  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_started',
    'Turnier gestartet',
    'Turnier "' || coalesce(v_name, '') || '" ist gestartet — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'format', v_format));
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_start(uuid) IS
  'Start-RPC (re-based 20261308000000). round_robin branch: the circle '
  'rotation now runs as a two-phase UPDATE (lift into a disjoint keyspace, '
  'then pull back) so the in-place +1 shift no longer collides with '
  '_tstart_ring_pkey for slot_count >= 3; the _tstart_slots.participant_id '
  'column is nullable so the odd-N bye no longer violates NOT NULL. All other '
  'branches (schoch_then_ko / swiss_then_ko stage graph, round_robin_then_ko '
  'pool, swiss/schoch round 1) are byte-identical.';
