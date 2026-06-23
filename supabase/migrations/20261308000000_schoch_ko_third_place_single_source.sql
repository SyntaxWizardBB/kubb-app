-- Schoch->KO single materialisation source, ko_config-aware — ADR-0039 §4 (M4 #1 follow-up).
--
-- Diagnose (3-Lens): das KO nach einer Schoch-Vorrunde wurde DOPPELT
-- materialisiert. Der M4-Stage-Graph-Runner (20261300) routet top_k in die
-- KO-Stufe und ruft tournament_generate_stage_matches auf, das das Bracket baut
-- (Auto-Route, der EIGENTLICHE Materializer auf dem Schoch-Pfad). Der Test-
-- Harness rief danach zusätzlich das Legacy tournament_start_ko_phase auf, das
-- mit ALREADY_STARTED (40001) gegen das schon vorhandene KO knallte.
--
-- Zugleich war die Auto-Route NICHT ko_config-aware: tournament_start legte die
-- KO-Stufe hart als single_elim an (20261302:143) und der single_elim-Zweig von
-- tournament_generate_stage_matches kodierte p_third_place hart false
-- (20261306:466). Folge: with_third_place_playoff wurde ignoriert (kein 3.-Platz-
-- Match), obwohl der advance-Trigger (20261306:968-1014) die Loser-Spiegelung
-- ins third_place-Match längst beherrscht.
--
-- Diese Migration macht die Stage-Graph-Auto-Route zur EINZIGEN, ko_config-
-- respektierenden Materialisierungs-Quelle für den eindeutig spezifizierten Fall
-- (single_elimination + with_third_place_playoff):
--
--   1. tournament_start leitet für eine schoch_then_ko / swiss_then_ko-
--      Vorrunde die KO-Stufen-config aus ko_config ab: with_third_place wird aus
--      ko_config.with_third_place_playoff übernommen und als Stage-config-Key
--      'with_third_place' geschrieben. Der Stufen-TYP bleibt single_elim — das
--      hält den T19-/Start-Pfad byte-stabil (with_third_place_playoff=false ->
--      with_third_place=false -> kein 3.-Platz, schoch_then_ko_start_path_test:144
--      'single_elim' unverändert).
--
--   2. tournament_generate_stage_matches liest im single_elim/consolation-Zweig
--      with_third_place aus v_config statt hart false. Damit erzeugt die Auto-
--      Route ein 3.-Platz-Match, wenn die Stufe es trägt. Jeder andere Zweig
--      (double_elim, round_robin/pool/group_phase, swiss/schoch, type_graph)
--      bleibt byte-identisch zum 20261306-Body.
--
-- PRODUKT-OFFEN (NICHT in dieser Migration umgesetzt — Owner-Spec nötig):
-- double_elimination- und consolation-NACH-Schoch sind unterspezifiziert (Seed-
-- Reihenfolge ins wb/lb, bracket_reset-Default, Routing der early_ko_losers in
-- den Trostbracket über den Stage-Graph). tournament_start lässt den KO-Stufen-
-- typ für diese Fälle KONSERVATIV bei single_elim (wie bisher 20261302) und
-- schreibt KEINE double_elim/consolation-config — bis der Owner die Seeding-
-- Semantik festlegt. ADR-0039 markiert die KO-Typ-Verfeinerung explizit als
-- spätere Unit.
--
-- Additiv: CREATE OR REPLACE auf die zuletzt angewendeten Bodies (20261302
-- tournament_start, 20261306 tournament_generate_stage_matches). GRANTs neu
-- gesetzt. Keine fremde Migration editiert, keine destruktiven Drops.
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

COMMENT ON FUNCTION public.tournament_start(uuid) IS
  'Start-RPC (re-based 20261302000000). ADR-0039 §4: schoch_then_ko / '
  'swiss_then_ko converge on the stage graph; the derived KO stage now carries '
  'with_third_place from ko_config.with_third_place_playoff (single_elim only) so '
  'the auto-route is the single ko_config-aware KO source for that case. KO type '
  'stays single_elim — double_elim / consolation after schoch remain an owner '
  'decision (seeding underspecified). round_robin_then_ko and the non-hybrid '
  'formats are unchanged.';

-- ===================================================================
-- ko_config-aware single_elim/consolation generation. Re-based verbatim from
-- 20261306000000 with ONE changed read: the single_elim/consolation branch now
-- passes with_third_place from v_config (the stage config tournament_start
-- derived) into _tournament_compute_ko_bracket, instead of the hard-coded false.
-- Every other branch (type_graph, double_elim, round_robin/pool/group_phase,
-- swiss/schoch) and the whole schedule/notify tail are byte-identical.
-- ===================================================================
CREATE OR REPLACE FUNCTION public.tournament_generate_stage_matches(
  p_tournament_id uuid,
  p_node_id       text,
  p_seeded        uuid[]
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_type        text;
  v_config      jsonb;
  v_with_reset  boolean;
  v_third_place boolean;   -- single_elim/consolation: stage with_third_place
  v_n           int;
  v_valid_count int;
  v_existing    int;
  v_seeds_jsonb jsonb;
  v_count       int := 0;
  v_pair_no     int;
  v_half        int;
  v_a           uuid;
  v_b           uuid;
  i             int;
  j             int;
  v_group_count int;       -- P5.3a: stage pool group_count from config
  v_pools       jsonb;     -- P5.3a: _tournament_compute_pools assignments
  v_ms          int;       -- P5.3c: round-1 match seconds
  v_bs          int;       -- P5.3c: round-1 break seconds
  v_ta          int;       -- P5.3c: round-1 tiebreak-after seconds
  v_has_graph   boolean;   -- U10a: stage carries a valid type_graph
  v_graph_cat   text;      -- U10a: type_graph category (ko|vorrunde)
BEGIN
  -- 1. Stage must exist in this tournament.
  SELECT type, config INTO v_type, v_config
    FROM public.tournament_stages
    WHERE tournament_id = p_tournament_id
      AND node_id = p_node_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'STAGE_NOT_FOUND: no stage % in tournament %', p_node_id, p_tournament_id
      USING ERRCODE = '22023';
  END IF;

  -- 2. Seeded subset must be non-empty.
  v_n := coalesce(array_length(p_seeded, 1), 0);
  IF p_seeded IS NULL OR v_n < 1 THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: p_seeded must contain at least one participant'
      USING ERRCODE = '22023';
  END IF;

  -- 3. Every seeded id must be a participant of THIS tournament.
  SELECT count(*) INTO v_valid_count
    FROM unnest(p_seeded) AS s(id)
    JOIN public.tournament_participants tp
      ON tp.id = s.id
     AND tp.tournament_id = p_tournament_id;
  IF v_valid_count <> v_n THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: p_seeded contains ids that are not participants of tournament %', p_tournament_id
      USING ERRCODE = '22023';
  END IF;

  -- 4. Idempotency guard: never generate twice for the same stage.
  SELECT count(*) INTO v_existing
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND stage_node_id = p_node_id;
  IF v_existing > 0 THEN
    RAISE EXCEPTION 'STAGE_ALREADY_GENERATED: stage % already has matches', p_node_id
      USING ERRCODE = '22023';
  END IF;

  v_has_graph := (v_config -> 'type_graph') IS NOT NULL
                 AND public._stage_type_graph_is_valid(v_config -> 'type_graph');
  IF v_has_graph THEN
    v_graph_cat := v_config #>> '{type_graph,category}';
  END IF;

  -- ko_config-aware third place (single_elim / consolation type-fixed stages).
  -- Set by tournament_start from ko_config.with_third_place_playoff; default
  -- false keeps the no-3rd-place bracket for stages that do not carry the key.
  v_third_place := coalesce((v_config ->> 'with_third_place')::boolean, false);

  -- 5. Type dispatch.
  IF v_has_graph THEN
    v_count := public._tournament_materialize_type_graph_round1(
      p_tournament_id, p_node_id, p_seeded);

  ELSIF v_type IN ('single_elim', 'consolation') THEN
    IF v_n < 2 THEN
      RAISE EXCEPTION 'INVALID_PARTICIPANT: % stage % needs at least 2 participants, got %', v_type, p_node_id, v_n
        USING ERRCODE = '22023';
    END IF;
    v_seeds_jsonb := to_jsonb(p_seeded);

    -- The third_place row shares the final's (round_number, bracket_position=1)
    -- slot; for a STAGE KO that collides with tournament_matches_stage_slot_uq
    -- (the type_graph round-2+ ON-CONFLICT index, scoped to bracket_position NOT
    -- NULL). Carry the stage third_place with bracket_position NULL so it is
    -- excluded from that index; the advance trigger locates it by phase only.
    -- match_number_in_round keeps the slot for display order.
    INSERT INTO public.tournament_matches(
        tournament_id, stage_node_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           p_node_id,
           b.round_number::smallint,
           b.bracket_position::smallint,
           CASE WHEN b.phase = 'third_place' THEN NULL
                ELSE b.bracket_position END,
           b.participant_a,
           b.participant_b,
           b.phase,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END
      FROM public._tournament_compute_ko_bracket(
             v_seeds_jsonb, v_third_place,
             coalesce(v_config ->> 'ko_matchup', 'seed_high_vs_low')) b;

    GET DIAGNOSTICS v_count = ROW_COUNT;

  ELSIF v_type = 'double_elim' THEN
    IF v_n < 2 THEN
      RAISE EXCEPTION 'INVALID_PARTICIPANT: double_elim stage % needs at least 2 participants, got %', p_node_id, v_n
        USING ERRCODE = '22023';
    END IF;
    v_with_reset := coalesce((v_config ->> 'with_reset')::boolean, false);
    v_seeds_jsonb := to_jsonb(p_seeded);

    INSERT INTO public.tournament_matches(
        tournament_id, stage_node_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           p_node_id,
           b.round_number::smallint,
           b.bracket_position::smallint,
           b.bracket_position,
           b.participant_a,
           b.participant_b,
           b.phase,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END
      FROM public._tournament_compute_de_bracket(v_seeds_jsonb, v_with_reset) b;

    GET DIAGNOSTICS v_count = ROW_COUNT;

  ELSIF v_type IN ('round_robin', 'pool', 'group_phase') THEN
    v_group_count := coalesce((v_config ->> 'groupCount')::int, 1);
    IF v_group_count > 1 THEN
      v_pools := public._tournament_compute_pools(
        to_jsonb(p_seeded),
        jsonb_build_object(
          'group_count', v_group_count,
          'qualifiers_per_group',
            greatest(1, coalesce((v_config ->> 'qualifierCount')::int, 1)),
          'strategy', lower(coalesce(v_config ->> 'grouping_strategy', 'snake')),
          'random_seed', coalesce((v_config ->> 'random_seed')::bigint, 0)
        ));
      WITH assign AS (
        SELECT (elem ->> 'participant_id')::uuid AS pid,
               elem ->> 'group_label'            AS lbl,
               (elem ->> 'group_position')::int  AS pos
          FROM jsonb_array_elements(v_pools) AS elem
      ),
      pairs AS (
        SELECT a.lbl,
               a.pid AS pid_a,
               b.pid AS pid_b,
               row_number() OVER (
                 PARTITION BY a.lbl ORDER BY a.pos, b.pos) AS pair_no
          FROM assign a
          JOIN assign b ON a.lbl = b.lbl AND a.pos < b.pos
      )
      INSERT INTO public.tournament_matches(
          tournament_id, stage_node_id, round_number, match_number_in_round,
          participant_a, participant_b, phase, status, pitch_number, group_label)
      SELECT p_tournament_id, p_node_id, 1::smallint, pair_no::smallint,
             pid_a, pid_b, 'group', 'scheduled', 1, lbl
        FROM pairs;
      GET DIAGNOSTICS v_count = ROW_COUNT;
    ELSE
      v_pair_no := 0;
      FOR i IN 1 .. v_n LOOP
        FOR j IN (i + 1) .. v_n LOOP
          v_pair_no := v_pair_no + 1;
          INSERT INTO public.tournament_matches(
              tournament_id, stage_node_id, round_number, match_number_in_round,
              participant_a, participant_b, phase, status, pitch_number)
          VALUES (
              p_tournament_id, p_node_id, 1::smallint, v_pair_no::smallint,
              p_seeded[i], p_seeded[j], 'group', 'scheduled', 1);
        END LOOP;
      END LOOP;
      v_count := v_pair_no;
    END IF;

  ELSIF v_type IN ('swiss', 'schoch') THEN
    IF v_n < 2 THEN
      RAISE EXCEPTION 'INVALID_PARTICIPANT: swiss stage % needs at least 2 participants, got %', p_node_id, v_n
        USING ERRCODE = '22023';
    END IF;
    v_half := v_n / 2;  -- floor
    v_pair_no := 0;
    FOR i IN 1 .. v_half LOOP
      v_pair_no := v_pair_no + 1;
      v_a := p_seeded[i];
      v_b := p_seeded[i + v_half];
      INSERT INTO public.tournament_matches(
          tournament_id, stage_node_id, round_number, match_number_in_round,
          participant_a, participant_b, phase, status, pitch_number)
      VALUES (
          p_tournament_id, p_node_id, 1::smallint, v_pair_no::smallint,
          v_a, v_b, 'group', 'scheduled', 1);
    END LOOP;
    IF (v_n % 2) = 1 THEN
      v_pair_no := v_pair_no + 1;
      v_a := p_seeded[v_n];
      INSERT INTO public.tournament_matches(
          tournament_id, stage_node_id, round_number, match_number_in_round,
          participant_a, participant_b, phase, status, winner_participant,
          pitch_number, finalized_at)
      VALUES (
          p_tournament_id, p_node_id, 1::smallint, v_pair_no::smallint,
          v_a, NULL, 'group', 'finalized', v_a, 1, now());
    END IF;
    v_count := v_pair_no;

  ELSE
    RAISE EXCEPTION 'stage type % not yet supported by the stage generator', v_type
      USING ERRCODE = '22023';
  END IF;

  -- ADR-0031 A1 + P5.3c + U10c (T17): materialise this stage's round 1 schedule.
  -- A type_graph stage (KO or vorrunde) times round 1 from its TypeRound-1
  -- matchFormat (the per-round source — closes the U10a MEDIUM). A type-fixed KO
  -- node keeps ko_round_formats[0] timing; other type-fixed stages keep prelim.
  IF v_has_graph THEN
    SELECT s.match_seconds, s.break_seconds, s.tiebreak_after
      INTO v_ms, v_bs, v_ta
      FROM public._tournament_schedule_type_graph_round_seconds(
             p_tournament_id, p_node_id, 1, false) s;
  ELSIF v_type IN ('single_elim', 'double_elim', 'consolation') THEN
    SELECT s.match_seconds, s.break_seconds, s.tiebreak_after
      INTO v_ms, v_bs, v_ta
      FROM public._tournament_schedule_stage_ko_seconds(
             p_tournament_id, p_node_id, 1, false) s;
  ELSE
    SELECT p.match_seconds, p.break_seconds, NULL::int
      INTO v_ms, v_bs, v_ta
      FROM public._tournament_schedule_prelim_seconds(p_tournament_id) p;
  END IF;
  PERFORM public._tournament_upsert_round_schedule(
    p_tournament_id, p_node_id, 1, 'group', v_ms, v_bs, v_ta, now());

  PERFORM public._tournament_notify_round_per_pitch(
    p_tournament_id, 1, 'group', 'round_published',
    'Runde 1 veröffentlicht',
    'Turnier-Stufe: Runde 1 ist da.');

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_generate_stage_matches(uuid, text, uuid[])
  TO authenticated;

COMMENT ON FUNCTION public.tournament_generate_stage_matches(uuid, text, uuid[]) IS
  'ADR-0030 runner Step 3 (re-based 20261306000000). ADR-0039 §4: the '
  'single_elim/consolation branch now honours the stage with_third_place config '
  '(derived by tournament_start from ko_config.with_third_place_playoff), so the '
  'schoch->KO auto-route emits a third_place match when configured. Every other '
  'branch (type_graph, double_elim, round_robin/pool/group_phase, swiss/schoch) '
  'and the schedule/notify tail are byte-identical to 20261306000000.';

-- ===================================================================
-- Re-based verbatim from 20261306000000 with ONE surgical change: the
-- single_elim third_place mirror locates the third_place match by phase alone
-- (dropping the `bracket_position = 1` filter), so it matches both the classic
-- third_place (bracket_position 1, stage_node_id NULL) and the new STAGE
-- third_place (bracket_position NULL, excluded from tournament_matches_stage_slot_uq
-- to avoid colliding with the stage final at the same slot). There is exactly one
-- third_place row per final round, so the phase predicate is unambiguous. Every
-- other path — type_graph routing, single_elim advance, double_elim, consolation,
-- the consolation_third_place mirror — is byte-identical to 20261306000000.
-- ===================================================================
CREATE OR REPLACE FUNCTION public.tournament_advance_ko_winner()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, auth
AS $function$
DECLARE
  v_loser_part      uuid;
  v_next_round      int;
  v_next_position   int;
  v_is_odd          boolean;
  v_third_enabled   boolean;
  v_final_round     int;
  v_next_a          uuid;
  v_next_b          uuid;
  v_next_status     text;
  v_tp_a            uuid;
  v_tp_b            uuid;
  v_tp_status       text;
  v_wb_count        int;
  v_size            int;
  v_lb_count        int;
  v_lb_target_round int;
  v_lb_slot0        int;
  v_lb_target_pos   int;
  v_lb_side_b       boolean;
  v_with_reset      boolean;
  v_gf_round        int;
  v_cons_exists     int;
  v_main_rounds     int;
  v_main_size       int;
  v_cons_target     int;
  v_cons_matches    int;
  v_cons_slot0      int;
  v_cons_pos        int;
  v_cons_side_b     boolean;
  v_cons_rounds     int;
  v_cons_p1         int;
  v_e1              int;
  v_next_matches    int;
  v_next_lr         int;
  v_graph           jsonb;
  v_src_field       text;
  v_tg_to_field     text;
  v_tg_round        int;
  v_tg_slot         int;
  v_tg_rank         int;
  v_tg_side_b       boolean;
  v_tg_last_round   int;
  v_tg_final_fields int;
  v_tg_phase        text;
  v_tg_exists       boolean;
BEGIN
  IF NEW.winner_participant IS NULL THEN
    RETURN NEW;
  END IF;

  v_loser_part := CASE
    WHEN NEW.winner_participant = NEW.participant_a THEN NEW.participant_b
    WHEN NEW.winner_participant = NEW.participant_b THEN NEW.participant_a
    ELSE NULL
  END;

  v_next_round    := NEW.round_number + 1;
  v_next_position := (NEW.bracket_position + 1) / 2;
  v_is_odd        := (NEW.bracket_position % 2) = 1;

  -- =====================================================================
  -- U10b (ADR-0039 §6.6): TYPE-GRAPH ROUTING (pre-dispatch guard).
  -- =====================================================================
  IF NEW.stage_node_id IS NOT NULL THEN
    SELECT s.config -> 'type_graph'
      INTO v_graph
      FROM public.tournament_stages s
      WHERE s.tournament_id = NEW.tournament_id
        AND s.node_id = NEW.stage_node_id;
  END IF;

  IF v_graph IS NOT NULL AND public._stage_type_graph_is_valid(v_graph) THEN
    SELECT f ->> 'id'
      INTO v_src_field
      FROM jsonb_array_elements(v_graph -> 'rounds') AS r
      CROSS JOIN jsonb_array_elements(r -> 'fields') AS f
      WHERE (f ->> 'round_number')::int = NEW.round_number
        AND (f ->> 'slot')::int = NEW.bracket_position
      LIMIT 1;

    IF v_src_field IS NOT NULL THEN
      SELECT max((r ->> 'round_number')::int)
        INTO v_tg_last_round
        FROM jsonb_array_elements(v_graph -> 'rounds') AS r;
      SELECT jsonb_array_length(r -> 'fields')
        INTO v_tg_final_fields
        FROM jsonb_array_elements(v_graph -> 'rounds') AS r
        WHERE (r ->> 'round_number')::int = v_tg_last_round
        LIMIT 1;

      -- T15 winner: follow the source field's WinnerEdge.
      SELECT e ->> 'to_field_id'
        INTO v_tg_to_field
        FROM jsonb_array_elements(v_graph -> 'edges') AS e
        WHERE e ->> 'kind' = 'winner'
          AND e ->> 'from_field_id' = v_src_field
        LIMIT 1;

      IF v_tg_to_field IS NOT NULL THEN
        PERFORM public._tournament_type_graph_route_into(
          NEW.tournament_id, NEW.stage_node_id, v_graph, v_src_field,
          v_tg_to_field, NEW.winner_participant,
          v_tg_last_round, v_tg_final_fields);
      END IF;

      -- T16 loser: follow the source field's LoserEdge (if any).
      IF v_loser_part IS NOT NULL THEN
        SELECT e ->> 'to_field_id'
          INTO v_tg_to_field
          FROM jsonb_array_elements(v_graph -> 'edges') AS e
          WHERE e ->> 'kind' = 'loser'
            AND e ->> 'from_field_id' = v_src_field
          LIMIT 1;

        IF v_tg_to_field IS NOT NULL THEN
          PERFORM public._tournament_type_graph_route_into(
            NEW.tournament_id, NEW.stage_node_id, v_graph, v_src_field,
            v_tg_to_field, v_loser_part,
            v_tg_last_round, v_tg_final_fields);
        END IF;
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  -- =====================================================================
  -- SINGLE-ELIMINATION PATH (verbatim).
  -- =====================================================================
  IF NEW.phase IN ('ko','final') THEN
    SELECT participant_a, participant_b, status
      INTO v_next_a, v_next_b, v_next_status
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND round_number  = v_next_round
        AND bracket_position = v_next_position
        AND phase IN ('ko','final')
      FOR UPDATE;

    IF FOUND THEN
      IF v_is_odd THEN
        v_next_a := NEW.winner_participant;
      ELSE
        v_next_b := NEW.winner_participant;
      END IF;

      IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
         AND v_next_status = 'scheduled' THEN
        v_next_status := 'awaiting_results';
      END IF;

      UPDATE public.tournament_matches
        SET participant_a = v_next_a,
            participant_b = v_next_b,
            status        = v_next_status
        WHERE tournament_id = NEW.tournament_id
          AND round_number  = v_next_round
          AND bracket_position = v_next_position
          AND phase IN ('ko','final');
    END IF;
  END IF;

  IF NEW.phase = 'ko' AND v_loser_part IS NOT NULL THEN
    SELECT (t.ko_config ->> 'with_third_place_playoff')::boolean
      INTO v_third_enabled
      FROM public.tournaments t
      WHERE t.id = NEW.tournament_id;

    IF COALESCE(v_third_enabled, false) THEN
      SELECT MAX(round_number)
        INTO v_final_round
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'final';

      IF v_final_round IS NOT NULL AND v_next_round = v_final_round THEN
        SELECT participant_a, participant_b, status
          INTO v_tp_a, v_tp_b, v_tp_status
          FROM public.tournament_matches
          WHERE tournament_id    = NEW.tournament_id
            AND round_number     = v_final_round
            AND phase            = 'third_place'
          FOR UPDATE;

        IF FOUND THEN
          IF v_is_odd THEN
            v_tp_a := v_loser_part;
          ELSE
            v_tp_b := v_loser_part;
          END IF;

          IF v_tp_a IS NOT NULL AND v_tp_b IS NOT NULL
             AND v_tp_status = 'scheduled' THEN
            v_tp_status := 'awaiting_results';
          END IF;

          UPDATE public.tournament_matches
            SET participant_a = v_tp_a,
                participant_b = v_tp_b,
                status        = v_tp_status
            WHERE tournament_id    = NEW.tournament_id
              AND round_number     = v_final_round
              AND phase            = 'third_place';
        END IF;
      END IF;
    END IF;
  END IF;

  -- =====================================================================
  -- DOUBLE-ELIMINATION PATH (verbatim).
  -- =====================================================================
  IF NEW.phase IN ('wb','lb','grand_final','grand_final_reset') THEN
    SELECT MAX(round_number) INTO v_wb_count
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND phase = 'wb';
    v_size := (1 << v_wb_count);
    v_lb_count := 2 * (v_wb_count - 1);
  END IF;

  IF NEW.phase = 'wb' THEN
    IF NEW.round_number < v_wb_count THEN
      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND round_number  = v_next_round
          AND bracket_position = v_next_position
          AND phase = 'wb'
        FOR UPDATE;
      IF FOUND THEN
        IF v_is_odd THEN v_next_a := NEW.winner_participant;
        ELSE             v_next_b := NEW.winner_participant; END IF;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_next_a,
              participant_b = v_next_b,
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND round_number  = v_next_round
            AND bracket_position = v_next_position
            AND phase = 'wb';
      END IF;
    ELSE
      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'grand_final'
          AND round_number = 1
          AND bracket_position = 1
        FOR UPDATE;
      IF FOUND THEN
        v_next_a := NEW.winner_participant;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_next_a, status = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'grand_final'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;

    IF v_loser_part IS NOT NULL AND v_lb_count > 0 THEN
      IF NEW.round_number = 1 THEN
        v_lb_target_round := 1;
        v_lb_target_pos   := ((v_size >> 2) - 1) - ((NEW.bracket_position - 1) / 2) + 1;
        v_lb_side_b       := ((NEW.bracket_position - 1) % 2) = 1;
      ELSE
        v_lb_target_round := 2 * NEW.round_number - 2;
        v_lb_slot0        := public._tournament_de_lb_target(
                               NEW.round_number, NEW.bracket_position, v_size);
        v_lb_target_pos   := (v_lb_slot0 / 2) + 1;
        v_lb_side_b       := (v_lb_slot0 % 2) = 1;
      END IF;

      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'lb'
          AND round_number = v_lb_target_round
          AND bracket_position = v_lb_target_pos
        FOR UPDATE;
      IF FOUND THEN
        IF v_lb_side_b THEN v_next_b := v_loser_part;
        ELSE                v_next_a := v_loser_part; END IF;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_next_a,
              participant_b = v_next_b,
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'lb'
            AND round_number = v_lb_target_round
            AND bracket_position = v_lb_target_pos;
      END IF;
    END IF;
  END IF;

  IF NEW.phase = 'lb' THEN
    IF NEW.round_number < v_lb_count THEN
      IF (NEW.round_number % 2) = 1 THEN
        v_lb_target_round := NEW.round_number + 1;
        v_lb_target_pos   := NEW.bracket_position;
        v_lb_side_b       := false;
      ELSE
        v_lb_target_round := NEW.round_number + 1;
        v_lb_target_pos   := (NEW.bracket_position + 1) / 2;
        v_lb_side_b       := (NEW.bracket_position % 2) = 0;
      END IF;

      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'lb'
          AND round_number = v_lb_target_round
          AND bracket_position = v_lb_target_pos
        FOR UPDATE;
      IF FOUND THEN
        IF v_lb_side_b THEN v_next_b := NEW.winner_participant;
        ELSE                v_next_a := NEW.winner_participant; END IF;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_next_a,
              participant_b = v_next_b,
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'lb'
            AND round_number = v_lb_target_round
            AND bracket_position = v_lb_target_pos;
      END IF;
    ELSE
      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'grand_final'
          AND round_number = 1
          AND bracket_position = 1
        FOR UPDATE;
      IF FOUND THEN
        v_next_b := NEW.winner_participant;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_b = v_next_b, status = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'grand_final'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;
  END IF;

  IF NEW.phase = 'grand_final' THEN
    SELECT coalesce((t.ko_config ->> 'with_bracket_reset')::boolean, true)
      INTO v_with_reset
      FROM public.tournaments t
      WHERE t.id = NEW.tournament_id;

    IF NEW.winner_participant = NEW.participant_b AND COALESCE(v_with_reset, true) THEN
      SELECT status INTO v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'grand_final_reset'
          AND round_number = 1
          AND bracket_position = 1
        FOR UPDATE;
      IF FOUND THEN
        v_next_status := CASE WHEN v_next_status = 'scheduled'
                              THEN 'awaiting_results' ELSE v_next_status END;
        UPDATE public.tournament_matches
          SET participant_a = NEW.participant_a,
              participant_b = NEW.participant_b,
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'grand_final_reset'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;
  END IF;

  -- =====================================================================
  -- CONSOLATION ROUTING (E2, ADR-0028 §7.4).
  -- =====================================================================

  -- (A) MAIN-LOSER FEED.
  IF NEW.phase IN ('ko','final') AND v_loser_part IS NOT NULL THEN
    SELECT count(*) INTO v_cons_exists
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND phase = 'consolation';

    IF v_cons_exists > 0 THEN
      SELECT MAX(round_number) INTO v_main_rounds
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase IN ('ko','final');
      v_main_size := (1 << v_main_rounds);

      v_cons_target := public._tournament_cons_drop_target(
                         NEW.round_number, v_main_size);

      IF v_cons_target >= 1 THEN
        IF v_cons_target = 1 THEN
          SELECT count(*) * 2 INTO v_cons_p1
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = 1;
          SELECT entrants INTO v_e1
            FROM public._tournament_cons_shape(
                   v_main_size,
                   greatest(0,
                     coalesce((SELECT (consolation_bracket ->> 'direct_count')::int
                                 FROM public.tournaments
                                WHERE id = NEW.tournament_id), 0)))
           WHERE round = 1;
          v_cons_slot0 := public._tournament_cons_seed_slot(
                            (v_e1 - (v_main_size / 2)) + (NEW.bracket_position - 1),
                            v_cons_p1);
          v_cons_pos    := (v_cons_slot0 / 2) + 1;
          v_cons_side_b := (v_cons_slot0 % 2) = 1;

          SELECT participant_a, participant_b, status
            INTO v_next_a, v_next_b, v_next_status
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = 1
              AND bracket_position = v_cons_pos
            FOR UPDATE;
          IF FOUND THEN
            IF v_cons_side_b THEN v_next_b := v_loser_part;
            ELSE                  v_next_a := v_loser_part; END IF;
            IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
               AND v_next_status = 'scheduled' THEN
              v_next_status := 'awaiting_results';
            END IF;
            UPDATE public.tournament_matches
              SET participant_a = v_next_a,
                  participant_b = v_next_b,
                  status        = v_next_status
              WHERE tournament_id = NEW.tournament_id
                AND phase = 'consolation'
                AND round_number = 1
                AND bracket_position = v_cons_pos;
          END IF;
        ELSE
          SELECT count(*) INTO v_cons_matches
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = v_cons_target;
          v_cons_slot0 := public._tournament_cons_drop_slot(
                            NEW.bracket_position, v_cons_matches);
          v_cons_pos    := (v_cons_slot0 / 2) + 1;
          v_cons_side_b := (v_cons_slot0 % 2) = 1;

          SELECT participant_a, participant_b, status
            INTO v_next_a, v_next_b, v_next_status
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = v_cons_target
              AND bracket_position = v_cons_pos
            FOR UPDATE;
          IF FOUND THEN
            IF v_cons_side_b THEN v_next_b := v_loser_part;
            ELSE                  v_next_a := v_loser_part; END IF;
            IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
               AND v_next_status = 'scheduled' THEN
              v_next_status := 'awaiting_results';
            END IF;
            UPDATE public.tournament_matches
              SET participant_a = v_next_a,
                  participant_b = v_next_b,
                  status        = v_next_status
              WHERE tournament_id = NEW.tournament_id
                AND phase = 'consolation'
                AND round_number = v_cons_target
                AND bracket_position = v_cons_pos;
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

  -- (B) CONSOLATION-INTERNAL progression + consolation 3rd-place mirror.
  IF NEW.phase = 'consolation' THEN
    SELECT MAX(round_number) INTO v_cons_rounds
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND phase = 'consolation';

    IF NEW.round_number < v_cons_rounds THEN
      SELECT MAX(round_number) INTO v_main_rounds
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase IN ('ko','final');
      v_main_size := (1 << v_main_rounds);

      IF public._tournament_cons_drop_target(v_next_round, v_main_size) >= 1 THEN
        v_next_position := NEW.bracket_position;
        v_is_odd        := true;  -- A-slot
      END IF;

      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'consolation'
          AND round_number = v_next_round
          AND bracket_position = v_next_position
        FOR UPDATE;
      IF FOUND THEN
        IF v_is_odd THEN v_next_a := NEW.winner_participant;
        ELSE             v_next_b := NEW.winner_participant; END IF;

        IF v_is_odd AND v_next_a IS NOT NULL AND v_next_b IS NULL THEN
          SELECT count(*) INTO v_next_matches
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = v_next_round;
          v_next_lr := v_main_size / (1 << v_next_round);
          IF v_next_position <= (v_next_matches - v_next_lr) THEN
            UPDATE public.tournament_matches
              SET participant_a      = v_next_a,
                  winner_participant = v_next_a,
                  status             = 'finalized',
                  finalized_at       = now()
              WHERE tournament_id = NEW.tournament_id
                AND phase = 'consolation'
                AND round_number = v_next_round
                AND bracket_position = v_next_position;
            v_next_status := NULL;
          END IF;
        END IF;

        IF v_next_status IS NOT NULL THEN
          IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
             AND v_next_status = 'scheduled' THEN
            v_next_status := 'awaiting_results';
          END IF;
          UPDATE public.tournament_matches
            SET participant_a = v_next_a,
                participant_b = v_next_b,
                status        = v_next_status
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = v_next_round
              AND bracket_position = v_next_position;
        END IF;
      END IF;
    END IF;

    IF v_loser_part IS NOT NULL
       AND v_cons_rounds >= 2
       AND NEW.round_number = v_cons_rounds - 1 THEN
      SELECT participant_a, participant_b, status
        INTO v_tp_a, v_tp_b, v_tp_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'consolation_third_place'
          AND round_number = 1
          AND bracket_position = 1
        FOR UPDATE;
      IF FOUND THEN
        IF (NEW.bracket_position % 2) = 1 THEN
          v_tp_a := v_loser_part;
        ELSE
          v_tp_b := v_loser_part;
        END IF;
        IF v_tp_a IS NOT NULL AND v_tp_b IS NOT NULL
           AND v_tp_status = 'scheduled' THEN
          v_tp_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_tp_a,
              participant_b = v_tp_b,
              status        = v_tp_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'consolation_third_place'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS tournament_advance_ko_winner ON public.tournament_matches;
CREATE TRIGGER tournament_advance_ko_winner
  AFTER UPDATE ON public.tournament_matches
  FOR EACH ROW
  WHEN (
    OLD.winner_participant IS NULL
    AND NEW.winner_participant IS NOT NULL
  )
  EXECUTE FUNCTION public.tournament_advance_ko_winner();

COMMENT ON FUNCTION public.tournament_advance_ko_winner() IS
  'AFTER-UPDATE advance trigger (re-based 20261306000000). ADR-0039 §4: the '
  'single_elim third_place mirror locates the third_place match by phase alone '
  'so it matches the stage KO third_place (bracket_position NULL, kept out of the '
  'type_graph slot index). type_graph routing, single_elim advance, double_elim, '
  'consolation and the consolation_third_place mirror are byte-identical.';
