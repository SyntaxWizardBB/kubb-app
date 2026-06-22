-- Tournament — ADR-0039 §6.6 (U10b, T15/T16): winner-advance + loser-route along
-- the FIELD EDGES of a stage's config['type_graph'].
--
-- U10a (20261304000000) materialised ROUND 1 of a type_graph stage. Round 2+ was
-- left to U10b: when a match of a type_graph stage is finalised, push its winner
-- along the matching WinnerEdge and its loser along the matching LoserEdge into
-- the target field's match (round 2+). Round 2+ matches are not pre-materialised
-- by the round-1 materializer, so the target match is UPSERTED here: the first
-- feeder of a target field INSERTS it (filling slot A/B by edge order), the
-- second feeder fills the remaining slot and flips scheduled -> awaiting_results.
--
-- This migration re-bases tournament_advance_ko_winner (verbatim live body) with
-- ONE additive branch at the very top of the dispatch: when the NEW match's
-- stage carries a valid config['type_graph'], do the edge-based routing and
-- RETURN NEW — the type-fixed single_elim / double_elim / consolation paths
-- below are never entered for a type_graph match. A match WITHOUT a type_graph
-- stage takes exactly the existing paths, byte-for-byte (the new branch is a
-- pre-dispatch guard that no classic match can satisfy).
--
-- Slot geometry: a target field's incoming participants are ranked by the
-- declaration order of the edges (winner OR loser) whose to_field_id is that
-- field. Rank 1 -> slot A, rank 2 -> slot B. For the canonical halving KO graph
-- this is exactly the two WinnerEdges feeding a round-2 field (R1F1 -> A,
-- R1F2 -> B). A side-cup field fed by two LoserEdges slots the same way.
--
-- T15 winner: the source field's WinnerEdge.to_field_id resolves the target
-- field (its round_number/slot). The winner is written into the edge-ranked slot
-- of that target match; both slots filled + scheduled -> awaiting_results, reusing
-- the live (bp+1)/2 promote idiom (slot here comes from the edge rank, not the
-- implicit bracket halving).
--
-- T16 loser: the source field's LoserEdge.to_field_id routes the loser into its
-- target field's match (e.g. a Neben-Cup). An OpenEdge on the loser slot, or no
-- loser edge at all, means the loser drops out — no routing, exactly like today's
-- KO loser without a third-place playoff.
--
-- Round 2+ scheduling (the round_schedule row + timing) and server-authoritative
-- ko_tiebreak are U10c/T17/T18 and are NOT touched here: the upserted target match
-- is created status 'scheduled' with no schedule row; the match_autostart trigger
-- no-ops without one (its documented COALESCE backstop stays in play).

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
  -- DE locals:
  v_wb_count        int;
  v_size            int;
  v_lb_count        int;
  v_lb_target_round int;
  v_lb_slot0        int;
  v_lb_target_pos   int;
  v_lb_side_b       boolean;
  v_with_reset      boolean;
  v_gf_round        int;
  -- CONSOLATION (E2) locals:
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
  -- P6-FIX C9 locals:
  v_next_matches    int;       -- pairings in the next consolation round
  v_next_lr         int;       -- L_{next} fed losers into the next cons round
  -- U10b (type_graph) locals:
  v_graph           jsonb;     -- the stage's config['type_graph'] (or NULL)
  v_src_field       text;      -- source field id of the NEW match
  v_tg_to_field     text;      -- resolved target field id (winner/loser edge)
  v_tg_round        int;       -- target field round_number
  v_tg_slot         int;       -- target field slot (= bracket_position)
  v_tg_rank         int;       -- 1-based edge rank into the target field (A/B)
  v_tg_side_b       boolean;   -- rank 2 -> B-slot
  v_tg_last_round   int;       -- highest round_number in the graph
  v_tg_final_fields int;       -- field count of the last round
  v_tg_phase        text;      -- 'final' iff target is the lone last-round field
  v_tg_exists       boolean;   -- target match already materialised?
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
  -- U10b (ADR-0039 §6.6): TYPE-GRAPH ROUTING.
  -- A match whose stage carries a valid config['type_graph'] is advanced along
  -- that graph's field edges instead of the type-fixed bracket geometry. This is
  -- a pre-dispatch guard: a classic match (NULL type_graph) never enters here, so
  -- the type-fixed paths below stay byte-for-byte. The branch RETURNs at its end.
  -- =====================================================================
  IF NEW.stage_node_id IS NOT NULL THEN
    SELECT s.config -> 'type_graph'
      INTO v_graph
      FROM public.tournament_stages s
      WHERE s.tournament_id = NEW.tournament_id
        AND s.node_id = NEW.stage_node_id;
  END IF;

  IF v_graph IS NOT NULL AND public._stage_type_graph_is_valid(v_graph) THEN
    -- Source field: the graph field at the NEW match's (round_number, slot).
    -- The materializer slots round-1 field slot == bracket_position; round 2+
    -- target matches are upserted below carrying the same slot == bracket_position.
    SELECT f ->> 'id'
      INTO v_src_field
      FROM jsonb_array_elements(v_graph -> 'rounds') AS r
      CROSS JOIN jsonb_array_elements(r -> 'fields') AS f
      WHERE (f ->> 'round_number')::int = NEW.round_number
        AND (f ->> 'slot')::int = NEW.bracket_position
      LIMIT 1;

    IF v_src_field IS NOT NULL THEN
      -- The graph's last round + its field count, for the target phase tag.
      SELECT max((r ->> 'round_number')::int)
        INTO v_tg_last_round
        FROM jsonb_array_elements(v_graph -> 'rounds') AS r;
      SELECT jsonb_array_length(r -> 'fields')
        INTO v_tg_final_fields
        FROM jsonb_array_elements(v_graph -> 'rounds') AS r
        WHERE (r ->> 'round_number')::int = v_tg_last_round
        LIMIT 1;

      -- ── T15 winner: follow the source field's WinnerEdge ───────────────
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

      -- ── T16 loser: follow the source field's LoserEdge (if any) ────────
      -- No loser edge / an OpenEdge on the loser slot -> the loser drops out.
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
        -- MAJOR (fresh-feed) round: survivor maps 1:1 into the A-slot.
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

        -- P6-FIX C9: if this MAJOR next-round match's B-slot is a structural
        -- bye (never fed by a staggered main loser), resolve it kampflos so the
        -- AFTER-UPDATE trigger fires recursively and the bye survivor advances.
        -- The fed B-slots are the top (high-index) L_{next} pairings; the unfed
        -- bye pairings are the low-index 1..(matches_next - L_next). L_{next} =
        -- mainSize / 2^v_next_round (number of main round-(v_next_round) matches,
        -- which is also the count of consolation losers fed into that round).
        IF v_is_odd AND v_next_a IS NOT NULL AND v_next_b IS NULL THEN
          SELECT count(*) INTO v_next_matches
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = v_next_round;
          v_next_lr := v_main_size / (1 << v_next_round);
          IF v_next_position <= (v_next_matches - v_next_lr) THEN
            -- Structural bye: A advances kampflos. Set status 'scheduled' ->
            -- 'finalized' transition so the trigger re-fires for this row.
            UPDATE public.tournament_matches
              SET participant_a      = v_next_a,
                  winner_participant = v_next_a,
                  status             = 'finalized',
                  finalized_at       = now()
              WHERE tournament_id = NEW.tournament_id
                AND phase = 'consolation'
                AND round_number = v_next_round
                AND bracket_position = v_next_position;
            -- Skip the normal scheduled/awaiting update for this row.
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

-- ===================================================================
-- U10b helper: route ONE participant into a type_graph target field.
-- Resolves the target field's round_number/slot, computes the A/B slot from the
-- edge declaration order into that field (rank 1 -> A, rank 2 -> B), and upserts
-- the target match: the first feeder INSERTs it (status scheduled), the second
-- feeder fills the remaining slot and flips scheduled -> awaiting_results when
-- both participants are present. Idempotent on the participant: re-writing the
-- same slot with the same participant is a no-op-by-value.
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
  v_next_a   uuid;
  v_next_b   uuid;
  v_next_st  text;
  v_found    boolean;
BEGIN
  -- Target field geometry: its round_number and slot (= bracket_position).
  SELECT (f ->> 'round_number')::int, (f ->> 'slot')::int
    INTO v_round, v_slot
    FROM jsonb_array_elements(p_graph -> 'rounds') AS r
    CROSS JOIN jsonb_array_elements(r -> 'fields') AS f
    WHERE f ->> 'id' = p_to_field
    LIMIT 1;

  IF v_round IS NULL THEN
    RETURN;  -- malformed edge: target field absent. Drop silently.
  END IF;

  -- A/B slot: rank of the SOURCE field's edge among all edges (winner OR loser)
  -- feeding the target field, in declaration order. Rank 1 -> A, rank 2 -> B.
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

  -- Phase tag mirrors the round-1 materializer: 'final' iff the target is the
  -- lone field of the graph's last round, else 'ko'.
  v_phase := CASE
    WHEN v_round = p_last_round AND coalesce(p_final_fields, 1) = 1
    THEN 'final' ELSE 'ko' END;

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
    -- First feeder: materialise the target match with this participant slotted.
    INSERT INTO public.tournament_matches(
        tournament_id, stage_node_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b, phase, status, pitch_number)
    VALUES (
        p_tournament_id, p_node_id, v_round::smallint, v_slot::smallint, v_slot,
        CASE WHEN v_side_b THEN NULL ELSE p_participant END,
        CASE WHEN v_side_b THEN p_participant ELSE NULL END,
        v_phase, 'scheduled', 1);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public._tournament_type_graph_route_into(
  uuid, text, jsonb, text, text, uuid, int, int) TO authenticated;

COMMENT ON FUNCTION public._tournament_type_graph_route_into(
  uuid, text, jsonb, text, text, uuid, int, int) IS
  'ADR-0039 §6.6 (U10b): route one participant (a field winner or loser) into a '
  'type_graph target field. Resolves the target field round/slot, computes the '
  'A/B slot from the edge declaration order into that field (rank 1 -> A, rank 2 '
  '-> B), and upserts the target match: first feeder INSERTs it (scheduled), the '
  'second feeder fills the other slot and flips scheduled -> awaiting_results. '
  'Phase final iff the target is the lone field of the last round.';

COMMENT ON FUNCTION public.tournament_advance_ko_winner() IS
  'AFTER-UPDATE advance trigger (re-based from 20261204000000). ADR-0039 §6.6 '
  '(U10b): a match whose stage carries a valid config[type_graph] is routed along '
  'that graph''s field edges — winner along the WinnerEdge, loser along the '
  'LoserEdge (no loser edge / OpenEdge -> loser drops out) — into the target '
  'field''s match (upserted for round 2+), then the trigger RETURNs. A classic '
  'match (NULL type_graph) takes the existing single_elim / third-place / '
  'double_elim / consolation paths byte-for-byte.';
