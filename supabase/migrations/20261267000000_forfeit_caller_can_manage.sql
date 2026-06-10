-- Tournament feature — ADR-0031 Phase D5 / OE-D2 / README K6.
--
-- Re-gate `tournament_match_forfeit` from creator-only to the shared manage
-- gate `tournament_caller_can_manage(v_tournament_id)` so the No-Show→Forfait
-- shortcut in the escalation panel is usable by the same role set that runs
-- the rest of the organizer tooling (Creator OR active club role in
-- {owner, admin, organizer, referee} — K4), instead of the tournament
-- creator alone. This removes the gate asymmetry called out in the phase-D
-- risks: check-in is already manage-gated, forfeit was not.
--
-- ADDITIVE: this is a NEW migration. It does NOT touch
-- 20260601000001_tournament_match_forfeit.sql. The function below is a
-- `CREATE OR REPLACE` re-based BYTE-FOR-BYTE on the only on-disk definition
-- of `tournament_match_forfeit` (highest timestamp = 20260601000001,
-- verified via `grep -rl 'FUNCTION public.tournament_match_forfeit('`).
--
-- BODY-DIFF vs 20260601000001 (the intended diff, and ONLY this diff):
--   - SELECT … t.created_by, … INTO v_creator, …            (creator no longer read)
--   + SELECT … t.status, t.forfeit_points … INTO v_t_status, v_forfeit_points
--   - IF v_creator IS DISTINCT FROM v_caller THEN
--   -   RAISE EXCEPTION 'only the tournament creator may declare a forfeit'
--   -     USING ERRCODE = '42501';
--   - END IF;
--   + IF NOT public.tournament_caller_can_manage(v_tournament_id) THEN
--   +   RAISE EXCEPTION 'not authorised to declare a forfeit'
--   +     USING ERRCODE = '42501';
--   + END IF;
-- The v_creator DECLARE is dropped (now unused). Signature (uuid,text,text),
-- SECURITY DEFINER, search_path, the absent-side / reason validation, the row
-- lock, the score derivation, the audit insert and the return shape are all
-- byte-identical to 20260601000001.

-- ---- tournament_match_forfeit (re-gated to caller_can_manage) ---------

CREATE OR REPLACE FUNCTION public.tournament_match_forfeit(
  p_match_id      uuid,
  p_absent_side   text,
  p_reason        text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller          uuid;
  v_tournament_id   uuid;
  v_match_status    text;
  v_round           smallint;
  v_part_a          uuid;
  v_part_b          uuid;
  v_t_status        text;
  v_forfeit_points  int;
  v_final_a         int;
  v_final_b         int;
  v_winner_part     uuid;
  v_absent_part     uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- DSCORE-63 absent-side validation up-front so the error surface is
  -- predictable before we touch the row lock.
  IF p_absent_side IS NULL OR p_absent_side NOT IN ('A','B') THEN
    RAISE EXCEPTION 'absent_side must be A or B' USING ERRCODE = '22023';
  END IF;

  -- DSCORE-65: free-text reason, min 10 chars (also caps to keep the
  -- audit-event payload bounded; mirrors the override RPC's 500 ceiling).
  IF p_reason IS NULL OR length(trim(p_reason)) < 10
     OR length(p_reason) > 500 THEN
    RAISE EXCEPTION 'forfeit reason length must be between 10 and 500 chars'
      USING ERRCODE = '22023';
  END IF;

  -- Lock the match row first so a concurrent score submission cannot
  -- race the forfeit declaration.
  SELECT m.tournament_id, m.status, m.consensus_round,
         m.participant_a, m.participant_b
    INTO v_tournament_id, v_match_status, v_round, v_part_a, v_part_b
    FROM public.tournament_matches m
    WHERE m.id = p_match_id
    FOR UPDATE;

  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'match not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_part_a IS NULL OR v_part_b IS NULL THEN
    RAISE EXCEPTION 'match has no two-sided pairing — forfeit not applicable'
      USING ERRCODE = '22023';
  END IF;
  IF v_match_status NOT IN ('scheduled','awaiting_results','disputed') THEN
    RAISE EXCEPTION 'match cannot be forfeited in status %', v_match_status
      USING ERRCODE = '22023';
  END IF;

  -- Status gate: a caller who can manage the tournament (Creator OR active
  -- club role in {owner, admin, organizer, referee} — K4/K6/OE-D2) may
  -- declare a forfeit, and only while the tournament is live (spec:
  -- "running").
  SELECT t.status, t.forfeit_points
    INTO v_t_status, v_forfeit_points
    FROM public.tournaments t
    WHERE t.id = v_tournament_id;
  IF NOT public.tournament_caller_can_manage(v_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to declare a forfeit'
      USING ERRCODE = '42501';
  END IF;
  IF v_t_status <> 'live' THEN
    RAISE EXCEPTION 'forfeit not allowed in tournament status %', v_t_status
      USING ERRCODE = '22023';
  END IF;

  -- FR-CFG-11: score is derived from the tournament's forfeit_points
  -- configuration. The absent side gets 0, the present side gets the
  -- configured points (default 18 per 20260525000001_tournament_schema).
  IF v_forfeit_points IS NULL OR v_forfeit_points < 0 THEN
    RAISE EXCEPTION 'tournament.forfeit_points is not configured'
      USING ERRCODE = '22023';
  END IF;

  IF p_absent_side = 'A' THEN
    v_final_a     := 0;
    v_final_b     := v_forfeit_points;
    v_winner_part := v_part_b;
    v_absent_part := v_part_a;
  ELSE
    v_final_a     := v_forfeit_points;
    v_final_b     := 0;
    v_winner_part := v_part_a;
    v_absent_part := v_part_b;
  END IF;

  UPDATE public.tournament_matches
    SET status              = 'finalized',
        winner_participant  = v_winner_part,
        final_score_a       = v_final_a,
        final_score_b       = v_final_b,
        finalized_at        = now(),
        started_at          = COALESCE(started_at, now())
    WHERE id = p_match_id;

  -- TODO(audit-log-sweep): the Sprint A audit-log sweep will consolidate
  -- cross-feature audit writes (currently scattered between
  -- tournament_audit_events and the per-match audit hooks); this insert
  -- is the canonical entry point for the `match_forfeit_declared` event
  -- and stays here until that sweep relocates it.
  INSERT INTO public.tournament_audit_events(
      tournament_id, match_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id, p_match_id, 'match_forfeit_declared', v_caller,
      jsonb_build_object(
        'absent_side',            p_absent_side,
        'absent_participant_id',  v_absent_part,
        'winner_participant_id',  v_winner_part,
        'final_score_a',          v_final_a,
        'final_score_b',          v_final_b,
        'forfeit_points',         v_forfeit_points,
        'reason',                 p_reason,
        'previous_status',        v_match_status,
        'consensus_round',        v_round
      ));

  RETURN jsonb_build_object(
    'match_id',              p_match_id,
    'status',                'finalized',
    'winner_participant_id', v_winner_part,
    'final_score_a',         v_final_a,
    'final_score_b',         v_final_b,
    'forfeit_points',        v_forfeit_points
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_match_forfeit(uuid, text, text)
  TO authenticated;
