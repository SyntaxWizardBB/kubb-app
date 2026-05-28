-- Sprint A · W3-T2 — Per-set King-Outcome wire column.
--
-- R11-F-01: every set score now carries an explicit King-Outcome
-- (`hit_by` / `missed` / `timed_out`) alongside the legacy `set_winner`.
-- The set-winner stays in the table because the consensus engine still
-- compares it as part of the agreement check; the new column drives the
-- EKC tally (TimedOut sets contribute 0:0). Existing rows are
-- back-filled with `'missed'` so the historical implicit behaviour is
-- preserved verbatim.
--
-- The single-set RPC `tournament_propose_set_score` is extended to
-- accept the outcome via the `p_score` JSON object under the
-- `king_outcome` key. Both the legacy 4-arg and the idempotent 6-arg
-- overloads are rewritten so the wire format stays in one place. For
-- backward compat, the older `king_hit_by: '<participant_id>' | null`
-- shape from W2 still works: a non-null value upgrades to `hit_by`,
-- `null` to `missed`. Missing both keys defaults to `missed`.

-- ---- 1. Schema column ------------------------------------------------

ALTER TABLE public.tournament_set_score_proposals
  ADD COLUMN IF NOT EXISTS set_king_outcome text
    NOT NULL
    DEFAULT 'missed'
    CHECK (set_king_outcome IN ('hit_by', 'missed', 'timed_out'));

COMMENT ON COLUMN public.tournament_set_score_proposals.set_king_outcome IS
  'R11-F-01: how the king was dealt with in this set. `hit_by` = king '
  'fell (set winner credited a king-point); `missed` = regular set win '
  'without a king-point; `timed_out` = no king-hit, set contributes 0:0 '
  'to the EKC tally.';


-- ---- 2. Internal helper: resolve king-outcome from JSON payload ------
-- Accepts both the new `king_outcome: 'hit_by'|'missed'|'timed_out'`
-- shape and the legacy `king_hit_by: '<uuid>'|null` shape from W2.
-- Defaults to `'missed'` when neither key is present.

CREATE OR REPLACE FUNCTION public._tournament_resolve_king_outcome(p_score jsonb)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_outcome text;
BEGIN
  IF p_score IS NULL THEN
    RETURN 'missed';
  END IF;

  -- Preferred: explicit `king_outcome` token.
  IF p_score ? 'king_outcome' THEN
    v_outcome := p_score ->> 'king_outcome';
    IF v_outcome NOT IN ('hit_by', 'missed', 'timed_out') THEN
      RAISE EXCEPTION 'king_outcome must be hit_by, missed or timed_out (got %)',
        v_outcome USING ERRCODE = '22023';
    END IF;
    RETURN v_outcome;
  END IF;

  -- Backward-compat: `king_hit_by` projection from W2.
  IF p_score ? 'king_hit_by' THEN
    IF p_score ->> 'king_hit_by' IS NULL THEN
      RETURN 'missed';
    END IF;
    RETURN 'hit_by';
  END IF;

  RETURN 'missed';
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_resolve_king_outcome(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_resolve_king_outcome(jsonb) FROM authenticated;


-- ---- 3. Rewrite legacy 4-arg tournament_propose_set_score ------------
-- Same body as `20260701000003_score_rpc_idempotency.sql` §4 but with
-- the new `set_king_outcome` column wired in via the resolver helper.

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
  v_round   smallint;
  v_outcome text;
BEGIN
  v_round := public._tournament_validate_set_proposal(
    p_match_id, p_consensus_round, p_set_index, p_score);
  v_outcome := public._tournament_resolve_king_outcome(p_score);

  INSERT INTO public.tournament_set_score_proposals(
      match_id, consensus_round, set_number, submitter_user_id,
      basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner,
      set_king_outcome)
    VALUES (
      p_match_id, v_round, p_set_index::smallint, auth.uid(),
      ((p_score ->> 'basekubbs_a')::int)::smallint,
      ((p_score ->> 'basekubbs_b')::int)::smallint,
      p_score ->> 'winner',
      v_outcome)
    ON CONFLICT (match_id, consensus_round, set_number, submitter_user_id)
    DO UPDATE SET
        basekubbs_knocked_by_a = EXCLUDED.basekubbs_knocked_by_a,
        basekubbs_knocked_by_b = EXCLUDED.basekubbs_knocked_by_b,
        set_winner             = EXCLUDED.set_winner,
        set_king_outcome       = EXCLUDED.set_king_outcome,
        proposed_at            = now();

  RETURN public._tournament_match_snapshot(p_match_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_propose_set_score(
  uuid, int, int, jsonb) TO authenticated;


-- ---- 4. Rewrite idempotent 6-arg tournament_propose_set_score --------

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
  v_round   smallint;
  v_outcome text;
BEGIN
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
  v_outcome := public._tournament_resolve_king_outcome(p_score);

  INSERT INTO public.tournament_set_score_proposals(
      match_id, consensus_round, set_number, submitter_user_id,
      basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner,
      set_king_outcome,
      lamport_counter, device_id)
    VALUES (
      p_match_id, v_round, p_set_index::smallint, auth.uid(),
      ((p_score ->> 'basekubbs_a')::int)::smallint,
      ((p_score ->> 'basekubbs_b')::int)::smallint,
      p_score ->> 'winner',
      v_outcome,
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
