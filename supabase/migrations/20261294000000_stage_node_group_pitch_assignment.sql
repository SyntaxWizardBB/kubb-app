-- Stage-graph group stages: apply the per-group pitch assignment stored on the
-- node config (group_pitch_assignment) to the generated group matches.
--
-- The stage generator (tournament_generate_stage_matches) inserts every group
-- match with pitch_number = 1 as a placeholder. The classic pool path runs
-- _tournament_assign_pitches (20261201000003) off tournaments.pitch_plan, but
-- the stage-graph path stores its pitch layout per node, in
-- tournament_stages.config -> 'group_pitch_assignment' (a map
-- { "A": [1,2], "B": [3] } of group label -> pitch numbers; mirror of the Dart
-- poolGroupPitchAssignmentFromConfig reader). Nothing read that map at runtime,
-- so stage-graph group matches kept pitch_number = 1.
--
-- This migration adds _tournament_assign_pitches_from_stage_node and wires it
-- into the two paths that materialise a stage:
--   * tournament_start_stage_graph (root boot loop) — re-stated from its latest
--     body (20261281000000_gate_split.sql).
--   * tournament_run_stage_graph (AFTER-UPDATE cascade) — re-stated from its
--     latest body (20261228000000_tournament_stage_runner.sql).
--
-- Coexistence: the classic single-tournament path keeps using
-- tournaments.pitch_plan via _tournament_assign_pitches. The stage-graph path
-- uses the node config. The new helper only ever touches matches that carry a
-- stage_node_id, and only when that node has a group_pitch_assignment, so the
-- two layouts never mix.
--
-- The new helper self-guards: absent / empty group_pitch_assignment -> no-op,
-- so it is safe to call after EVERY tournament_generate_stage_matches, for any
-- stage type. Non-group stages have no such key and are left untouched.

-- ── 1. _tournament_assign_pitches_from_stage_node ─────────────────────────
--
-- Mirror of the per-group branch of _tournament_assign_pitches, but the pitch
-- source is tournament_stages.config -> 'group_pitch_assignment' for THIS node
-- instead of tournaments.pitch_plan -> 'group_assignment'.
--
-- Per group_label: take the group's assigned pitch list (in the list's own
-- order), rank the group's matches by match_number_in_round (the natural
-- "strongest pairing first" order the generator emits — group matches carry no
-- bracket_position, so this matches the classic helper's
-- coalesce(bracket_position, match_number_in_round) ordering), then assign
-- pitch[(rn - 1) % len + 1] round-robin. A group with no entry in the map keeps
-- the placeholder pitch_number. Matches with NULL group_label (a single flat
-- group) are never touched: the node config is keyed per group.
CREATE OR REPLACE FUNCTION public._tournament_assign_pitches_from_stage_node(
  p_tournament_id uuid,
  p_node_id       text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_assignment jsonb;
BEGIN
  SELECT config -> 'group_pitch_assignment'
    INTO v_assignment
    FROM public.tournament_stages
    WHERE tournament_id = p_tournament_id
      AND node_id = p_node_id;

  -- No (or malformed) assignment -> leave the placeholder pitch_number = 1.
  IF v_assignment IS NULL OR jsonb_typeof(v_assignment) <> 'object' THEN
    RETURN;
  END IF;

  WITH lists AS (
    -- Per group label: the assigned pitch list in its own (ordinal) order.
    SELECT g.key AS group_label,
           (
             SELECT coalesce(
                      array_agg((e.val #>> '{}')::int ORDER BY e.ord)
                        FILTER (WHERE jsonb_typeof(e.val) = 'number'),
                      ARRAY[]::int[])
               FROM jsonb_array_elements(g.value)
                    WITH ORDINALITY AS e(val, ord)
           ) AS pitches
      FROM jsonb_each(v_assignment) AS g(key, value)
     WHERE jsonb_typeof(g.value) = 'array'
  ),
  ranked AS (
    SELECT m.id,
           m.group_label,
           row_number() OVER (
             PARTITION BY m.group_label
             ORDER BY m.match_number_in_round
           ) AS rn
      FROM public.tournament_matches m
      WHERE m.tournament_id = p_tournament_id
        AND m.stage_node_id = p_node_id
        AND m.group_label IS NOT NULL
  )
  UPDATE public.tournament_matches t
     SET pitch_number =
           l.pitches[ ((r.rn - 1) % array_length(l.pitches, 1)) + 1 ]
    FROM ranked r
    JOIN lists l ON l.group_label = r.group_label
   WHERE t.id = r.id
     AND array_length(l.pitches, 1) IS NOT NULL;  -- empty list -> skip group
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public._tournament_assign_pitches_from_stage_node(uuid, text) FROM PUBLIC;

COMMENT ON FUNCTION
  public._tournament_assign_pitches_from_stage_node(uuid, text) IS
  'Applies tournament_stages.config -> group_pitch_assignment (group label -> '
  'pitch numbers) to the stage node''s generated group matches: per group, rank '
  'matches by match_number_in_round and round-robin over the group''s pitch '
  'list. No-op when the node has no group_pitch_assignment. Stage-graph mirror '
  'of the per-group branch of _tournament_assign_pitches (source is the node '
  'config, not tournaments.pitch_plan).';


-- ── 2. tournament_start_stage_graph — assign pitches per booted root ──────
--
-- Re-stated verbatim from 20261281000000_gate_split.sql with one line added in
-- the root boot loop (marked STAGE-PITCH): after a root stage's matches are
-- generated, apply its node group_pitch_assignment.
CREATE OR REPLACE FUNCTION public.tournament_start_stage_graph(p_tournament_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller       uuid;
  v_status       text;
  v_created_by   uuid;
  v_stage_count  int;
  v_unknown_node text;
  v_has_cycle    boolean;
  v_root_count   int;
  v_roots        text[];
  v_root_node    text;
  v_seeded       uuid[];
  v_booted       text[] := ARRAY[]::text[];
BEGIN
  -- 1. Auth gate.
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- 2. Load + lock the tournament (not-found OR not-authorised => one 42501).
  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;

  -- 3. Status gate: only non-terminal pre-live stati are startable.
  IF v_status NOT IN ('published', 'registration_open', 'registration_closed', 'draft') THEN
    RAISE EXCEPTION 'tournament is not in a startable status' USING ERRCODE = '22023';
  END IF;

  -- 4. NO_STAGES.
  SELECT count(*) INTO v_stage_count
    FROM public.tournament_stages
    WHERE tournament_id = p_tournament_id;
  IF v_stage_count = 0 THEN
    RAISE EXCEPTION 'NO_STAGES: tournament has no stages' USING ERRCODE = '22023';
  END IF;

  -- 5. UNKNOWN_NODE: every edge endpoint must reference an existing stage.
  SELECT missing INTO v_unknown_node
    FROM (
      SELECT e.from_node_id AS missing
        FROM public.tournament_stage_edges e
        WHERE e.tournament_id = p_tournament_id
          AND NOT EXISTS (
            SELECT 1 FROM public.tournament_stages s
             WHERE s.tournament_id = p_tournament_id
               AND s.node_id = e.from_node_id)
      UNION ALL
      SELECT e.to_node_id AS missing
        FROM public.tournament_stage_edges e
        WHERE e.tournament_id = p_tournament_id
          AND NOT EXISTS (
            SELECT 1 FROM public.tournament_stages s
             WHERE s.tournament_id = p_tournament_id
               AND s.node_id = e.to_node_id)
    ) q
    LIMIT 1;
  IF v_unknown_node IS NOT NULL THEN
    RAISE EXCEPTION 'UNKNOWN_NODE: edge references node % which is not a stage', v_unknown_node
      USING ERRCODE = '22023';
  END IF;

  -- 6. CYCLE: recursive-CTE detection with a path accumulator.
  WITH RECURSIVE walk(node, path, is_cycle) AS (
    SELECT s.node_id, ARRAY[s.node_id], false
      FROM public.tournament_stages s
      WHERE s.tournament_id = p_tournament_id
    UNION ALL
    SELECT e.to_node_id,
           w.path || e.to_node_id,
           e.to_node_id = ANY(w.path)
      FROM walk w
      JOIN public.tournament_stage_edges e
        ON e.tournament_id = p_tournament_id
       AND e.from_node_id = w.node
      WHERE NOT w.is_cycle
  )
  SELECT bool_or(is_cycle) INTO v_has_cycle FROM walk;
  IF coalesce(v_has_cycle, false) THEN
    RAISE EXCEPTION 'CYCLE: stage graph contains a cycle' USING ERRCODE = '22023';
  END IF;

  -- 7. ROOTS: all stages with no incoming edge. >=1 required (0 only via a
  --    cycle, already reported). Multiple roots are now allowed (F3).
  SELECT array_agg(s.node_id ORDER BY s.node_id) INTO v_roots
    FROM public.tournament_stages s
    WHERE s.tournament_id = p_tournament_id
      AND NOT EXISTS (
        SELECT 1 FROM public.tournament_stage_edges e
         WHERE e.tournament_id = p_tournament_id
           AND e.to_node_id = s.node_id);

  v_root_count := coalesce(array_length(v_roots, 1), 0);
  IF v_root_count = 0 THEN
    RAISE EXCEPTION 'NO_ROOT: no stage without an incoming edge' USING ERRCODE = '22023';
  END IF;

  -- 8. Idempotency: if ANY root is already started (active/completed or has
  --    matches), the whole start is a no-op error.
  IF EXISTS (
    SELECT 1
      FROM public.tournament_stages s
      WHERE s.tournament_id = p_tournament_id
        AND s.node_id = ANY(v_roots)
        AND (
          s.status IN ('active', 'completed')
          OR EXISTS (
            SELECT 1 FROM public.tournament_matches m
             WHERE m.tournament_id = p_tournament_id
               AND m.stage_node_id = s.node_id)
        )
  ) THEN
    RAISE EXCEPTION 'ALREADY_STARTED: a root stage is already started' USING ERRCODE = '22023';
  END IF;

  -- 9. The full confirmed field (index 0 = seed 1) — every root is fed this
  --    field. 'approved' is inert in this schema (only 'confirmed' matches);
  --    kept for forward-compat.
  SELECT array_agg(tp.id ORDER BY tp.seed NULLS LAST, tp.id) INTO v_seeded
    FROM public.tournament_participants tp
    WHERE tp.tournament_id = p_tournament_id
      AND tp.registration_status IN ('confirmed', 'approved');

  IF v_seeded IS NULL OR array_length(v_seeded, 1) IS NULL THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: no confirmed participants' USING ERRCODE = '22023';
  END IF;

  -- 10. Boot every root with the full field.
  FOREACH v_root_node IN ARRAY v_roots LOOP
    PERFORM public.tournament_generate_stage_matches(p_tournament_id, v_root_node, v_seeded);

    -- STAGE-PITCH: apply the node's group_pitch_assignment to the freshly
    -- generated group matches (no-op for non-group nodes / no assignment).
    PERFORM public._tournament_assign_pitches_from_stage_node(p_tournament_id, v_root_node);

    UPDATE public.tournament_stages
      SET status = 'active'
      WHERE tournament_id = p_tournament_id
        AND node_id = v_root_node;

    v_booted := v_booted || v_root_node;
  END LOOP;

  -- 11. Tournament goes live (mirror tournament_start).
  UPDATE public.tournaments
    SET status = 'live', started_at = now()
    WHERE id = p_tournament_id;

  -- 12. Audit.
  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'stage_graph_started',
      v_caller,
      jsonb_build_object('root_nodes', to_jsonb(v_booted)));

  RETURN array_to_string(v_booted, ',');
END;
$function$
;


-- ── 3. tournament_run_stage_graph — assign pitches per cascaded target ────
--
-- Re-stated verbatim from 20261228000000_tournament_stage_runner.sql (its only
-- and latest definition) with one line added after the cascade generator call
-- (marked STAGE-PITCH). Downstream group stages activated by the cascade now
-- also get their node group_pitch_assignment applied. The trigger itself
-- (tournament_run_stage_graph ON tournament_matches) is unchanged and is left
-- in place — only the function body is replaced.
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

        -- STAGE-PITCH: apply the cascaded target node's group_pitch_assignment
        -- to its freshly generated group matches (no-op otherwise).
        PERFORM public._tournament_assign_pitches_from_stage_node(
          NEW.tournament_id, v_target);
      END IF;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;
