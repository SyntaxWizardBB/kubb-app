-- P6 "TournierStart" — Stage C (2/2): ROUND-PROGRESSION GATE (swiss/schoch).
--
-- Ensures the NEXT preliminary (swiss/schoch == live-score Swiss) round can
-- only be generated once ALL matches of the CURRENT (latest) round are
-- terminal — finalized, overridden, or voided. Today tournament_pair_round
-- (20260801000001 §2, re-stated with pitch-assign in 20261001000010 §5)
-- validates the client-supplied pairing (legal permutation, no repeats, no
-- double-bye) but does NOT check that the previous round actually finished.
-- A racing/buggy client could thus pair round N+1 while round N still has
-- open matches, corrupting Buchholz/standings (which feed the next pairing)
-- and producing an inconsistent schedule.
--
-- This migration CREATE OR REPLACEs tournament_pair_round, re-stating the
-- CURRENT body VERBATIM (the pitch-assign-enabled version from
-- 20261001000010 §5) and adding ONE guard block, marked PROGRESSION-GATE,
-- right after the swiss-dispatch short-circuit and BEFORE validate +
-- v_next_round. Everything else is byte-identical to the prior definition.
--
-- ======================== GUARD SEMANTICS =============================
-- "Current round" = MAX(round_number) among this tournament's matches.
-- The guard raises a CLEAR error (not a silent no-op) when ANY match of
-- that round is still open (status NOT IN finalized/overridden/voided):
--   ERRCODE 22023, MESSAGE prefix 'round_not_complete' (machine-readable,
--   sibling of the existing 'invalid_pairing' token in validate_swiss_pairing
--   20260801000001 §1; same SQLSTATE 22023). The count of open matches is
--   appended so the client can surface "N matches still open".
-- We RAISE rather than no-op because the client is explicitly requesting a
-- new round; silently doing nothing would hide the precondition violation
-- (the swiss UI must keep the organizer on the current round until it
-- finishes). This mirrors tournament_start_ko_phase's PHASE_NOT_COMPLETE
-- guard (20261101000002 §4 / 20261001000010 §6, l.842-851), which already
-- refuses to start the KO bracket while group matches remain open — the
-- gate here is the per-round analogue for the prelim phase.
--
-- TERMINAL set = ('finalized','overridden','voided'):
--   * finalized  — consensus agreement (20260525000004 §2).
--   * overridden — organizer override (20260525000004 §3).
--   * voided     — match annulled (status CHECK 20260525000001 l.68-70);
--                  carries no result but is DONE, so it must not block the
--                  next round. (Same terminal set as the KO-start guard.)
-- A 'disputed' match is NOT terminal and correctly blocks progression until
-- the organizer overrides or the sides re-reach consensus.
--
-- ===================== FORMAT IMPACT (how each is affected) ===========
-- This gate lives in tournament_pair_round, which ONLY the swiss/schoch
-- live-pairing path calls (p_strategy='swiss_system' with a payload). Other
-- formats are unaffected BY DESIGN, and each already has its own correct
-- progression rule documented here for cross-reference:
--   * swiss / schoch (swiss & schoch & *_then_ko swiss-pools)
--       — GATED here: round N+1 needs all of round N terminal. This is the
--         meaningful case (rounds are generated incrementally from results).
--   * round_robin (and round_robin_then_ko pool RR)
--       — NO per-round gate needed: ALL rounds are pre-materialised at
--         tournament_start (circle rotation, 20261001000010 §3) / at
--         tournament_start_pool_phase (full per-group RR, §4). There is no
--         "generate next round" step to gate; matches are simply played in
--         any order. round_robin therefore never reaches this RPC.
--   * pool (group phase of *_then_ko)
--       — Same as round_robin: the whole group RR is materialised up front;
--         no incremental round generation, so no gate here.
--   * single_elimination / KO / double_elimination (ko/final/third_place/
--     wb/lb/grand_final[_reset])
--       — Progression is TRIGGER-driven, not RPC-driven: the winner of a
--         finalized match is written into its successor slot by
--         tournament_advance_ko_winner (20260601000016 / DE successor
--         20261101000002 §5). A KO "round" advances match-by-match as each
--         feeder finalizes; there is no all-of-round precondition to enforce
--         (a later-round match simply stays 'scheduled' with empty slots
--         until BOTH its feeders finalize). The cross-phase gate that DOES
--         exist — "all group matches terminal before the KO bracket is
--         built" — is enforced in tournament_start_ko_phase (PHASE_NOT_-
--         COMPLETE), which this migration does not touch.
-- =====================================================================
-- ============================ DEPENDENCIES ============================
-- Function REPLACED: public.tournament_pair_round(uuid, text, jsonb)
--   — latest body: 20261001000010_tournament_start_formats.sql §5
--     (swiss dispatch + pitch-assign). Re-stated verbatim + gate.
-- Function called (unchanged): public.validate_swiss_pairing(uuid, jsonb)
--   — 20260801000001 §1.
-- Function called (unchanged): public._tournament_assign_pitches(uuid, smallint)
--   — 20261201000003 §2.
-- Tables read: public.tournaments(created_by, status),
--   public.tournament_matches(tournament_id, round_number, status)
--   — 20260525000001.
-- Grants: unchanged (REVOKE ALL from public; GRANT EXECUTE to authenticated).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.tournament_pair_round(
  p_tournament_id uuid,
  p_strategy      text,
  p_pairings      jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_creator      uuid;
  v_status       text;
  v_next_round   int;
  v_inserted     int := 0;
  v_current_round int;      -- PROGRESSION-GATE
  v_open_count    int;      -- PROGRESSION-GATE
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, status INTO v_creator, v_status
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_creator <> v_caller THEN
    RAISE EXCEPTION 'not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'live' THEN
    RAISE EXCEPTION 'tournament must be in status live' USING ERRCODE = '22023';
  END IF;

  -- Backward-compat: non-swiss strategies (or swiss_system without a
  -- pairing payload) keep the original no-op behaviour.
  IF p_strategy IS DISTINCT FROM 'swiss_system' OR p_pairings IS NULL THEN
    RETURN;
  END IF;

  -- ---- PROGRESSION-GATE ------------------------------------------------
  -- Refuse to pair the next round while the CURRENT (latest) round still
  -- has open matches. Terminal = finalized/overridden/voided (same set as
  -- the KO-start PHASE_NOT_COMPLETE guard). Runs under the FOR UPDATE lock
  -- taken on the tournaments row above, so concurrent pair_round calls for
  -- the same tournament serialise and cannot both pass the gate.
  SELECT max(round_number) INTO v_current_round
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id;

  IF v_current_round IS NOT NULL THEN
    SELECT count(*) INTO v_open_count
      FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND round_number  = v_current_round
        AND status NOT IN ('finalized','overridden','voided');

    IF v_open_count > 0 THEN
      RAISE EXCEPTION
        'round_not_complete: round % still has % open match(es); finalize them before pairing the next round',
        v_current_round, v_open_count
        USING ERRCODE = '22023';
    END IF;
  END IF;
  -- ---- end PROGRESSION-GATE -------------------------------------------

  -- Trust-boundary: validate the client-supplied pairing before any INSERT.
  PERFORM public.validate_swiss_pairing(p_tournament_id, p_pairings);

  SELECT coalesce(max(round_number), 0) + 1
    INTO v_next_round
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id;

  WITH ins AS (
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        participant_a, participant_b, pitch_number, status)
    SELECT
      p_tournament_id,
      v_next_round::smallint,
      (row_number() OVER ())::smallint,
      (elem ->> 'participant_a')::uuid,
      NULLIF(elem ->> 'participant_b','')::uuid,
      1,
      'scheduled'
    FROM jsonb_array_elements(p_pairings) AS elem
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM ins;

  -- PITCH-PLAN: assign pitch_number for the freshly paired round (no-op
  -- if plan NULL).
  PERFORM public._tournament_assign_pitches(p_tournament_id, v_next_round::smallint);

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'swiss_round_paired',
      v_caller,
      jsonb_build_object(
        'round_number', v_next_round,
        'match_count',  v_inserted,
        'strategy',     p_strategy
      )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_pair_round(uuid, text, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_pair_round(uuid, text, jsonb) TO authenticated;

COMMENT ON FUNCTION public.tournament_pair_round(uuid, text, jsonb) IS
  'Swiss/Schoch next-round generator. Organizer-only, status=live. Gate: '
  'refuses to pair the next round (ERRCODE 22023, MESSAGE round_not_complete) '
  'while the latest round has any non-terminal match. Validates the '
  'client-supplied pairing (validate_swiss_pairing), inserts the round and '
  'assigns pitches. No-op for non-swiss strategies / missing payload.';
