-- Per-Stufe-Seed-Resolver — Seeding-Spec §6 (Quellen-Wire) + §6.5 (Resolver),
-- architecture.md §5.5 (Engine-Resolver = Kern-Lücke), ADR-0038.
--
-- Bisher ignorieren der Boot (tournament_start_stage_graph) und der Runner
-- (tournament_run_stage_graph) das per-Stufe-Feld node.seeding: der Boot
-- ordnet die Wurzel-Stufe stur nach tp.seed, der Runner übernimmt die
-- Routing-Reihenfolge (tournament_stage_inputs.ordinal = Quell-Rangliste).
-- Diese Migration zieht eine Seed-Resolution ein, die für jede Stufe
-- node.seeding auswertet und die Setzliste pro Stufe danach bestimmt:
--
--   from_elo          -> tournament_autoseed_from_elo (REUSE), dann
--                        Kandidaten nach seed_override ASC ordnen.
--   random            -> _tournament_seed_random mit einem EINMALIG gezogenen,
--                        in config.random_seed PERSISTIERTEN Seed (Vorschau ==
--                        gespielte Liste: ein zweiter Aufruf liest denselben
--                        Seed).
--   manual            -> gespeicherte Liste (tournament_seeding_overrides
--                        seed_override ASC). Fehlt sie ganz -> Kandidaten-
--                        Reihenfolge unverändert.
--   from_prev_ranking -> Quell-Rangliste. Beim Boot existiert keine Vorrunde
--                        (Wurzel) -> Kandidaten-Reihenfolge. Im Runner ist die
--                        Kandidatenliste bereits die Routing-Reihenfolge aus
--                        tournament_stage_ranking der Quellstufe(n) (M2), also
--                        identisch.
--   as_routed / sonst -> Kandidaten-Reihenfolge unverändert (Default).
--
-- Additiv, CREATE OR REPLACE; GRANTs bleiben erhalten. Keine fremde Migration
-- wird editiert.

-- ============================================================
-- T11a — _tournament_seed_random: byte-genauer plpgsql-Zwilling von
-- packages/kubb_domain/lib/src/tournament/seeding.dart `seedRandom`.
-- ============================================================
--
-- Algorithmus-Identität (Dart -> plpgsql), 1:1:
--   * 32-bit-LCG (Numerical Recipes): next = (state*1664525 + 1013904223)
--     mod 2^32, Startzustand state = seed & 0xFFFFFFFF.
--   * Rejection-Sampling gegen die Modulo-Verzerrung: limit = 2^32 - (2^32 mod
--     bound); ziehe neu solange draw >= limit; index = draw mod bound.
--   * Fisher-Yates von hoch nach tief.
--
-- Dart läuft 0-basiert: for i in (n-1)..1 { j = nextBelow(i+1); swap(i,j) }.
-- Postgres-Arrays sind 1-basiert: i_dart+1 = v_i, bound = i_dart+1 = v_i, das
-- 0-basierte j wird zu v_j = j+1. Daher v_i läuft REVERSE von v_n bis 2,
-- v_bound = v_i, v_j = (draw mod v_bound) + 1.
--
-- bigint deckt jedes Zwischenprodukt ab: state < 2^32, state*1664525 < 2^53,
-- also exakt darstellbar -> kein Genauigkeitsverlust gegen das Dart-int (das
-- auf 64-bit-Plattformen ebenfalls exakt rechnet). T12 belegt die Identität
-- mit geteilten Golden-Vektoren (Dart-Test + pgTAP).

CREATE OR REPLACE FUNCTION public._tournament_seed_random(
  p_ids  uuid[],
  p_seed bigint
)
RETURNS uuid[]
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_out   uuid[] := p_ids;
  v_n     int    := coalesce(array_length(p_ids, 1), 0);
  v_state bigint;
  v_i     int;
  v_j     int;
  v_bound int;
  v_limit bigint;
  v_draw  bigint;
  v_tmp   uuid;
BEGIN
  IF v_n < 2 THEN
    RETURN v_out;  -- 0/1 element: returned unchanged (mirrors Dart guard).
  END IF;

  v_state := p_seed & x'FFFFFFFF'::bigint;

  FOR v_i IN REVERSE v_n .. 2 LOOP
    v_bound := v_i;
    v_limit := 4294967296::bigint - (4294967296::bigint % v_bound);
    LOOP
      v_state := (v_state * 1664525 + 1013904223) % 4294967296::bigint;
      v_draw  := v_state;
      EXIT WHEN v_draw < v_limit;
    END LOOP;
    v_j := (v_draw % v_bound)::int + 1;

    v_tmp      := v_out[v_i];
    v_out[v_i] := v_out[v_j];
    v_out[v_j] := v_tmp;
  END LOOP;

  RETURN v_out;
END;
$$;

GRANT EXECUTE ON FUNCTION public._tournament_seed_random(uuid[], bigint)
  TO authenticated;

COMMENT ON FUNCTION public._tournament_seed_random(uuid[], bigint) IS
  'Seeding-Spec §2/§7.3: byte-genauer plpgsql-Zwilling von seeding.dart '
  'seedRandom. 32-bit-LCG (next = state*1664525+1013904223 mod 2^32, '
  'state0 = seed & 0xFFFFFFFF), Rejection-Sampling gegen Modulo-Bias, '
  'Fisher-Yates hoch->tief (1-basiert: i = n..2, bound = i, j = draw mod '
  'bound + 1). bigint rechnet exakt (Zwischenprodukt < 2^53). Gleicher '
  '(ids, seed) -> gleiche Permutation. Parity-Beweis: T12 Golden-Vektoren.';

-- ============================================================
-- T11b — _tournament_resolve_stage_seeding: wertet node.seeding aus und gibt
-- die Setzliste für p_candidate (Boot: ganzes Feld; Runner: Routing-Inputs)
-- in der Reihenfolge der gewählten Quelle zurück. SECURITY DEFINER, weil der
-- random-Zweig den Seed in tournament_stages.config schreibt (server-autoritativ,
-- kein Client-Write-Policy) und from_elo den autoseed-Store füllt.
-- ============================================================

CREATE OR REPLACE FUNCTION public._tournament_resolve_stage_seeding(
  p_tournament_id uuid,
  p_node_id       text,
  p_candidate     uuid[]
)
RETURNS uuid[]
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_seeding  text;
  v_config   jsonb;
  v_n        int := coalesce(array_length(p_candidate, 1), 0);
  v_seed     bigint;
  v_ordered  uuid[];
BEGIN
  IF v_n < 2 THEN
    RETURN p_candidate;  -- nothing to order.
  END IF;

  SELECT s.seeding, s.config
    INTO v_seeding, v_config
    FROM public.tournament_stages s
    WHERE s.tournament_id = p_tournament_id
      AND s.node_id = p_node_id;

  IF NOT FOUND THEN
    RETURN p_candidate;
  END IF;

  IF v_seeding = 'from_elo' THEN
    -- REUSE the ELO autoseed: it (re)writes tournament_seeding_overrides with
    -- a 1..N order over the confirmed field. Order the candidate subset by that
    -- seed_override; candidates without an override (shouldn't happen for the
    -- full confirmed field) sort last in stable id order.
    PERFORM public.tournament_autoseed_from_elo(p_tournament_id);

    SELECT array_agg(c.pid ORDER BY o.seed_override ASC NULLS LAST, c.pid)
      INTO v_ordered
      FROM unnest(p_candidate) AS c(pid)
      LEFT JOIN public.tournament_seeding_overrides o
        ON o.tournament_id = p_tournament_id
       AND o.participant_id = c.pid;
    RETURN coalesce(v_ordered, p_candidate);

  ELSIF v_seeding = 'random' THEN
    -- Draw ONCE, then persist into config.random_seed so a preview and the
    -- played list share the same seed (Spec §7.3). A re-resolve reads the
    -- stored seed and reproduces the identical order.
    v_seed := (v_config ->> 'random_seed')::bigint;
    IF v_seed IS NULL THEN
      v_seed := floor(random() * 4294967296::double precision)::bigint;
      UPDATE public.tournament_stages
        SET config = jsonb_set(
              coalesce(config, '{}'::jsonb),
              '{random_seed}',
              to_jsonb(v_seed),
              true)
        WHERE tournament_id = p_tournament_id
          AND node_id = p_node_id;
    END IF;
    RETURN public._tournament_seed_random(p_candidate, v_seed);

  ELSIF v_seeding = 'manual' THEN
    -- Stored manual list: tournament_seeding_overrides seed_override ASC.
    -- Candidates not in the manual list keep ranking/candidate order behind the
    -- listed ones (stable id tail). With no overrides at all the candidate
    -- order is unchanged.
    SELECT array_agg(c.pid ORDER BY o.seed_override ASC NULLS LAST, c.pid)
      INTO v_ordered
      FROM unnest(p_candidate) AS c(pid)
      LEFT JOIN public.tournament_seeding_overrides o
        ON o.tournament_id = p_tournament_id
       AND o.participant_id = c.pid;

    IF NOT EXISTS (
      SELECT 1 FROM public.tournament_seeding_overrides o
        WHERE o.tournament_id = p_tournament_id
          AND o.participant_id = ANY(p_candidate))
    THEN
      RETURN p_candidate;
    END IF;
    RETURN coalesce(v_ordered, p_candidate);

  ELSE
    -- from_prev_ranking / as_routed / unknown: keep the candidate order. For a
    -- follow-up stage the candidate array IS the routed source ranking
    -- (tournament_stage_inputs.ordinal, fed by tournament_stage_ranking, M2);
    -- for a root there is no previous round, so the field order stands.
    RETURN p_candidate;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public._tournament_resolve_stage_seeding(uuid, text, uuid[])
  TO authenticated;

COMMENT ON FUNCTION public._tournament_resolve_stage_seeding(uuid, text, uuid[]) IS
  'Seeding-Spec §6.5 Resolver: ordnet p_candidate nach tournament_stages.seeding. '
  'from_elo -> tournament_autoseed_from_elo (REUSE) + seed_override-Sortierung; '
  'random -> _tournament_seed_random mit einmalig gezogenem + in config.random_seed '
  'persistiertem Seed (Vorschau == gespielte Liste); manual -> gespeicherte Liste; '
  'from_prev_ranking/as_routed -> Kandidaten-Reihenfolge (im Runner = Routing-/M2-'
  'Rangliste). SECURITY DEFINER: schreibt config.random_seed und ruft den '
  'autoseed-Store, beide ohne Client-Write-Policy.';

-- ============================================================
-- T11c — tournament_start_stage_graph: resolve each root's seeding before
-- booting. Verbatim copy of the multi-root boot (20261249000000); ONLY the
-- boot loop changes — each root's full-field is run through the resolver.
-- ============================================================

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
  v_resolved     uuid[];
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
  --    cycle, already reported). Multiple roots are allowed (F3).
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

  -- 8. Idempotency: if ANY root is already started, the whole start is a no-op
  --    error.
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

  -- 9. The full confirmed field (index 0 = seed 1). 'approved' is inert in this
  --    schema (only 'confirmed' matches); kept for forward-compat.
  SELECT array_agg(tp.id ORDER BY tp.seed NULLS LAST, tp.id) INTO v_seeded
    FROM public.tournament_participants tp
    WHERE tp.tournament_id = p_tournament_id
      AND tp.registration_status IN ('confirmed', 'approved');

  IF v_seeded IS NULL OR array_length(v_seeded, 1) IS NULL THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: no confirmed participants' USING ERRCODE = '22023';
  END IF;

  -- 10. Boot every root with its PER-STAGE-resolved seeding (Seeding-Spec §6.5).
  --     The full confirmed field is the candidate set; the resolver orders it by
  --     this root's node.seeding (from_elo / random / manual / from_prev_ranking
  --     -> field order for a root with no previous round).
  FOREACH v_root_node IN ARRAY v_roots LOOP
    v_resolved := public._tournament_resolve_stage_seeding(
      p_tournament_id, v_root_node, v_seeded);

    PERFORM public.tournament_generate_stage_matches(p_tournament_id, v_root_node, v_resolved);

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
  'NO_STAGES->UNKNOWN_NODE->CYCLE->ROOT. Boots EVERY root (F3 multi-root); each '
  'root''s full confirmed field is ordered by its per-stage node.seeding via '
  '_tournament_resolve_stage_seeding (Seeding-Spec §6.5: from_elo/random/manual/'
  'from_prev_ranking) before tournament_generate_stage_matches. Sets each root '
  'active + tournament live + started_at, audits kind=stage_graph_started. '
  'Idempotent: ALREADY_STARTED (22023) if any root already started. Returns the '
  'booted root node_ids comma-joined. Distinct from the trigger '
  'tournament_run_stage_graph (advance/routing engine).';

-- ============================================================
-- T11d — tournament_run_stage_graph: resolve each activated target's seeding
-- before generating. Verbatim copy of 20261228000000; ONLY the per-target
-- generation changes — the routed input order is run through the resolver so
-- node.seeding (random / from_elo / manual) overrides the routed order; the
-- from_prev_ranking / as_routed default keeps the routed (source-ranking) order.
-- ============================================================

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
  v_resolved     uuid[];
BEGIN
  IF NEW.stage_node_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT bool_and(m.status IN ('finalized','overridden','voided'))
    INTO v_all_terminal
    FROM public.tournament_matches m
    WHERE m.tournament_id = NEW.tournament_id
      AND m.stage_node_id = NEW.stage_node_id;

  IF NOT coalesce(v_all_terminal, false) THEN
    RETURN NEW;
  END IF;

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

  -- Guard D (sink stage): no outgoing edges -> nothing to route. Must not call
  -- the routing building block (its single_elim ranking path raises for small
  -- brackets and would abort the championship-finalizing UPDATE).
  PERFORM 1
    FROM public.tournament_stage_edges e
    WHERE e.tournament_id = NEW.tournament_id
      AND e.from_node_id = NEW.stage_node_id
    LIMIT 1;
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- Step 2: route the completed stage's participants into its targets' inputs.
  PERFORM public.tournament_route_completed_stage(NEW.tournament_id, NEW.stage_node_id);

  -- Step 3: for every distinct outgoing target, check the join barrier and
  -- (if open and the target is still pending) resolve seeding + activate +
  -- generate.
  FOR v_target IN
    SELECT DISTINCT e.to_node_id
      FROM public.tournament_stage_edges e
      WHERE e.tournament_id = NEW.tournament_id
        AND e.from_node_id = NEW.stage_node_id
  LOOP
    SELECT bool_and(s.status = 'completed')
      INTO v_barrier_open
      FROM public.tournament_stage_edges e
      JOIN public.tournament_stages s
        ON s.tournament_id = e.tournament_id
       AND s.node_id = e.from_node_id
      WHERE e.tournament_id = NEW.tournament_id
        AND e.to_node_id = v_target;

    SELECT s.status
      INTO v_stage_status
      FROM public.tournament_stages s
      WHERE s.tournament_id = NEW.tournament_id
        AND s.node_id = v_target;

    IF coalesce(v_barrier_open, false) AND v_stage_status = 'pending' THEN
      -- Routed inputs for Y (ordinal is the source ranking order).
      SELECT array_agg(i.participant_id ORDER BY i.ordinal)
        INTO v_seeded
        FROM public.tournament_stage_inputs i
        WHERE i.tournament_id = NEW.tournament_id
          AND i.target_node_id = v_target;

      IF coalesce(array_length(v_seeded, 1), 0) >= 1 THEN
        -- Per-stage seed resolution (Seeding-Spec §6.5). node.seeding orders the
        -- routed field: random/from_elo/manual reorder it; from_prev_ranking and
        -- as_routed keep the routed (source-ranking) order.
        v_resolved := public._tournament_resolve_stage_seeding(
          NEW.tournament_id, v_target, v_seeded);

        UPDATE public.tournament_stages
          SET status = 'active'
          WHERE tournament_id = NEW.tournament_id
            AND node_id = v_target;

        PERFORM public.tournament_generate_stage_matches(
          NEW.tournament_id, v_target, v_resolved);
      END IF;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

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
  '+ step 3 cascade). Fires when a stage-graph match transitions into terminal. '
  'When ALL of the stage''s matches are terminal it closes the stage, routes it '
  'via tournament_route_completed_stage, and for every outgoing target Y checks '
  'the JOIN BARRIER + pending-guard, then resolves Y''s per-stage node.seeding '
  '(Seeding-Spec §6.5) over the routed tournament_stage_inputs via '
  '_tournament_resolve_stage_seeding before activating Y and generating its '
  'matches. random/from_elo/manual reorder the routed field; from_prev_ranking '
  'and as_routed keep the routed (source-ranking) order. Idempotent twice over. '
  'A target with empty inputs stays pending. A SINK stage is only closed (routing '
  'skipped). INVARIANT: the FIRST stage is booted by the start-RPC, never here. '
  'SECURITY DEFINER (writes tournament_stages / inputs / matches, no client-write '
  'RLS policy).';
