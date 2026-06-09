-- Phase E (ADR-0031 §3b) Block E1 — shared round-anchor helper.
--
-- The "round anchor" is the instant a round's clock should start ticking:
-- greatest(starts_at, now()) — a future starts_at is kept, a past starts_at is
-- clamped UP to now() so a late start never back-dates the clock. Today this
-- formula lives inline in TWO places that must agree forever: the A2 autostart
-- trigger (20261253000000) and the upcoming E2 schedule tick. This migration
-- extracts it into ONE pure helper so there is a single source of truth, and
-- re-bases A2 onto it. The helper takes p_now explicitly (not now()) so it is
-- IMMUTABLE and tests can inject a fixed instant (pgTAP freezes now() inside the
-- transaction — README K7).
--
-- This migration is PURELY ADDITIVE: it CREATEs ONE new helper function and
-- CREATE-OR-REPLACEs the existing A2 trigger function so its anchor line calls
-- the helper instead of an inline greatest(...). No table, column, policy, data
-- or trigger BINDING is altered or dropped — the A2 trigger stays wired exactly
-- as 20261253000000 left it (BEFORE INSERT OR UPDATE OF status, FOR EACH ROW),
-- so no DROP/CREATE TRIGGER is needed.

-- ============================ E1 — round-anchor helper =================
-- Pure, deterministic, side-effect-free: result depends only on its two
-- arguments => IMMUTABLE. LANGUAGE sql, empty search_path (no schema-resolved
-- objects are touched). Semantics === greatest(p_starts_at, p_now):
--   * p_starts_at in the PAST  (< p_now) => p_now        (clamp up)
--   * p_starts_at in the FUTURE (> p_now) => p_starts_at (future kept)
--   * equal                              => either (identical instant)
CREATE OR REPLACE FUNCTION public._tournament_round_anchor(p_starts_at timestamptz, p_now timestamptz)
RETURNS timestamptz LANGUAGE sql IMMUTABLE SET search_path = ''
AS $$ SELECT greatest(p_starts_at, p_now); $$;

COMMENT ON FUNCTION public._tournament_round_anchor(timestamptz, timestamptz) IS
  'ADR-0031 Block E1: shared round-anchor = greatest(p_starts_at, p_now). '
  'Single source of truth for the play-ready clock anchor used by the A2 '
  'autostart trigger and the E2 schedule tick. IMMUTABLE; p_now is explicit '
  'so tests can inject a fixed instant (pgTAP freezes now() in the TX, K7).';

-- Least-privilege: the helper is internal plumbing, not a public API.
REVOKE ALL ON FUNCTION public._tournament_round_anchor(timestamptz, timestamptz) FROM public;

-- ============================ A2 re-base ===============================
-- CREATE OR REPLACE of the A2 trigger function, re-based on the ACTUAL on-disk
-- body from 20261253000000 (LANGUAGE plpgsql, SET search_path = public — NOT '',
-- DECLARE v_starts_at, same signature/COMMENT). The ONLY functional change is
-- the anchor line: greatest(v_starts_at, now()) -> _tournament_round_anchor(
-- v_starts_at, now()). The idempotency guard, the IS NOT DISTINCT FROM schedule
-- lookup and the no-op-without-schedule behaviour are byte-for-byte unchanged.
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
  -- backstop stays in play. Otherwise anchor via the shared E1 helper
  -- (greatest(starts_at, now())): future starts_at is kept; past starts_at
  -- yields started_at = now().
  IF v_starts_at IS NOT NULL THEN
    NEW.started_at := public._tournament_round_anchor(v_starts_at, now());
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
