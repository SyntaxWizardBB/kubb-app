-- Stage KO slot index gains a phase column — ADR-0039 §6.6 follow-up (Unit 8b A/B).
--
-- Context. tournament_matches_stage_slot_uq (20261306000000:73) is the U10c
-- concurrency hardening behind the type_graph round-2+ ON-CONFLICT upsert. Its
-- columns are (tournament_id, stage_node_id, round_number, bracket_position)
-- WHERE stage_node_id IS NOT NULL AND bracket_position IS NOT NULL. That shape
-- assumes ONE row per (stage, round, slot) — true for a type_graph KO field and
-- a single_elim stage bracket, but FALSE for a double_elim stage bracket: the
-- DE generator emits (round 1, bracket_position 1) THREE TIMES — once per phase
-- (wb / lb / grand_final) — so materialising a double_elim stage trips 23505.
--
-- Fix. Drop and recreate the index WITH phase as a fifth column. The slot is now
-- unique per (tournament, stage, round, position, PHASE), which:
--   * lets the DE generator emit the three phase-distinct rows of a slot;
--   * keeps the U10c duplicate-race closed — two feeders into the SAME field
--     (same tournament/stage/round/position AND same phase, since a type_graph
--     field carries exactly one phase per slot) still collide to one row, so the
--     ON-CONFLICT upsert still serialises them (the race U10b/U10c guards);
--   * does not collide with existing data — a schoch vorrunde / group match has
--     bracket_position NULL (excluded by the partial predicate), and the
--     single_elim stage KO rows keep one phase per (round, position) so adding
--     phase cannot split or merge any existing key.
--
-- _tournament_type_graph_route_into's ON CONFLICT target must match the new
-- index columns or the inference fails ("no unique constraint matching ON
-- CONFLICT"); it is re-based here from 20261306000000 with phase added to the
-- conflict target and nothing else changed (round-2+ routing/scheduling from
-- U10b/U10c stays byte-identical — a type_graph KO match's phase is 'ko' or
-- 'final', a fixed value per slot, so the wider target lands on the same row).

-- ===================================================================
-- A) Phase-inclusive unique partial index.
-- ===================================================================
DROP INDEX IF EXISTS public.tournament_matches_stage_slot_uq;

CREATE UNIQUE INDEX IF NOT EXISTS tournament_matches_stage_slot_uq
  ON public.tournament_matches
     (tournament_id, stage_node_id, round_number, bracket_position, phase)
  WHERE stage_node_id IS NOT NULL AND bracket_position IS NOT NULL;

-- ===================================================================
-- B) _tournament_type_graph_route_into — re-based verbatim from
-- 20261306000000 with ONE change: the first-feeder INSERT's ON CONFLICT target
-- gains `phase` so it matches the 5-column index. The DO UPDATE body, the
-- side-A/B resolution, the schedule/tiebreak tail (T17/T18) and idempotency are
-- byte-identical to 20261306000000.
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
    -- slot instead of inserting a duplicate (U10b hardening). The conflict
    -- target carries phase to match the 5-column index (20261315000000); a
    -- type_graph KO slot's phase is a fixed value, so the target lands on the
    -- same row the 4-column index used to.
    INSERT INTO public.tournament_matches(
        tournament_id, stage_node_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b, phase, status,
        pitch_number, ko_tiebreak_method)
    VALUES (
        p_tournament_id, p_node_id, v_round::smallint, v_slot::smallint, v_slot,
        CASE WHEN v_side_b THEN NULL ELSE p_participant END,
        CASE WHEN v_side_b THEN p_participant ELSE NULL END,
        v_phase, 'scheduled', 1, v_tiebreak)
    ON CONFLICT (tournament_id, stage_node_id, round_number, bracket_position, phase)
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
  'ADR-0039 §6.6 (U10b; U10c T17/T18; Unit 8b): route one participant into a '
  'type_graph target field. Re-based from 20261306000000 with the ON CONFLICT '
  'target widened to the 5-column phase-inclusive index '
  '(tournament_matches_stage_slot_uq). Resolves target round/slot, computes the '
  'A/B slot from edge order, UPSERTs the target match (no duplicate under '
  'concurrent feeders), carries the target round''s ko_tiebreak_method, and '
  'materialises the round schedule from the target TypeRound matchFormat when '
  'both slots fill. Behaviour otherwise byte-identical to 20261306000000.';
