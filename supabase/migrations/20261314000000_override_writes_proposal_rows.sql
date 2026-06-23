-- Organizer override now persists per-set consensus rows.
--
-- Two score endpoints fed the standings differently. The consensus path
-- (tournament_propose_set_scores) writes ONE tournament_set_score_proposals
-- row per set and stamps tournament_matches with final_score_a/b + winner.
-- The override path (tournament_organizer_override, last def in
-- 20261281000000_gate_split.sql) computed the EKC totals and stamped ONLY
-- tournament_matches (status='overridden', winner, final_score, finalized_at)
-- — it never wrote a proposal row.
--
-- The standings/ranking RPCs (tournament_pool_standings,
-- tournament_stage_ranking, _tournament_schoch_buchholz classic branch) derive
-- kubb_diff + wins from exactly those proposal rows via DISTINCT ON
-- (match_id, set_number). For an overridden match the LEFT JOIN found nothing
-- and collapsed kubb_diff/wins to 0 — wrong group-phase ordering whenever the
-- points tie and kubb_diff is the deciding criterion.
--
-- Fix: keep the match-row stamp and the audit event byte-identical, and
-- additively write the same per-set proposal rows the consensus path writes,
-- using the same columns and the same king-outcome resolver. A stale-cleanup
-- runs first so an override out of 'disputed' drops conflicting player rows —
-- otherwise player and organizer rows would mix in the DISTINCT ON aggregate
-- (which orders by submitter_user_id) and corrupt kubb_diff.
--
-- The upsert targets the TOTAL unique_slot (match_id, consensus_round,
-- set_number, submitter_user_id), consistent with the consensus path since
-- 20261309000000 — a repeated override by the same organizer replaces in place
-- instead of duplicating. The consensus path is untouched.

CREATE OR REPLACE FUNCTION public.tournament_organizer_override(p_match_id uuid, p_final_set_scores jsonb, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
  v_set            jsonb;
  v_set_no         int := 0;
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

  -- P2-S gate split: live intervention gate tournament_caller_can_administer
  -- (creator OR club owner/admin/referee) replaces the creator-only check.
  IF NOT public.tournament_caller_can_administer(v_tournament_id) THEN
    RAISE EXCEPTION 'caller cannot administer this tournament'
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

  -- Additive: persist the same per-set consensus rows the player path writes,
  -- so kubb_diff + wins flow into the standings/ranking RPCs for overridden
  -- matches too. v_round defaults to 1 on the match row (always set, even for
  -- an override out of 'scheduled').
  --
  -- Stale-cleanup first: an override out of 'disputed' can leave conflicting
  -- player consensus rows for this round. They must go, otherwise player and
  -- organizer rows mix in the DISTINCT ON (match_id, set_number) aggregate —
  -- which orders by submitter_user_id — and the wrong row wins, corrupting
  -- kubb_diff.
  DELETE FROM public.tournament_set_score_proposals
    WHERE match_id = p_match_id
      AND consensus_round = v_round;

  FOR v_set IN SELECT * FROM jsonb_array_elements(p_final_set_scores) LOOP
    v_set_no := v_set_no + 1;
    INSERT INTO public.tournament_set_score_proposals(
        match_id, consensus_round, set_number, submitter_user_id,
        basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner,
        set_king_outcome)
      VALUES (
        p_match_id, v_round, v_set_no::smallint, v_caller,
        (v_set ->> 'basekubbs_a')::smallint,
        (v_set ->> 'basekubbs_b')::smallint,
        v_set ->> 'winner',
        public._tournament_resolve_king_outcome(v_set))
      ON CONFLICT (match_id, consensus_round, set_number, submitter_user_id)
      DO UPDATE SET
          basekubbs_knocked_by_a = EXCLUDED.basekubbs_knocked_by_a,
          basekubbs_knocked_by_b = EXCLUDED.basekubbs_knocked_by_b,
          set_winner             = EXCLUDED.set_winner,
          set_king_outcome       = EXCLUDED.set_king_outcome,
          proposed_at            = now();
  END LOOP;

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
$function$
;

GRANT EXECUTE ON FUNCTION public.tournament_organizer_override TO authenticated;
