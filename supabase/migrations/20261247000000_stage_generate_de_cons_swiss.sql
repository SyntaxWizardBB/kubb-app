-- Tournament stage-graph runner — Step 3 extension (F1).
--
-- Extends public.tournament_generate_stage_matches (20261226000000) to
-- materialize three previously-deferred stage types. The auth-free
-- materializer contract is unchanged (pure INSERTs into tournament_matches,
-- every row bound via stage_node_id; no status/pitch/audit side effects;
-- idempotency + participant validation as before). Only the type dispatch
-- grows:
--
--   * 'double_elim' — reuses the parity-tested _tournament_compute_de_bracket
--     (ADR-0027). with_reset is read from the stage config
--     (config->>'with_reset', default false). WB/LB/grand_final(+reset) rows;
--     BYE pairings auto-finalized so the advance trigger pushes the winner on.
--
--   * 'consolation' — in the stage-graph framework a consolation node is a
--     STANDALONE bracket fed by routing edges (the losers already arrive via
--     tournament_stage_edges, e.g. the KubbMAIster Klingnauer/Höseler cups).
--     It is therefore structurally a single-elimination bracket over the
--     routed participants and is generated EXACTLY like single_elim (phase
--     ko/final). This differs from the integrated ADR-0028 consolation
--     (one bracket, main winners + consolation losers) that
--     skv_consolation_placements models; the companion ranking change
--     (20261248000000) ranks a consolation STAGE as single_elim accordingly.
--
--   * 'swiss' — Swiss is iterative; this generates ONLY round 1 as a
--     deterministic seed "slide" pairing (seed i vs seed i+h, h = N/2), phase
--     'group'. An odd field gives the lowest seed a BYE (auto-finalized).
--     Later rounds are paired live via the existing swiss flow
--     (tournament_pair_round). Non-KO ranking already covers swiss stages.
--
-- 'shootout_quali' stays deferred (needs the shoot-out machinery) and still
-- raises 22023.
--
-- CREATE OR REPLACE reproduces the WHOLE function (single_elim + round_robin
-- branches preserved verbatim) so no stale body survives.

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
  v_config      jsonb;
  v_with_reset  boolean;
  v_n           int;
  v_valid_count int;
  v_existing    int;
  v_seeds_jsonb jsonb;
  v_count       int := 0;
  v_pair_no     int;
  v_half        int;
  v_a           uuid;
  v_b           uuid;
  i             int;
  j             int;
BEGIN
  -- 1. Stage must exist in this tournament.
  SELECT type, config INTO v_type, v_config
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

  -- 3. Every seeded id must be a participant of THIS tournament.
  SELECT count(*) INTO v_valid_count
    FROM unnest(p_seeded) AS s(id)
    JOIN public.tournament_participants tp
      ON tp.id = s.id
     AND tp.tournament_id = p_tournament_id;
  IF v_valid_count <> v_n THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: p_seeded contains ids that are not participants of tournament %', p_tournament_id
      USING ERRCODE = '22023';
  END IF;

  -- 4. Idempotency guard: never generate twice for the same stage.
  SELECT count(*) INTO v_existing
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND stage_node_id = p_node_id;
  IF v_existing > 0 THEN
    RAISE EXCEPTION 'STAGE_ALREADY_GENERATED: stage % already has matches', p_node_id
      USING ERRCODE = '22023';
  END IF;

  -- 5. Type dispatch.
  IF v_type IN ('single_elim', 'consolation') THEN
    -- single_elim and (standalone, routed) consolation are the same bracket
    -- shape: a single-elimination bracket over the seed-ordered subset.
    IF v_n < 2 THEN
      RAISE EXCEPTION 'INVALID_PARTICIPANT: % stage % needs at least 2 participants, got %', v_type, p_node_id, v_n
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

  ELSIF v_type = 'double_elim' THEN
    -- Double-elimination bracket (ADR-0027). with_reset from stage config.
    IF v_n < 2 THEN
      RAISE EXCEPTION 'INVALID_PARTICIPANT: double_elim stage % needs at least 2 participants, got %', p_node_id, v_n
        USING ERRCODE = '22023';
    END IF;
    v_with_reset := coalesce((v_config ->> 'with_reset')::boolean, false);
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
      FROM public._tournament_compute_de_bracket(v_seeds_jsonb, v_with_reset) b;

    GET DIAGNOSTICS v_count = ROW_COUNT;

  ELSIF v_type IN ('round_robin', 'pool') THEN
    -- Single group: all N*(N-1)/2 unordered pairs over the seed order.
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

  ELSIF v_type = 'swiss' THEN
    -- Swiss round 1 only: deterministic seed "slide" pairing (seed i vs
    -- seed i+h, h = floor(N/2)), phase 'group', round 1. Odd field -> the
    -- lowest seed (last in seed order) gets a BYE, auto-finalized. Later
    -- rounds are paired live (tournament_pair_round).
    IF v_n < 2 THEN
      RAISE EXCEPTION 'INVALID_PARTICIPANT: swiss stage % needs at least 2 participants, got %', p_node_id, v_n
        USING ERRCODE = '22023';
    END IF;
    v_half := v_n / 2;  -- floor
    v_pair_no := 0;
    FOR i IN 1 .. v_half LOOP
      v_pair_no := v_pair_no + 1;
      v_a := p_seeded[i];
      v_b := p_seeded[i + v_half];
      INSERT INTO public.tournament_matches(
          tournament_id, stage_node_id, round_number, match_number_in_round,
          participant_a, participant_b, phase, status, pitch_number)
      VALUES (
          p_tournament_id, p_node_id, 1::smallint, v_pair_no::smallint,
          v_a, v_b, 'group', 'scheduled', 1);
    END LOOP;
    -- Odd field: the unpaired lowest seed (index N when N is odd) gets a BYE.
    IF (v_n % 2) = 1 THEN
      v_pair_no := v_pair_no + 1;
      v_a := p_seeded[v_n];
      INSERT INTO public.tournament_matches(
          tournament_id, stage_node_id, round_number, match_number_in_round,
          participant_a, participant_b, phase, status, winner_participant,
          pitch_number, finalized_at)
      VALUES (
          p_tournament_id, p_node_id, 1::smallint, v_pair_no::smallint,
          v_a, NULL, 'group', 'finalized', v_a, 1, now());
    END IF;
    v_count := v_pair_no;

  ELSE
    -- shootout_quali — deferred step (needs the shoot-out machinery).
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
  'participant subset. single_elim and (standalone routed) consolation share the '
  'single-elim bracket (phase ko/final); double_elim uses '
  '_tournament_compute_de_bracket (with_reset from config); round_robin/pool emit '
  'all N*(N-1)/2 group pairs; swiss emits round 1 as a seed slide pairing (odd '
  'field -> lowest-seed BYE), later rounds paired live. shootout_quali raises '
  '22023 (deferred). BYE pairings auto-finalized. Every row sets '
  'stage_node_id = p_node_id. Pure materializer: only inserts tournament_matches. '
  'Returns rows inserted.';
