-- Tournament — ADR-0033 §4 / ADR-0034 §1 P5.3b: KO matchup is consumed.
--
-- ko_matchup ('seed_high_vs_low' | 'one_vs_two') was stored but never read.
-- This makes BOTH paths honour it at round-1 bracket pairing:
--   * _tournament_compute_ko_bracket gains an additive p_matchup param
--     (DEFAULT 'seed_high_vs_low'); only the ROUND-1 pairing branches —
--     'one_vs_two' pairs adjacent seeds (1-2, 3-4, ...). bracket_position
--     and round 2+ advance slots are UNCHANGED (advance logic intact).
--   * classic tournament_start_ko_phase passes tournaments.ko_matchup.
--   * stage tournament_generate_stage_matches passes config->>'ko_matchup'
--     for single_elim / consolation.
-- Double-elim keeps standard seeding (DE matchup is out of scope here).
--
-- The old 2-arg helper is dropped and replaced by the 3-arg/default form,
-- so every existing 2-arg caller resolves to it (matchup defaulted).
-- Additive; no schema/CDC/publication change.

DROP FUNCTION IF EXISTS public._tournament_compute_ko_bracket(jsonb, boolean);

CREATE OR REPLACE FUNCTION public._tournament_compute_ko_bracket(
  p_seeds       jsonb,
  p_third_place boolean,
  p_matchup     text DEFAULT 'seed_high_vs_low'
)
RETURNS TABLE (
  round_number     int,
  bracket_position int,
  participant_a    uuid,
  participant_b    uuid,
  phase            text,
  is_bye_pairing   boolean
)
LANGUAGE plpgsql
AS $$
DECLARE
  v_n            int;
  v_size         int := 1;
  v_total_rounds int := 0;
  v_slots        uuid[];     -- 1-indexed: slot[i] = seed-i Teilnehmer (NULL = BYE)
  v_order        int[];      -- 1-indexed: recursive standard bracket seed order
  v_inner        int[];
  v_next         int[];
  v_half         int;
  v_a            uuid;
  v_b            uuid;
  v_is_bye       boolean;
  v_phase        text;
  i              int;
  r              int;
  bp             int;
  pairings_in_r  int;
BEGIN
  IF p_seeds IS NULL OR jsonb_typeof(p_seeds) <> 'array' THEN
    RAISE EXCEPTION 'seeds must be a JSON array' USING ERRCODE = '22023';
  END IF;
  v_n := jsonb_array_length(p_seeds);
  IF v_n < 2 OR v_n > 64 THEN
    RAISE EXCEPTION 'seeds length must be in [2, 64], got %', v_n
      USING ERRCODE = '22023';
  END IF;

  -- next_pow2(n)
  WHILE v_size < v_n LOOP
    v_size := v_size * 2;
  END LOOP;

  -- Pad slots with NULL (BYE) marker at positions n+1 .. size (1-indexed).
  v_slots := ARRAY[]::uuid[];
  FOR i IN 1 .. v_size LOOP
    IF i <= v_n THEN
      v_slots := v_slots || (p_seeds ->> (i - 1))::uuid;
    ELSE
      v_slots := v_slots || NULL::uuid;
    END IF;
  END LOOP;

  -- Recursive standard bracket order (iterative build, doubling).
  -- inner = order(1) = [1]; for k = 2,4,8,...,size:
  --   next[2i-1] := inner[i],         next[2i] := k+1-inner[i]   (i odd)
  --   next[2i-1] := k+1-inner[i],     next[2i] := inner[i]       (i even)
  -- (1-indexed mirror of Dart `_standardBracketOrder`.)
  v_inner := ARRAY[1];
  v_half := 1;
  WHILE v_half < v_size LOOP
    v_half := v_half * 2;
    v_next := ARRAY[]::int[];
    FOR i IN 1 .. array_length(v_inner, 1) LOOP
      IF (i % 2) = 1 THEN
        v_next := v_next || v_inner[i] || (v_half + 1 - v_inner[i]);
      ELSE
        v_next := v_next || (v_half + 1 - v_inner[i]) || v_inner[i];
      END IF;
    END LOOP;
    v_inner := v_next;
  END LOOP;
  v_order := v_inner;

  -- total_rounds = log2(size)
  v_total_rounds := 0;
  i := v_size;
  WHILE i > 1 LOOP
    v_total_rounds := v_total_rounds + 1;
    i := i / 2;
  END LOOP;

  -- ---- Round 1: real pairings derived from seed order ----------------
  -- P5.3b: matchup only changes WHO meets in round 1; bracket_position and the
  -- round 2+ advance slots are untouched, so the advance logic stays intact.
  --   * 'seed_high_vs_low' (default): standard recursive bracket order
  --     (slot[order[2i-1]] vs slot[order[2i]] => 1-N, 2-(N-1), ...).
  --   * 'one_vs_two': adjacent seeds meet (slot[2i-1] vs slot[2i] => 1-2, 3-4,
  --     ...); BYE-padded bottom slots fall into the last pairs.
  bp := 0;
  FOR i IN 1 .. (v_size / 2) LOOP
    bp := bp + 1;
    IF p_matchup = 'one_vs_two' THEN
      v_a := v_slots[2 * i - 1];
      v_b := v_slots[2 * i];
    ELSE
      v_a := v_slots[v_order[2 * i - 1]];
      v_b := v_slots[v_order[2 * i]];
    END IF;
    v_is_bye := (v_a IS NULL) OR (v_b IS NULL);
    -- Phase: 'final' wenn R1 == Final (n=2), sonst 'ko'.
    v_phase := CASE WHEN v_total_rounds = 1 THEN 'final' ELSE 'ko' END;
    round_number     := 1;
    bracket_position := bp;
    participant_a    := v_a;
    participant_b    := v_b;
    phase            := v_phase;
    is_bye_pairing   := v_is_bye;
    RETURN NEXT;
  END LOOP;

  -- ---- Round 2 .. total_rounds: Placeholder-Rows ---------------------
  FOR r IN 2 .. v_total_rounds LOOP
    pairings_in_r := v_size / (1 << r);
    v_phase := CASE WHEN r = v_total_rounds THEN 'final' ELSE 'ko' END;
    FOR bp IN 1 .. pairings_in_r LOOP
      round_number     := r;
      bracket_position := bp;
      participant_a    := NULL;
      participant_b    := NULL;
      phase            := v_phase;
      is_bye_pairing   := false;
      RETURN NEXT;
    END LOOP;
  END LOOP;

  -- ---- Optional Third-Place-Match ------------------------------------
  -- Konvention: round_number = total_rounds, bracket_position = 1,
  -- phase = 'third_place'. Phase-Spalte disambiguiert gegen die
  -- Final-Row (selbes round_number + bp=1, aber phase='final').
  -- Wird vom `advance_ko_winner`-Trigger (T4) **nicht** als regulaeres
  -- Folge-Ziel betrachtet — die Loser-Spiegelung ist eine separate
  -- Phasen-Sonderbehandlung (ADR-0017 §5).
  IF p_third_place THEN
    round_number     := v_total_rounds;
    bracket_position := 1;
    participant_a    := NULL;
    participant_b    := NULL;
    phase            := 'third_place';
    is_bye_pairing   := false;
    RETURN NEXT;
  END IF;

  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_compute_ko_bracket(jsonb, boolean, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_compute_ko_bracket(jsonb, boolean, text) FROM authenticated;

COMMENT ON FUNCTION public._tournament_compute_ko_bracket(jsonb, boolean, text) IS
  'Mirror of Dart Bracket.singleElimination (kubb_domain). p_matchup 
  (seed_high_vs_low|one_vs_two) branches ONLY the round-1 pairing 
  (ADR-0034 §1). Consumed by tournament_start_ko_phase and the stage 
  generator. See ADR-0017 §7.';

-- ===================================================================
-- Caller 1 (classic): tournament_start_ko_phase — pass tournaments.ko_matchup
-- Re-based from its latest body (20261281000000_gate_split.sql).
-- ===================================================================

CREATE OR REPLACE FUNCTION public.tournament_start_ko_phase(p_tournament_id uuid, p_ko_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller            uuid;
  v_creator           uuid;
  v_with_third_place  boolean;
  v_qualifier_count   int;
  v_incomplete        uuid[];
  v_ko_exists         int;
  v_has_pool_phase    boolean;
  v_seeds_jsonb       jsonb;
  v_match_count       int := 0;
  v_bye_count         int := 0;
  v_group_label       text;
  v_top_n             int;
  v_cut_result        jsonb;
  v_conflict_ids      jsonb := '[]'::jsonb;
  v_override_ids      uuid[];
  v_pool_count        int;
  v_bracket_type      text;
  v_with_reset        boolean;
  v_round             smallint;   -- PITCH-PLAN loop variable
  v_max_round         smallint;   -- ADR-0031 A1: final-round discriminator
  v_name              text;       -- GO-LIVE-NOTIFY
  v_grp               record;     -- SHOOTOUT-GATE
  v_pending_shootouts int := 0;   -- SHOOTOUT-GATE
  v_full_order        uuid[];     -- SHOOTOUT-RESOLVE
  v_chain             text[];     -- SHOOTOUT-RESOLVE / C6
  v_so                record;     -- SHOOTOUT-RESOLVE
  v_k                 int;        -- SHOOTOUT-RESOLVE
  -- CONSOLATION (E2):
  v_cons_cfg          jsonb;      -- tournaments.consolation_bracket
  v_cons_enabled      boolean;
  v_cons_main_size    int;
  v_cons_direct_cnt   int;
  v_cons_direct_ids   jsonb := '[]'::jsonb;
  -- CF6 manual-seeding gate:
  v_seeding_mode      text;
  v_seed_override_cnt int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, bracket_type,
         coalesce((ko_config ->> 'with_bracket_reset')::boolean, true),
         display_name, consolation_bracket, tiebreaker_order
    INTO v_creator, v_bracket_type, v_with_reset, v_name, v_cons_cfg, v_chain
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_ko_config IS NULL OR jsonb_typeof(p_ko_config) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: ko_config must be a JSON object'
      USING ERRCODE = '22023';
  END IF;
  v_with_third_place := coalesce(
    (p_ko_config ->> 'with_third_place_playoff')::boolean, false);
  v_qualifier_count := coalesce((p_ko_config ->> 'qualifier_count')::int, 0);
  IF v_qualifier_count < 2 OR v_qualifier_count > 64 THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count must be in [2, 64]'
      USING ERRCODE = '22023';
  END IF;

  IF v_bracket_type = 'double_elimination' THEN
    v_with_reset := coalesce(
      (p_ko_config ->> 'with_bracket_reset')::boolean, v_with_reset);
    IF v_with_third_place THEN
      RAISE EXCEPTION 'INVALID_KO_CONFIG: with_third_place_playoff is not allowed for double_elimination'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  v_cons_enabled := coalesce((v_cons_cfg ->> 'enabled')::boolean, false)
                    AND v_bracket_type <> 'double_elimination';

  SELECT count(*) INTO v_ko_exists
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','third_place','final',
                    'wb','lb','grand_final','grand_final_reset',
                    'consolation','consolation_third_place');
  IF v_ko_exists > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: ko phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  SELECT coalesce(array_agg(id ORDER BY id), ARRAY[]::uuid[])
    INTO v_incomplete
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase = 'group'
      AND status NOT IN ('finalized','overridden','voided');
  IF array_length(v_incomplete, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'PHASE_NOT_COMPLETE: % group match(es) not terminal: %',
      array_length(v_incomplete, 1), v_incomplete
      USING ERRCODE = '22023';
  END IF;

  -- ==================================================================
  -- CF6 manual-seeding gate. SINGLE functional addition vs the
  -- 20261204000000_p6_fix_bundle baseline. When the tournament is
  -- configured for manual seeding (ko_config.seeding_mode = 'manual'),
  -- the organizer MUST set a complete seed list before the KO can
  -- start. We treat the seeding as "set" once at least
  -- `qualifier_count` overrides exist in tournament_seeding_overrides
  -- (the seeding screen writes one row per qualifier via
  -- tournament_set_seeding). For auto seeding (or a missing
  -- discriminator = default auto) no gate fires. Position: after the
  -- 40001 idempotency guard and the 22023 phase-complete guard, before
  -- the SHOOTOUT-GATE / pool detection / bracket insert, so it only
  -- fires on a legitimate Vorrunde->KO transition. The exception is
  -- machine-readable: ERRCODE 22023 + 'seeding_required' prefix, so the
  -- client can route the organizer to the seeding screen instead of
  -- showing a raw error.
  -- ==================================================================
  v_seeding_mode := coalesce(p_ko_config ->> 'seeding_mode', 'auto');
  IF v_seeding_mode = 'manual' THEN
    SELECT count(*) INTO v_seed_override_cnt
      FROM public.tournament_seeding_overrides
      WHERE tournament_id = p_tournament_id;
    IF v_seed_override_cnt < v_qualifier_count THEN
      RAISE EXCEPTION
        'seeding_required: manual seeding must be set before KO start'
        USING ERRCODE = '22023';
    END IF;
  END IF;
  -- ==================== end CF6 manual-seeding gate =================

  -- ==================================================================
  -- SHOOTOUT-GATE (P6 D2a). VERBATIM.
  -- ==================================================================
  FOR v_grp IN
    SELECT * FROM public._tournament_detect_shootout_groups(
                     p_tournament_id, v_qualifier_count)
  LOOP
    INSERT INTO public.tournament_shootouts(
        tournament_id, start_rank, tied_participant_ids)
      VALUES (p_tournament_id, v_grp.start_rank, v_grp.participant_ids)
      ON CONFLICT (tournament_id, tie_key) DO NOTHING;

    IF FOUND THEN
      PERFORM public._tournament_notify_shootout_group(
        p_tournament_id,
        v_grp.participant_ids,
        'Shoot-Out nötig',
        'Turnier "' || coalesce(v_name, '')
          || '": Gleichstand an der Qualifikations-Grenze — tragt den '
          || 'Shoot-Out-Sieger ein.',
        jsonb_build_object(
          'tournament_id', p_tournament_id,
          'kind',          'shootout',
          'start_rank',    v_grp.start_rank,
          'tied',          to_jsonb(v_grp.participant_ids)));
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.tournament_shootouts s
       WHERE s.tournament_id = p_tournament_id
         AND s.status = 'resolved'
         AND s.tied_participant_ids @> v_grp.participant_ids
         AND s.tied_participant_ids <@ v_grp.participant_ids
    ) THEN
      v_pending_shootouts := v_pending_shootouts + 1;
    END IF;
  END LOOP;

  IF v_pending_shootouts > 0 THEN
    RAISE EXCEPTION 'SHOOTOUT_PENDING: % qualification-relevant shoot-out(s) unresolved',
      v_pending_shootouts USING ERRCODE = 'P0001';
  END IF;
  -- ==================== end SHOOTOUT-GATE ===========================

  SELECT EXISTS (
    SELECT 1 FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL
  ) INTO v_has_pool_phase;

  IF v_has_pool_phase THEN
    SELECT coalesce(array_agg(participant_id), ARRAY[]::uuid[])
      INTO v_override_ids
      FROM public.tournament_seeding_overrides
     WHERE tournament_id = p_tournament_id;

    SELECT count(DISTINCT group_label) INTO v_pool_count
      FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL;
    v_top_n := greatest(1, ((v_qualifier_count + v_pool_count - 1) / v_pool_count));

    CREATE TEMP TABLE IF NOT EXISTS _tmp_pool_cuts (
      group_label text,
      rank_in_pool int,
      participant_id uuid
    ) ON COMMIT DROP;
    TRUNCATE _tmp_pool_cuts;

    FOR v_group_label IN
      SELECT DISTINCT group_label
        FROM public.tournament_participants
       WHERE tournament_id = p_tournament_id
         AND group_label IS NOT NULL
       ORDER BY 1
    LOOP
      v_cut_result := public._tournament_compute_pool_cut(
        p_tournament_id, v_group_label, v_top_n);

      IF coalesce((v_cut_result ->> 'tie_resolution_needed')::boolean, false) THEN
        v_conflict_ids := v_conflict_ids
          || coalesce(v_cut_result -> 'conflicting_participants', '[]'::jsonb);
      END IF;

      INSERT INTO _tmp_pool_cuts(group_label, rank_in_pool, participant_id)
      SELECT v_group_label,
             (ord)::int,
             (val #>> '{}')::uuid
        FROM jsonb_array_elements(v_cut_result -> 'qualifiers')
             WITH ORDINALITY AS t(val, ord);
    END LOOP;

    IF jsonb_array_length(v_conflict_ids) > 0 THEN
      SELECT coalesce(jsonb_agg(elem ORDER BY elem), '[]'::jsonb)
        INTO v_conflict_ids
        FROM (
          SELECT DISTINCT elem
            FROM jsonb_array_elements_text(v_conflict_ids) AS elem
           WHERE (elem)::uuid <> ALL (v_override_ids)
        ) sub;

      IF jsonb_array_length(v_conflict_ids) > 0 THEN
        RAISE EXCEPTION 'TIEBREAKER_NEEDS_RESOLUTION'
          USING ERRCODE = 'P0001',
                DETAIL = jsonb_build_object(
                  'conflicting_participants', v_conflict_ids)::text;
      END IF;
    END IF;

    WITH labels AS (
      SELECT group_label,
             dense_rank() OVER (ORDER BY group_label) AS label_idx
        FROM (SELECT DISTINCT group_label FROM _tmp_pool_cuts) g
    ),
    base AS (
      SELECT c.participant_id,
             (c.rank_in_pool - 1) * 1000 + l.label_idx AS interleave_seed
        FROM _tmp_pool_cuts c
        JOIN labels l USING (group_label)
    ),
    overrides AS (
      SELECT participant_id, seed_override
        FROM public.tournament_seeding_overrides
       WHERE tournament_id = p_tournament_id
    ),
    combined AS (
      SELECT b.participant_id,
             coalesce(o.seed_override::numeric,
                      b.interleave_seed::numeric + 1000000) AS effective_seed,
             b.interleave_seed
        FROM base b
        LEFT JOIN overrides o USING (participant_id)
    ),
    seeded AS (
      SELECT participant_id,
             row_number() OVER (ORDER BY effective_seed, interleave_seed) AS final_seed
        FROM combined
    )
    SELECT coalesce(jsonb_agg(to_jsonb(participant_id::text) ORDER BY final_seed), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM seeded
     WHERE final_seed <= v_qualifier_count;

  ELSE
    -- ============================================================
    -- P6-FIX C6: chain-gated, total_points-first default seed ranking. This
    -- matches _tournament_detect_shootout_groups, SHOOTOUT-RESOLVE's v_full_order
    -- and tournament_pool_standings (the canonical order). Previously this CTE
    -- ranked "wins DESC, kubb_diff DESC" without total_points and without chain
    -- gating, so the cut line (detector) and the actual seeds could diverge.
    -- v_chain was loaded above (tiebreaker_order). registered_at/participant_id
    -- remain the deterministic ID-fallback tail, not a separating criterion.
    -- ============================================================
    WITH stats AS (
      SELECT p.id AS participant_id,
             p.registered_at,
             coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                    WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                    ELSE 0 END), 0) AS total_points,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id
                      THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                    WHEN m.participant_b = p.id
                      THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                    ELSE 0 END), 0) AS kubb_diff
        FROM public.tournament_participants p
        LEFT JOIN public.tournament_matches m
          ON m.tournament_id = p.tournament_id
         AND m.phase = 'group'
         AND m.status IN ('finalized','overridden')
         AND (m.participant_a = p.id OR m.participant_b = p.id)
       WHERE p.tournament_id = p_tournament_id
         AND p.registration_status = 'confirmed'
       GROUP BY p.id, p.registered_at
    ),
    ranked AS (
      SELECT participant_id,
             row_number() OVER (
               ORDER BY
                 CASE WHEN 'total_points'    = ANY(v_chain) THEN -total_points ELSE 0 END,
                 CASE WHEN 'wins'            = ANY(v_chain) THEN -wins         ELSE 0 END,
                 CASE WHEN 'kubb_difference' = ANY(v_chain) THEN -kubb_diff    ELSE 0 END,
                 registered_at ASC,
                 participant_id ASC
             ) AS auto_seed
        FROM stats
    ),
    overrides AS (
      SELECT participant_id, seed_override
        FROM public.tournament_seeding_overrides
       WHERE tournament_id = p_tournament_id
    ),
    combined AS (
      SELECT r.participant_id,
             coalesce(o.seed_override::numeric,
                      r.auto_seed::numeric + 1000) AS effective_seed,
             r.auto_seed
        FROM ranked r
        LEFT JOIN overrides o USING (participant_id)
    ),
    seeded AS (
      SELECT participant_id,
             row_number() OVER (ORDER BY effective_seed, auto_seed) AS final_seed
        FROM combined
    )
    SELECT coalesce(jsonb_agg(to_jsonb(participant_id::text) ORDER BY final_seed), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM seeded
     WHERE final_seed <= v_qualifier_count;
  END IF;

  -- ==================================================================
  -- SHOOTOUT-RESOLVE (resolveWithShootouts). VERBATIM (v_chain already loaded).
  -- ==================================================================
  IF NOT v_has_pool_phase AND EXISTS (
    SELECT 1 FROM public.tournament_shootouts
     WHERE tournament_id = p_tournament_id AND status = 'resolved'
  ) THEN
    WITH stats AS (
      SELECT p.id AS pid,
             p.registered_at,
             coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                    WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                    ELSE 0 END), 0) AS total_points,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id
                      THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                    WHEN m.participant_b = p.id
                      THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                    ELSE 0 END), 0) AS kubb_diff
        FROM public.tournament_participants p
        LEFT JOIN public.tournament_matches m
          ON m.tournament_id = p.tournament_id
         AND m.phase = 'group'
         AND m.status IN ('finalized','overridden')
         AND (m.participant_a = p.id OR m.participant_b = p.id)
       WHERE p.tournament_id = p_tournament_id
         AND p.registration_status = 'confirmed'
       GROUP BY p.id, p.registered_at
    )
    SELECT array_agg(pid ORDER BY rnk)
      INTO v_full_order
      FROM (
        SELECT s.pid,
               row_number() OVER (
                 ORDER BY
                   CASE WHEN 'total_points'    = ANY(v_chain) THEN -s.total_points ELSE 0 END,
                   CASE WHEN 'wins'            = ANY(v_chain) THEN -s.wins         ELSE 0 END,
                   CASE WHEN 'kubb_difference' = ANY(v_chain) THEN -s.kubb_diff    ELSE 0 END,
                   s.registered_at ASC,
                   s.pid ASC
               ) AS rnk
          FROM stats s
      ) r;

    FOR v_so IN
      SELECT start_rank, ordered_winners
        FROM public.tournament_shootouts
       WHERE tournament_id = p_tournament_id
         AND status = 'resolved'
         AND ordered_winners IS NOT NULL
    LOOP
      FOR v_k IN 1 .. array_length(v_so.ordered_winners, 1) LOOP
        v_full_order[v_so.start_rank + v_k] := v_so.ordered_winners[v_k];
      END LOOP;
    END LOOP;

    SELECT coalesce(jsonb_agg(to_jsonb(pid::text) ORDER BY ord), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM (
        SELECT pid, ord
          FROM unnest(v_full_order) WITH ORDINALITY AS t(pid, ord)
         WHERE ord <= v_qualifier_count
      ) q;
  END IF;
  -- ==================== end SHOOTOUT-RESOLVE ========================

  IF jsonb_array_length(v_seeds_jsonb) < v_qualifier_count THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count % exceeds confirmed participants',
      v_qualifier_count USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET ko_config = p_ko_config
    WHERE id = p_tournament_id;

  IF v_bracket_type = 'double_elimination' THEN
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
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
  ELSE
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
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
             v_seeds_jsonb, v_with_third_place,
             coalesce((SELECT ko_matchup FROM public.tournaments
                         WHERE id = p_tournament_id), 'seed_high_vs_low')) b;
  END IF;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  -- ==================================================================
  -- CONSOLATION-MATERIALISE (E2, ADR-0028 §1.1/§3/§4).
  -- ==================================================================
  IF v_cons_enabled THEN
    -- P6-FIX C11: honour the persisted main_bracket_size (ADR-0028 §5) when set;
    -- fall back to next_pow2(qualifier_count) (== main bracket size) otherwise.
    v_cons_main_size := coalesce((v_cons_cfg ->> 'main_bracket_size')::int, 0);
    IF v_cons_main_size < 2 THEN
      v_cons_main_size := 1;
      WHILE v_cons_main_size < v_qualifier_count LOOP
        v_cons_main_size := v_cons_main_size * 2;
      END LOOP;
    END IF;

    -- direct_count (now persisted by the wire; defensive default 0).
    v_cons_direct_cnt := greatest(0, coalesce((v_cons_cfg ->> 'direct_count')::int, 0));
    -- Direct starters: the top prelim ranks NOT already seeded into the main
    -- bracket (seeds beyond qualifier_count), best-first, capped at direct_count.
    IF v_cons_direct_cnt > 0 AND NOT v_has_pool_phase THEN
      WITH stats AS (
        SELECT p.id AS pid,
               p.registered_at,
               coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
               coalesce(sum(
                 CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                      WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                      ELSE 0 END), 0) AS total_points,
               coalesce(sum(
                 CASE WHEN m.participant_a = p.id
                        THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                      WHEN m.participant_b = p.id
                        THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                      ELSE 0 END), 0) AS kubb_diff
          FROM public.tournament_participants p
          LEFT JOIN public.tournament_matches m
            ON m.tournament_id = p.tournament_id
           AND m.phase = 'group'
           AND m.status IN ('finalized','overridden')
           AND (m.participant_a = p.id OR m.participant_b = p.id)
         WHERE p.tournament_id = p_tournament_id
           AND p.registration_status = 'confirmed'
         GROUP BY p.id, p.registered_at
      ),
      ranked AS (
        SELECT pid,
               row_number() OVER (
                 ORDER BY
                   CASE WHEN 'total_points'    = ANY(v_chain) THEN -total_points ELSE 0 END,
                   CASE WHEN 'wins'            = ANY(v_chain) THEN -wins         ELSE 0 END,
                   CASE WHEN 'kubb_difference' = ANY(v_chain) THEN -kubb_diff    ELSE 0 END,
                   registered_at ASC,
                   pid ASC
               ) AS rnk
          FROM stats
      )
      SELECT coalesce(jsonb_agg(to_jsonb(pid::text) ORDER BY rnk), '[]'::jsonb)
        INTO v_cons_direct_ids
        FROM ranked
       WHERE rnk > v_qualifier_count
         AND rnk <= v_qualifier_count + v_cons_direct_cnt;
    ELSE
      v_cons_direct_ids := '[]'::jsonb;
    END IF;

    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           c.round_number::smallint,
           c.bracket_position::smallint,
           c.bracket_position,
           c.participant_a,
           c.participant_b,
           c.phase,
           CASE WHEN c.is_bye_pairing THEN 'awaiting_results' ELSE 'scheduled' END,
           CASE WHEN c.is_bye_pairing
                THEN coalesce(c.participant_a, c.participant_b) END,
           1,
           NULL
      FROM public._tournament_compute_cons_bracket(
             v_cons_main_size, v_cons_direct_ids, '[]'::jsonb) c;

    UPDATE public.tournament_matches
      SET status = 'finalized',
          finalized_at = now()
      WHERE tournament_id = p_tournament_id
        AND phase = 'consolation'
        AND winner_participant IS NOT NULL
        AND status = 'awaiting_results';

    SELECT count(*) INTO v_match_count
      FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND phase IN ('ko','third_place','final',
                      'consolation','consolation_third_place');
  END IF;

  -- ADR-0031 A1: the highest KO round_number is the final (final-round
  -- discriminator for the schedule phase below).
  SELECT max(round_number) INTO v_max_round
    FROM public.tournament_matches
   WHERE tournament_id = p_tournament_id
     AND phase IN ('ko','third_place','final',
                   'wb','lb','grand_final','grand_final_reset',
                   'consolation','consolation_third_place');

  FOR v_round IN
    SELECT DISTINCT round_number
      FROM public.tournament_matches
     WHERE tournament_id = p_tournament_id
       AND phase IN ('ko','third_place','final',
                     'wb','lb','grand_final','grand_final_reset',
                     'consolation','consolation_third_place')
     ORDER BY round_number
  LOOP
    PERFORM public._tournament_assign_pitches(p_tournament_id, v_round);

    -- ADR-0031 A1: one schedule row per KO round (phase 'final' for the last
    -- round, else 'ko'); seconds from ko_round_formats[round-1] with fallback.
    PERFORM public._tournament_upsert_round_schedule(
      p_tournament_id, NULL, v_round,
      CASE WHEN v_round = v_max_round THEN 'final' ELSE 'ko' END,
      (public._tournament_schedule_ko_seconds(
         p_tournament_id, v_round, v_round = v_max_round)).match_seconds,
      (public._tournament_schedule_ko_seconds(
         p_tournament_id, v_round, v_round = v_max_round)).break_seconds,
      (public._tournament_schedule_ko_seconds(
         p_tournament_id, v_round, v_round = v_max_round)).tiebreak_after,
      now());

    -- ADR-0031 C1 (E1): one per-pitch publish-notify per KO round, phase
    -- mirroring the schedule row ('final' for the max round, else 'ko').
    -- After pitches + the schedule row exist for this round.
    PERFORM public._tournament_notify_round_per_pitch(
      p_tournament_id, v_round,
      CASE WHEN v_round = v_max_round THEN 'final' ELSE 'ko' END,
      'round_published',
      'Runde ' || v_round || ' veröffentlicht',
      'Turnier "' || coalesce(v_name, '') || '": K.-o.-Runde ' || v_round
        || ' ist da.');
  END LOOP;

  SELECT count(*) INTO v_bye_count
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','final','wb','lb','consolation')
      AND status = 'finalized';

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'ko_phase_started',
      v_caller,
      jsonb_build_object(
        'qualifier_count',          v_qualifier_count,
        'with_third_place_playoff', v_with_third_place,
        'bracket_type',             v_bracket_type,
        'with_bracket_reset',       v_with_reset,
        'consolation_enabled',      v_cons_enabled,
        'match_count',              v_match_count,
        'bye_count',                v_bye_count,
        'pool_phase_present',       v_has_pool_phase,
        'seeds',                    v_seeds_jsonb));

  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_round',
    'Neue Runde',
    'Turnier "' || coalesce(v_name, '') || '": K.-o.-Phase — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'phase', 'ko'));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'match_count',   v_match_count,
    'bye_count',     v_bye_count,
    'pool_phase',    v_has_pool_phase,
    'bracket_type',  v_bracket_type,
    'consolation',   v_cons_enabled);
END;
$function$
;

-- ===================================================================
-- Caller 2 (stage): tournament_generate_stage_matches — pass config matchup
-- Re-based from its latest body (20261286000000_stage_pool_multi_group.sql).
-- ===================================================================

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

  ELSIF v_type IN ('round_robin', 'pool') THEN
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

  -- ADR-0031 A1: materialise this stage's round 1 schedule (stage_node_id =
  -- p_node_id, phase 'group'); time from the prelim match_format (OE-6).
  PERFORM public._tournament_upsert_round_schedule(
    p_tournament_id, p_node_id, 1, 'group',
    (public._tournament_schedule_prelim_seconds(p_tournament_id)).match_seconds,
    (public._tournament_schedule_prelim_seconds(p_tournament_id)).break_seconds,
    NULL, now());

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
