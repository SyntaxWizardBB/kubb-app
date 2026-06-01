-- Tournament feature — P6 Double-Elimination server side (ADR-0027 §3).
--
-- Mirrors the pure-Dart domain (`packages/kubb_domain/lib/src/tournament/
-- bracket.dart`: `Bracket.doubleElimination`, `lbDropTarget`, `_lbR1DropSlot`)
-- 1:1 in plpgsql, so the property-parity gate (ADR-0017 §7, ADR-0027 §5.2)
-- can assert Dart == server. Adds:
--   1. `_tournament_seed_order(int)`        — shared recursive seed order
--                                             (extracted from the inline loop
--                                             in _tournament_compute_ko_bracket).
--   2. `_tournament_compute_de_bracket(jsonb, boolean)`
--                                           — DE topology generator.
--   3. `_tournament_de_lb_target(int,int,int)` — pure LB drop-target reflection.
--   4. `tournament_start_ko_phase(uuid, jsonb)` — REPLACED to branch on
--                                             tournaments.bracket_type.
--   5. `tournament_advance_ko_winner()`     — REPLACED to feed WB losers into
--                                             the LB and run the grand-final
--                                             (+ reset) path.
--
-- Bezug: ADR-0027 §3, P6_RULES_DECISIONS.md §D, ADR-0017 §5/§7.
--
-- ============================== DEPENDENCIES ==============================
-- This migration depends on the following EXISTING objects (verified by
-- reading the listed source files; cannot be executed here — no local PG):
--
--   FUNCTIONS (replaced / parallel):
--     * public._tournament_compute_ko_bracket(jsonb, boolean)
--         — single-elim helper, UNCHANGED, kept as the single_elimination
--           branch target. Returns the same row-shape this file reuses.
--         SOURCE: 20260601000014_fn_compute_ko_bracket.sql
--     * public.tournament_start_ko_phase(uuid, jsonb)
--         — latest definition (pool-aware) is REPLACED here. The full
--           pool-cut / standings seeding body is preserved verbatim; only the
--           bracket-INSERT step (Z. 282-299 of the pool-extend migration) is
--           branched on bracket_type.
--         SOURCE: 20260615000010_start_ko_phase_pool_extend.sql (latest def).
--                 (earlier defs: 20260601000015_rpc_tournament_start_ko_phase.sql)
--     * public._tournament_compute_pool_cut(uuid, text, int)
--         — called inside the preserved pool branch, UNCHANGED.
--         SOURCE: 20260615000009/10 (pool phase).
--     * public.tournament_advance_ko_winner()  (+ its TRIGGER)
--         — REPLACED to add WB→LB and GF logic. Existing single-elim
--           ('ko'/'third_place'/'final') behaviour preserved verbatim.
--         SOURCE: 20260601000016_trigger_advance_ko_winner.sql
--
--   TABLES / COLUMNS:
--     * public.tournament_matches(
--         tournament_id uuid, round_number smallint,
--         match_number_in_round smallint, bracket_position int|smallint,
--         participant_a uuid, participant_b uuid, phase text, status text,
--         winner_participant uuid, pitch_number, finalized_at, ...)
--         — phase CHECK already widened to include wb/lb/grand_final/
--           grand_final_reset.
--         SOURCE: 20260601000010_tournament_ko_phase.sql (phase, bracket_position),
--                 20261101000001_double_elim_phase.sql (widened CHECK).
--     * public.tournaments(id, created_by, ko_config jsonb,
--         bracket_type text)
--         — bracket_type from 20261001000001 (Z. 134-135);
--           ko_config from 20260601000010 (Z. 44-46), carries
--           with_bracket_reset (default true) + with_third_place_playoff.
--     * public.tournament_participants, public.tournament_seeding_overrides,
--       public.tournament_audit_events — UNCHANGED, used by the preserved
--       seeding/audit body.
--         SOURCE: M1/M2/M3 migrations (unchanged).
--
--   STATUS / PHASE enums used:
--     status  IN ('scheduled','awaiting_results','finalized','overridden',
--                 'voided','disputed')  — existing tournament_matches values.
--     phase   IN ('group','ko','third_place','final',
--                 'wb','lb','grand_final','grand_final_reset').
-- ==========================================================================


-- ======================================================================
-- 1. Shared recursive standard bracket seed order.
--    Extracted verbatim from _tournament_compute_ko_bracket (Z. 99-113);
--    returns the 1-indexed seed order for a power-of-two `size`.
--    Mirror of Dart `_standardBracketOrder` (bracket.dart Z. 304+).
-- ======================================================================
CREATE OR REPLACE FUNCTION public._tournament_seed_order(p_size int)
RETURNS int[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_inner int[];
  v_next  int[];
  v_half  int;
  i       int;
BEGIN
  IF p_size < 1 THEN
    RAISE EXCEPTION 'size must be >= 1, got %', p_size USING ERRCODE = '22023';
  END IF;
  v_inner := ARRAY[1];
  v_half := 1;
  WHILE v_half < p_size LOOP
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
  RETURN v_inner;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_seed_order(int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_seed_order(int) FROM authenticated;

COMMENT ON FUNCTION public._tournament_seed_order(int) IS
  'Recursive standard bracket seed order (1-indexed) for a power-of-two size. '
  'Extracted from _tournament_compute_ko_bracket; mirror of Dart '
  '_standardBracketOrder. Shared by single- and double-elim helpers.';


-- ======================================================================
-- 2. Pure LB drop-target reflection (mirror of Dart lbDropTarget §1.4).
--    For a WB round k >= 2 and 1-based WB bracket_position, returns the
--    0-based LB slot (pairing_index * 2 + side) in LB round 2k-2 (major).
--    The WB loser always lands on the B-slot (+1). `lbMatches = size / 2^k`.
-- ======================================================================
CREATE OR REPLACE FUNCTION public._tournament_de_lb_target(
  p_wb_round    int,
  p_wb_position int,
  p_size        int
)
RETURNS int           -- 0-based LB slot in the target major round
LANGUAGE sql
IMMUTABLE
AS $$
  -- lbMatches = size >> k ; i = wbPosition-1 ; lbPairing = (lbMatches-1)-i
  -- result = lbPairing*2 + 1  (B-slot). Mirror of Dart bracket.dart Z. 283-289.
  SELECT (((p_size >> p_wb_round) - 1) - (p_wb_position - 1)) * 2 + 1;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_de_lb_target(int, int, int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_de_lb_target(int, int, int) FROM authenticated;

COMMENT ON FUNCTION public._tournament_de_lb_target(int, int, int) IS
  'Pure LB drop-target reflection (ADR-0027 §1.4). Mirror of Dart '
  'lbDropTarget. WB-R k>=2 loser of bracket_position p drops into LB round '
  '2k-2, B-slot of pairing (size/2^k - 1) - (p-1). Property-parity asserted '
  'against the Dart impl.';


-- ======================================================================
-- 3. Double-elim topology generator (mirror of Bracket.doubleElimination).
--    Output row-shape IDENTICAL to _tournament_compute_ko_bracket plus the
--    new phases. Deterministic emit order: WB R1..wbCount, LB R1..lbCount,
--    grand_final, then grand_final_reset (only when p_with_reset).
-- ======================================================================
CREATE OR REPLACE FUNCTION public._tournament_compute_de_bracket(
  p_seeds      jsonb,
  p_with_reset boolean
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
  v_n         int;
  v_size      int := 1;
  v_wb_count  int := 0;   -- = log2(size)
  v_lb_count  int := 0;   -- = 2 * (wb_count - 1)
  v_slots     uuid[];     -- 1-indexed seed slots (NULL = BYE)
  v_order     int[];      -- recursive standard order
  v_a         uuid;
  v_b         uuid;
  v_is_bye    boolean;
  v_matches   int;
  v_slot0     int;        -- 0-based LB-R1 slot for a WB-R1 BYE feeder
  v_lb_pair   int;        -- 0-based LB-R1 pairing index that becomes a walkover
  v_bye_pairs int[];      -- 1-based LB-R1 pairing indices pre-marked BYE
  i           int;
  r           int;
  bp          int;
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

  -- wb_count = log2(size)
  i := v_size;
  WHILE i > 1 LOOP
    v_wb_count := v_wb_count + 1;
    i := i / 2;
  END LOOP;
  v_lb_count := 2 * (v_wb_count - 1);  -- 0 when size == 2

  -- Pad slots with NULL (BYE) at positions n+1..size (1-indexed).
  v_slots := ARRAY[]::uuid[];
  FOR i IN 1 .. v_size LOOP
    IF i <= v_n THEN
      v_slots := v_slots || (p_seeds ->> (i - 1))::uuid;
    ELSE
      v_slots := v_slots || NULL::uuid;
    END IF;
  END LOOP;

  v_order := public._tournament_seed_order(v_size);

  -- ---- WB-R1: real pairings from seed order (phase always 'wb') ---------
  -- Also collect, for every BYE WB-R1 pairing, the LB-R1 pairing it feeds
  -- (mirror of Dart §1.5 pre-mark via _lbR1DropSlot). lbMatches_R1 = size/4.
  v_bye_pairs := ARRAY[]::int[];
  bp := 0;
  FOR i IN 1 .. (v_size / 2) LOOP
    bp := bp + 1;
    v_a := v_slots[v_order[2 * i - 1]];
    v_b := v_slots[v_order[2 * i]];
    v_is_bye := (v_a IS NULL) OR (v_b IS NULL);

    IF v_is_bye AND v_lb_count > 0 THEN
      -- _lbR1DropSlot(bp, size): lbPairing = (size/4 - 1) - ((bp-1) >> 1)
      --   slot = lbPairing*2 + ((bp-1) % 2).  We pre-mark the *pairing*.
      v_lb_pair := ((v_size >> 2) - 1) - ((bp - 1) / 2);  -- 0-based pairing
      v_bye_pairs := v_bye_pairs || (v_lb_pair + 1);      -- store 1-based
    END IF;

    round_number     := 1;
    bracket_position := bp;
    participant_a    := v_a;
    participant_b    := v_b;
    phase            := 'wb';
    is_bye_pairing   := v_is_bye;
    RETURN NEXT;
  END LOOP;

  -- ---- WB-R2 .. wb_count: placeholder rows (phase 'wb', incl. WB final) --
  FOR r IN 2 .. v_wb_count LOOP
    v_matches := v_size / (1 << r);
    FOR bp IN 1 .. v_matches LOOP
      round_number     := r;
      bracket_position := bp;
      participant_a    := NULL;
      participant_b    := NULL;
      phase            := 'wb';
      is_bye_pairing   := false;
      RETURN NEXT;
    END LOOP;
  END LOOP;

  -- ---- LB-R1 .. lb_count: placeholder rows (phase 'lb') -----------------
  -- minor (odd j):  size >> ((j+3)/2) ; major (even j): size >> ((j+2)/2).
  -- LB-R1 pairings that receive a WB-R1 BYE feeder are pre-marked
  -- is_bye_pairing=true (walkover) — mirror of Dart pre-mark (§1.5).
  FOR r IN 1 .. v_lb_count LOOP
    IF (r % 2) = 1 THEN
      v_matches := v_size >> ((r + 3) / 2);   -- minor
    ELSE
      v_matches := v_size >> ((r + 2) / 2);   -- major
    END IF;
    FOR bp IN 1 .. v_matches LOOP
      round_number     := r;
      bracket_position := bp;
      participant_a    := NULL;
      participant_b    := NULL;
      phase            := 'lb';
      -- Only LB-R1 carries pre-marked BYE walkovers.
      is_bye_pairing   := (r = 1 AND bp = ANY (v_bye_pairs));
      RETURN NEXT;
    END LOOP;
  END LOOP;

  -- ---- Grand Final (phase 'grand_final', round_number=1, bp=1) ----------
  round_number     := 1;
  bracket_position := 1;
  participant_a    := NULL;
  participant_b    := NULL;
  phase            := 'grand_final';
  is_bye_pairing   := false;
  RETURN NEXT;

  -- ---- Grand Final Reset (only when with_reset) -------------------------
  IF p_with_reset THEN
    round_number     := 1;
    bracket_position := 1;
    participant_a    := NULL;
    participant_b    := NULL;
    phase            := 'grand_final_reset';
    is_bye_pairing   := false;
    RETURN NEXT;
  END IF;

  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_compute_de_bracket(jsonb, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_compute_de_bracket(jsonb, boolean) FROM authenticated;

COMMENT ON FUNCTION public._tournament_compute_de_bracket(jsonb, boolean) IS
  'Mirror of Dart Bracket.doubleElimination (kubb_domain, ADR-0027 §1). '
  'Generates WB/LB/grand_final(+reset) match rows from a seed-ordered '
  'participant list. WB reuses the single-elim seed order; LB uses the '
  'major/minor closed form; LB-R1 BYE walkovers pre-marked. Consumed by '
  'tournament_start_ko_phase. Property-parity asserted vs. Dart (ADR-0027 §5.2).';


-- ======================================================================
-- 4. tournament_start_ko_phase — branch the bracket-INSERT on bracket_type.
--    The seeding body (auth, idempotency, group-phase check, pool-cut /
--    standings seeding, ko_config persist, audit) is preserved VERBATIM
--    from 20260615000010_start_ko_phase_pool_extend.sql. Only:
--      * idempotency guard widened to the DE phases,
--      * with_third_place_playoff + double_elimination => INVALID_KO_CONFIG,
--      * v_bracket_type / v_with_reset read,
--      * the INSERT…SELECT branched on bracket_type,
--      * bye_count count widened to include LB-R1 walkovers.
-- ======================================================================
CREATE OR REPLACE FUNCTION public.tournament_start_ko_phase(
  p_tournament_id uuid,
  p_ko_config     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
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
  v_bracket_type      text;     -- DE: single_elimination | double_elimination
  v_with_reset        boolean;  -- DE: grand-final reset toggle
BEGIN
  -- 1. Authentication + Organizer-Lock.
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, bracket_type,
         coalesce((ko_config ->> 'with_bracket_reset')::boolean, true)
    INTO v_creator, v_bracket_type, v_with_reset
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL OR v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  -- 2. KO-Config validieren.
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

  -- 2b. DE: with_bracket_reset can be overridden in the request config;
  --     P6 §D.5 forbids the third-place playoff for double-elimination.
  IF v_bracket_type = 'double_elimination' THEN
    v_with_reset := coalesce(
      (p_ko_config ->> 'with_bracket_reset')::boolean, v_with_reset);
    IF v_with_third_place THEN
      RAISE EXCEPTION 'INVALID_KO_CONFIG: with_third_place_playoff is not allowed for double_elimination'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- 3. Idempotency-Guard: existieren bereits KO-/DE-Match-Rows? (ADR-0017 §7)
  SELECT count(*) INTO v_ko_exists
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','third_place','final',
                    'wb','lb','grand_final','grand_final_reset');
  IF v_ko_exists > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: ko phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  -- 4. Vorrunde komplett?
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

  -- 5. Pool-Phase erkennen.
  SELECT EXISTS (
    SELECT 1 FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL
  ) INTO v_has_pool_phase;

  IF v_has_pool_phase THEN
    -- 5a. Pre-existing manual overrides.
    SELECT coalesce(array_agg(participant_id), ARRAY[]::uuid[])
      INTO v_override_ids
      FROM public.tournament_seeding_overrides
     WHERE tournament_id = p_tournament_id;

    -- 5b. Top-N pro Gruppe.
    SELECT count(DISTINCT group_label) INTO v_pool_count
      FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL;
    v_top_n := greatest(1, ((v_qualifier_count + v_pool_count - 1) / v_pool_count));

    -- 5c. Per-Gruppe Helper.
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

    -- 5d. Konflikt-Filter.
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

    -- 5e. Cross-Pool-Interleave.
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
    -- 6a. M2-Pfad: Standings-Order + Overrides → Top-N (unverändert).
    WITH stats AS (
      SELECT p.id AS participant_id,
             p.registered_at,
             coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id THEN m.final_score_a - m.final_score_b
                    WHEN m.participant_b = p.id THEN m.final_score_b - m.final_score_a
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
               ORDER BY wins DESC, kubb_diff DESC, registered_at ASC, participant_id ASC
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

  IF jsonb_array_length(v_seeds_jsonb) < v_qualifier_count THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count % exceeds confirmed participants',
      v_qualifier_count USING ERRCODE = '22023';
  END IF;

  -- 7. Persistiere ko_config (inkl. with_bracket_reset für DE).
  UPDATE public.tournaments
    SET ko_config = p_ko_config
    WHERE id = p_tournament_id;

  -- 8. Bracket via Helper berechnen und Match-Rows inserten — branch auf
  --    bracket_type. Beide Pfade teilen die identische Row-Shape
  --    (round_number, bracket_position, participant_a/b, phase, is_bye_pairing).
  --    BYE-Auto-Advance: is_bye_pairing → status='finalized' + winner, damit
  --    der Trigger den BYE-Sieger weiterschiebt (WB-R2 bzw. LB-Walkover).
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
      FROM public._tournament_compute_ko_bracket(v_seeds_jsonb, v_with_third_place) b;
  END IF;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  -- BYE-Count: für single-elim wie bisher ('ko','final'); für DE auch
  -- WB-/LB-Walkover-Rows (phase 'wb'/'lb', status finalized).
  SELECT count(*) INTO v_bye_count
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','final','wb','lb')
      AND status = 'finalized';

  -- 9. Audit-Event ko_phase_started.
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
        'match_count',              v_match_count,
        'bye_count',                v_bye_count,
        'pool_phase_present',       v_has_pool_phase,
        'seeds',                    v_seeds_jsonb));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'match_count',   v_match_count,
    'bye_count',     v_bye_count,
    'pool_phase',    v_has_pool_phase,
    'bracket_type',  v_bracket_type);
END;
$$;

COMMENT ON FUNCTION public.tournament_start_ko_phase(uuid, jsonb) IS
  'P6-erweitert (ADR-0027 §3.2): verzweigt den Bracket-INSERT auf '
  'tournaments.bracket_type. double_elimination ruft '
  '_tournament_compute_de_bracket (WB/LB/GF + optional Reset), '
  'single_elimination unverändert _tournament_compute_ko_bracket. '
  'with_third_place_playoff bei double_elimination = INVALID_KO_CONFIG '
  '(P6 §D.5). Seeding/Pool-Cut/Audit unverändert (M3.3). Siehe ADR-0017 §7.';


-- ======================================================================
-- 5. tournament_advance_ko_winner — WB→LB feed + grand-final (+reset).
--    Single-elim branch ('ko'/'third_place'/'final') preserved verbatim.
--    Double-elim branches added for 'wb'/'lb'/'grand_final'/
--    'grand_final_reset'. Property-parity with Dart §1.4 via
--    _tournament_de_lb_target.
-- ======================================================================
CREATE OR REPLACE FUNCTION public.tournament_advance_ko_winner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, auth
AS $$
DECLARE
  v_loser_part      uuid;
  v_next_round      int;
  v_next_position   int;
  v_is_odd          boolean;
  v_third_enabled   boolean;
  v_final_round     int;
  v_next_a          uuid;
  v_next_b          uuid;
  v_next_status     text;
  v_tp_a            uuid;
  v_tp_b            uuid;
  v_tp_status       text;
  -- DE locals:
  v_wb_count        int;       -- = log2(size); WB final round
  v_size            int;       -- 2^wb_count
  v_lb_count        int;       -- 2*(wb_count-1)
  v_lb_target_round int;
  v_lb_slot0        int;       -- 0-based LB slot from _tournament_de_lb_target
  v_lb_target_pos   int;       -- 1-based LB pairing
  v_lb_side_b       boolean;   -- true => B-slot
  v_with_reset      boolean;
  v_gf_round        int;
BEGIN
  -- Defensive: nothing to propagate without a winner.
  IF NEW.winner_participant IS NULL THEN
    RETURN NEW;
  END IF;

  -- Loser (used by third-place AND LB feed).
  v_loser_part := CASE
    WHEN NEW.winner_participant = NEW.participant_a THEN NEW.participant_b
    WHEN NEW.winner_participant = NEW.participant_b THEN NEW.participant_a
    ELSE NULL
  END;

  v_next_round    := NEW.round_number + 1;
  v_next_position := (NEW.bracket_position + 1) / 2;  -- ceil(x/2) for x>=1
  v_is_odd        := (NEW.bracket_position % 2) = 1;

  -- =====================================================================
  -- SINGLE-ELIMINATION PATH (unchanged from 20260601000016).
  -- =====================================================================
  IF NEW.phase IN ('ko','final') THEN
    SELECT participant_a, participant_b, status
      INTO v_next_a, v_next_b, v_next_status
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND round_number  = v_next_round
        AND bracket_position = v_next_position
        AND phase IN ('ko','final')
      FOR UPDATE;

    IF FOUND THEN
      IF v_is_odd THEN
        v_next_a := NEW.winner_participant;
      ELSE
        v_next_b := NEW.winner_participant;
      END IF;

      IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
         AND v_next_status = 'scheduled' THEN
        v_next_status := 'awaiting_results';
      END IF;

      UPDATE public.tournament_matches
        SET participant_a = v_next_a,
            participant_b = v_next_b,
            status        = v_next_status
        WHERE tournament_id = NEW.tournament_id
          AND round_number  = v_next_round
          AND bracket_position = v_next_position
          AND phase IN ('ko','final');
    END IF;
  END IF;

  IF NEW.phase = 'ko' AND v_loser_part IS NOT NULL THEN
    SELECT (t.ko_config ->> 'with_third_place_playoff')::boolean
      INTO v_third_enabled
      FROM public.tournaments t
      WHERE t.id = NEW.tournament_id;

    IF COALESCE(v_third_enabled, false) THEN
      SELECT MAX(round_number)
        INTO v_final_round
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'final';

      IF v_final_round IS NOT NULL AND v_next_round = v_final_round THEN
        SELECT participant_a, participant_b, status
          INTO v_tp_a, v_tp_b, v_tp_status
          FROM public.tournament_matches
          WHERE tournament_id    = NEW.tournament_id
            AND round_number     = v_final_round
            AND bracket_position = 1
            AND phase            = 'third_place'
          FOR UPDATE;

        IF FOUND THEN
          IF v_is_odd THEN
            v_tp_a := v_loser_part;
          ELSE
            v_tp_b := v_loser_part;
          END IF;

          IF v_tp_a IS NOT NULL AND v_tp_b IS NOT NULL
             AND v_tp_status = 'scheduled' THEN
            v_tp_status := 'awaiting_results';
          END IF;

          UPDATE public.tournament_matches
            SET participant_a = v_tp_a,
                participant_b = v_tp_b,
                status        = v_tp_status
            WHERE tournament_id    = NEW.tournament_id
              AND round_number     = v_final_round
              AND bracket_position = 1
              AND phase            = 'third_place';
        END IF;
      END IF;
    END IF;
  END IF;

  -- =====================================================================
  -- DOUBLE-ELIMINATION PATH (ADR-0027 §3.3).
  -- size = 2 ^ max(round_number over phase='wb').
  -- =====================================================================
  IF NEW.phase IN ('wb','lb','grand_final','grand_final_reset') THEN
    SELECT MAX(round_number) INTO v_wb_count
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND phase = 'wb';
    v_size := (1 << v_wb_count);          -- 2^wb_count
    v_lb_count := 2 * (v_wb_count - 1);
  END IF;

  -- ---- 3.3 (1) WB: winner advances in WB; loser drops into LB ----------
  IF NEW.phase = 'wb' THEN
    IF NEW.round_number < v_wb_count THEN
      -- Winner → next WB match (round+1, ceil(bp/2); odd→A, even→B).
      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND round_number  = v_next_round
          AND bracket_position = v_next_position
          AND phase = 'wb'
        FOR UPDATE;
      IF FOUND THEN
        IF v_is_odd THEN v_next_a := NEW.winner_participant;
        ELSE             v_next_b := NEW.winner_participant; END IF;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_next_a,
              participant_b = v_next_b,
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND round_number  = v_next_round
            AND bracket_position = v_next_position
            AND phase = 'wb';
      END IF;
    ELSE
      -- WB FINAL: winner → grand_final slot A.
      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'grand_final'
          AND round_number = 1
          AND bracket_position = 1
        FOR UPDATE;
      IF FOUND THEN
        v_next_a := NEW.winner_participant;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_next_a, status = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'grand_final'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;

    -- LOSER → LB. NULL loser (BYE WB match) leaves the LB slot empty so the
    -- LB walkover resolves once the real opponent arrives (mirror of Dart
    -- §1.5 / ADR-0027 §3.3 BYE note).
    IF v_loser_part IS NOT NULL AND v_lb_count > 0 THEN
      IF NEW.round_number = 1 THEN
        -- WB-R1 → LB-R1 (minor). Both losers of a WB slot-pair meet; the
        -- reflection mirrors halves. _lbR1DropSlot(bp,size):
        --   lbPairing = (size/4 - 1) - ((bp-1)>>1) ; side = (bp-1) % 2.
        v_lb_target_round := 1;
        v_lb_target_pos   := ((v_size >> 2) - 1) - ((NEW.bracket_position - 1) / 2) + 1; -- 1-based
        v_lb_side_b       := ((NEW.bracket_position - 1) % 2) = 1;  -- odd index => B
      ELSE
        -- WB-R k>=2 → LB-R 2k-2 (major), B-slot, reflected.
        v_lb_target_round := 2 * NEW.round_number - 2;
        v_lb_slot0        := public._tournament_de_lb_target(
                               NEW.round_number, NEW.bracket_position, v_size);
        v_lb_target_pos   := (v_lb_slot0 / 2) + 1;   -- 1-based pairing
        v_lb_side_b       := (v_lb_slot0 % 2) = 1;   -- always B for major
      END IF;

      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'lb'
          AND round_number = v_lb_target_round
          AND bracket_position = v_lb_target_pos
        FOR UPDATE;
      IF FOUND THEN
        IF v_lb_side_b THEN v_next_b := v_loser_part;
        ELSE                v_next_a := v_loser_part; END IF;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_next_a,
              participant_b = v_next_b,
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'lb'
            AND round_number = v_lb_target_round
            AND bracket_position = v_lb_target_pos;
      END IF;
    END IF;
  END IF;

  -- ---- 3.3 (2) LB: winner advances inside LB; LB-final → GF slot B ------
  IF NEW.phase = 'lb' THEN
    IF NEW.round_number < v_lb_count THEN
      -- Next LB round. Two regimes (mirror of the §1.3 closed form):
      --   * current round is MINOR (odd): consolidation → MAJOR (even),
      --     same #matches; winner lands in A-slot (B reserved for WB feed).
      --     LB pairing index is preserved (1:1).
      --   * current round is MAJOR (even): feeds the next MINOR (odd) round,
      --     #matches halves; pairing = ceil(bp/2), odd→A even→B.
      IF (NEW.round_number % 2) = 1 THEN
        -- minor → major: same pairing index, A-slot.
        v_lb_target_round := NEW.round_number + 1;
        v_lb_target_pos   := NEW.bracket_position;
        v_lb_side_b       := false;  -- A-slot; B reserved for WB-loser feed
      ELSE
        -- major → minor: consolidate two majors into one minor.
        v_lb_target_round := NEW.round_number + 1;
        v_lb_target_pos   := (NEW.bracket_position + 1) / 2;  -- ceil
        v_lb_side_b       := (NEW.bracket_position % 2) = 0;  -- odd→A, even→B
      END IF;

      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'lb'
          AND round_number = v_lb_target_round
          AND bracket_position = v_lb_target_pos
        FOR UPDATE;
      IF FOUND THEN
        IF v_lb_side_b THEN v_next_b := NEW.winner_participant;
        ELSE                v_next_a := NEW.winner_participant; END IF;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_next_a,
              participant_b = v_next_b,
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'lb'
            AND round_number = v_lb_target_round
            AND bracket_position = v_lb_target_pos;
      END IF;
    ELSE
      -- LB FINAL: winner → grand_final slot B.
      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'grand_final'
          AND round_number = 1
          AND bracket_position = 1
        FOR UPDATE;
      IF FOUND THEN
        v_next_b := NEW.winner_participant;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_b = v_next_b, status = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'grand_final'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;
  END IF;

  -- ---- 3.3 (3) GRAND FINAL: maybe materialise the reset --------------
  IF NEW.phase = 'grand_final' THEN
    -- Slot A = WB-Champion, Slot B = LB-Champion.
    SELECT coalesce((t.ko_config ->> 'with_bracket_reset')::boolean, true)
      INTO v_with_reset
      FROM public.tournaments t
      WHERE t.id = NEW.tournament_id;

    -- WB-Champion (A) won → tournament over, no reset.
    -- LB-Champion (B) won AND with_reset → materialise the reset:
    --   A = WB-Champion (GF1 slot A), B = LB-Champion (GF1 winner).
    IF NEW.winner_participant = NEW.participant_b AND COALESCE(v_with_reset, true) THEN
      SELECT status INTO v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'grand_final_reset'
          AND round_number = 1
          AND bracket_position = 1
        FOR UPDATE;
      IF FOUND THEN
        v_next_status := CASE WHEN v_next_status = 'scheduled'
                              THEN 'awaiting_results' ELSE v_next_status END;
        UPDATE public.tournament_matches
          SET participant_a = NEW.participant_a,  -- WB-Champion
              participant_b = NEW.participant_b,  -- LB-Champion (GF1 winner)
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'grand_final_reset'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;
    -- WB-Champion won, OR LB-Champion won without reset → no propagation;
    -- tournament-end is governed by terminal-match logic elsewhere
    -- (unchanged, analog single-elim final).
  END IF;

  -- ---- 3.3 (4) GRAND FINAL RESET: winner = champion, no propagation ----
  -- (Nothing to do: the reset match is terminal.)

  RETURN NEW;
END;
$$;

-- WHEN-Clause widened to the four DE phases (in addition to the single-elim
-- ones). All other trigger attributes unchanged from 20260601000016.
DROP TRIGGER IF EXISTS tournament_advance_ko_winner ON public.tournament_matches;
CREATE TRIGGER tournament_advance_ko_winner
  AFTER UPDATE ON public.tournament_matches
  FOR EACH ROW
  WHEN (
    OLD.status NOT IN ('finalized','overridden')
    AND NEW.status     IN ('finalized','overridden')
    AND NEW.phase      IN ('ko','third_place','final',
                           'wb','lb','grand_final','grand_final_reset')
  )
  EXECUTE FUNCTION public.tournament_advance_ko_winner();

COMMENT ON FUNCTION public.tournament_advance_ko_winner() IS
  'AFTER-UPDATE-Trigger: schreibt KO-/DE-Sieger fort (ADR-0017 §5, ADR-0027 §3.3). '
  'Single-elim (ko/third_place/final) unverändert. Double-elim: WB-Sieger → '
  'WB-Folge bzw. GF-A; WB-Verlierer → LB (Reflexion via _tournament_de_lb_target); '
  'LB-Sieger steigt minor→major→…→GF-B; GF1-Verlierer (WB-Champ) → '
  'grand_final_reset wenn with_bracket_reset. Walkover/Forfeit-kompatibel.';
