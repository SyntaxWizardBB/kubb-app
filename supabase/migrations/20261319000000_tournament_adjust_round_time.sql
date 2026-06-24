-- W4-T10 — tournament_adjust_round_time RPC (spec
-- organizer-cockpit-dashboard-spec.md §6 / §9.5: the organizer lengthens AND
-- shortens the LIVE round's time).
--
-- PURELY ADDITIVE. One brand-new CREATE OR REPLACE FUNCTION (+ its REVOKE/GRANT
-- and COMMENT). The name did NOT exist on disk before (no stale-body risk).
-- This migration redefines no table/policy and no foreign function — it only
-- ADDS the adjust RPC and re-uses the existing administer gate as the single
-- source of authority. No DELETE/TRUNCATE, no db reset, no ALTER PUBLICATION.
--
-- ============================ SEMANTICS =================================
-- Writes ONLY public.tournament_round_schedule, targeting the ACTIVE
-- (non-terminal) round row(s): status IN ('call','running','awaiting_results'),
-- i.e. status <> 'completed'. The terminal ('completed') row is NEVER touched
-- (terminal guard). It NEVER touches tournament_matches, so running / finalised
-- matches stay byte-for-byte immune.
--
--   p_delta_seconds > 0  | lengthen the round
--   p_delta_seconds < 0  | shorten the round
--   p_delta_seconds = 0  | no-op (still gated, still row-locked)
--
-- The delta is applied ADDITIVELY to match_seconds, clamped to >= 0 (a delta
-- that would drive match_seconds negative pins it at 0 — the CHECK
-- (match_seconds >= 0) is honoured). ends_at is re-anchored to
-- starts_at + clamped_match_seconds so the server-side Restzeit-Formel
-- (remaining = match_seconds - effective_elapsed) and the ends_at the clients
-- read agree. Because tournament_round_schedule is in the supabase_realtime
-- publication, the write is pushed to clients via the existing schedule CDC
-- (skew-conform, no client polling) — exactly like the B2s control RPCs.
--
-- Like the B2s schedule-control RPCs this takes a transaction-scoped advisory
-- lock keyed on the tournament BEFORE mutating, to serialise against the E cron
-- tick and concurrent control / adjust calls.
--
-- Authorisation: gate public.tournament_caller_can_administer(p_tournament_id),
-- raising SQLSTATE 42501 when it returns false.
--
-- ============================ DEPENDENCIES ==============================
--   * public.tournament_caller_can_administer(uuid) — 20261281000000 (gate).
--   * public.tournament_round_schedule — 20261251000000 (the only write target).


CREATE OR REPLACE FUNCTION public.tournament_adjust_round_time(
  p_tournament_id uuid,
  p_delta_seconds int
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authorised to administer this tournament'
      USING ERRCODE = '42501';
  END IF;

  IF NOT public.tournament_caller_can_administer(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to administer this tournament'
      USING ERRCODE = '42501';
  END IF;

  -- Serialise against the E cron tick and concurrent control / adjust calls.
  PERFORM pg_advisory_xact_lock(hashtext(p_tournament_id::text));

  -- Lock the active (non-terminal) row(s) first so the additive read-modify-
  -- write is consistent under concurrency.
  PERFORM 1
     FROM public.tournament_round_schedule s
    WHERE s.tournament_id = p_tournament_id
      AND s.status IN ('call','running','awaiting_results')
    FOR UPDATE;

  -- Additive adjust on match_seconds, clamped to >= 0 (CHECK-safe), with
  -- ends_at re-anchored to starts_at + the clamped length so the Restzeit
  -- formula and the CDC-pushed ends_at agree.
  UPDATE public.tournament_round_schedule s
     SET match_seconds = GREATEST(s.match_seconds + p_delta_seconds, 0),
         ends_at = s.starts_at
                 + make_interval(secs => GREATEST(s.match_seconds + p_delta_seconds, 0))
   WHERE s.tournament_id = p_tournament_id
     AND s.status IN ('call','running','awaiting_results');
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_adjust_round_time(uuid, int) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_adjust_round_time(uuid, int) TO authenticated;

COMMENT ON FUNCTION public.tournament_adjust_round_time(uuid, int) IS
  'Spec organizer-cockpit §6/§9.5: additively adjust the LIVE round''s length. '
  'p_delta_seconds > 0 lengthens, < 0 shortens; match_seconds += delta clamped '
  'to >= 0, with ends_at re-anchored to starts_at + match_seconds so the '
  'Restzeit formula and the CDC-pushed ends_at agree. Gate '
  'tournament_caller_can_administer (42501). Advisory xact-lock + FOR UPDATE on '
  'the active (non-terminal) tournament_round_schedule row(s). Writes ONLY the '
  'schedule; never touches tournament_matches or the completed row.';
