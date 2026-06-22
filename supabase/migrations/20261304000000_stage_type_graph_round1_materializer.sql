-- Tournament — ADR-0039 §6.6 (U10a, T13/T14): generic round-1 materializer for
-- a stage that carries a CUSTOM type graph in config['type_graph'].
--
-- Until now every stage materialised round 1 through the TYPE-FIXED CASE in
-- tournament_generate_stage_matches (dispatch on tournament_stages.type:
-- single_elim / double_elim / round_robin / group_phase / swiss / schoch / ...).
-- A stage built from an Ebene-2 StageTypeGraph (U1/U7/U8/U9, persisted into
-- config['type_graph'] by the client) had no server materialisation path: the
-- only server awareness of a type_graph was the shape check
-- _stage_type_graph_is_valid (20261303000000).
--
-- This migration adds, purely additively:
--   1. _tournament_materialize_type_graph_round1 — a new SECURITY DEFINER
--      helper that inserts ROUND 1 of a stage from its type_graph: one match per
--      round-1 TypeField, with the round's per-field match format and the
--      seed-resolved input order (M3 resolver supplies p_seeded).
--   2. A re-based tournament_generate_stage_matches (verbatim copy of its live
--      body, 20261293000000) with TWO additive hooks:
--        a) a new FIRST branch at the top of the Step-5 type dispatch that fires
--           when config['type_graph'] is present + valid: it delegates to the
--           new materializer and SKIPS the type-fixed CASE entirely;
--        b) the round-1 schedule tail's KO-timing IF widened so a KO-category
--           type_graph is timed through _tournament_schedule_stage_ko_seconds
--           (a vorrunde-category type_graph keeps prelim timing).
--
-- A stage WITHOUT config['type_graph'] is unaffected: it still hits exactly the
-- existing type-fixed branches and the existing schedule tail, byte-for-byte.
--
-- Scope is ONLY round-1 materialisation (T13/T14). Winner-advance along a
-- WinnerEdge (T15), loser-route along a LoserEdge (T16), stage-KO round 2+
-- scheduling (T17) and server-authoritative ko_tiebreak (T18) are U10b/U10c and
-- are NOT touched here. Idempotency stays enforced upstream by guard 4
-- (STAGE_ALREADY_GENERATED); the materializer never re-touches the guards.
--
-- KO slot geometry: a clean halving KO type_graph numbers its round-1 fields
-- F1..F(ceil(N/2)) with slot == bracket_position, exactly the numbering
-- _tournament_compute_ko_bracket produces. We reuse that builder for the
-- round-1 seed slotting (open-decision 1, recommendation B) and map each
-- computed round-1 row onto the TypeField with the matching slot.

-- ===================================================================
-- T14 — _tournament_materialize_type_graph_round1
-- ===================================================================

CREATE OR REPLACE FUNCTION public._tournament_materialize_type_graph_round1(
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
  v_graph     jsonb;
  v_category  text;
  v_round1    jsonb;       -- the round_number = 1 TypeRound object
  v_fmt       jsonb;       -- round 1 match_format
  v_matchup   text;        -- round 1 ko_matchup
  v_pairing   text;        -- round 1 pairing_rule (vorrunde only)
  v_field_cnt int;         -- number of round-1 fields in the graph
  v_n         int := coalesce(array_length(p_seeded, 1), 0);
  v_count     int := 0;
  v_seeds_jsonb jsonb;
  v_half      int;
  v_pair_no   int;
  v_a         uuid;
  v_b         uuid;
  i           int;
BEGIN
  -- Load + validate the type graph (the stage row was already located by the
  -- caller; we read config -> 'type_graph' directly).
  SELECT config -> 'type_graph' INTO v_graph
    FROM public.tournament_stages
    WHERE tournament_id = p_tournament_id
      AND node_id = p_node_id;

  IF v_graph IS NULL OR NOT public._stage_type_graph_is_valid(v_graph) THEN
    RAISE EXCEPTION 'INVALID_TYPE_GRAPH: stage % carries no valid type_graph', p_node_id
      USING ERRCODE = '22023';
  END IF;

  IF v_n < 1 THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: p_seeded must contain at least one participant'
      USING ERRCODE = '22023';
  END IF;

  v_category := v_graph ->> 'category';

  -- Round 1 of the graph: the rounds[] element with round_number = 1.
  SELECT r INTO v_round1
    FROM jsonb_array_elements(v_graph -> 'rounds') AS r
    WHERE (r ->> 'round_number')::int = 1
    LIMIT 1;

  IF v_round1 IS NULL THEN
    RAISE EXCEPTION 'INVALID_TYPE_GRAPH: stage % type_graph has no round 1', p_node_id
      USING ERRCODE = '22023';
  END IF;

  v_fmt     := v_round1 -> 'match_format';
  v_matchup := coalesce(v_round1 ->> 'ko_matchup', 'seed_high_vs_low');
  v_pairing := v_round1 ->> 'pairing_rule';
  v_field_cnt := coalesce(jsonb_array_length(v_round1 -> 'fields'), 0);

  IF v_category = 'ko' THEN
    -- KO: 2 participants per field. Reuse the canonical bracket builder for the
    -- round-1 seed slotting; slot == bracket_position for a clean halving graph,
    -- so we map each round-1 computed row onto the field of the same slot.
    -- match_number_in_round = bracket_position (mirrors the type-fixed KO path).
    IF v_n < 2 THEN
      RAISE EXCEPTION 'INVALID_PARTICIPANT: ko type_graph stage % needs at least 2 participants, got %', p_node_id, v_n
        USING ERRCODE = '22023';
    END IF;
    v_seeds_jsonb := to_jsonb(p_seeded);

    INSERT INTO public.tournament_matches(
        tournament_id, stage_node_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           p_node_id,
           1::smallint,
           b.bracket_position::smallint,
           b.bracket_position,
           b.participant_a,
           b.participant_b,
           -- 'final' when round 1 IS the final (single field), else 'ko'.
           CASE WHEN v_field_cnt = 1 THEN 'final' ELSE 'ko' END,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END
      FROM public._tournament_compute_ko_bracket(
             v_seeds_jsonb, false, v_matchup) b
      JOIN jsonb_array_elements(v_round1 -> 'fields') AS f
        ON (f ->> 'slot')::int = b.bracket_position
      WHERE b.round_number = 1;

    GET DIAGNOSTICS v_count = ROW_COUNT;

  ELSE
    -- vorrunde: round-1 seed slotting is the U6 emission keyed on pairing_rule.
    --   group_round_robin -> all N*(N-1)/2 flat round-robin pairs.
    --   schoch_monrad (or unset) -> seed slide (seed i vs seed i + floor(N/2)),
    --     odd field -> lowest seed BYE auto-finalized (Schoch round 1).
    IF v_n < 2 THEN
      RAISE EXCEPTION 'INVALID_PARTICIPANT: vorrunde type_graph stage % needs at least 2 participants, got %', p_node_id, v_n
        USING ERRCODE = '22023';
    END IF;

    IF v_pairing = 'group_round_robin' THEN
      v_pair_no := 0;
      FOR i IN 1 .. v_n LOOP
        FOR v_count IN (i + 1) .. v_n LOOP
          v_pair_no := v_pair_no + 1;
          INSERT INTO public.tournament_matches(
              tournament_id, stage_node_id, round_number, match_number_in_round,
              participant_a, participant_b, phase, status, pitch_number)
          VALUES (
              p_tournament_id, p_node_id, 1::smallint, v_pair_no::smallint,
              p_seeded[i], p_seeded[v_count], 'group', 'scheduled', 1);
        END LOOP;
      END LOOP;
      v_count := v_pair_no;
    ELSE
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
    END IF;
  END IF;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION
  public._tournament_materialize_type_graph_round1(uuid, text, uuid[])
  TO authenticated;

COMMENT ON FUNCTION
  public._tournament_materialize_type_graph_round1(uuid, text, uuid[]) IS
  'ADR-0039 §6.6 (U10a/T14): materialise ROUND 1 of a stage from its '
  'config[type_graph] (StageTypeGraph). KO category: one 2-participant match per '
  'round-1 TypeField, seed-slotted by _tournament_compute_ko_bracket (slot == '
  'bracket_position), phase final iff round 1 has a single field, BYE pairings '
  'auto-finalized. Vorrunde category: round-1 emission keyed on the round-1 '
  'pairing_rule — group_round_robin -> all N*(N-1)/2 group pairs; schoch_monrad '
  '-> seed slide with odd-field lowest-seed BYE. Round 2+ / winner-advance / '
  'loser-route are U10b/U10c. Returns rows inserted.';

-- ===================================================================
-- Re-based tournament_generate_stage_matches: additive type_graph branch.
-- Verbatim copy of the live body (20261293000000) with TWO additive hooks:
--   (a) a new FIRST branch at the top of Step 5 that delegates to the
--       round-1 materializer when config['type_graph'] is present + valid;
--   (b) the round-1 schedule KO-timing IF widened with a type_graph KO arm.
-- Every existing type branch and the guards 1-4 stay byte-for-byte.
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

  -- U10a (ADR-0039 §6.6): a stage carrying a valid config['type_graph']
  -- materialises round 1 generically from the type graph (one match per round-1
  -- TypeField, per-field format) and SKIPS the type-fixed CASE below.
  v_has_graph := (v_config -> 'type_graph') IS NOT NULL
                 AND public._stage_type_graph_is_valid(v_config -> 'type_graph');
  IF v_has_graph THEN
    v_graph_cat := v_config #>> '{type_graph,category}';
  END IF;

  -- 5. Type dispatch.
  IF v_has_graph THEN
    -- U10a: generic round-1 materialisation from config['type_graph']. The
    -- type-fixed CASE is skipped entirely; v_count comes from the materializer.
    v_count := public._tournament_materialize_type_graph_round1(
      p_tournament_id, p_node_id, p_seeded);

  ELSIF v_type IN ('single_elim', 'consolation') THEN
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

  ELSIF v_type IN ('round_robin', 'pool', 'group_phase') THEN
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

  ELSIF v_type IN ('swiss', 'schoch') THEN
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
  -- U10a: a KO-CATEGORY type_graph is timed the same KO way; a vorrunde-category
  -- type_graph (and every non-KO type-fixed stage) keeps prelim timing.
  IF v_type IN ('single_elim', 'double_elim', 'consolation')
     OR (v_has_graph AND v_graph_cat = 'ko') THEN
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
  'ADR-0030 runner Step 3 (re-based 20261293000000); ADR-0031 A1 adds one '
  'tournament_round_schedule row per stage (round 1, phase group); ADR-0031 C1 '
  'GAP-CLOSE adds a per-pitch publish-notify. ADR-0039 §6.6 (U10a): a stage '
  'carrying a valid config[type_graph] materialises round 1 generically via '
  '_tournament_materialize_type_graph_round1 and SKIPS the type-fixed CASE; its '
  'round-1 schedule is KO-timed when the graph category is ko, prelim-timed when '
  'vorrunde. Stages WITHOUT a type_graph keep the type-fixed dispatch '
  '(single_elim/consolation/double_elim/round_robin/pool/group_phase/swiss/'
  'schoch) byte-for-byte. shootout_quali raises 22023. Returns rows inserted.';
