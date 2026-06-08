-- Tournament stage-graph runner trigger — ADR-0030 (§Runner-Semantik step 1
-- "close stage" + step 3 "join barrier / activate + generate target stages").
--
-- This is the AFTER-UPDATE orchestration trigger on public.tournament_matches.
-- It fires exactly on the transition of a STAGE-GRAPH match (stage_node_id NOT
-- NULL) into a terminal status and cascades the stage-graph forward:
--
--   1. If the just-terminal match's stage has ALL its matches terminal, the
--      stage is closed (status -> 'completed').
--   2. The completed stage is routed into its target stages' inputs via
--      public.tournament_route_completed_stage (fills tournament_stage_inputs,
--      idempotent ON CONFLICT DO NOTHING).
--   3. For every outgoing target Y, the JOIN BARRIER is checked: Y is activated
--      and its matches generated ONLY when ALL of Y's incoming source stages are
--      'completed' (not merely the source that just finished). Activation +
--      generation also require Y to still be 'pending' (per-target idempotency).
--
-- IMPORTANT INVARIANT: the FIRST stage (a stage with NO incoming edges) is NEVER
-- started by this runner. Bootstrapping the root stage (activating it +
-- generating its matches) is the job of a separate start-RPC (follow-up step).
-- The runner only CASCADES already-completed stages onward; it never boots the
-- graph. Consequently, without an external start the trigger never fires.
--
-- SECURITY DEFINER because the function writes tournament_stages.status and
-- (via the routing/generate building blocks) tournament_stage_inputs /
-- tournament_matches, none of which have a client-write RLS policy
-- (server-authoritative materialization — identical rationale to 20261223 /
-- 20261226 / 20261227). search_path = '' => every reference is fully
-- schema-qualified.

CREATE OR REPLACE FUNCTION public.tournament_run_stage_graph()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_all_terminal boolean;
  v_stage_status text;
  v_target       text;
  v_barrier_open boolean;
  v_seeded       uuid[];
BEGIN
  -- Guard A: a match without stage-graph binding is a classic preset match and
  -- is ignored. Redundant with the trigger WHEN clause, kept as in-function
  -- defensive.
  IF NEW.stage_node_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Guard B: is the WHOLE stage terminal? Aggregate over ALL matches of the
  -- stage (NEW itself is already committed-terminal and visible in this
  -- AFTER trigger). bool_and(...) = false => at least one non-terminal match
  -- remains, so the stage is not finished yet -> early return (no cascade).
  SELECT bool_and(m.status IN ('finalized','overridden','voided'))
    INTO v_all_terminal
    FROM public.tournament_matches m
    WHERE m.tournament_id = NEW.tournament_id
      AND m.stage_node_id = NEW.stage_node_id;

  IF NOT coalesce(v_all_terminal, false) THEN
    RETURN NEW;
  END IF;

  -- Guard C (stage idempotency): if the stage is already 'completed', a
  -- second firing (e.g. an 'overridden' correction of an already terminal
  -- stage match) must NOT re-route / re-generate -> early return.
  SELECT s.status
    INTO v_stage_status
    FROM public.tournament_stages s
    WHERE s.tournament_id = NEW.tournament_id
      AND s.node_id = NEW.stage_node_id;

  IF v_stage_status = 'completed' THEN
    RETURN NEW;
  END IF;

  -- Step 1: close the stage (active -> completed).
  UPDATE public.tournament_stages
    SET status = 'completed'
    WHERE tournament_id = NEW.tournament_id
      AND node_id = NEW.stage_node_id;

  -- Guard D (sink stage): a stage with NO outgoing edges is a terminal/leaf
  -- stage (typically the championship single_elim). It has nothing to route and
  -- nothing to cascade onward, so once closed we are done. Crucially we must NOT
  -- call the routing building block on it: routing reads
  -- tournament_stage_ranking, whose single_elim path delegates to
  -- skv_single_elim_placements, which RAISES for small brackets (e.g.
  -- 'koRankCount must be in 4..2' for a 2-player final). That exception would
  -- propagate out of this AFTER trigger and ABORT the very UPDATE that finalized
  -- the championship match. Routing a sink stage is meaningless anyway, so skip
  -- it entirely and return.
  PERFORM 1
    FROM public.tournament_stage_edges e
    WHERE e.tournament_id = NEW.tournament_id
      AND e.from_node_id = NEW.stage_node_id
    LIMIT 1;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- Step 2: route the completed stage's participants into its targets' inputs
  -- (idempotent via ON CONFLICT DO NOTHING inside the building block).
  PERFORM public.tournament_route_completed_stage(NEW.tournament_id, NEW.stage_node_id);

  -- Step 3: for every distinct outgoing target of THIS stage, check the join
  -- barrier and (if open and the target is still pending) activate + generate.
  FOR v_target IN
    SELECT DISTINCT e.to_node_id
      FROM public.tournament_stage_edges e
      WHERE e.tournament_id = NEW.tournament_id
        AND e.from_node_id = NEW.stage_node_id
  LOOP
    -- Join barrier: Y may be activated only when ALL distinct source stages of
    -- edges WITH to_node_id = Y are 'completed' (not just the source that just
    -- finished). With a single incoming edge this is trivially satisfied.
    SELECT bool_and(s.status = 'completed')
      INTO v_barrier_open
      FROM public.tournament_stage_edges e
      JOIN public.tournament_stages s
        ON s.tournament_id = e.tournament_id
       AND s.node_id = e.from_node_id
      WHERE e.tournament_id = NEW.tournament_id
        AND e.to_node_id = v_target;

    -- Pending guard: only a still-'pending' target is activated/generated.
    -- This is the second idempotency barrier (an already active/completed Y is
    -- not re-generated).
    SELECT s.status
      INTO v_stage_status
      FROM public.tournament_stages s
      WHERE s.tournament_id = NEW.tournament_id
        AND s.node_id = v_target;

    IF coalesce(v_barrier_open, false) AND v_stage_status = 'pending' THEN
      -- Read the seed-ordered routed inputs for Y (ordinal is 1-based per
      -- target). Read BEFORE flipping status so an empty target is not left
      -- half-activated.
      SELECT array_agg(i.participant_id ORDER BY i.ordinal)
        INTO v_seeded
        FROM public.tournament_stage_inputs i
        WHERE i.tournament_id = NEW.tournament_id
          AND i.target_node_id = v_target;

      -- Defensive empty seeding: a target with no inputs is NOT activated and
      -- NOT generated (it stays 'pending'). Calling the generator with an empty
      -- array would raise INVALID_PARTICIPANT and abort the triggering UPDATE,
      -- so the generator must not even be called in that case.
      IF coalesce(array_length(v_seeded, 1), 0) >= 1 THEN
        UPDATE public.tournament_stages
          SET status = 'active'
          WHERE tournament_id = NEW.tournament_id
            AND node_id = v_target;

        PERFORM public.tournament_generate_stage_matches(
          NEW.tournament_id, v_target, v_seeded);
      END IF;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

-- WHEN gating mirrors the existing AFTER-UPDATE triggers
-- (tournament_write_match_elo / tournament_advance_ko_winner): only the
-- TRANSITION into terminal fires (OLD non-terminal -> NEW terminal). Extension
-- over the reference triggers: 'voided' is added to BOTH lists, because a stage
-- match can also become terminal by voiding and the stage may then be complete.
-- The NEW.stage_node_id IS NOT NULL predicate keeps the trigger off classic
-- preset matches at the WHEN level.
DROP TRIGGER IF EXISTS tournament_run_stage_graph ON public.tournament_matches;
CREATE TRIGGER tournament_run_stage_graph
  AFTER UPDATE ON public.tournament_matches
  FOR EACH ROW
  WHEN (
    OLD.status NOT IN ('finalized','overridden','voided')
    AND NEW.status     IN ('finalized','overridden','voided')
    AND NEW.stage_node_id IS NOT NULL
  )
  EXECUTE FUNCTION public.tournament_run_stage_graph();

COMMENT ON FUNCTION public.tournament_run_stage_graph() IS
  'AFTER-UPDATE stage-graph runner (ADR-0030 §Runner-Semantik step 1 close-stage '
  '+ step 3 cascade). Fires when a stage-graph match (stage_node_id NOT NULL) '
  'transitions into terminal (finalized/overridden/voided). When ALL of the '
  'stage''s matches are terminal it closes the stage (-> completed), routes it '
  'via tournament_route_completed_stage, and for every outgoing target Y checks '
  'the JOIN BARRIER (ALL of Y''s incoming source stages completed) plus the '
  'pending-guard before activating Y and generating its matches via '
  'tournament_generate_stage_matches with the seed-ordered tournament_stage_inputs. '
  'Idempotent twice over: the stage-completed guard skips re-routing, and the '
  'per-target pending-guard (plus ON CONFLICT inputs and the generator''s '
  'STAGE_ALREADY_GENERATED) prevents re-generation. A target with empty inputs '
  'stays pending and is not generated. A SINK stage (no OUTGOING edges, e.g. the '
  'championship single_elim) is only closed (-> completed): routing/cascade is '
  'skipped, because tournament_route_completed_stage would invoke the single_elim '
  'ranking path (skv_single_elim_placements raises for small brackets) and abort '
  'the championship-finalizing UPDATE. INVARIANT: the FIRST stage (no incoming '
  'edges) is NEVER started by this runner — booting the root stage is a separate '
  'start-RPC; the runner only cascades already-completed stages onward. '
  'SECURITY DEFINER because it writes tournament_stages / tournament_stage_inputs '
  '/ tournament_matches, which have no client-write RLS policy.';
