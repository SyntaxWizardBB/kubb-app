-- Tournament stage-graph BOOT RPC — multi-root support (System 3 F3).
--
-- CREATE OR REPLACE of public.tournament_start_stage_graph (20261229000000)
-- to boot a graph with MORE THAN ONE root. Everything up to the root check
-- (auth/manage gate, status gate, NO_STAGES, UNKNOWN_NODE, CYCLE) is
-- preserved verbatim; only the root handling and boot loop change:
--
--   * The MULTIPLE_ROOTS error is removed. NO_ROOT (0 roots, only reachable
--     with a cycle) is kept.
--   * Every root stage is booted with the FULL confirmed field. This is the
--     validation capacity model (stage_validation.dart _checkCapacities:
--     "roots with no incoming edge are entry stages fed by the full field").
--     Per-root field partitioning (divisional splits) is intentionally NOT
--     done here: tournament_stage_inputs requires a source_node_id and is the
--     runner's ROUTED-input channel, so there is no schema mechanism to
--     pre-seed a root with a subset; that is a future feature.
--   * Idempotency: if ANY root is already active/completed or already has
--     matches, the whole start raises ALREADY_STARTED (unchanged token).
--   * Returns a comma-joined list of the booted root node_ids (a single root
--     returns just its node_id, so the single-root contract is unchanged).
--
-- Distinct from the trigger tournament_run_stage_graph (advance/routing).

CREATE OR REPLACE FUNCTION public.tournament_start_stage_graph(p_tournament_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
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
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
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
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start_stage_graph(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_start_stage_graph(uuid) IS
  'ADR-0030 §Validierung-Gate + §Runner: boot a stage-graph tournament. Manage '
  'gate (42501) + startable-status gate (22023). Structural server gate raises '
  '22023 with a CODE token: NO_STAGES / UNKNOWN_NODE / CYCLE / NO_ROOT; order '
  'NO_STAGES->UNKNOWN_NODE->CYCLE->ROOT. Boots EVERY root (F3 multi-root): each '
  'root is fed the full confirmed field (validation capacity model: roots are '
  'entry stages fed by the full field). Sets each root active + tournament live + started_at, '
  'audits kind=stage_graph_started with root_nodes. Idempotent: ALREADY_STARTED '
  '(22023) if any root already started. Returns the booted root node_ids '
  'comma-joined (single root => its node_id). Distinct from the trigger '
  'tournament_run_stage_graph (advance/routing engine).';
