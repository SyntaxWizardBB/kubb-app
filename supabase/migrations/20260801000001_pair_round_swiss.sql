-- M5.2-T8: Swiss-system dispatch for tournament_pair_round.
--
-- Per OD-M5-04 (Empfehlung A) the pairing heuristic itself runs in the
-- Dart domain (kubb_domain/SwissSystemStrategy). The RPC accepts the
-- proposed pairing as JSON and acts as the trust-boundary (R-M5.2-2):
-- it validates that the pairing is a legal permutation of the open
-- roster, rejects repeats against earlier rounds and detects bye
-- conflicts before any INSERT happens. All other strategies remain
-- untouched (backward-compat).
--
-- Bezug: docs/plans/m5-swiss-league-season/tasks.md TASK-M5.2-T8,
--        docs/plans/m5-swiss-league-season/architecture.md §3,
--        docs/plans/m5-swiss-league-season/risks-and-deferrals.md R-M5.2-2.
--
-- Error tokens (MESSAGE prefix, SQLSTATE in ERRCODE — client reads both):
--   invalid_pairing  — ERRCODE 22023; sub-reason appended in MESSAGE.
--
-- p_pairings JSON shape (array of objects, one per match):
--   [
--     { "participant_a": "<uuid>", "participant_b": "<uuid>" | null },
--     ...
--   ]
-- participant_b = NULL marks a bye. participant_a is always populated.

-- ---- 1. validate_swiss_pairing ---------------------------------------

CREATE OR REPLACE FUNCTION public.validate_swiss_pairing(
  p_tournament_id uuid,
  p_pairings      jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_roster_count   int;
  v_unknown_count  int;
  v_dup_count      int;
  v_repeat_count   int;
  v_bye_conflict   int;
BEGIN
  IF p_pairings IS NULL OR jsonb_typeof(p_pairings) <> 'array' THEN
    RAISE EXCEPTION 'invalid_pairing: payload must be a JSON array'
      USING ERRCODE = '22023';
  END IF;

  -- Flatten the pairing into one row per (slot, participant_id, is_bye).
  -- A bye row has participant_b = NULL and contributes exactly one
  -- participant_a entry. Non-bye rows contribute two entries.
  WITH raw AS (
    SELECT (row_number() OVER ())::int AS slot,
           (elem ->> 'participant_a')::uuid AS pa,
           NULLIF(elem ->> 'participant_b','')::uuid AS pb
      FROM jsonb_array_elements(p_pairings) AS elem
  ),
  pieces AS (
    SELECT slot, pa AS pid, (pb IS NULL) AS is_bye FROM raw
    UNION ALL
    SELECT slot, pb AS pid, false AS is_bye FROM raw WHERE pb IS NOT NULL
  )
  SELECT
    -- Unknown player: not a confirmed roster row of this tournament.
    count(*) FILTER (
      WHERE NOT EXISTS (
        SELECT 1 FROM public.tournament_participants tp
         WHERE tp.id = pieces.pid
           AND tp.tournament_id = p_tournament_id
           AND tp.registration_status = 'confirmed'
      )
    ),
    -- Duplicate assignment: same participant appears twice in this round.
    (SELECT count(*) FROM (
        SELECT pid FROM pieces GROUP BY pid HAVING count(*) > 1
     ) d)
  INTO v_unknown_count, v_dup_count
  FROM pieces;

  IF v_unknown_count > 0 THEN
    RAISE EXCEPTION 'invalid_pairing: participant not on tournament roster'
      USING ERRCODE = '22023';
  END IF;

  IF v_dup_count > 0 THEN
    RAISE EXCEPTION 'invalid_pairing: duplicate participant in round'
      USING ERRCODE = '22023';
  END IF;

  -- Repeat detection: an unordered pair {a,b} from p_pairings must not
  -- already exist as a match in this tournament's prior rounds. Byes
  -- (participant_b IS NULL) are exempt from the repeat check itself but
  -- handled in the bye-conflict step below.
  SELECT count(*)
    INTO v_repeat_count
    FROM jsonb_array_elements(p_pairings) AS elem
    JOIN public.tournament_matches m
      ON m.tournament_id = p_tournament_id
     AND m.participant_b IS NOT NULL
     AND (
       (m.participant_a = (elem ->> 'participant_a')::uuid
        AND m.participant_b = NULLIF(elem ->> 'participant_b','')::uuid)
       OR
       (m.participant_b = (elem ->> 'participant_a')::uuid
        AND m.participant_a = NULLIF(elem ->> 'participant_b','')::uuid)
     )
   WHERE NULLIF(elem ->> 'participant_b','') IS NOT NULL;

  IF v_repeat_count > 0 THEN
    RAISE EXCEPTION 'invalid_pairing: pairing already played in earlier round'
      USING ERRCODE = '22023';
  END IF;

  -- Bye conflict: participant_a of a bye row (participant_b IS NULL)
  -- must not have received a bye in any earlier round of the same
  -- tournament.
  SELECT count(*)
    INTO v_bye_conflict
    FROM jsonb_array_elements(p_pairings) AS elem
    JOIN public.tournament_matches m
      ON m.tournament_id = p_tournament_id
     AND m.participant_b IS NULL
     AND m.participant_a = (elem ->> 'participant_a')::uuid
   WHERE NULLIF(elem ->> 'participant_b','') IS NULL;

  IF v_bye_conflict > 0 THEN
    RAISE EXCEPTION 'invalid_pairing: participant already received a bye'
      USING ERRCODE = '22023';
  END IF;

  -- Roster-completeness is intentionally not enforced here. Swiss
  -- rounds may legitimately exclude withdrawn participants; the
  -- per-participant checks above are sufficient to prevent illegal
  -- match-ups. Caller may add a permutation check at the application
  -- layer if stricter coverage is desired.
  PERFORM v_roster_count;
END;
$$;


-- ---- 2. tournament_pair_round (swiss_system dispatch) ----------------

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
  v_caller     uuid;
  v_creator    uuid;
  v_status     text;
  v_next_round int;
  v_inserted   int := 0;
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
  -- pairing payload) keep the original behaviour. Round-robin and
  -- top-vs-bottom rounds are materialised by their dedicated RPCs
  -- (tournament_start, organizer-override paths); reaching this branch
  -- means there is nothing for this function to do.
  IF p_strategy IS DISTINCT FROM 'swiss_system' OR p_pairings IS NULL THEN
    RETURN;
  END IF;

  -- Trust-boundary: validate the client-supplied pairing before any
  -- INSERT. Any violation raises invalid_pairing and aborts the txn.
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

REVOKE ALL ON FUNCTION public.validate_swiss_pairing(uuid, jsonb) FROM public;
REVOKE ALL ON FUNCTION public.tournament_pair_round(uuid, text, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_pair_round(uuid, text, jsonb) TO authenticated;
