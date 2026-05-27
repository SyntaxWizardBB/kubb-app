-- Tournament feature — M4.3 server-side score-proposal idempotency.
--
-- Outbox-Flusher (M4.3) may re-send the same per-set score after a
-- network round-trip is lost. Without server-side deduplication, the
-- second attempt would land as a duplicate row. This migration adds
-- two optional discriminators to `tournament_set_score_proposals`
-- (`lamport_counter`, `device_id`) plus a partial UNIQUE index that
-- fires only when a caller opts into the idempotency contract by
-- sending both values.
--
-- A new per-set RPC `tournament_propose_set_score` is introduced with
-- two overloads sharing the same JSONB Match-snapshot return shape:
--
--   * Legacy (4-arg): UPSERTs the proposal exactly like the M1 array
--     engine and ignores the Lamport columns.
--   * Idempotent (6-arg): INSERT ... ON CONFLICT (partial UNIQUE
--     index) DO NOTHING — duplicate re-submits silently no-op and
--     return the existing snapshot; distinct counters or device_ids
--     count as separate submissions.

-- ---- 1. Schema columns + partial UNIQUE index ------------------------

ALTER TABLE public.tournament_set_score_proposals
  ADD COLUMN IF NOT EXISTS lamport_counter int,
  ADD COLUMN IF NOT EXISTS device_id       text;

CREATE UNIQUE INDEX IF NOT EXISTS tournament_set_scores_idempotency_idx
  ON public.tournament_set_score_proposals
     (match_id, consensus_round, set_number, submitter_user_id,
      lamport_counter, device_id)
  WHERE lamport_counter IS NOT NULL;


-- ---- 2. Match-snapshot return shape (shared by both overloads) -------

CREATE OR REPLACE FUNCTION public._tournament_match_snapshot(p_match_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT jsonb_build_object(
    'match_id',              m.id,
    'status',                m.status,
    'consensus_round',       m.consensus_round,
    'winner_participant_id', m.winner_participant,
    'final_score_a',         m.final_score_a,
    'final_score_b',         m.final_score_b)
    FROM public.tournament_matches m
    WHERE m.id = p_match_id;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_match_snapshot(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_match_snapshot(uuid) FROM authenticated;


-- ---- 3. Shared validation helper -------------------------------------
-- Returns the locked match's current consensus_round on success;
-- raises on any precondition violation. Both RPC overloads route
-- through here so the error contract stays in one place.

CREATE OR REPLACE FUNCTION public._tournament_validate_set_proposal(
  p_match_id        uuid,
  p_consensus_round int,
  p_set_index       int,
  p_score           jsonb)
RETURNS smallint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_round  smallint;
  v_status text;
  v_a int := (p_score ->> 'basekubbs_a')::int;
  v_b int := (p_score ->> 'basekubbs_b')::int;
  v_w text :=  p_score ->> 'winner';
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT m.status, m.consensus_round INTO v_status, v_round
    FROM public.tournament_matches m
    WHERE m.id = p_match_id FOR UPDATE;
  IF v_round IS NULL THEN
    RAISE EXCEPTION 'match not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status NOT IN ('scheduled','awaiting_results') THEN
    RAISE EXCEPTION 'match not accepting proposals in status %', v_status
      USING ERRCODE = '22023';
  END IF;
  IF p_consensus_round IS NULL OR p_consensus_round <> v_round THEN
    RAISE EXCEPTION 'stale consensus_round (expected %, got %)',
      v_round, p_consensus_round USING ERRCODE = '40001';
  END IF;
  IF p_set_index IS NULL OR p_set_index < 1 OR p_set_index > 9 THEN
    RAISE EXCEPTION 'set_index out of range 1..9' USING ERRCODE = '22023';
  END IF;
  IF p_score IS NULL OR jsonb_typeof(p_score) <> 'object' THEN
    RAISE EXCEPTION 'score must be a JSON object' USING ERRCODE = '22023';
  END IF;
  IF v_a IS NULL OR v_a < 0 OR v_a > 6
     OR v_b IS NULL OR v_b < 0 OR v_b > 6 THEN
    RAISE EXCEPTION 'basekubbs must be integers 0..6' USING ERRCODE = '22023';
  END IF;
  IF v_w NOT IN ('A','B','none') THEN
    RAISE EXCEPTION 'winner must be A, B or none' USING ERRCODE = '22023';
  END IF;

  RETURN v_round;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_validate_set_proposal(
  uuid, int, int, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_validate_set_proposal(
  uuid, int, int, jsonb) FROM authenticated;


-- ---- 4. Legacy 4-arg RPC: tournament_propose_set_score ---------------

CREATE OR REPLACE FUNCTION public.tournament_propose_set_score(
  p_match_id        uuid,
  p_consensus_round int,
  p_set_index       int,
  p_score           jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_round smallint;
BEGIN
  v_round := public._tournament_validate_set_proposal(
    p_match_id, p_consensus_round, p_set_index, p_score);

  INSERT INTO public.tournament_set_score_proposals(
      match_id, consensus_round, set_number, submitter_user_id,
      basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner)
    VALUES (
      p_match_id, v_round, p_set_index::smallint, auth.uid(),
      ((p_score ->> 'basekubbs_a')::int)::smallint,
      ((p_score ->> 'basekubbs_b')::int)::smallint,
      p_score ->> 'winner')
    ON CONFLICT (match_id, consensus_round, set_number, submitter_user_id)
    DO UPDATE SET
        basekubbs_knocked_by_a = EXCLUDED.basekubbs_knocked_by_a,
        basekubbs_knocked_by_b = EXCLUDED.basekubbs_knocked_by_b,
        set_winner             = EXCLUDED.set_winner,
        proposed_at            = now();

  RETURN public._tournament_match_snapshot(p_match_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_propose_set_score(
  uuid, int, int, jsonb) TO authenticated;


-- ---- 5. Idempotent 6-arg RPC: tournament_propose_set_score -----------

CREATE OR REPLACE FUNCTION public.tournament_propose_set_score(
  p_match_id        uuid,
  p_consensus_round int,
  p_set_index       int,
  p_score           jsonb,
  p_lamport_counter int,
  p_device_id       text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_round smallint;
BEGIN
  -- Caller didn't opt into the idempotency contract → legacy path.
  IF p_lamport_counter IS NULL AND p_device_id IS NULL THEN
    RETURN public.tournament_propose_set_score(
      p_match_id, p_consensus_round, p_set_index, p_score);
  END IF;
  IF p_lamport_counter IS NULL OR p_device_id IS NULL THEN
    RAISE EXCEPTION 'lamport_counter and device_id must both be set'
      USING ERRCODE = '22023';
  END IF;
  IF p_lamport_counter < 0 THEN
    RAISE EXCEPTION 'lamport_counter must be non-negative'
      USING ERRCODE = '22023';
  END IF;
  IF length(p_device_id) < 1 OR length(p_device_id) > 128 THEN
    RAISE EXCEPTION 'device_id length must be 1..128'
      USING ERRCODE = '22023';
  END IF;

  v_round := public._tournament_validate_set_proposal(
    p_match_id, p_consensus_round, p_set_index, p_score);

  -- Partial UNIQUE index `tournament_set_scores_idempotency_idx`
  -- catches duplicate re-submits; a no-op INSERT still returns the
  -- existing match snapshot below.
  INSERT INTO public.tournament_set_score_proposals(
      match_id, consensus_round, set_number, submitter_user_id,
      basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner,
      lamport_counter, device_id)
    VALUES (
      p_match_id, v_round, p_set_index::smallint, auth.uid(),
      ((p_score ->> 'basekubbs_a')::int)::smallint,
      ((p_score ->> 'basekubbs_b')::int)::smallint,
      p_score ->> 'winner',
      p_lamport_counter, p_device_id)
    ON CONFLICT (match_id, consensus_round, set_number,
                 submitter_user_id, lamport_counter, device_id)
      WHERE lamport_counter IS NOT NULL
    DO NOTHING;

  RETURN public._tournament_match_snapshot(p_match_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_propose_set_score(
  uuid, int, int, jsonb, int, text) TO authenticated;
