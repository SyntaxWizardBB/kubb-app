-- Tournament stage-graph runner — Step 3 (materialization).
--
-- `tournament_generate_stage_matches(p_tournament_id, p_node_id, p_seeded)`
-- materializes the matches of ONE stage-graph stage from an already
-- seed-ordered participant subset (index 0 = seed 1). It is the runner's
-- "generate the stage's matches" step per ADR-0030 §Runner-Semantik (Step 3).
--
-- Unlike the start-RPCs (`tournament_start_ko_phase`,
-- `tournament_start_pool_phase`) this is a PURE match materializer: it does
-- NOT touch tournaments.status, does NOT assign pitches, writes no audit
-- event and no notification. Its only side effect is INSERTs into
-- public.tournament_matches, each row bound to the owning stage via
-- stage_node_id = p_node_id.
--
-- Supported stage types (read from public.tournament_stages.type):
--   * 'single_elim'             — single-elimination bracket. Reuses the exact
--                                 recursive standard-seeding + BYE-at-top-seed
--                                 idea of _tournament_compute_ko_bracket
--                                 (called read-only, never modified). Round 1 =
--                                 real pairings; BYE pairings finalized with
--                                 winner; later rounds = placeholders. Phase
--                                 'ko' for early rounds, 'final' for the last.
--   * 'round_robin' / 'pool'    — single group; all N*(N-1)/2 unordered pairs
--                                 as phase='group' scheduled matches.
--
-- Unsupported in THIS step (deliberately deferred to a follow-up step):
--   'double_elim', 'consolation', 'swiss', 'shootout_quali' -> ERRCODE 22023
--   'stage type % not yet supported by the stage generator'.
--
-- Error mapping (token in MESSAGE, SQLSTATE in ERRCODE):
--   STAGE_NOT_FOUND            — 22023 (no such stage in this tournament)
--   INVALID_PARTICIPANT        — 22023 (p_seeded empty, or an id is not a
--                                       participant of this tournament)
--   STAGE_ALREADY_GENERATED    — 22023 (matches already exist for this stage;
--                                       no double generation)
--   not yet supported          — 22023 (unsupported stage type)
--
-- Returns: number of tournament_matches rows actually inserted (> 0 on success).

CREATE OR REPLACE FUNCTION public.tournament_generate_stage_matches(
  p_tournament_id uuid,
  p_node_id       text,
  p_seeded        uuid[]
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_type        text;
  v_n           int;
  v_valid_count int;
  v_existing    int;
  v_seeds_jsonb jsonb;
  v_count       int := 0;
  v_pair_no     int;
  i             int;
  j             int;
BEGIN
  -- 1. Stage must exist in this tournament.
  SELECT type INTO v_type
    FROM public.tournament_stages
    WHERE tournament_id = p_tournament_id
      AND node_id = p_node_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'STAGE_NOT_FOUND: no stage % in tournament %', p_node_id, p_tournament_id
      USING ERRCODE = '22023';
  END IF;

  -- 2. Seeded subset must be non-empty.
  v_n := coalesce(array_length(p_seeded, 1), 0);
  IF p_seeded IS NULL OR v_n < 1 THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: p_seeded must contain at least one participant'
      USING ERRCODE = '22023';
  END IF;

  -- 3. Every seeded id must be a participant of THIS tournament (defensive
  --    count match over unnest(p_seeded) JOIN tournament_participants).
  SELECT count(*) INTO v_valid_count
    FROM unnest(p_seeded) AS s(id)
    JOIN public.tournament_participants tp
      ON tp.id = s.id
     AND tp.tournament_id = p_tournament_id;
  IF v_valid_count <> v_n THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: p_seeded contains ids that are not participants of tournament %', p_tournament_id
      USING ERRCODE = '22023';
  END IF;

  -- 4. Idempotency guard: never generate twice for the same stage. Runs
  --    BEFORE any insert so a failure leaves no partial rows.
  SELECT count(*) INTO v_existing
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND stage_node_id = p_node_id;
  IF v_existing > 0 THEN
    RAISE EXCEPTION 'STAGE_ALREADY_GENERATED: stage % already has matches', p_node_id
      USING ERRCODE = '22023';
  END IF;

  -- 5. Type dispatch.
  IF v_type = 'single_elim' THEN
    -- Reuse the bracket logic idea of tournament_start_ko_phase: feed the
    -- seed-ordered list into _tournament_compute_ko_bracket (read-only) and
    -- map its rows 1:1 like start_ko_phase does, plus stage_node_id. No
    -- third-place match here (out of scope for stage materialization).
    --
    -- Stage-scoped lower bound: a single-elim bracket needs >= 2 participants.
    -- Guard here so N=1 raises a stage-scoped INVALID_PARTICIPANT token instead
    -- of leaking the helper-internal "seeds length must be in [2, 64]" message.
    IF v_n < 2 THEN
      RAISE EXCEPTION 'INVALID_PARTICIPANT: single_elim stage % needs at least 2 participants, got %', p_node_id, v_n
        USING ERRCODE = '22023';
    END IF;
    v_seeds_jsonb := to_jsonb(p_seeded);

    INSERT INTO public.tournament_matches(
        tournament_id, stage_node_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           p_node_id,
           b.round_number::smallint,
           b.bracket_position::smallint,
           b.bracket_position,
           b.participant_a,
           b.participant_b,
           b.phase,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END
      FROM public._tournament_compute_ko_bracket(v_seeds_jsonb, false) b;

    GET DIAGNOSTICS v_count = ROW_COUNT;

  ELSIF v_type IN ('round_robin', 'pool') THEN
    -- Single group: all N*(N-1)/2 unordered pairs over the seed order.
    -- round_number=1, match_number_in_round = running pair number (>=1),
    -- like tournament_start_pool_phase's pair_no within a group.
    v_pair_no := 0;
    FOR i IN 1 .. v_n LOOP
      FOR j IN (i + 1) .. v_n LOOP
        v_pair_no := v_pair_no + 1;
        INSERT INTO public.tournament_matches(
            tournament_id, stage_node_id, round_number, match_number_in_round,
            participant_a, participant_b, phase, status, pitch_number)
        VALUES (
            p_tournament_id, p_node_id, 1::smallint, v_pair_no::smallint,
            p_seeded[i], p_seeded[j], 'group', 'scheduled', 1);
      END LOOP;
    END LOOP;
    v_count := v_pair_no;

  ELSE
    -- double_elim / consolation / swiss / shootout_quali — deferred step.
    RAISE EXCEPTION 'stage type % not yet supported by the stage generator', v_type
      USING ERRCODE = '22023';
  END IF;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_generate_stage_matches(uuid, text, uuid[])
  TO authenticated;

COMMENT ON FUNCTION public.tournament_generate_stage_matches(uuid, text, uuid[]) IS
  'ADR-0030 runner Step 3: materialize ONE stage''s matches from a seed-ordered '
  'participant subset. single_elim reuses _tournament_compute_ko_bracket '
  '(recursive seeding + BYE-at-top-seed, phase ko/final); round_robin/pool emit '
  'all N*(N-1)/2 group pairs. Unsupported types (double_elim/consolation/swiss/'
  'shootout_quali) raise 22023 (deferred step). Every row sets '
  'stage_node_id = p_node_id. Pure materializer: only inserts tournament_matches, '
  'no status/pitch/audit/notification side effects. Returns rows inserted.';
