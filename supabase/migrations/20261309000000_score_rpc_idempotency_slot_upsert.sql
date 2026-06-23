-- Tournament feature — fix the idempotent per-set score path so a
-- same-slot re-submit with a bumped Lamport-Counter no longer dies on
-- the total `unique_slot` constraint.
--
-- Background. `tournament_set_score_proposals_unique_slot` is a TOTAL
-- UNIQUE on (match_id, consensus_round, set_number, submitter_user_id) —
-- exactly one current proposal per submitter per attempt per set
-- (DSCORE-30: the last input before attempt-close is THE team input).
-- The 6-arg overload introduced in 20260701000003 arbitrated its
-- INSERT ... ON CONFLICT against the PARTIAL idempotency index
-- (six columns incl. lamport_counter + device_id) and did DO NOTHING.
--
-- That arbiter only fires on a byte-identical replay. An outbox flush
-- that re-sends the same slot with a NEW lamport_counter (or corrected
-- device) misses the partial index, then hits the total unique_slot and
-- raises 23505. The legacy 4-arg path already does the right thing —
-- UPSERT on unique_slot. This migration makes the idempotent path do the
-- same UPSERT, with a guard that keeps an identical replay a clean no-op.
--
-- Behaviour after this migration:
--   * identical replay (same lamport + device) → no write (the WHERE
--     guard suppresses the UPDATE), still returns the existing snapshot.
--   * bumped lamport / changed device on the same slot → replace-in-place,
--     one row, latest values + lamport + device persisted (DSCORE-30).
--   * distinct submitter or distinct (round, set) slot → its own row,
--     because unique_slot stays total and still discriminates those.
--
-- Additive: only the 6-arg function body changes. Schema, constraints
-- and the legacy 4-arg overload are untouched. The partial idempotency
-- index stays as a defensive guard but is no longer the arbiter.

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

  -- Arbitrate on the TOTAL slot key so a bumped Lamport on the same slot
  -- replaces in place instead of colliding on unique_slot. The WHERE
  -- guard keeps a byte-identical replay a no-op (no write, no row churn).
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
    ON CONFLICT (match_id, consensus_round, set_number, submitter_user_id)
    DO UPDATE SET
        basekubbs_knocked_by_a = EXCLUDED.basekubbs_knocked_by_a,
        basekubbs_knocked_by_b = EXCLUDED.basekubbs_knocked_by_b,
        set_winner             = EXCLUDED.set_winner,
        lamport_counter        = EXCLUDED.lamport_counter,
        device_id              = EXCLUDED.device_id,
        proposed_at            = now()
      WHERE tournament_set_score_proposals.lamport_counter
              IS DISTINCT FROM EXCLUDED.lamport_counter
         OR tournament_set_score_proposals.device_id
              IS DISTINCT FROM EXCLUDED.device_id;

  RETURN public._tournament_match_snapshot(p_match_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_propose_set_score(
  uuid, int, int, jsonb, int, text) TO authenticated;
