-- Start-Pfad-Konvergenz für schoch_then_ko — ADR-0039 §4 (Mangel #1).
--
-- Bis hierher startete schoch_then_ko (und swiss_then_ko) über den Hybrid-Zweig
-- von tournament_start, der via tournament_start_pool_phase einen flachen
-- Round-Robin-Pool über alle Teilnehmer materialisierte (group_count == 1):
-- N*(N-1)/2 Matches, phase 'group', stage_node_id NULL. Damit ging der
-- Schoch-Charakter (Seed-Slide-Runde 1, Folgerunden live gepaart) verloren und
-- der Stufen-Runner (20261300/20261301) griff nie, weil er stage_node_id NOT
-- NULL braucht.
--
-- Diese Migration konvergiert den Start auf den Stufen-Graph-Pfad:
--
--   * schoch_then_ko / swiss_then_ko: tournament_start leitet aus dem Format und
--     der pool_phase_config einen minimalen 2-Stufen-Graph ab — eine Schoch-Root-
--     Stufe (type 'schoch', config['rounds'] = R) und eine KO-Stufe (single_elim
--     bzw. consolation) mit einer top_k-Edge dazwischen — und startet dann über
--     tournament_start_stage_graph. Runde 1 entsteht so über den swiss/schoch-
--     Zweig von tournament_generate_stage_matches (Seed-Slide, ceil(N/2) Felder),
--     NICHT als RR-Pool. stage_node_id der Root-Stufe ist gesetzt, der Loop greift.
--
--   * round_robin_then_ko: UNVERÄNDERT — bleibt auf tournament_start_pool_phase.
--   * round_robin / swiss / schoch / single_elimination: UNVERÄNDERT.
--
-- Auto-Derive nur wenn noch keine Stufen existieren. Hat ein Turnier bereits
-- einen (Editor-/Template-)Stufen-Graph, startet es direkt darüber, ohne dass
-- der Ableiter etwas anlegt — so kollidiert der spätere Editor-/Materializer-Pfad
-- (eigene Units) nicht mit diesem Default.
--
-- Werte-Quellen (alle bereits am Turnier persistiert):
--   * R                = pool_phase_config->>'schoch_rounds' (Wizard-Draft, M4 #3)
--                        -> stage 'vorrunde'.config['rounds'] (positiv int, sonst R=1)
--   * qualifier_count  = ko_config->>'qualifier_count'      -> Edge selector k
--   * ko_matchup       = tournaments.ko_matchup             -> KO-stage.config['ko_matchup']
--   * KO-Typ           = aus dem Format (single_elim Default; consolation, wenn
--                        ko_config['with_third_place_playoff'] gesetzt wird heute
--                        NICHT als consolation gewertet — konservativ single_elim,
--                        siehe ADR-0039: KO-Typ-Verfeinerung ist spätere Unit).
--
-- Seeding der Root-Stufe: 'as_routed' (Default). Der Seed-Resolver lässt die
-- Kandidaten-Reihenfolge dann unverändert — das entspricht dem bisherigen flachen
-- Pool, der ebenfalls KEIN explizites Seeding hatte (Registrierungs-/id-Ordnung).
-- Konservative Wahl; ELO/Random-Seeding ist eine spätere Owner-Entscheidung.
--
-- CREATE OR REPLACE, GRANTs erhalten (authenticated/postgres/PUBLIC). Keine
-- fremde Migration editiert. Basis ist der zuletzt angewendete Body von
-- tournament_start (live: status-Gate registration_open/closed, can_setup,
-- Pitch-Assign + Notify im swiss/RR-Pfad).
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

      -- Conservative KO type: single_elim. Consolation/3rd-place routing is a
      -- later unit; the KO stage only activates once the Vorrunde completes.
      v_ko_type := 'single_elim';

      INSERT INTO public.tournament_stages(
          tournament_id, node_id, type, config, seeding, status)
        VALUES
          (p_tournament_id, 'vorrunde', 'schoch',
             jsonb_build_object('rounds', v_rounds),
             'as_routed', 'pending'),
          (p_tournament_id, 'ko', v_ko_type,
             jsonb_build_object('ko_matchup',
                                coalesce(v_ko_matchup, 'seed_high_vs_low')),
             'from_prev_ranking', 'pending');

      INSERT INTO public.tournament_stage_edges(
          tournament_id, from_node_id, to_node_id, selector, seeding_in)
        VALUES (
          p_tournament_id, 'vorrunde', 'ko',
          jsonb_build_object('kind', 'top_k', 'k', v_qualifiers),
          'reseed_by_source_rank');
    END IF;

    -- Boot the (derived or pre-existing) stage graph. Round 1 of the schoch
    -- root is generated by the swiss/schoch branch of
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
    participant_id uuid NOT NULL
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

    UPDATE _tstart_ring
      SET pos = CASE
                  WHEN pos = 1 THEN 1
                  WHEN pos = v_slot_count THEN 2
                  ELSE pos + 1
                END;
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
