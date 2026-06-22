-- Schoch-Runden-Brücke im Stufen-Graph-Runner — ADR-0039 §2 (HIGH-1).
--
-- Der Runner (tournament_run_stage_graph) schliesst eine Stufe heute, sobald
-- ALLE ihre Matches terminal sind, routet sie und cascaded ins Ziel. Für eine
-- Schoch-Stufe mit R internen Runden ist das falsch: nach Runde 1 wären alle
-- bis dahin materialisierten Matches terminal und der Runner würde die Stufe
-- vorzeitig schliessen und ins KO routen, obwohl noch R-1 Runden fehlen.
--
-- Diese Migration zieht eine typ-spezifische Verzweigung ein, die NUR für
-- Schoch (Legacy 'swiss' toleriert, 20261293-Rename) greift. Direkt nach
-- Guard A (stage_node_id NOT NULL) wird der Stufen-Typ gelesen:
--
--   * Schoch/Swiss: runden-scoped statt stufenweit prüfen. R = config['rounds']
--     (positiver int wie der Domain-Reader stage_validation.dart
--     schochRoundsFromConfig; fehlt/ungültig -> konservativer Fallback, siehe
--     unten). v_max_round = höchste round_number dieser Stufe. v_round_terminal
--     = bool_and(terminal) NUR über die Matches der höchsten Runde.
--       - Runde nicht fertig    -> RETURN NEW (runden-scoped early-return,
--                                  analog zum bestehenden not-all-terminal-Pfad).
--       - r fertig, r < R        -> KEINE Stufenschliessung. Audit-Signal
--                                  'swiss_round_complete' (Organizer-Trigger für
--                                  die nächste Paarung, ADR-0039 §2). KEIN
--                                  Generate (Paarung = Client, B4/B5). RETURN NEW.
--       - r fertig, r >= R       -> bewusst in den BESTEHENDEN Schliess-/Route-/
--                                  Cascade-Pfad fallen (REUSE, unverändert).
--     Fallback bei fehlendem/ungültigem config['rounds']: konservativ R := 1, d.h.
--     die Stufe wird nach Runde 1 wie eine gewöhnliche Stufe geschlossen und ein
--     Audit-Warnsignal 'swiss_rounds_missing' gesetzt (Owner-Empfehlung ADR-0039;
--     KEIN ceil(log2(n)) in plpgsql nachbauen).
--
--   * alle anderen Typen (single_elim, double_elim, round_robin, pool,
--     group_phase, consolation, shootout_quali): der Schoch-Zweig wird NICHT
--     betreten, der bestehende stufenweite Pfad läuft BYTE-IDENTISCH wie in
--     20261299000000 (Guard B/C/D + route + cascade unverändert).
--
-- Idempotenz: 'swiss_round_complete' / 'swiss_rounds_missing' sind rein
-- informativ (kein State-Flip). Ein Doppel-Feuern des Triggers (z.B. wenn eine
-- bereits terminale Korrektur als 'overridden' erneut feuert) ist harmlos — es
-- wird höchstens ein weiteres Audit-Event geschrieben, der Stufenzustand bleibt
-- 'active'. Sobald die Stufe einmal geschlossen ist, greift der bestehende
-- v_stage_status='completed'-Guard und macht den ganzen Body idempotent.
--
-- Additiv: CREATE OR REPLACE auf den 20261299-Body; Trigger und GRANTs werden
-- unverändert neu gesetzt. Keine fremde Migration editiert.
-- =====================================================================

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
  v_type         text;
  v_rounds_raw   jsonb;
  v_rounds_total int;
  v_max_round    int;
  v_round_terminal boolean;
BEGIN
  IF NEW.stage_node_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- ADR-0039 §2: Schoch-Stufen verzweigen runden-scoped. Der Typ wird einmal
  -- gelesen; nur 'schoch' (Legacy 'swiss') betritt den neuen Pfad, jeder andere
  -- Typ fällt unverändert in die bestehende stufenweite Logik unten.
  SELECT s.type, s.config -> 'rounds'
    INTO v_type, v_rounds_raw
    FROM public.tournament_stages s
    WHERE s.tournament_id = NEW.tournament_id
      AND s.node_id = NEW.stage_node_id;

  IF v_type IN ('schoch', 'swiss') THEN
    -- R aus config['rounds'] wie der Domain-Reader (positiver int, sonst
    -- Fallback). Fallback ist konservativ: R := 1 -> nach Runde 1 schliessen.
    IF jsonb_typeof(v_rounds_raw) = 'number'
       AND (v_rounds_raw)::int >= 1 THEN
      v_rounds_total := (v_rounds_raw)::int;
    ELSE
      v_rounds_total := 1;
      INSERT INTO public.tournament_audit_events(
          tournament_id, kind, actor_user_id, payload)
        VALUES (
          NEW.tournament_id,
          'swiss_rounds_missing',
          NULL,
          jsonb_build_object(
            'stage_node_id', NEW.stage_node_id,
            'fallback_rounds', 1));
    END IF;

    -- Höchste materialisierte Runde dieser Stufe + runden-scoped terminal-Check.
    SELECT max(m.round_number)
      INTO v_max_round
      FROM public.tournament_matches m
      WHERE m.tournament_id = NEW.tournament_id
        AND m.stage_node_id = NEW.stage_node_id;

    SELECT bool_and(m.status IN ('finalized','overridden','voided'))
      INTO v_round_terminal
      FROM public.tournament_matches m
      WHERE m.tournament_id = NEW.tournament_id
        AND m.stage_node_id = NEW.stage_node_id
        AND m.round_number = v_max_round;

    IF NOT coalesce(v_round_terminal, false) THEN
      RETURN NEW;
    END IF;

    IF coalesce(v_max_round, 0) < v_rounds_total THEN
      -- Runde r < R fertig: KEINE Stufenschliessung, kein Generate (Paarung der
      -- nächsten Runde ist eine Organizer-Aktion, ADR-0039 §2). Nur das Signal.
      INSERT INTO public.tournament_audit_events(
          tournament_id, kind, actor_user_id, payload)
        VALUES (
          NEW.tournament_id,
          'swiss_round_complete',
          NULL,
          jsonb_build_object(
            'stage_node_id',  NEW.stage_node_id,
            'completed_round', v_max_round,
            'rounds_total',    v_rounds_total,
            'awaiting',        v_max_round + 1));
      RETURN NEW;
    END IF;
    -- r >= R: in den bestehenden Schliess-/Route-/Cascade-Pfad fallen (REUSE).
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
  'AFTER-UPDATE stage-graph runner (ADR-0030 §Runner-Semantik + ADR-0039 §2 '
  'schoch round bridge). Fires when a stage-graph match transitions into '
  'terminal. For a schoch/swiss stage it branches round-scoped: R = '
  'config[''rounds''] (positive int, else conservative fallback R=1 + '
  '''swiss_rounds_missing'' audit). When the highest round is terminal and r < R '
  'it emits ''swiss_round_complete'' and keeps the stage active (next round is '
  'an organizer-paired action, not an auto-cascade); r >= R falls into the '
  'shared close/route/cascade path. Every other type runs the stage-wide path '
  'byte-identically to 20261299000000: when ALL of the stage''s matches are '
  'terminal it closes the stage, routes it via tournament_route_completed_stage, '
  'and for every outgoing target Y checks the JOIN BARRIER + pending-guard, then '
  'resolves Y''s per-stage node.seeding (Seeding-Spec §6.5) over the routed '
  'tournament_stage_inputs via _tournament_resolve_stage_seeding before '
  'activating Y and generating its matches. Idempotent twice over. A target with '
  'empty inputs stays pending. A SINK stage is only closed (routing skipped). '
  'INVARIANT: the FIRST stage is booted by the start-RPC, never here. SECURITY '
  'DEFINER (writes tournament_stages / inputs / matches, no client-write RLS '
  'policy).';
