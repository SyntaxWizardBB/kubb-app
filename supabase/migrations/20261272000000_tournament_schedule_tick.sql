-- Phase E (ADR-0031 §Runner / §3b) Block E2 — pg_cron schedule tick.
--
-- public.tournament_schedule_tick(p_now timestamptz DEFAULT now()) RETURNS int
-- is the once-a-minute, server-authoritative driver of the PURE TIME transitions
-- of a round's clock. pg_cron (1.6, in-DB, runs as postgres) calls it with no
-- argument every minute; tests inject a fixed p_now because pgTAP freezes now()
-- inside the transaction (README K7). It is IDEMPOTENT — every UPDATE guards on
-- the source status (WHERE status = <source>), so a doubled / late / replayed
-- tick re-applies nothing and RETURNS 0 transitions.
--
-- SCOPE / what this does and does NOT do:
--   * It ONLY flips tournament_round_schedule.status along the time axis:
--       published|call -> running              (starts_at reached)
--       running|awaiting_results -> completed  (ends_at reached, all matches terminal)
--       running -> awaiting_results            (ends_at reached, a result is missing)
--   * K8 / OE-1: it creates NO pairings and NO follow-up rounds. The next round
--     is materialised by the EXISTING result-driven triggers (the stage-graph
--     runner / the KO-advance trigger). This function NEVER invokes the
--     stage-graph runner, the KO-advance step, the swiss/round pairing RPC, the
--     KO-phase start RPC or the stage-match generator — only status flips.
--   * OE-2: NO auto-forfait. When the clock runs out with an open result the
--     round goes to awaiting_results (the clock holds, Pause-semantics) and the
--     dashboard flags it; the result is entered by players / organiser.
--
-- GUARDS:
--   * K5 — tournament-wide pause lives ON the schedule row: the loop skips rows
--     with s.paused_at IS NOT NULL. There is NO tournaments.paused_at (it does
--     not exist); the ONLY pause guard is s.paused_at on the schedule row.
--   * R2 / OE-3 — per tournament a NON-BLOCKING pg_try_advisory_xact_lock guards
--     against a race with the result-trigger; a tournament whose lock is held is
--     SKIPPED this tick (it is picked up on the next one). The lock is xact-
--     scoped, released automatically at function end.
--   * R3 — each tournament runs in its OWN subtransaction (BEGIN..EXCEPTION WHEN
--     OTHERS THEN RAISE WARNING); one broken tournament can NOT abort the tick
--     for the others. No re-raise.
--
-- PURELY ADDITIVE: this migration CREATE-OR-REPLACEs ONLY the new function
-- tournament_schedule_tick and adds its REVOKE + COMMENT. No table, column,
-- policy, trigger or OTHER function is altered or dropped; no supabase db reset.
-- search_path = '' => every reference is fully schema-qualified (R9).

CREATE OR REPLACE FUNCTION public.tournament_schedule_tick(p_now timestamptz DEFAULT now())
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_tid    uuid;
  v_count  int := 0;   -- total transitions actually applied (RETURNS this)
BEGIN
  -- One pass over the DISTINCT tournaments that have at least one due, non-paused
  -- schedule row. Due = a source status that can still time-transition AND a time
  -- boundary already crossed at p_now AND the row is not paused (K5: s.paused_at).
  -- Iterating per tournament lets each tournament take its own advisory lock and
  -- run inside its own subtransaction (R2/R3).
  FOR v_tid IN
    SELECT DISTINCT s.tournament_id
      FROM public.tournament_round_schedule s
     WHERE s.status IN ('published', 'call', 'running', 'awaiting_results')
       AND s.paused_at IS NULL
       AND (s.starts_at <= p_now OR s.ends_at <= p_now)
  LOOP
    -- R3: isolate each tournament. A failure here RAISEs a WARNING and the loop
    -- continues with the next tournament; it never aborts the whole tick.
    BEGIN
      -- R2 / OE-3: non-blocking, transaction-scoped lock per tournament. If the
      -- result-trigger (or a parallel tick) holds it, skip this tournament now;
      -- the next tick retries. hashtextextended(text, 0) -> bigint lock key.
      IF NOT pg_catalog.pg_try_advisory_xact_lock(
               pg_catalog.hashtextextended(v_tid::text, 0)) THEN
        CONTINUE;
      END IF;

      -- ---- Transition 1: published|call -> running (starts_at reached) -------
      -- Idempotent via WHERE status IN ('published','call'): a row already
      -- running is untouched. Only non-paused rows whose start has arrived flip.
      WITH flipped AS (
        UPDATE public.tournament_round_schedule s
           SET status = 'running'
         WHERE s.tournament_id = v_tid
           AND s.status IN ('published', 'call')
           AND s.paused_at IS NULL
           AND s.starts_at <= p_now
        RETURNING 1
      )
      SELECT v_count + count(*)::int INTO v_count FROM flipped;

      -- ---- Transition 2: running|awaiting_results & ends_at reached ----------
      -- For every due (ends_at <= p_now), non-paused row in running OR
      -- awaiting_results, decide via bool_and over the round's matches whether
      -- ALL matches are terminal (finalized/overridden/voided):
      --   * all terminal  -> completed   (the result-trigger has already, or
      --                                    will, materialise the next round — K8)
      --   * not all terminal AND status='running' -> awaiting_results
      --                                    (clock holds, NO auto-forfait — OE-2)
      --   * not all terminal AND already awaiting_results -> stays awaiting_results
      -- Matches join the schedule row on (tournament_id, round_number) and
      -- stage_node_id IS NOT DISTINCT FROM s.stage_node_id, so the classic
      -- (NULL stage_node_id) path hits NULL-stage matches and the stage path
      -- hits its own stage. A round with NO matches => bool_and over zero rows is
      -- NULL => coalesce(...,false) keeps it non-complete (awaiting_results).
      --
      -- Each branch guards on its source status (idempotent re-tick = 0):
      --   completed-branch:        WHERE status IN ('running','awaiting_results')
      --   awaiting_results-branch: WHERE status = 'running'

      -- 2a: all-terminal -> completed.
      WITH flipped AS (
        UPDATE public.tournament_round_schedule s
           SET status = 'completed'
         WHERE s.tournament_id = v_tid
           AND s.status IN ('running', 'awaiting_results')
           AND s.paused_at IS NULL
           AND s.ends_at <= p_now
           AND coalesce(
                 (SELECT bool_and(m.status IN ('finalized', 'overridden', 'voided'))
                    FROM public.tournament_matches m
                   WHERE m.tournament_id = s.tournament_id
                     AND m.round_number  = s.round_number
                     AND m.stage_node_id IS NOT DISTINCT FROM s.stage_node_id),
                 false)
        RETURNING 1
      )
      SELECT v_count + count(*)::int INTO v_count FROM flipped;

      -- 2b: running -> awaiting_results (a result still missing; clock holds).
      -- Only 'running' rows flip here; rows already in awaiting_results stay put
      -- (they only leave via 2a once all matches are terminal). No forfait.
      WITH flipped AS (
        UPDATE public.tournament_round_schedule s
           SET status = 'awaiting_results'
         WHERE s.tournament_id = v_tid
           AND s.status = 'running'
           AND s.paused_at IS NULL
           AND s.ends_at <= p_now
           AND NOT coalesce(
                 (SELECT bool_and(m.status IN ('finalized', 'overridden', 'voided'))
                    FROM public.tournament_matches m
                   WHERE m.tournament_id = s.tournament_id
                     AND m.round_number  = s.round_number
                     AND m.stage_node_id IS NOT DISTINCT FROM s.stage_node_id),
                 false)
        RETURNING 1
      )
      SELECT v_count + count(*)::int INTO v_count FROM flipped;

    EXCEPTION WHEN OTHERS THEN
      -- R3 fault isolation: log and move on; never abort the tick. SQLSTATE +
      -- SQLERRM identify the broken tournament for observability.
      RAISE WARNING 'tournament_schedule_tick: tournament % skipped (%): %',
        v_tid, SQLSTATE, SQLERRM;
    END;
  END LOOP;

  -- RETURNS the number of transitions actually applied (sum of the UPDATEs'
  -- affected rows), NOT the number of rows considered. Re-ticking with the same
  -- p_now applies nothing => returns 0 (idempotency / observability — OE-4).
  RETURN v_count;
END;
$$;

COMMENT ON FUNCTION public.tournament_schedule_tick(timestamptz) IS
  'ADR-0031 Block E2: pg_cron 1-min schedule tick. Idempotent (WHERE status = '
  'source) PURE-TIME transitions of tournament_round_schedule: published|call -> '
  'running (starts_at<=p_now), running|awaiting_results -> completed (ends_at<= '
  'p_now AND all matches terminal), else running -> awaiting_results (clock '
  'holds, NO auto-forfait, OE-2). K5: ONLY s.paused_at guards pause (no '
  'tournaments.paused_at). K8: creates NO pairings — the result-trigger '
  'materialises follow-up rounds. K7: p_now is explicit so tests inject a fixed '
  'instant; cron calls it with DEFAULT now(). Per tournament: non-blocking '
  'pg_try_advisory_xact_lock (R2) + own subtransaction with RAISE WARNING (R3). '
  'RETURNS the count of transitions applied (re-tick = 0).';

-- Least-privilege: cron runs as postgres; this is not a public client API.
REVOKE ALL ON FUNCTION public.tournament_schedule_tick(timestamptz) FROM public;
