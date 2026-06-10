-- Phase A (ADR-0031) Block A2 — tournament_match_autostart trigger.
--
-- Today started_at is only stamped on the FIRST score (the COALESCE(started_at,
-- now()) backstop in the score RPCs). ADR-0031 wants started_at anchored when a
-- match becomes play-ready, not when the first set lands, so the synced clock
-- (greatest(starts_at, now())) is identical across all devices from the start.
--
-- This migration is PURELY ADDITIVE: it creates ONE new trigger function
-- public.tournament_match_autostart() and ONE trigger on tournament_matches.
-- No existing table, column, policy or function is altered or dropped, no data
-- is mutated. The score RPCs and their COALESCE(started_at, now()) backstop are
-- left untouched and remain reachable for any match that has no schedule row.
--
-- ============================ SEMANTICS (ADR-0031 / Plan A2) ============
-- BEFORE INSERT OR UPDATE OF status ON tournament_matches, FOR EACH ROW:
--   * Idempotency guard: NEW.started_at already set (IS NOT NULL) => RETURN NEW
--     unchanged. An already-anchored started_at is NEVER overwritten.
--   * Otherwise read the owning round's tournament_round_schedule.starts_at and
--     set NEW.started_at := greatest(v_starts_at, now()). Future starts_at is
--     kept (greatest picks the larger); past starts_at => started_at = starts_at.
--   * No matching schedule row => no-op: NEW.started_at stays NULL, the trigger
--     does NOT error, the existing COALESCE(started_at, now()) backstop stays in
--     play. Legacy live tournaments without a schedule row keep working.
--
-- The schedule row is matched on (tournament_id, round_number, stage_node_id)
-- — the same key as UNIQUE(tournament_id, round_number, stage_node_id) and the
-- partial unique index for stage_node_id IS NULL. The classic (NULL stage)
-- match must hit the NULL schedule row, so the stage join uses IS NOT DISTINCT
-- FROM (NULL = NULL semantics), NOT plain "=", which would never match NULL.
--
-- The function modifies ONLY the NEW tuple (BEFORE-trigger semantics): it
-- writes no other table, fires no NOTIFY, creates no pairings; it just returns
-- NEW. tournament_matches is already a CDC table (20261234000000), so the new
-- started_at value pushes to subscribers automatically — no extra work here.
--
-- search_path is pinned (SET search_path = public) like the other
-- security-relevant functions; the function is plain (not SECURITY DEFINER):
-- it only mutates the NEW tuple of the row the caller is already writing.

CREATE OR REPLACE FUNCTION public.tournament_match_autostart()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_starts_at timestamptz;
BEGIN
  -- Idempotency: an already-anchored started_at is never overwritten.
  IF NEW.started_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  -- Read the owning round's schedule anchor. IS NOT DISTINCT FROM makes the
  -- classic (NULL stage_node_id) match hit the NULL schedule row.
  SELECT s.starts_at
    INTO v_starts_at
    FROM public.tournament_round_schedule s
   WHERE s.tournament_id = NEW.tournament_id
     AND s.round_number  = NEW.round_number
     AND s.stage_node_id IS NOT DISTINCT FROM NEW.stage_node_id
   LIMIT 1;

  -- No schedule row => no-op: leave started_at NULL, the score-RPC COALESCE
  -- backstop stays in play. Otherwise anchor at greatest(starts_at, now()):
  -- future starts_at is kept; past starts_at yields started_at = starts_at.
  IF v_starts_at IS NOT NULL THEN
    NEW.started_at := greatest(v_starts_at, now());
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.tournament_match_autostart() IS
  'ADR-0031 Block A2: BEFORE INSERT OR UPDATE OF status on tournament_matches. '
  'Anchors started_at = greatest(schedule.starts_at, now()) when play-ready, '
  'idempotent (never overwrites a set started_at), no-op without a matching '
  'tournament_round_schedule row (score-RPC COALESCE backstop stays). Only '
  'mutates the NEW tuple; tournament_matches CDC pushes started_at automatically.';

-- Idempotent (re)create of the trigger. DROP TRIGGER IF EXISTS targets ONLY
-- this A2-owned trigger (never a foreign object) so the migration can be
-- re-applied cleanly; it removes nothing of the existing schema.
DROP TRIGGER IF EXISTS tournament_match_autostart ON public.tournament_matches;
CREATE TRIGGER tournament_match_autostart
  BEFORE INSERT OR UPDATE OF status ON public.tournament_matches
  FOR EACH ROW
  EXECUTE FUNCTION public.tournament_match_autostart();
