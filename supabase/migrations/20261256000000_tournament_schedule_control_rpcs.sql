-- Phase B (ADR-0031) Block B2s — schedule-control RPCs:
-- tournament_pause / resume / skip_forward / skip_back.
--
-- PURELY ADDITIVE. Four brand-new CREATE OR REPLACE FUNCTION statements (+ their
-- REVOKE/GRANT). The four names did NOT exist on disk before this block (no
-- stale-body risk). This migration does NOT redefine the pre-existing gate
-- tournament_caller_can_manage (20261255000000), the materialisation RPCs,
-- _tournament_upsert_round_schedule, or any other foreign function/table — it
-- only ADDS the four control RPCs and re-uses the existing gate as the single
-- source of authority. No table/column/policy is altered or dropped, no
-- DELETE/TRUNCATE/db reset, no ALTER PUBLICATION, no tournaments.paused_at.
--
-- ============================ SEMANTICS (ADR-0031) =======================
-- All four write ONLY to public.tournament_round_schedule, targeting the ACTIVE
-- (non-terminal) round row(s): status IN ('call','running','awaiting_results'),
-- i.e. status <> 'completed'. Terminal ('completed') rows are NEVER touched
-- (terminal guard). They NEVER touch tournament_matches, so running / finalised
-- matches stay byte-for-byte immune. K5: the "tournament-wide pause" lives on
-- the schedule row (paused_at / paused_accum_seconds) — the single source for
-- the restzeit formula. Each RPC takes a transaction-scoped advisory lock keyed
-- on the tournament (pg_advisory_xact_lock(hashtext(tournament_id::text)))
-- BEFORE mutating, to serialise against the E cron tick and concurrent control
-- calls.
--
--   tournament_pause       | paused_at = now() WHERE paused_at IS NULL
--                          | (idempotent: a 2nd pause does not advance paused_at).
--   tournament_resume      | paused_accum_seconds += EXTRACT(EPOCH FROM
--                          | now()-paused_at)::int; paused_at = NULL, WHERE
--                          | paused_at IS NOT NULL (idempotent no-op otherwise).
--   tournament_skip_forward| starts_at=now(), ends_at=now()+match_seconds,
--                          | status='running', pause cleared (paused_at NULL,
--                          | paused_accum_seconds 0) — skip the call/break window.
--   tournament_skip_back   | starts_at=now()+break_seconds, ends_at=starts_at+
--                          | match_seconds, status='call', pause cleared —
--                          | re-call the window (NOT a true rewind, OE-B4).
--
-- Authorisation: each RPC enforces the SINGLE source-of-truth gate
-- public.tournament_caller_can_manage(p_tournament_id) and raises a
-- NOT-AUTHORISED error mapped to SQLSTATE 42501 when it returns false. No role
-- logic is re-implemented here.
--
-- Realtime is free: tournament_round_schedule is already in the
-- supabase_realtime publication (A1, 20261251000000) so every write is pushed
-- via the existing schedule CDC. No new client polling is introduced.
--
-- ============================ DEPENDENCIES ===============================
-- Requires (all earlier on disk):
--   * public.tournament_caller_can_manage(uuid) — 20261255000000 (the gate).
--   * public.tournament_round_schedule — 20261251000000 (the only write target).
-- =====================================================================


-- ====================================================================
-- tournament_pause(uuid) — K5 tournament-wide pause. Idempotent.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_pause(
  p_tournament_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  -- Serialise against the E cron tick and concurrent control calls.
  PERFORM pg_advisory_xact_lock(hashtext(p_tournament_id::text));

  -- Freeze the active round's clock: set paused_at only when not already paused
  -- (idempotent — a 2nd consecutive pause does not advance/overwrite paused_at
  -- and does not corrupt paused_accum_seconds). Active = non-terminal row.
  UPDATE public.tournament_round_schedule s
     SET paused_at = now()
   WHERE s.tournament_id = p_tournament_id
     AND s.status IN ('call','running','awaiting_results')
     AND s.paused_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_pause(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_pause(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_pause(uuid) IS
  'ADR-0031 Block B2s: tournament-wide pause (K5). Sets paused_at = now() on '
  'the active (non-terminal) tournament_round_schedule row when paused_at IS '
  'NULL (idempotent). Gate tournament_caller_can_manage (42501). Advisory '
  'xact-lock on the tournament. Writes ONLY tournament_round_schedule. '
  'Targets ALL active (non-terminal) rows of the tournament; the classic '
  'single-active-round case touches exactly one row. A future parallel-stage '
  'feature may add a p_stage_node_id / p_round_number scope.';


-- ====================================================================
-- tournament_resume(uuid) — accumulate the frozen interval. Idempotent.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_resume(
  p_tournament_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_tournament_id::text));

  -- Add the frozen interval to paused_accum_seconds and clear paused_at.
  -- Guarded on paused_at IS NOT NULL so a resume while not paused is a no-op
  -- (no negative / garbage accumulation, idempotent).
  UPDATE public.tournament_round_schedule s
     SET paused_accum_seconds =
           s.paused_accum_seconds
           + EXTRACT(EPOCH FROM (now() - s.paused_at))::int,
         paused_at = NULL
   WHERE s.tournament_id = p_tournament_id
     AND s.status IN ('call','running','awaiting_results')
     AND s.paused_at IS NOT NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_resume(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_resume(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_resume(uuid) IS
  'ADR-0031 Block B2s: resume a paused tournament. Adds EXTRACT(EPOCH FROM '
  'now()-paused_at)::int to paused_accum_seconds and clears paused_at on the '
  'active tournament_round_schedule row (no-op when paused_at IS NULL, '
  'idempotent). Gate (42501). Advisory xact-lock. Writes ONLY the schedule.';


-- ====================================================================
-- tournament_skip_forward(uuid) — skip the call/break window into running.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_skip_forward(
  p_tournament_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_tournament_id::text));

  -- Skip the call/break window: start the match window now and transition to
  -- running. Per the skip/pause interaction rule, clear any pause state.
  UPDATE public.tournament_round_schedule s
     SET starts_at = now(),
         ends_at   = now() + make_interval(secs => s.match_seconds),
         status    = 'running',
         paused_at = NULL,
         paused_accum_seconds = 0
   WHERE s.tournament_id = p_tournament_id
     AND s.status IN ('call','running','awaiting_results');
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_skip_forward(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_skip_forward(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_skip_forward(uuid) IS
  'ADR-0031 Block B2s: skip the call/break window. Sets starts_at = now(), '
  'ends_at = now() + match_seconds, status = ''running'' and clears pause '
  '(paused_at NULL, paused_accum_seconds 0) on the active '
  'tournament_round_schedule row. Gate (42501). Advisory xact-lock. Writes '
  'ONLY the schedule.';


-- ====================================================================
-- tournament_skip_back(uuid) — re-call the window (OE-B4, not a rewind).
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_skip_back(
  p_tournament_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_tournament_id::text));

  -- Re-call the window (NOT a true rewind, OE-B4): the call/break window starts
  -- now, the match window follows it, status returns to 'call'. Clear any pause.
  UPDATE public.tournament_round_schedule s
     SET starts_at = now() + make_interval(secs => s.break_seconds),
         ends_at   = now() + make_interval(secs => s.break_seconds)
                          + make_interval(secs => s.match_seconds),
         status    = 'call',
         paused_at = NULL,
         paused_accum_seconds = 0
   WHERE s.tournament_id = p_tournament_id
     AND s.status IN ('call','running','awaiting_results');
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_skip_back(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_skip_back(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_skip_back(uuid) IS
  'ADR-0031 Block B2s: re-call the round window (OE-B4, not a rewind). Sets '
  'starts_at = now() + break_seconds, ends_at = starts_at + match_seconds, '
  'status = ''call'' and clears pause on the active tournament_round_schedule '
  'row. Gate (42501). Advisory xact-lock. Writes ONLY the schedule.';
