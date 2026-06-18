-- Tournament — ADR-0033 §4 / ADR-0034 §3 P5.3c: stage KO round-1 honours the
-- per-node per-round format.
--
-- KO-typed stage nodes (single_elim/double_elim/consolation) now time their
-- round-1 schedule from config->'ko_round_formats'[0] (the node's per-round
-- format) via a new stage-aware helper, instead of the tournament prelim
-- format. Non-KO stages keep prelim timing. Honest partial: later stage KO
-- rounds are materialised by a stage-advance scheduler that does not exist yet
-- (separate ADR-0031 block) — only round 1 is timed from node config here.
--
-- Additive: a new helper + a CREATE OR REPLACE of the stage generator (re-based
-- from its latest body 20261287000000). No schema/CDC/publication change.

-- ── New helper: stage-aware per-round KO timing ───────────────────────────
-- Mirrors _tournament_schedule_ko_seconds (20261251000000) but sources the
-- per-round array from tournament_stages.config->'ko_round_formats' for the
-- given node, falling back to the tournament match_format.
CREATE OR REPLACE FUNCTION public._tournament_schedule_stage_ko_seconds(
  p_tournament_id  uuid,
  p_node_id        text,
  p_round_number   int,
  p_is_final       boolean,
  OUT match_seconds   int,
  OUT break_seconds   int,
  OUT tiebreak_after  int
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_config     jsonb;
  v_ko_formats jsonb;
  v_match_fmt  jsonb;
  v_fmt        jsonb;
  v_round_fmt  jsonb;
BEGIN
  SELECT config INTO v_config
    FROM public.tournament_stages
    WHERE tournament_id = p_tournament_id AND node_id = p_node_id;
  SELECT match_format INTO v_match_fmt
    FROM public.tournaments WHERE id = p_tournament_id;

  -- Per-round element (index N-1) of the node config wins; else match_format.
  v_ko_formats := v_config -> 'ko_round_formats';
  v_round_fmt := NULL;
  IF v_ko_formats IS NOT NULL
     AND jsonb_typeof(v_ko_formats) = 'array'
     AND jsonb_array_length(v_ko_formats) >= p_round_number THEN
    v_round_fmt := v_ko_formats -> (p_round_number - 1);
  END IF;

  IF v_round_fmt IS NOT NULL AND jsonb_typeof(v_round_fmt) = 'object' THEN
    v_fmt := v_round_fmt;
  ELSE
    v_fmt := v_match_fmt;
  END IF;

  IF v_fmt IS NULL OR jsonb_typeof(v_fmt) <> 'object' THEN
    match_seconds  := 0;
    break_seconds  := 0;
    tiebreak_after := NULL;
    RETURN;
  END IF;

  match_seconds := greatest(0, coalesce(
    (v_fmt ->> 'round_time_seconds')::int,
    (v_fmt ->> 'time_limit_seconds')::int,
    0));
  break_seconds := greatest(0, coalesce(
    (v_fmt ->> 'break_between_matches_seconds')::int, 0));
  IF p_is_final AND coalesce((v_fmt ->> 'final_no_tiebreak')::boolean, false) THEN
    tiebreak_after := NULL;
  ELSE
    tiebreak_after := (v_fmt ->> 'tiebreak_after_seconds')::int;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_schedule_stage_ko_seconds(uuid, text, int, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_schedule_stage_ko_seconds(uuid, text, int, boolean) FROM authenticated;

-- ── Re-based stage generator: KO round-1 uses the stage-aware timing ──────
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

  -- 5. Type dispatch.
  IF v_type IN ('single_elim', 'consolation') THEN
    -- single_elim and (standalone, routed) consolation are the same bracket
    -- shape: a single-elimination bracket over the seed-ordered subset.
    IF v_n < 2 THEN
      RAISE EXCEPTION 'INVALID_PARTICIPANT: % stage % needs at least 2 participants, got %', v_type, p_node_id, v_n
        USING ERRCODE = '22023';
    END IF;
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
      FROM public._tournament_compute_ko_bracket(
             v_seeds_jsonb, false,
             coalesce(v_config ->> 'ko_matchup', 'seed_high_vs_low')) b;

    GET DIAGNOSTICS v_count = ROW_COUNT;

  ELSIF v_type = 'double_elim' THEN
    -- Double-elimination bracket (ADR-0027). with_reset from stage config.
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

  ELSIF v_type IN ('round_robin', 'pool') THEN
    -- P5.3a (ADR-0033 §4): multi-group support. group_count>1 splits the seeded
    -- field into groups via _tournament_compute_pools (snake/seeded/random) and
    -- emits intra-group round-robin pairs tagged with group_label (mirroring the
    -- classic pool path). group_count<=1 keeps the original single flat group
    -- (group_label NULL) so existing single-pool stages are byte-for-byte stable.
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
      -- Single group: all N*(N-1)/2 unordered pairs over the seed order.
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

  ELSIF v_type = 'swiss' THEN
    -- Swiss round 1 only: deterministic seed "slide" pairing (seed i vs
    -- seed i+h, h = floor(N/2)), phase 'group', round 1. Odd field -> the
    -- lowest seed (last in seed order) gets a BYE, auto-finalized. Later
    -- rounds are paired live (tournament_pair_round).
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
    -- Odd field: the unpaired lowest seed (index N when N is odd) gets a BYE.
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
    -- shootout_quali — deferred step (needs the shoot-out machinery).
    RAISE EXCEPTION 'stage type % not yet supported by the stage generator', v_type
      USING ERRCODE = '22023';
  END IF;

  -- ADR-0031 A1 + P5.3c: materialise this stage's round 1 schedule. KO-typed
  -- stage nodes time round 1 from their per-round node format
  -- (config->'ko_round_formats'[0]); non-KO stages keep prelim timing (OE-6).
  IF v_type IN ('single_elim', 'double_elim', 'consolation') THEN
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

  -- ADR-0031 C1 (E1) GAP-CLOSE: stage-graph rounds were SILENT before C1
  -- (this runner fired NO participant notify). Add a per-pitch publish-notify
  -- of the stage's materialised round (round 1, phase 'group') AFTER the
  -- matches and the stage schedule row exist; starts_at resolved inside the
  -- helper from the schedule row (degrades cleanly without one).
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
  'ADR-0030 runner Step 3 (re-based 20261247000000 via A1 20261252000000); '
  'ADR-0031 A1 adds one tournament_round_schedule row per stage (stage_node_id '
  '= p_node_id, round 1, phase group; time from prelim match_format, OE-6); '
  'ADR-0031 C1 GAP-CLOSE adds a per-pitch publish-notify (round_published, '
  'round 1, phase group) — stage-graph rounds were previously silent. '
  'single_elim and routed consolation share the single-elim bracket; '
  'double_elim uses _tournament_compute_de_bracket (with_reset from config); '
  'round_robin/pool emit all N*(N-1)/2 group pairs; swiss emits round 1 seed '
  'slide (odd field -> lowest-seed BYE). shootout_quali raises 22023. BYE '
  'pairings auto-finalized. Pure materializer otherwise. Returns rows inserted.';
