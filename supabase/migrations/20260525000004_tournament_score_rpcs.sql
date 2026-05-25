-- Tournament feature — M1 score-proposal consensus engine and
-- organizer-override RPCs.
--
-- Two SECURITY DEFINER functions plus one internal helper. The
-- consensus engine is `tournament_propose_set_scores`: it row-locks
-- the match, upserts the caller's per-set proposals for the current
-- consensus_round, then runs the consensus check. If both sides have
-- submitted complete, identical proposals (in agreement on every per-
-- set value), the match is FINALIZED. If both sides have submitted
-- but disagree on at least one value, the round is bumped — except
-- on round 3, where the match flips to `disputed`. The
-- `tournament_organizer_override` RPC short-circuits the consensus
-- engine: the creator writes final scores directly to the match and
-- the match is marked `overridden`. A required free-text reason is
-- captured in the audit-event payload per DSCORE-55.
--
-- EKC totals per side =
--   sum_over_sets(basekubbs_knocked_by_side
--                 + 3 * (1 if set_winner = side else 0)).

-- ---- 1. Internal helper: EKC totals + set-count winner ---------------

CREATE OR REPLACE FUNCTION public._tournament_compute_ekc(p_set_scores jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_set       jsonb;
  v_a_kubbs   int;
  v_b_kubbs   int;
  v_winner    text;
  v_total_a   int := 0;
  v_total_b   int := 0;
  v_sets_a    int := 0;
  v_sets_b    int := 0;
  v_match_w   text;
BEGIN
  IF p_set_scores IS NULL OR jsonb_typeof(p_set_scores) <> 'array' THEN
    RAISE EXCEPTION 'set_scores must be a JSON array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_set_scores) < 1
     OR jsonb_array_length(p_set_scores) > 9 THEN
    RAISE EXCEPTION 'set_scores length must be 1..9' USING ERRCODE = '22023';
  END IF;

  FOR v_set IN SELECT * FROM jsonb_array_elements(p_set_scores) LOOP
    v_a_kubbs := (v_set ->> 'basekubbs_a')::int;
    v_b_kubbs := (v_set ->> 'basekubbs_b')::int;
    v_winner  := v_set ->> 'winner';
    IF v_a_kubbs IS NULL OR v_a_kubbs < 0 OR v_a_kubbs > 6
       OR v_b_kubbs IS NULL OR v_b_kubbs < 0 OR v_b_kubbs > 6 THEN
      RAISE EXCEPTION 'basekubbs must be integers 0..6' USING ERRCODE = '22023';
    END IF;
    IF v_winner NOT IN ('A','B','none') THEN
      RAISE EXCEPTION 'winner must be A, B or none' USING ERRCODE = '22023';
    END IF;
    v_total_a := v_total_a + v_a_kubbs + CASE WHEN v_winner = 'A' THEN 3 ELSE 0 END;
    v_total_b := v_total_b + v_b_kubbs + CASE WHEN v_winner = 'B' THEN 3 ELSE 0 END;
    IF v_winner = 'A' THEN v_sets_a := v_sets_a + 1; END IF;
    IF v_winner = 'B' THEN v_sets_b := v_sets_b + 1; END IF;
  END LOOP;

  IF v_sets_a > v_sets_b THEN v_match_w := 'A';
  ELSIF v_sets_b > v_sets_a THEN v_match_w := 'B';
  ELSE v_match_w := NULL;
  END IF;

  RETURN jsonb_build_object(
    'final_score_a', v_total_a,
    'final_score_b', v_total_b,
    'sets_won_a',    v_sets_a,
    'sets_won_b',    v_sets_b,
    'match_winner',  v_match_w
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_compute_ekc(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_compute_ekc(jsonb) FROM authenticated;


-- ---- 2. tournament_propose_set_scores --------------------------------

CREATE OR REPLACE FUNCTION public.tournament_propose_set_scores(
  p_match_id        uuid,
  p_consensus_round int,
  p_set_scores      jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller          uuid;
  v_tournament_id   uuid;
  v_creator         uuid;
  v_status          text;
  v_round           smallint;
  v_part_a          uuid;
  v_part_b          uuid;
  v_user_a          uuid;
  v_user_b          uuid;
  v_match_format    jsonb;
  v_sets_to_win     int;
  v_set_count       int;
  v_set             jsonb;
  v_set_no          int := 0;
  v_winner_part     uuid;
  v_final_a         int;
  v_final_b         int;
  v_sets_a          int;
  v_sets_b          int;
  v_match_winner    text;
  v_ekc             jsonb;
  v_my_side         text;
  v_other_user      uuid;
  v_other_count     int;
  v_disagree_count  int;
  v_result_status   text;
  v_result_round    smallint;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Lock the match row first so concurrent proposals serialise.
  SELECT m.tournament_id, m.status, m.consensus_round,
         m.participant_a, m.participant_b
    INTO v_tournament_id, v_status, v_round, v_part_a, v_part_b
    FROM public.tournament_matches m
    WHERE m.id = p_match_id
    FOR UPDATE;

  IF v_tournament_id IS NULL THEN
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
  IF v_part_a IS NULL OR v_part_b IS NULL THEN
    RAISE EXCEPTION 'match has no two-sided pairing' USING ERRCODE = '22023';
  END IF;

  -- Resolve tournament header (creator + match_format).
  SELECT t.created_by, t.match_format
    INTO v_creator, v_match_format
    FROM public.tournaments t
    WHERE t.id = v_tournament_id;

  v_sets_to_win := COALESCE((v_match_format ->> 'sets_to_win')::int, 1);
  IF v_sets_to_win < 1 OR v_sets_to_win > 5 THEN
    RAISE EXCEPTION 'invalid match_format.sets_to_win: %', v_sets_to_win
      USING ERRCODE = '22023';
  END IF;

  -- Resolve each side's user_id (M1: one user per participant).
  SELECT user_id INTO v_user_a
    FROM public.tournament_participants WHERE id = v_part_a;
  SELECT user_id INTO v_user_b
    FROM public.tournament_participants WHERE id = v_part_b;

  -- Determine caller's side. Creator may submit only as themself
  -- (still has to be a participant of this match) — per task spec.
  IF v_caller = v_user_a THEN
    v_my_side := 'A';
    v_other_user := v_user_b;
  ELSIF v_caller = v_user_b THEN
    v_my_side := 'B';
    v_other_user := v_user_a;
  ELSE
    RAISE EXCEPTION 'caller is not a participant of this match'
      USING ERRCODE = '42501';
  END IF;

  -- Validate set_scores array length.
  IF p_set_scores IS NULL OR jsonb_typeof(p_set_scores) <> 'array' THEN
    RAISE EXCEPTION 'set_scores must be a JSON array' USING ERRCODE = '22023';
  END IF;
  v_set_count := jsonb_array_length(p_set_scores);
  IF v_set_count < 1 OR v_set_count > (2 * v_sets_to_win - 1) THEN
    RAISE EXCEPTION 'set count % out of range 1..%',
      v_set_count, (2 * v_sets_to_win - 1) USING ERRCODE = '22023';
  END IF;

  -- Auto-promote scheduled → awaiting_results on the first proposal.
  IF v_status = 'scheduled' THEN
    UPDATE public.tournament_matches
      SET status     = 'awaiting_results',
          started_at = COALESCE(started_at, now())
      WHERE id = p_match_id;
    v_status := 'awaiting_results';
    INSERT INTO public.tournament_audit_events(
        tournament_id, match_id, kind, actor_user_id, payload)
      VALUES (v_tournament_id, p_match_id, 'match_started',
              v_caller, jsonb_build_object('consensus_round', v_round));
  END IF;

  -- Validate each set and upsert the caller's proposals for this round.
  FOR v_set IN SELECT * FROM jsonb_array_elements(p_set_scores) LOOP
    v_set_no := v_set_no + 1;
    DECLARE
      v_a_kubbs int := (v_set ->> 'basekubbs_a')::int;
      v_b_kubbs int := (v_set ->> 'basekubbs_b')::int;
      v_winner  text := v_set ->> 'winner';
    BEGIN
      IF v_a_kubbs IS NULL OR v_a_kubbs < 0 OR v_a_kubbs > 6
         OR v_b_kubbs IS NULL OR v_b_kubbs < 0 OR v_b_kubbs > 6 THEN
        RAISE EXCEPTION 'basekubbs must be integers 0..6 (set %)', v_set_no
          USING ERRCODE = '22023';
      END IF;
      IF v_winner NOT IN ('A','B','none') THEN
        RAISE EXCEPTION 'winner must be A, B or none (set %)', v_set_no
          USING ERRCODE = '22023';
      END IF;

      INSERT INTO public.tournament_set_score_proposals(
          match_id, consensus_round, set_number, submitter_user_id,
          basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner)
        VALUES (
          p_match_id, v_round, v_set_no::smallint, v_caller,
          v_a_kubbs::smallint, v_b_kubbs::smallint, v_winner)
        ON CONFLICT (match_id, consensus_round, set_number, submitter_user_id)
        DO UPDATE SET
            basekubbs_knocked_by_a = EXCLUDED.basekubbs_knocked_by_a,
            basekubbs_knocked_by_b = EXCLUDED.basekubbs_knocked_by_b,
            set_winner             = EXCLUDED.set_winner,
            proposed_at            = now();
    END;
  END LOOP;

  -- If the caller resubmits a different set-count for this round, drop
  -- any stale set rows past the new length (keeps the per-side proposal
  -- coherent for the consensus check).
  DELETE FROM public.tournament_set_score_proposals
    WHERE match_id = p_match_id
      AND consensus_round = v_round
      AND submitter_user_id = v_caller
      AND set_number > v_set_count;

  INSERT INTO public.tournament_audit_events(
      tournament_id, match_id, kind, actor_user_id, payload)
    VALUES (v_tournament_id, p_match_id, 'set_score_proposed', v_caller,
            jsonb_build_object(
              'consensus_round', v_round,
              'set_count', v_set_count,
              'side', v_my_side));

  -- Consensus check: does the other side also have a complete proposal
  -- for this round, and do both sides agree on every per-set value?
  SELECT count(*) INTO v_other_count
    FROM public.tournament_set_score_proposals
    WHERE match_id = p_match_id
      AND consensus_round = v_round
      AND submitter_user_id = v_other_user;

  IF v_other_count = 0 OR v_other_count <> v_set_count THEN
    -- Other side hasn't (yet) submitted a proposal of equal length.
    RETURN jsonb_build_object(
      'match_id',              p_match_id,
      'status',                v_status,
      'consensus_round',       v_round,
      'winner_participant_id', NULL,
      'final_score_a',         NULL,
      'final_score_b',         NULL);
  END IF;

  -- Both sides submitted same set-count. Compare set-by-set.
  SELECT count(*) INTO v_disagree_count
    FROM public.tournament_set_score_proposals a
    JOIN public.tournament_set_score_proposals b
      ON  b.match_id = a.match_id
      AND b.consensus_round = a.consensus_round
      AND b.set_number = a.set_number
    WHERE a.match_id = p_match_id
      AND a.consensus_round = v_round
      AND a.submitter_user_id = v_user_a
      AND b.submitter_user_id = v_user_b
      AND (a.basekubbs_knocked_by_a IS DISTINCT FROM b.basekubbs_knocked_by_a
        OR a.basekubbs_knocked_by_b IS DISTINCT FROM b.basekubbs_knocked_by_b
        OR a.set_winner             IS DISTINCT FROM b.set_winner);

  IF v_disagree_count = 0 THEN
    -- Agreement. Finalise the match.
    v_ekc := public._tournament_compute_ekc(p_set_scores);
    v_final_a      := (v_ekc ->> 'final_score_a')::int;
    v_final_b      := (v_ekc ->> 'final_score_b')::int;
    v_sets_a       := (v_ekc ->> 'sets_won_a')::int;
    v_sets_b       := (v_ekc ->> 'sets_won_b')::int;
    v_match_winner :=  v_ekc ->> 'match_winner';

    IF v_match_winner IS NULL
       OR (v_sets_a < v_sets_to_win AND v_sets_b < v_sets_to_win) THEN
      RAISE EXCEPTION 'agreed result is not decisive (sets_to_win=%, sets %-%)',
        v_sets_to_win, v_sets_a, v_sets_b USING ERRCODE = '22023';
    END IF;

    v_winner_part := CASE WHEN v_match_winner = 'A' THEN v_part_a
                          ELSE v_part_b END;

    UPDATE public.tournament_matches
      SET status              = 'finalized',
          winner_participant  = v_winner_part,
          final_score_a       = v_final_a,
          final_score_b       = v_final_b,
          finalized_at        = now()
      WHERE id = p_match_id;

    INSERT INTO public.tournament_audit_events(
        tournament_id, match_id, kind, actor_user_id, payload)
      VALUES (v_tournament_id, p_match_id, 'match_finalized', v_caller,
              jsonb_build_object(
                'consensus_round',       v_round,
                'winner_participant_id', v_winner_part,
                'final_score_a',         v_final_a,
                'final_score_b',         v_final_b,
                'sets_won_a',            v_sets_a,
                'sets_won_b',            v_sets_b));

    RETURN jsonb_build_object(
      'match_id',              p_match_id,
      'status',                'finalized',
      'consensus_round',       v_round,
      'winner_participant_id', v_winner_part,
      'final_score_a',         v_final_a,
      'final_score_b',         v_final_b);
  END IF;

  -- Disagreement. Either bump consensus_round or flip to disputed.
  IF v_round < 3 THEN
    UPDATE public.tournament_matches
      SET consensus_round = v_round + 1
      WHERE id = p_match_id;
    v_result_round  := v_round + 1;
    v_result_status := 'awaiting_results';
    INSERT INTO public.tournament_audit_events(
        tournament_id, match_id, kind, actor_user_id, payload)
      VALUES (v_tournament_id, p_match_id, 'consensus_round_bumped', v_caller,
              jsonb_build_object('from', v_round, 'to', v_round + 1,
                                 'disagree_set_count', v_disagree_count));
  ELSE
    UPDATE public.tournament_matches
      SET status = 'disputed'
      WHERE id = p_match_id;
    v_result_round  := v_round;
    v_result_status := 'disputed';
    INSERT INTO public.tournament_audit_events(
        tournament_id, match_id, kind, actor_user_id, payload)
      VALUES (v_tournament_id, p_match_id, 'dispute_raised', v_caller,
              jsonb_build_object('consensus_round', v_round,
                                 'disagree_set_count', v_disagree_count));
  END IF;

  RETURN jsonb_build_object(
    'match_id',              p_match_id,
    'status',                v_result_status,
    'consensus_round',       v_result_round,
    'winner_participant_id', NULL,
    'final_score_a',         NULL,
    'final_score_b',         NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_propose_set_scores TO authenticated;


-- ---- 3. tournament_organizer_override --------------------------------

CREATE OR REPLACE FUNCTION public.tournament_organizer_override(
  p_match_id         uuid,
  p_final_set_scores jsonb,
  p_reason           text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller         uuid;
  v_tournament_id  uuid;
  v_creator        uuid;
  v_status         text;
  v_round          smallint;
  v_part_a         uuid;
  v_part_b         uuid;
  v_final_a        int;
  v_final_b        int;
  v_match_winner   text;
  v_ekc            jsonb;
  v_winner_part    uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR length(p_reason) < 1 OR length(p_reason) > 500 THEN
    RAISE EXCEPTION 'override reason length must be 1..500'
      USING ERRCODE = '22023';
  END IF;

  -- Lock the match row.
  SELECT m.tournament_id, m.status, m.consensus_round,
         m.participant_a, m.participant_b
    INTO v_tournament_id, v_status, v_round, v_part_a, v_part_b
    FROM public.tournament_matches m
    WHERE m.id = p_match_id
    FOR UPDATE;

  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'match not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT created_by INTO v_creator
    FROM public.tournaments WHERE id = v_tournament_id;
  IF v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'only the tournament creator may override'
      USING ERRCODE = '42501';
  END IF;

  IF v_status NOT IN ('awaiting_results','disputed') THEN
    RAISE EXCEPTION 'match cannot be overridden in status %', v_status
      USING ERRCODE = '22023';
  END IF;
  IF v_part_a IS NULL OR v_part_b IS NULL THEN
    RAISE EXCEPTION 'match has no two-sided pairing' USING ERRCODE = '22023';
  END IF;

  -- Compute EKC totals from the organizer's final set scores.
  v_ekc := public._tournament_compute_ekc(p_final_set_scores);
  v_final_a      := (v_ekc ->> 'final_score_a')::int;
  v_final_b      := (v_ekc ->> 'final_score_b')::int;
  v_match_winner :=  v_ekc ->> 'match_winner';

  IF v_match_winner IS NULL THEN
    RAISE EXCEPTION 'override result must have a set-count winner'
      USING ERRCODE = '22023';
  END IF;
  v_winner_part := CASE WHEN v_match_winner = 'A' THEN v_part_a
                        ELSE v_part_b END;

  UPDATE public.tournament_matches
    SET status              = 'overridden',
        winner_participant  = v_winner_part,
        final_score_a       = v_final_a,
        final_score_b       = v_final_b,
        finalized_at        = now()
    WHERE id = p_match_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, match_id, kind, actor_user_id, payload)
    VALUES (v_tournament_id, p_match_id, 'organizer_override', v_caller,
            jsonb_build_object(
              'reason',                p_reason,
              'final_set_scores',      p_final_set_scores,
              'final_score_a',         v_final_a,
              'final_score_b',         v_final_b,
              'winner_participant_id', v_winner_part,
              'previous_status',       v_status,
              'consensus_round',       v_round,
              'caller',                v_caller));
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_organizer_override TO authenticated;
