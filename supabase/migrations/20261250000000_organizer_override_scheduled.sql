-- T1 fix: let the organizer enter a result for a match that is still
-- `scheduled` (nobody proposed yet) — the typical on-site case where the
-- organizer runs the match physically and types the final score directly.
-- Previously the override gate only allowed `awaiting_results`/`disputed`,
-- so a fresh match had no organizer entry path at all (only forfeit).
--
-- The function writes the final score and flips status straight to
-- `overridden`, so no intermediate promotion is needed — we only widen the
-- status gate to include `scheduled`. Additive CREATE OR REPLACE on the
-- current definition (20260525000004); body identical except the gate.
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

  -- T1: include 'scheduled' so the organizer can enter a result for a match
  -- that hasn't received any player proposal yet (on-site entry). Terminal
  -- states (finalized/overridden/voided) stay rejected.
  IF v_status NOT IN ('scheduled','awaiting_results','disputed') THEN
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
