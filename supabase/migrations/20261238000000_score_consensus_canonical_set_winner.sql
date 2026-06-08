-- Tournament feature — M2a: canonical, phase-/scoring-aware set winner in
-- the array score-consensus RPC + persist set_king_outcome.
--
-- ROOT-CAUSE FIX for the "Konsens hängt / disputed" bug. Two defects in the
-- array RPC `tournament_propose_set_scores` (latest body:
-- 20260615000007_score_rpc_team_patch.sql — confirmed via
-- pg_get_functiondef against the live DB; no later migration overrides it):
--
--   (1) The INSERT into tournament_set_score_proposals never wrote
--       set_king_outcome (the single-set RPC does, since 20260601000002),
--       so every array-RPC proposal stored NULL for the king outcome.
--   (2) The consensus comparison matched only basekubbs_a/b + the RAW
--       set_winner string. Combined with the OLD client fallback
--       (`d.king ?? (kubbsA >= kubbsB ? A : B)`) that FORCED an A/B winner
--       for a king-less group set, two identical real inputs could be
--       scored as disagreement and the match ran to consensus_round 3 ->
--       disputed.
--
-- This migration:
--   * Adds a deterministic server-side canonical set-winner helper
--     `_tournament_canonical_set_winner(king_outcome, winner, kubbs_a,
--      kubbs_b, phase, scoring)` that MIRRORS the pure-Dart
--      `resolveSetWinnerForSide` (packages/kubb_domain ekc_score.dart):
--        - king fell ('hit_by') -> the submitted A/B winner,
--        - no king + group + classic -> 'none',
--        - no king + group + ekc    -> by base-kubbs, draw -> 'none',
--        - no king + KO             -> the submitted winner verbatim
--          (the M2b finisher prompt is authoritative client-side; the
--           server takes the value the client delivered, with NO auto
--           kubb-majority fallback).
--   * Persists set_king_outcome on INSERT (and ON CONFLICT DO UPDATE),
--     read from the wire 'king_outcome' field via the existing
--     `_tournament_resolve_king_outcome` resolver (hit_by/missed/timed_out).
--   * Compares the CANONICAL set winner (plus base-kubbs and king-outcome)
--     in the consensus check, so two identical real inputs — including
--     beidseitig 'none'/'Keiner' in the group phase — count as agreement
--     and the match finalises / the standing stays; only real differences
--     bump consensus_round / flip to disputed.
--
-- Additive only: CREATE OR REPLACE of the function + one new helper. No
-- DROP / DELETE / TRUNCATE / schema removal. The rest of the function body
-- is restated VERBATIM from 20260615000007 (the team-path submitter check,
-- the per-side aggregation, the EKC finalisation, the round-bump/dispute
-- branches) — only the INSERT columns and the consensus comparison change.

-- ---- 1. Canonical set-winner helper (server mirror of Dart) ----------

CREATE OR REPLACE FUNCTION public._tournament_canonical_set_winner(
  p_king_outcome text,   -- 'hit_by' | 'missed' | 'timed_out' | NULL
  p_winner       text,   -- submitted 'A' | 'B' | 'none'
  p_kubbs_a      int,
  p_kubbs_b      int,
  p_phase        text,   -- tournament_matches.phase ('group' | KO phases)
  p_scoring      text    -- tournaments.scoring ('classic' | 'ekc')
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  -- King fell -> the side the client recorded as winner wins the set,
  -- regardless of phase / scoring. (The client encodes the king side in
  -- set_winner; we trust that A/B value.)
  IF p_king_outcome = 'hit_by' THEN
    RETURN CASE WHEN p_winner IN ('A','B') THEN p_winner ELSE 'none' END;
  END IF;

  -- No king.
  IF p_phase = 'group' THEN
    IF coalesce(p_scoring, 'ekc') = 'classic' THEN
      -- Classic group set, no king -> not a won set.
      RETURN 'none';
    ELSE
      -- EKC group set -> result by base-kubbs, draw allowed.
      IF p_kubbs_a > p_kubbs_b THEN RETURN 'A'; END IF;
      IF p_kubbs_b > p_kubbs_a THEN RETURN 'B'; END IF;
      RETURN 'none';
    END IF;
  END IF;

  -- KO phase, no king: the decisive winner comes from the client finisher
  -- prompt (M2b). Take the value the client delivered verbatim; NO auto
  -- kubb-majority fallback.
  RETURN CASE WHEN p_winner IN ('A','B','none') THEN p_winner ELSE 'none' END;
END;
$$;

REVOKE ALL ON FUNCTION public._tournament_canonical_set_winner(
  text, text, int, int, text, text) FROM PUBLIC;

COMMENT ON FUNCTION public._tournament_canonical_set_winner(
  text, text, int, int, text, text) IS
  'M2a: deterministic canonical set winner (A/B/none), server mirror of '
  'resolveSetWinnerForSide (kubb_domain ekc_score.dart). King fell -> '
  'submitted A/B; no king + group + classic -> none; no king + group + ekc '
  '-> by base-kubbs (draw none); no king + KO -> submitted value (finisher '
  'prompt is authoritative client-side; no auto kubb-majority fallback).';


-- ---- 2. CREATE OR REPLACE tournament_propose_set_scores --------------
-- Body verbatim from 20260615000007 EXCEPT the two marked M2a changes.

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
  v_team_a          uuid;
  v_team_b          uuid;
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
  v_other_part      uuid;
  v_other_count     int;
  v_disagree_count  int;
  v_result_status   text;
  v_result_round    smallint;
  v_phase           text;   -- M2a: canonical-winner inputs
  v_scoring         text;   -- M2a
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Lock the match row first so concurrent proposals serialise.
  -- M2a: also read m.phase for the canonical set-winner derivation.
  SELECT m.tournament_id, m.status, m.consensus_round,
         m.participant_a, m.participant_b, m.phase
    INTO v_tournament_id, v_status, v_round, v_part_a, v_part_b, v_phase
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

  -- Resolve tournament header (creator + match_format + scoring mode).
  -- M2a: scoring drives the canonical set-winner for king-less EKC sets.
  SELECT t.created_by, t.match_format, t.scoring
    INTO v_creator, v_match_format, v_scoring
    FROM public.tournaments t
    WHERE t.id = v_tournament_id;

  v_sets_to_win := COALESCE((v_match_format ->> 'sets_to_win')::int, 1);
  IF v_sets_to_win < 1 OR v_sets_to_win > 5 THEN
    RAISE EXCEPTION 'invalid match_format.sets_to_win: %', v_sets_to_win
      USING ERRCODE = '22023';
  END IF;

  -- Resolve each side's user_id and team_id. team_id is NULL on the
  -- single-path; user_id is NULL on the team-path (see T1 CHECK).
  SELECT user_id, team_id INTO v_user_a, v_team_a
    FROM public.tournament_participants WHERE id = v_part_a;
  SELECT user_id, team_id INTO v_user_b, v_team_b
    FROM public.tournament_participants WHERE id = v_part_b;

  -- Determine the caller's side. Match either the participant's
  -- user_id directly, or an active pool-membership when team_id is set.
  IF v_user_a IS NOT NULL AND v_caller = v_user_a THEN
    v_my_side := 'A';
    v_other_part := v_part_b;
  ELSIF v_user_b IS NOT NULL AND v_caller = v_user_b THEN
    v_my_side := 'B';
    v_other_part := v_part_a;
  ELSIF v_team_a IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.team_memberships
          WHERE team_id = v_team_a
            AND user_id = v_caller
            AND removed_at IS NULL) THEN
    v_my_side := 'A';
    v_other_part := v_part_b;
  ELSIF v_team_b IS NOT NULL AND EXISTS (
          SELECT 1 FROM public.team_memberships
          WHERE team_id = v_team_b
            AND user_id = v_caller
            AND removed_at IS NULL) THEN
    v_my_side := 'B';
    v_other_part := v_part_a;
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
      -- M2a: resolve the king-outcome token (hit_by/missed/timed_out)
      -- from the wire payload via the shared resolver. Default 'missed'.
      v_king    text := public._tournament_resolve_king_outcome(v_set);
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

      -- M2a: persist set_king_outcome alongside the legacy columns.
      INSERT INTO public.tournament_set_score_proposals(
          match_id, consensus_round, set_number, submitter_user_id,
          basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner,
          set_king_outcome)
        VALUES (
          p_match_id, v_round, v_set_no::smallint, v_caller,
          v_a_kubbs::smallint, v_b_kubbs::smallint, v_winner,
          v_king)
        ON CONFLICT (match_id, consensus_round, set_number, submitter_user_id)
        DO UPDATE SET
            basekubbs_knocked_by_a = EXCLUDED.basekubbs_knocked_by_a,
            basekubbs_knocked_by_b = EXCLUDED.basekubbs_knocked_by_b,
            set_winner             = EXCLUDED.set_winner,
            set_king_outcome       = EXCLUDED.set_king_outcome,
            proposed_at            = now();
    END;
  END LOOP;

  -- If the caller resubmits a different set-count for this round, drop
  -- any stale set rows past the new length.
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

  -- Consensus check: aggregate by side (participant) rather than by a
  -- single user_id, so multiple pool-members on the same team-side
  -- still count as one logical submission. The most recent submitter
  -- per side is taken via DISTINCT ON (set_number, side) ordered by
  -- proposed_at DESC.
  WITH side_a AS (
    SELECT DISTINCT ON (set_number)
      set_number, basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner
    FROM public.tournament_set_score_proposals p
    WHERE p.match_id = p_match_id
      AND p.consensus_round = v_round
      AND (
        (v_user_a IS NOT NULL AND p.submitter_user_id = v_user_a)
        OR (v_team_a IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.team_memberships tm
              WHERE tm.team_id = v_team_a
                AND tm.user_id = p.submitter_user_id))
      )
    ORDER BY set_number, proposed_at DESC
  ),
  side_b AS (
    SELECT DISTINCT ON (set_number)
      set_number, basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner
    FROM public.tournament_set_score_proposals p
    WHERE p.match_id = p_match_id
      AND p.consensus_round = v_round
      AND (
        (v_user_b IS NOT NULL AND p.submitter_user_id = v_user_b)
        OR (v_team_b IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.team_memberships tm
              WHERE tm.team_id = v_team_b
                AND tm.user_id = p.submitter_user_id))
      )
    ORDER BY set_number, proposed_at DESC
  )
  SELECT count(*) INTO v_other_count
    FROM (SELECT set_number FROM side_a INTERSECT SELECT set_number FROM side_b) s;

  -- Did the *other* side submit a complete proposal of equal length?
  -- v_other_count is the number of overlapping set numbers between
  -- both sides; consensus requires it to match v_set_count exactly.
  IF v_other_count = 0 OR v_other_count <> v_set_count THEN
    RETURN jsonb_build_object(
      'match_id',              p_match_id,
      'status',                v_status,
      'consensus_round',       v_round,
      'winner_participant_id', NULL,
      'final_score_a',         NULL,
      'final_score_b',         NULL);
  END IF;

  -- Both sides submitted same set-count. Compare set-by-set using the
  -- latest proposal per side.
  -- M2a: the per-side CTEs now also carry set_king_outcome, and the
  -- disagreement test compares the CANONICAL set winner (phase-/scoring-
  -- aware) plus base-kubbs + king-outcome, so two identical real inputs
  -- (incl. beidseitig 'none' in the group phase) count as agreement.
  WITH side_a AS (
    SELECT DISTINCT ON (set_number)
      set_number, basekubbs_knocked_by_a, basekubbs_knocked_by_b,
      set_winner, set_king_outcome
    FROM public.tournament_set_score_proposals p
    WHERE p.match_id = p_match_id
      AND p.consensus_round = v_round
      AND (
        (v_user_a IS NOT NULL AND p.submitter_user_id = v_user_a)
        OR (v_team_a IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.team_memberships tm
              WHERE tm.team_id = v_team_a
                AND tm.user_id = p.submitter_user_id))
      )
    ORDER BY set_number, proposed_at DESC
  ),
  side_b AS (
    SELECT DISTINCT ON (set_number)
      set_number, basekubbs_knocked_by_a, basekubbs_knocked_by_b,
      set_winner, set_king_outcome
    FROM public.tournament_set_score_proposals p
    WHERE p.match_id = p_match_id
      AND p.consensus_round = v_round
      AND (
        (v_user_b IS NOT NULL AND p.submitter_user_id = v_user_b)
        OR (v_team_b IS NOT NULL AND EXISTS (
              SELECT 1 FROM public.team_memberships tm
              WHERE tm.team_id = v_team_b
                AND tm.user_id = p.submitter_user_id))
      )
    ORDER BY set_number, proposed_at DESC
  )
  SELECT count(*) INTO v_disagree_count
    FROM side_a a
    JOIN side_b b ON b.set_number = a.set_number
    WHERE a.basekubbs_knocked_by_a IS DISTINCT FROM b.basekubbs_knocked_by_a
       OR a.basekubbs_knocked_by_b IS DISTINCT FROM b.basekubbs_knocked_by_b
       OR a.set_king_outcome       IS DISTINCT FROM b.set_king_outcome
       OR public._tournament_canonical_set_winner(
            a.set_king_outcome, a.set_winner,
            a.basekubbs_knocked_by_a, a.basekubbs_knocked_by_b,
            v_phase, v_scoring)
          IS DISTINCT FROM
          public._tournament_canonical_set_winner(
            b.set_king_outcome, b.set_winner,
            b.basekubbs_knocked_by_a, b.basekubbs_knocked_by_b,
            v_phase, v_scoring);

  IF v_disagree_count = 0 THEN
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
