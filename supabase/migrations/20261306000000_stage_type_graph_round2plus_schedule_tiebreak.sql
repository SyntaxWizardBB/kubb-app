-- Tournament — ADR-0039 §6.6 (U10c, T17/T18 + two U10b carry-over hardenings):
-- round-2+ scheduling for a stage type_graph, server-authoritative ko_tiebreak
-- per field, and concurrency-hardening of the round-2+ upsert.
--
-- Context. U10a (20261304000000) materialised ROUND 1 of a type_graph stage and
-- U10b (20261305000000) routed winners/losers along the field edges, UPSERTing
-- round-2+ target matches lazily (first feeder INSERTs, second feeder flips
-- scheduled -> awaiting_results). Three gaps were left open and are closed here.
--
-- T17 — round-2+ scheduling from the TypeRound matchFormat.
--   A round-2+ target match upserted by U10b carried NO tournament_round_schedule
--   row, so match_autostart no-op'd on it. Fix: the moment a round-2+ target match
--   is fully filled (both slots, scheduled -> awaiting_results), materialise its
--   round's schedule row, timed from the TARGET round's TypeRound.matchFormat
--   (sets/time/break/tiebreak), reusing the central _tournament_upsert_round_schedule.
--   This also closes the U10a MEDIUM: a type_graph stage's match timing — round 1
--   AND round 2+ — is the per-round TypeRound.matchFormat, NOT the stage-wide
--   config->'ko_round_formats'. The U10a round-1 schedule tail is rewired here to
--   read the TypeRound-1 matchFormat through the new
--   _tournament_schedule_type_graph_round_seconds helper (the U10a materializer
--   parsed match_format into v_fmt but never used it for timing).
--
-- T18 — ko_tiebreak_method server-authoritative per field.
--   The method was only consumed at the match detail, which resolved it from the
--   NODE config — and a type_graph node carries no top-level ko_tiebreak_method
--   (it lives PER ROUND under config->'type_graph'->'rounds'[r]->'ko_tiebreak_method').
--   So the per-round value was never enforced. Fix: a new additive nullable
--   column tournament_matches.ko_tiebreak_method, written server-side from the
--   match's TypeRound when materialising (round 1) and routing (round 2+), and
--   projected by tournament_match_get so the detail screen reads the authoritative
--   server value instead of computing its own.
--
-- U10b hardening — round-2+ upsert concurrency.
--   _tournament_type_graph_route_into did SELECT ... FOR UPDATE then INSERT with
--   no backing unique constraint, so two simultaneous feeders of the same target
--   field could each take the INSERT branch and duplicate the match. Fix: a UNIQUE
--   PARTIAL INDEX on (tournament_id, stage_node_id, round_number, bracket_position)
--   WHERE stage_node_id IS NOT NULL AND bracket_position IS NOT NULL (scoped to the
--   type_graph KO upsert rows — vorrunde/group stage matches share a (round,node)
--   but carry a NULL bracket_position and are excluded, so no Bestandsdaten
--   collision), and the route INSERT becomes ON CONFLICT DO UPDATE.
--
-- Everything is additive: a new column, a new index, two new helpers, and
-- CREATE OR REPLACE of four functions re-based verbatim from their latest bodies
-- (20261304 generate_stage_matches, 20261305 advance trigger + route helper,
-- 20261289 match_get). The standard KO path stays byte-for-byte: the new column
-- is NULL for every classic match, the index is partial on stage type_graph rows
-- only, and the schedule/tiebreak hooks live inside the type_graph branches.

-- ===================================================================
-- T18 schema: per-match ko_tiebreak_method (additive, nullable).
-- NULL for every classic match (resolution stays tournament-level there); set
-- server-side for a type_graph KO match from its round's TypeRound.ko_tiebreak.
-- ===================================================================
ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS ko_tiebreak_method text NULL
    CHECK (ko_tiebreak_method IS NULL OR ko_tiebreak_method IN (
      'classic_kingtoss_removal', 'mighty_finisher_shootout'));

COMMENT ON COLUMN public.tournament_matches.ko_tiebreak_method IS
  'ADR-0039 §6.6 (U10c/T18): server-authoritative KO tiebreak method for THIS '
  'match. Set from the match''s TypeRound.ko_tiebreak_method for a type_graph KO '
  'match (round 1 at materialisation, round 2+ at routing); NULL for a classic '
  'match (resolution stays tournament-level). Projected by tournament_match_get '
  'so the match detail uses the server value, not a client-computed method.';

-- ===================================================================
-- U10b hardening: unique partial index backing the round-2+ ON CONFLICT.
-- Scoped to type_graph KO upsert rows (bracket_position NOT NULL); vorrunde /
-- group / schoch stage matches carry a NULL bracket_position and are excluded,
-- so existing data cannot collide.
-- ===================================================================
CREATE UNIQUE INDEX IF NOT EXISTS tournament_matches_stage_slot_uq
  ON public.tournament_matches
     (tournament_id, stage_node_id, round_number, bracket_position)
  WHERE stage_node_id IS NOT NULL AND bracket_position IS NOT NULL;

-- ===================================================================
-- T18 helper: the ko_tiebreak_method of a graph's round r (1-based), or NULL.
-- Reads rounds[r-1]->'ko_tiebreak_method' (TypeRound.ko_tiebreak_method); a
-- missing/null value (KO round without an explicit method, or a vorrunde round)
-- yields NULL so the column stays unset and the classic fallback applies.
-- ===================================================================
CREATE OR REPLACE FUNCTION public._stage_type_graph_round_tiebreak(
  p_graph        jsonb,
  p_round_number int
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT r ->> 'ko_tiebreak_method'
    FROM jsonb_array_elements(p_graph -> 'rounds') AS r
    WHERE (r ->> 'round_number')::int = p_round_number
    LIMIT 1;
$$;

COMMENT ON FUNCTION public._stage_type_graph_round_tiebreak(jsonb, int) IS
  'ADR-0039 §6.6 (U10c/T18): the ko_tiebreak_method of a stage type_graph round '
  '(1-based), or NULL when the round carries none. Source of the server-'
  'authoritative per-field tiebreak written onto tournament_matches.';

-- ===================================================================
-- T17 helper: schedule seconds for round r of a stage type_graph, sourced from
-- the round's TypeRound.match_format (StageTypeGraph -> rounds[r-1] ->
-- 'match_format'). Mirrors _tournament_schedule_stage_ko_seconds' field reads
-- (round_time_seconds | time_limit_seconds; break_between_matches_seconds;
-- tiebreak_after_seconds; final_no_tiebreak) but binds the timing to the
-- per-round matchFormat instead of config->'ko_round_formats'. This is THE
-- type_graph match-time source for round 1 and round 2+ (closes the U10a MEDIUM).
-- ===================================================================
CREATE OR REPLACE FUNCTION public._tournament_schedule_type_graph_round_seconds(
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
  v_graph     jsonb;
  v_match_fmt jsonb;   -- tournament-level fallback
  v_round_fmt jsonb;   -- TypeRound.match_format of round p_round_number
  v_fmt       jsonb;
BEGIN
  SELECT config -> 'type_graph' INTO v_graph
    FROM public.tournament_stages
    WHERE tournament_id = p_tournament_id AND node_id = p_node_id;
  SELECT match_format INTO v_match_fmt
    FROM public.tournaments WHERE id = p_tournament_id;

  SELECT r -> 'match_format'
    INTO v_round_fmt
    FROM jsonb_array_elements(v_graph -> 'rounds') AS r
    WHERE (r ->> 'round_number')::int = p_round_number
    LIMIT 1;

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

REVOKE EXECUTE ON FUNCTION public._tournament_schedule_type_graph_round_seconds(uuid, text, int, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_schedule_type_graph_round_seconds(uuid, text, int, boolean) FROM authenticated;

COMMENT ON FUNCTION public._tournament_schedule_type_graph_round_seconds(uuid, text, int, boolean) IS
  'ADR-0039 §6.6 (U10c/T17): schedule seconds for round r of a stage type_graph, '
  'sourced from the round''s TypeRound.match_format (config->type_graph->rounds[r]->'
  'match_format), tournament match_format as fallback. The type_graph match-time '
  'source for round 1 and round 2+ (closes the U10a match_format-parsed-but-unused '
  'gap). Mirrors _tournament_schedule_stage_ko_seconds'' field reads.';

-- ===================================================================
-- T14/T18 re-base: _tournament_materialize_type_graph_round1.
-- Verbatim from 20261304000000 with ONE additive write: the round-1 KO match
-- rows now carry ko_tiebreak_method from the TypeRound-1 ko_tiebreak (T18). The
-- vorrunde path is unchanged (its rounds carry no KO tiebreak). Round count and
-- slotting are byte-for-byte identical.
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
  v_tiebreak  text;        -- T18: round-1 ko_tiebreak_method (KO only)
  v_n         int := coalesce(array_length(p_seeded, 1), 0);
  v_count     int := 0;
  v_seeds_jsonb jsonb;
  v_half      int;
  v_pair_no   int;
  v_a         uuid;
  v_b         uuid;
  i           int;
BEGIN
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
  v_tiebreak := v_round1 ->> 'ko_tiebreak_method';

  IF v_category = 'ko' THEN
    IF v_n < 2 THEN
      RAISE EXCEPTION 'INVALID_PARTICIPANT: ko type_graph stage % needs at least 2 participants, got %', p_node_id, v_n
        USING ERRCODE = '22023';
    END IF;
    v_seeds_jsonb := to_jsonb(p_seeded);

    INSERT INTO public.tournament_matches(
        tournament_id, stage_node_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at,
        ko_tiebreak_method)
    SELECT p_tournament_id,
           p_node_id,
           1::smallint,
           b.bracket_position::smallint,
           b.bracket_position,
           b.participant_a,
           b.participant_b,
           CASE WHEN v_field_cnt = 1 THEN 'final' ELSE 'ko' END,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END,
           v_tiebreak
      FROM public._tournament_compute_ko_bracket(
             v_seeds_jsonb, false, v_matchup) b
      JOIN jsonb_array_elements(v_round1 -> 'fields') AS f
        ON (f ->> 'slot')::int = b.bracket_position
      WHERE b.round_number = 1;

    GET DIAGNOSTICS v_count = ROW_COUNT;

  ELSE
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
  'ADR-0039 §6.6 (U10a/T14; U10c/T18): materialise ROUND 1 of a stage from its '
  'config[type_graph]. KO: one 2-participant match per round-1 TypeField, seed-'
  'slotted by _tournament_compute_ko_bracket, phase final iff round 1 is the lone '
  'field, BYE auto-finalized; each KO match now carries the round-1 '
  'ko_tiebreak_method server-side (T18). Vorrunde: round-1 emission keyed on the '
  'round-1 pairing_rule. Returns rows inserted.';

-- ===================================================================
-- T17/T18 re-base: tournament_generate_stage_matches.
-- Verbatim from 20261304000000 with ONE changed line: a type_graph stage's
-- round-1 schedule is now timed from the TypeRound-1 matchFormat via
-- _tournament_schedule_type_graph_round_seconds (closing the U10a MEDIUM where
-- match_format was parsed into v_fmt but the schedule still used
-- config->'ko_round_formats'). A vorrunde-category type_graph times round 1 from
-- the round's matchFormat too (its non-KO timing). Type-fixed stages keep
-- ko_round_formats / prelim timing byte-for-byte.
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

  v_has_graph := (v_config -> 'type_graph') IS NOT NULL
                 AND public._stage_type_graph_is_valid(v_config -> 'type_graph');
  IF v_has_graph THEN
    v_graph_cat := v_config #>> '{type_graph,category}';
  END IF;

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
  'ADR-0030 runner Step 3 (re-based 20261304000000); ADR-0031 A1 adds one '
  'tournament_round_schedule row per stage. ADR-0039 §6.6 (U10a) materialises a '
  'type_graph stage''s round 1 via _tournament_materialize_type_graph_round1; '
  'U10c (T17) times that round 1 from the TypeRound-1 matchFormat (the per-round '
  'source, closing the U10a parsed-but-unused gap), KO type-fixed nodes keep '
  'ko_round_formats[0], other type-fixed stages keep prelim. Stages WITHOUT a '
  'type_graph keep the type-fixed dispatch byte-for-byte. Returns rows inserted.';

-- ===================================================================
-- U10b/U10c re-base: _tournament_type_graph_route_into.
-- Verbatim from 20261305000000 with three additive changes:
--   * the first-feeder INSERT carries the TARGET round's ko_tiebreak_method (T18)
--     and uses ON CONFLICT ... DO UPDATE on the new unique partial index, so two
--     simultaneous feeders cannot duplicate the target match (U10b hardening);
--   * when the upsert fills both slots and flips to awaiting_results, a round-r
--     schedule row is materialised, timed from the TARGET round's TypeRound
--     matchFormat (T17). Phase 'final' iff the target is the lone last-round field.
-- Idempotency on the participant is preserved (re-writing the same slot/value is
-- a no-op-by-value); the schedule row helper is itself ON CONFLICT DO NOTHING.
-- ===================================================================
CREATE OR REPLACE FUNCTION public._tournament_type_graph_route_into(
  p_tournament_id   uuid,
  p_node_id         text,
  p_graph           jsonb,
  p_src_field       text,
  p_to_field        text,
  p_participant     uuid,
  p_last_round      int,
  p_final_fields    int
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_round    int;
  v_slot     int;
  v_rank     int;
  v_side_b   boolean;
  v_phase    text;
  v_is_final boolean;
  v_tiebreak text;
  v_next_a   uuid;
  v_next_b   uuid;
  v_next_st  text;
  v_found    boolean;
  v_ms       int;
  v_bs       int;
  v_ta       int;
BEGIN
  SELECT (f ->> 'round_number')::int, (f ->> 'slot')::int
    INTO v_round, v_slot
    FROM jsonb_array_elements(p_graph -> 'rounds') AS r
    CROSS JOIN jsonb_array_elements(r -> 'fields') AS f
    WHERE f ->> 'id' = p_to_field
    LIMIT 1;

  IF v_round IS NULL THEN
    RETURN;  -- malformed edge: target field absent. Drop silently.
  END IF;

  SELECT rank
    INTO v_rank
    FROM (
      SELECT e ->> 'from_field_id' AS from_field,
             row_number() OVER () AS rank
        FROM jsonb_array_elements(p_graph -> 'edges') AS e
        WHERE e ->> 'kind' IN ('winner','loser')
          AND e ->> 'to_field_id' = p_to_field
    ) ranked
    WHERE from_field = p_src_field
    LIMIT 1;

  v_side_b := coalesce(v_rank, 1) >= 2;

  v_is_final := v_round = p_last_round AND coalesce(p_final_fields, 1) = 1;
  v_phase := CASE WHEN v_is_final THEN 'final' ELSE 'ko' END;

  -- T18: the target round's server-authoritative tiebreak method.
  v_tiebreak := public._stage_type_graph_round_tiebreak(p_graph, v_round);

  -- Lock the target match if it already exists.
  SELECT participant_a, participant_b, status, true
    INTO v_next_a, v_next_b, v_next_st, v_found
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND stage_node_id = p_node_id
      AND round_number  = v_round
      AND bracket_position = v_slot
    FOR UPDATE;

  IF coalesce(v_found, false) THEN
    IF v_side_b THEN v_next_b := p_participant;
    ELSE             v_next_a := p_participant; END IF;
    IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
       AND v_next_st = 'scheduled' THEN
      v_next_st := 'awaiting_results';
    END IF;
    UPDATE public.tournament_matches
      SET participant_a = v_next_a,
          participant_b = v_next_b,
          status        = v_next_st
      WHERE tournament_id = p_tournament_id
        AND stage_node_id = p_node_id
        AND round_number  = v_round
        AND bracket_position = v_slot;
  ELSE
    -- First feeder: materialise the target match. ON CONFLICT DO UPDATE on the
    -- unique partial index serialises a concurrent feeder so it fills the other
    -- slot instead of inserting a duplicate (U10b hardening).
    INSERT INTO public.tournament_matches(
        tournament_id, stage_node_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b, phase, status,
        pitch_number, ko_tiebreak_method)
    VALUES (
        p_tournament_id, p_node_id, v_round::smallint, v_slot::smallint, v_slot,
        CASE WHEN v_side_b THEN NULL ELSE p_participant END,
        CASE WHEN v_side_b THEN p_participant ELSE NULL END,
        v_phase, 'scheduled', 1, v_tiebreak)
    ON CONFLICT (tournament_id, stage_node_id, round_number, bracket_position)
      WHERE stage_node_id IS NOT NULL AND bracket_position IS NOT NULL
    DO UPDATE SET
        participant_a = CASE WHEN v_side_b
                             THEN public.tournament_matches.participant_a
                             ELSE p_participant END,
        participant_b = CASE WHEN v_side_b
                             THEN p_participant
                             ELSE public.tournament_matches.participant_b END,
        status = CASE
                   WHEN public.tournament_matches.status = 'scheduled'
                    AND (CASE WHEN v_side_b
                              THEN public.tournament_matches.participant_a
                              ELSE p_participant END) IS NOT NULL
                    AND (CASE WHEN v_side_b
                              THEN p_participant
                              ELSE public.tournament_matches.participant_b END) IS NOT NULL
                   THEN 'awaiting_results'
                   ELSE public.tournament_matches.status
                 END
    RETURNING participant_a, participant_b, status
      INTO v_next_a, v_next_b, v_next_st;
  END IF;

  -- T17: once the target match is fully filled (both slots, awaiting_results),
  -- materialise its round's schedule row from the TARGET round's TypeRound
  -- matchFormat. Idempotent (the helper is ON CONFLICT DO NOTHING).
  IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
     AND v_next_st = 'awaiting_results' THEN
    SELECT s.match_seconds, s.break_seconds, s.tiebreak_after
      INTO v_ms, v_bs, v_ta
      FROM public._tournament_schedule_type_graph_round_seconds(
             p_tournament_id, p_node_id, v_round, v_is_final) s;
    PERFORM public._tournament_upsert_round_schedule(
      p_tournament_id, p_node_id, v_round, v_phase, v_ms, v_bs, v_ta, now());
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public._tournament_type_graph_route_into(
  uuid, text, jsonb, text, text, uuid, int, int) TO authenticated;

COMMENT ON FUNCTION public._tournament_type_graph_route_into(
  uuid, text, jsonb, text, text, uuid, int, int) IS
  'ADR-0039 §6.6 (U10b; U10c T17/T18): route one participant into a type_graph '
  'target field. Resolves the target round/slot, computes the A/B slot from the '
  'edge declaration order, and UPSERTs the target match via ON CONFLICT on the '
  'unique partial index (no duplicate under concurrent feeders). The match '
  'carries the target round''s ko_tiebreak_method (T18); when both slots fill and '
  'the match flips to awaiting_results, its round''s schedule row is materialised '
  'from the target round''s TypeRound matchFormat (T17). Phase final iff the '
  'target is the lone field of the last round.';

-- ===================================================================
-- T15/T16 re-base: tournament_advance_ko_winner.
-- Verbatim from 20261305000000 (no behavioural change in the trigger itself —
-- the routing helper carries the T17/T18 additions). Re-stated here so this
-- migration's body is the authoritative latest definition.
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
            AND bracket_position = 1
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
              AND bracket_position = 1
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

COMMENT ON FUNCTION public.tournament_advance_ko_winner() IS
  'AFTER-UPDATE advance trigger (re-based from 20261305000000). ADR-0039 §6.6 '
  '(U10b): a match whose stage carries a valid config[type_graph] is routed along '
  'that graph''s field edges via _tournament_type_graph_route_into (which now '
  'carries the U10c T17 round-2+ schedule + T18 per-field ko_tiebreak), then the '
  'trigger RETURNs. A classic match (NULL type_graph) takes the existing '
  'single_elim / third-place / double_elim / consolation paths byte-for-byte.';

-- ===================================================================
-- T18 re-base: tournament_match_get.
-- Verbatim from 20261289000000 with ONE additive projection: ko_tiebreak_method
-- (the server-authoritative per-match method). The detail screen prefers this
-- value, so a type_graph KO match cannot be scored with a divergent method.
-- ===================================================================
CREATE OR REPLACE FUNCTION public.tournament_match_get(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_tournament   uuid;
  v_status       text;
  v_created_by   uuid;
  v_consensus    smallint;
  v_match        jsonb;
  v_proposals    jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT m.tournament_id, m.consensus_round, t.status, t.created_by
    INTO v_tournament, v_consensus, v_status, v_created_by
    FROM public.tournament_matches m
    JOIN public.tournaments t ON t.id = m.tournament_id
   WHERE m.id = p_match_id;
  IF v_tournament IS NULL THEN
    RETURN NULL;
  END IF;
  IF v_status = 'draft' AND v_created_by IS DISTINCT FROM v_caller THEN
    RETURN NULL;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'proposal_id',            pr.id,
           'set_number',             pr.set_number,
           'submitter_user_id',      pr.submitter_user_id,
           'basekubbs_knocked_by_a', pr.basekubbs_knocked_by_a,
           'basekubbs_knocked_by_b', pr.basekubbs_knocked_by_b,
           'set_winner',             pr.set_winner,
           'proposed_at',            pr.proposed_at
         ) ORDER BY pr.set_number, pr.proposed_at), '[]'::jsonb)
    INTO v_proposals
    FROM public.tournament_set_score_proposals pr
    WHERE pr.match_id = p_match_id
      AND pr.consensus_round = v_consensus;

  SELECT jsonb_build_object(
           'match_id',              m.id,
           'tournament_id',         m.tournament_id,
           'round_number',          m.round_number,
           'match_number_in_round', m.match_number_in_round,
           'participant_a_id',      m.participant_a,
           'participant_b_id',      m.participant_b,
           'participant_a_display_name',
             CASE WHEN pa.team_id IS NULL THEN upa.nickname
                  ELSE tma.display_name END,
           'participant_b_display_name',
             CASE WHEN pb.team_id IS NULL THEN upb.nickname
                  ELSE tmb.display_name END,
           'status',                m.status,
           'consensus_round',       m.consensus_round,
           'started_at',            m.started_at,
           'completed_at',          m.finalized_at,
           'winner_participant_id', m.winner_participant,
           'final_score_a',         m.final_score_a,
           'final_score_b',         m.final_score_b,
           'phase',                 m.phase,
           'stage_node_id',         m.stage_node_id,
           -- U10c (T18): the server-authoritative per-match KO tiebreak method
           -- (set from the match's TypeRound for a type_graph KO match, NULL for
           -- classic). The detail screen prefers this over a client-computed one.
           'ko_tiebreak_method',    m.ko_tiebreak_method,
           'set_score_proposals',   v_proposals
         )
    INTO v_match
    FROM public.tournament_matches m
    LEFT JOIN public.tournament_participants pa ON pa.id = m.participant_a
    LEFT JOIN public.user_profiles            upa ON upa.user_id = pa.user_id
    LEFT JOIN public.teams                    tma ON tma.id      = pa.team_id
    LEFT JOIN public.tournament_participants pb ON pb.id = m.participant_b
    LEFT JOIN public.user_profiles            upb ON upb.user_id = pb.user_id
    LEFT JOIN public.teams                    tmb ON tmb.id      = pb.team_id
    WHERE m.id = p_match_id;

  RETURN v_match;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_match_get(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_match_get(uuid) IS
  'Match-detail RPC (re-based 20261289000000). ADR-0039 §6.6 (U10c/T18) projects '
  'ko_tiebreak_method — the server-authoritative per-match KO tiebreak — so the '
  'detail screen uses the server value (set from the match''s TypeRound for a '
  'type_graph KO match) rather than computing one from the node config.';
