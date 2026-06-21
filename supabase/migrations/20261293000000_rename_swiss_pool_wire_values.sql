-- Rename the swiss/pool wire values to schoch/group_phase (additive, deploy-safe).
--
-- Welle B of the glossar refactor (docs/glossar.md): the Dart side now writes
-- the new wire strings — StageNodeType.groupPhase -> 'group_phase',
-- StageNodeType.schoch -> 'schoch', and the hybrid TournamentFormat.schochThenKo
-- -> 'schoch_then_ko'. This migration brings the stored data and the CHECK
-- constraints in line, and teaches the stage generator to dispatch on both the
-- old and the new type strings.
--
-- Deploy safety: the CHECK constraints are WIDENED to allow old AND new values,
-- so there is no window where the constraint rejects a value the running app
-- (old or new) might still write. The old values ('pool','swiss') are LEFT in
-- the constraint on purpose; a later cleanup migration may drop them once every
-- deploy is known to write only the new strings.
--
-- tournaments.format keeps 'swiss'/'swiss_then_ko' too: the app derives the
-- hybrid 'schoch_then_ko' (already allowed) and never emits a bare 'schoch',
-- but legacy rows are migrated for consistency.

-- ── 1. Widen the CHECK constraints (old + new values) ─────────────────────

-- tournaments.format — inline CHECK from 20260525000001, Postgres-named
-- "tournaments_format_check". 'schoch'/'schoch_then_ko' already existed; this
-- only re-asserts the full vocabulary explicitly.
ALTER TABLE public.tournaments
  DROP CONSTRAINT IF EXISTS tournaments_format_check;
ALTER TABLE public.tournaments
  ADD CONSTRAINT tournaments_format_check CHECK (format IN (
    'round_robin','single_elimination','round_robin_then_ko',
    'schoch','schoch_then_ko',
    -- legacy aliases, kept until a later cleanup migration
    'swiss','swiss_then_ko'));

-- tournament_stages.type — inline CHECK from 20261223000000, Postgres-named
-- "tournament_stages_type_check". Adds 'group_phase' alongside 'pool' and
-- 'schoch' alongside 'swiss'.
ALTER TABLE public.tournament_stages
  DROP CONSTRAINT IF EXISTS tournament_stages_type_check;
ALTER TABLE public.tournament_stages
  ADD CONSTRAINT tournament_stages_type_check CHECK (type IN (
    'group_phase','round_robin','schoch','single_elim','double_elim',
    'consolation','shootout_quali',
    -- legacy aliases, kept until a later cleanup migration
    'pool','swiss'));

-- ── 2. Migrate stored rows to the new vocabulary ──────────────────────────

UPDATE public.tournament_stages SET type = 'group_phase' WHERE type = 'pool';
UPDATE public.tournament_stages SET type = 'schoch'      WHERE type = 'swiss';

UPDATE public.tournaments SET format = 'schoch'          WHERE format = 'swiss';
UPDATE public.tournaments SET format = 'schoch_then_ko'  WHERE format = 'swiss_then_ko';

-- ── 3. Migrate the template graph jsonb (nodes[].type) ────────────────────

-- Rewrite each nodes[] element's "type" in place: 'pool' -> 'group_phase',
-- 'swiss' -> 'schoch'. Only rows whose graph actually contains one of the old
-- values are touched.
UPDATE public.tournament_stage_graph_templates AS t
SET graph = jsonb_set(
      t.graph,
      '{nodes}',
      (
        SELECT jsonb_agg(
          CASE node->>'type'
            WHEN 'pool'  THEN jsonb_set(node, '{type}', '"group_phase"'::jsonb)
            WHEN 'swiss' THEN jsonb_set(node, '{type}', '"schoch"'::jsonb)
            ELSE node
          END
          ORDER BY ord
        )
        FROM jsonb_array_elements(t.graph->'nodes') WITH ORDINALITY AS n(node, ord)
      )
    )
WHERE EXISTS (
  SELECT 1
  FROM jsonb_array_elements(t.graph->'nodes') AS n(node)
  WHERE node->>'type' IN ('pool', 'swiss')
);

-- ── 4. Re-base the stage generator to dispatch on both vocabularies ───────

-- Verbatim copy of the authoritative tournament_generate_stage_matches body
-- (20261288000000) with the two type branches widened: round_robin/pool now
-- also matches 'group_phase', and the swiss branch also matches 'schoch'. No
-- other RPC hard-branches on tournament_stages.type, and tournaments.format
-- routing already covers 'schoch'/'schoch_then_ko'.

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
  v_group_count int;       -- P5.3a: stage pool group_count from config
  v_pools       jsonb;     -- P5.3a: _tournament_compute_pools assignments
  v_ms          int;       -- P5.3c: round-1 match seconds
  v_bs          int;       -- P5.3c: round-1 break seconds
  v_ta          int;       -- P5.3c: round-1 tiebreak-after seconds
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
      FROM public._tournament_compute_ko_bracket(
             v_seeds_jsonb, false,
             coalesce(v_config ->> 'ko_matchup', 'seed_high_vs_low')) b;

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

  ELSIF v_type IN ('round_robin', 'pool', 'group_phase') THEN
    -- P5.3a (ADR-0033 §4): multi-group support. group_count>1 splits the seeded
    -- field into groups via _tournament_compute_pools (snake/seeded/random) and
    -- emits intra-group round-robin pairs tagged with group_label (mirroring the
    -- classic pool path). group_count<=1 keeps the original single flat group
    -- (group_label NULL) so existing single-pool stages are byte-for-byte stable.
    v_group_count := coalesce((v_config ->> 'groupCount')::int, 1);
    IF v_group_count > 1 THEN
      v_pools := public._tournament_compute_pools(
        to_jsonb(p_seeded),
        jsonb_build_object(
          'group_count', v_group_count,
          'qualifiers_per_group',
            greatest(1, coalesce((v_config ->> 'qualifierCount')::int, 1)),
          'strategy', lower(coalesce(v_config ->> 'grouping_strategy', 'snake')),
          'random_seed', coalesce((v_config ->> 'random_seed')::bigint, 0)
        ));
      WITH assign AS (
        SELECT (elem ->> 'participant_id')::uuid AS pid,
               elem ->> 'group_label'            AS lbl,
               (elem ->> 'group_position')::int  AS pos
          FROM jsonb_array_elements(v_pools) AS elem
      ),
      pairs AS (
        SELECT a.lbl,
               a.pid AS pid_a,
               b.pid AS pid_b,
               row_number() OVER (
                 PARTITION BY a.lbl ORDER BY a.pos, b.pos) AS pair_no
          FROM assign a
          JOIN assign b ON a.lbl = b.lbl AND a.pos < b.pos
      )
      INSERT INTO public.tournament_matches(
          tournament_id, stage_node_id, round_number, match_number_in_round,
          participant_a, participant_b, phase, status, pitch_number, group_label)
      SELECT p_tournament_id, p_node_id, 1::smallint, pair_no::smallint,
             pid_a, pid_b, 'group', 'scheduled', 1, lbl
        FROM pairs;
      GET DIAGNOSTICS v_count = ROW_COUNT;
    ELSE
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
    END IF;

  ELSIF v_type IN ('swiss', 'schoch') THEN
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

  -- ADR-0031 A1 + P5.3c: materialise this stage's round 1 schedule. KO-typed
  -- stage nodes time round 1 from their per-round node format
  -- (config->'ko_round_formats'[0]); non-KO stages keep prelim timing (OE-6).
  IF v_type IN ('single_elim', 'double_elim', 'consolation') THEN
    SELECT s.match_seconds, s.break_seconds, s.tiebreak_after
      INTO v_ms, v_bs, v_ta
      FROM public._tournament_schedule_stage_ko_seconds(
             p_tournament_id, p_node_id, 1, false) s;
  ELSE
    SELECT p.match_seconds, p.break_seconds, NULL::int
      INTO v_ms, v_bs, v_ta
      FROM public._tournament_schedule_prelim_seconds(p_tournament_id) p;
  END IF;
  PERFORM public._tournament_upsert_round_schedule(
    p_tournament_id, p_node_id, 1, 'group', v_ms, v_bs, v_ta, now());

  -- ADR-0031 C1 (E1) GAP-CLOSE: stage-graph rounds were SILENT before C1
  -- (this runner fired NO participant notify). Add a per-pitch publish-notify
  -- of the stage's materialised round (round 1, phase 'group') AFTER the
  -- matches and the stage schedule row exist; starts_at resolved inside the
  -- helper from the schedule row (degrades cleanly without one).
  PERFORM public._tournament_notify_round_per_pitch(
    p_tournament_id, 1, 'group', 'round_published',
    'Runde 1 veröffentlicht',
    'Turnier-Stufe: Runde 1 ist da.');

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_generate_stage_matches(uuid, text, uuid[])
  TO authenticated;

COMMENT ON FUNCTION public.tournament_generate_stage_matches(uuid, text, uuid[]) IS
  'ADR-0030 runner Step 3 (re-based 20261247000000 via A1 20261252000000); '
  'ADR-0031 A1 adds one tournament_round_schedule row per stage (stage_node_id '
  '= p_node_id, round 1, phase group; time from prelim match_format, OE-6); '
  'ADR-0031 C1 GAP-CLOSE adds a per-pitch publish-notify (round_published, '
  'round 1, phase group) — stage-graph rounds were previously silent. '
  'single_elim and routed consolation share the single-elim bracket; '
  'double_elim uses _tournament_compute_de_bracket (with_reset from config); '
  'round_robin/pool emit all N*(N-1)/2 group pairs; swiss emits round 1 seed '
  'slide (odd field -> lowest-seed BYE). shootout_quali raises 22023. BYE '
  'pairings auto-finalized. Pure materializer otherwise. Returns rows inserted.';
