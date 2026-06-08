-- Tournament stage-graph BOOT RPC — ADR-0030 (§Validierung & Spielbarkeits-Gate
-- + §Runner).
--
-- `tournament_start_stage_graph(p_tournament_id)` is the START-RPC that boots a
-- stage-graph tournament: it runs the structural server-side validation gate
-- (ADR-0030 §Validierung — an ERROR here blocks the start) and then boots the
-- single root stage via the runner's materializer
-- `tournament_generate_stage_matches` (ADR-0030 §Runner: "die erste Stufe wird
-- per Start-RPC gebootet"). On success the tournament goes 'live' and the
-- booted root `node_id` is returned.
--
-- This RPC is DISTINCT from the already-existing trigger function
-- `tournament_run_stage_graph()` (the routing/advance engine) — that one is
-- NOT touched here.
--
-- Auth / manage gate (mirrors tournament_start / tournament_finalize):
--   * auth.uid() must be present (else 42501 'authentication required').
--   * caller must pass public.tournament_caller_can_manage(p_tournament_id);
--     not-found and not-authorised collapse into one 42501 by design
--     ('tournament not found or not authorised') — no existence oracle.
--
-- Status gate: only the NON-TERMINAL PRE-LIVE stati of
-- tournaments_status_check are startable. That check list is
-- {draft, published, registration_open, registration_closed, live, finalized,
-- aborted}; pre-live non-terminal = {draft, published, registration_open,
-- registration_closed}. The brief names published/registration_closed/draft;
-- registration_open is the remaining non-terminal pre-live status and is
-- included for completeness. The started/terminal stati (live/finalized/
-- aborted) raise 22023 'tournament is not in a startable status' — so a
-- tournament that is already 'live' is not re-startable via the status gate,
-- complementing the §10 ALREADY_STARTED idempotency guard.
--
-- Structural server gate (each a distinct ERROR; ERRCODE 22023, the MESSAGE
-- carries a stable CODE token). Order: NO_STAGES -> UNKNOWN_NODE -> CYCLE ->
-- ROOT, so a malformed/cyclic graph is reported before the root computation
-- (which assumes well-formed edges):
--   NO_STAGES       — tournament has no stages.
--   UNKNOWN_NODE    — an edge endpoint (from/to) is not a stage of this
--                     tournament.
--   CYCLE           — the directed graph from_node_id -> to_node_id contains a
--                     cycle (recursive-CTE detection with a path accumulator,
--                     bounded so it terminates on a cyclic graph).
--   NO_ROOT         — no stage without an incoming edge (only reachable with a
--                     cycle, which CYCLE reports first).
--   MULTIPLE_ROOTS  — more than one root stage (multi-root boot is a deliberate
--                     follow-up step).
--
-- Idempotency: ALREADY_STARTED (22023) if the root stage is already active/
-- completed or already has matches — belt-and-suspenders with the status gate
-- and with the generator's own STAGE_ALREADY_GENERATED guard, so the second
-- call in the fixture always raises a stable token.
--
-- Boot: seed-order the confirmed participants and PERFORM
-- tournament_generate_stage_matches(p_tournament_id, root, seeded). NOTE:
-- tournament_participants_registration_status_check permits only
-- {pending,confirmed,rejected,withdrawn,waitlist} — 'approved' is NOT a valid
-- value in this schema, so the 'approved' arm is inert today (only 'confirmed'
-- ever matches); it is kept per the brief for forward-compat.
--
-- Returns: the booted root node_id (text).

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
  v_root_node    text;
  v_root_status  text;
  v_root_matches int;
  v_seeded       uuid[];
BEGIN
  -- 1. Auth gate.
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- 2. Load + lock the tournament. Not-found OR not-authorised collapse into
  --    one 42501 (no existence oracle) — identical idiom to tournament_start /
  --    tournament_finalize.
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

  -- 5. UNKNOWN_NODE: every edge endpoint must reference an existing stage of
  --    THIS tournament (checked for both from_node_id and to_node_id).
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

  -- 6. CYCLE: detect any cycle in from_node_id -> to_node_id via a recursive
  --    CTE that carries the visited path. A step whose target is already on the
  --    path FLAGS the cycle (is_cycle=true) and is emitted; the
  --    `WHERE NOT w.is_cycle` predicate then stops re-expanding that flagged row,
  --    which both bounds the recursion (a cycle-closing edge is taken at most
  --    once per path) and makes the cycle observable to bool_or().
  WITH RECURSIVE walk(node, path, is_cycle) AS (
    -- Seed: every stage as a potential walk start.
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
      WHERE NOT w.is_cycle                       -- stop expanding once a cycle is flagged (also bounds recursion)
  )
  SELECT bool_or(is_cycle) INTO v_has_cycle FROM walk;
  IF coalesce(v_has_cycle, false) THEN
    RAISE EXCEPTION 'CYCLE: stage graph contains a cycle' USING ERRCODE = '22023';
  END IF;

  -- 7. ROOT: exactly one stage with no incoming edge.
  SELECT count(*) INTO v_root_count
    FROM public.tournament_stages s
    WHERE s.tournament_id = p_tournament_id
      AND NOT EXISTS (
        SELECT 1 FROM public.tournament_stage_edges e
         WHERE e.tournament_id = p_tournament_id
           AND e.to_node_id = s.node_id);

  IF v_root_count = 0 THEN
    -- Only reachable with a cycle (covered by CYCLE first); kept for safety.
    RAISE EXCEPTION 'NO_ROOT: no stage without an incoming edge' USING ERRCODE = '22023';
  ELSIF v_root_count > 1 THEN
    -- Multi-root boot is a deliberate follow-up step.
    RAISE EXCEPTION 'MULTIPLE_ROOTS: more than one root stage' USING ERRCODE = '22023';
  END IF;

  SELECT s.node_id INTO v_root_node
    FROM public.tournament_stages s
    WHERE s.tournament_id = p_tournament_id
      AND NOT EXISTS (
        SELECT 1 FROM public.tournament_stage_edges e
         WHERE e.tournament_id = p_tournament_id
           AND e.to_node_id = s.node_id);

  -- 8. Idempotency: never re-boot the root. Belt-and-suspenders with the
  --    status gate (§3) and the generator's STAGE_ALREADY_GENERATED guard.
  SELECT status INTO v_root_status
    FROM public.tournament_stages
    WHERE tournament_id = p_tournament_id
      AND node_id = v_root_node;

  SELECT count(*) INTO v_root_matches
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND stage_node_id = v_root_node;

  IF v_root_status IN ('active', 'completed') OR v_root_matches > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: root stage % already started', v_root_node
      USING ERRCODE = '22023';
  END IF;

  -- 9. Build the seed-ordered confirmed participant subset (index 0 = seed 1).
  --    'approved' is inert in this schema (see header) — only 'confirmed'
  --    matches; kept per brief for forward-compat.
  SELECT array_agg(tp.id ORDER BY tp.seed NULLS LAST, tp.id) INTO v_seeded
    FROM public.tournament_participants tp
    WHERE tp.tournament_id = p_tournament_id
      AND tp.registration_status IN ('confirmed', 'approved');

  IF v_seeded IS NULL OR array_length(v_seeded, 1) IS NULL THEN
    -- Clearer message than the generator's INVALID_PARTICIPANT; do not boot an
    -- empty stage.
    RAISE EXCEPTION 'INVALID_PARTICIPANT: no confirmed participants' USING ERRCODE = '22023';
  END IF;

  -- 10. Boot the root stage (ADR-0030 §Runner "boot first stage"). The
  --     generator's internal guards (STAGE_NOT_FOUND, INVALID_PARTICIPANT,
  --     STAGE_ALREADY_GENERATED, unsupported-type) propagate unchanged.
  PERFORM public.tournament_generate_stage_matches(p_tournament_id, v_root_node, v_seeded);

  -- 11. State transitions (mirror tournament_start).
  UPDATE public.tournament_stages
    SET status = 'active'
    WHERE tournament_id = p_tournament_id
      AND node_id = v_root_node;

  UPDATE public.tournaments
    SET status = 'live', started_at = now()
    WHERE id = p_tournament_id;

  -- 12. Audit (tournament_audit_events.kind has no check constraint).
  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'stage_graph_started',
      v_caller,
      jsonb_build_object('root_node', v_root_node));

  RETURN v_root_node;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start_stage_graph(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_start_stage_graph(uuid) IS
  'ADR-0030 §Validierung-Gate + §Runner: boot a stage-graph tournament. Manage '
  'gate (creator/club role, 42501) + startable-status gate (non-terminal '
  'pre-live, else 22023). Structural server gate raises 22023 with a CODE token: '
  'NO_STAGES / UNKNOWN_NODE / CYCLE (recursive-CTE) / NO_ROOT / MULTIPLE_ROOTS; '
  'order NO_STAGES->UNKNOWN_NODE->CYCLE->ROOT. Boots the single root via '
  'tournament_generate_stage_matches over the seed-ordered confirmed '
  'participants, sets root stage active + tournament live + started_at, audits '
  'kind=stage_graph_started. Idempotent: ALREADY_STARTED (22023) on re-boot. '
  'Returns the booted root node_id. Distinct from the trigger '
  'tournament_run_stage_graph (advance/routing engine).';
