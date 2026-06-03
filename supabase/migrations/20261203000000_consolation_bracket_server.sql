-- Tournament feature — P6 E2: Consolation bracket (Trostturnier, Model B)
-- SERVER side (ADR-0028).
--
-- Mirrors the pure-Dart domain (packages/kubb_domain/lib/src/tournament/
-- bracket.dart: Bracket.consolation, consolationShape, consolationDropTarget,
-- consolationDropSlot) 1:1 in plpgsql, so the property-parity gate
-- (ADR-0017 §7, ADR-0027 §5.2, ADR-0028 "Drift-Risiko") can assert
-- Dart == server. The main bracket stays the UNCHANGED single-elimination
-- output (_tournament_compute_ko_bracket); the consolation tree is an additive
-- second match block under the new phases 'consolation' / 'consolation_third_place'.
--
-- This migration adds:
--   1. phase CHECK widened (idempotent) to include 'consolation' and
--      'consolation_third_place' (ADR-0028 §7.3).
--   2. _tournament_cons_shape(int,int)        — staggered-aware recurrence
--                                               (mirror of consolationShape, §3.3).
--   3. _tournament_cons_drop_target(int,int)  — pure target-round mapping with
--                                               sentinels -1 / 0
--                                               (mirror of consolationDropTarget, §2.2).
--   4. _tournament_cons_drop_slot(int,int)    — pure B-slot reflection
--                                               (mirror of consolationDropSlot, §3.3).
--   5. _tournament_cons_seed_slot(int,int)    — 0-based consolation-R1 slot for the
--                                               j-th seeded entry (inverse of the
--                                               recursive seed order; used to route
--                                               main-R1 losers into R1, §3.3 step 2).
--   6. _tournament_compute_cons_bracket(int,jsonb,jsonb) — consolation topology
--                                               generator (mirror of Bracket.consolation).
--   7. tournament_start_ko_phase(uuid,jsonb)  — REPLACED: latest body
--                                               (20261202000000 shoot-out) re-stated
--                                               VERBATIM + a CONSOLATION-MATERIALISE
--                                               step and the consolation phases in the
--                                               idempotency guard.
--   8. tournament_advance_ko_winner()         — REPLACED: latest body
--                                               (20261101000002 double-elim) re-stated
--                                               VERBATIM + a CONSOLATION-ROUTING branch
--                                               (main-loser feed, consolation-internal
--                                               progression, consolation 3rd-place mirror).
--
-- !!! CONFIG-PERSISTENCE REALITY (ADR-0028 §5 vs. actual wire) — DOD-09 !!!
-- The Dart ConsolationConfig.toJson (tournament_setup.dart) persists ONLY
--   { enabled, source, source_rounds, rank_from, rank_to, match_format }
-- into tournaments.consolation_bracket (20261001000002 §INSERT). The Model-B
-- extension keys consolation_main_bracket_size / consolation_direct_count /
-- consolation_name and a per-round consolation_round_formats[] list are emitted
-- by tournament_config_draft.toSetupConfig() as TOP-LEVEL setup keys and are
-- DROPPED at create-time (no dedicated tournaments column). Consequence for this
-- server migration:
--   * mainSize: derived deterministically from the materialised MAIN bracket —
--       at start it is next_pow2(qualifier_count) (the seed count handed to
--       _tournament_compute_ko_bracket); at routing time it is
--       2 ^ max(round_number over phase IN ('ko','final')) (ADR-0028 §7.4),
--       exactly like the DE size derivation. NOT read from consolation_bracket.
--   * direct_count: read defensively from consolation_bracket->>'direct_count'
--       if ever present, else 0 (the only value the current wire ever yields).
--   * per-round formats: the single consolation_bracket->'match_format' is the
--       only persisted consolation rule set; there is no per-round list to read.
--       It is applied to every consolation round, falling back to the §E default
--       (Bo3/30min, final Bo5/60min) when absent. tournament_matches has NO
--       per-row match-format column, so the format is carried exactly the same
--       way the MAIN KO per-round formats are: not stamped onto the match row
--       (see ko_round_formats — persisted on tournaments, read by the client).
--       The consolation tree therefore inherits the same format-application path
--       as the main KO; no per-row stamping is introduced here.
-- This Brief↔reality discrepancy is documented in the verification report.
--
-- Bezug: ADR-0028 (§2/§3/§4/§6/§7), ADR-0017 §5/§7, ADR-0027 §3.3.
--
-- ============================== DEPENDENCIES ==============================
--   FUNCTIONS (replaced / reused):
--     * public._tournament_compute_ko_bracket(jsonb, boolean)
--         — single-elim main-bracket helper, UNCHANGED, reused verbatim.
--         SOURCE: 20260601000014_fn_compute_ko_bracket.sql
--     * public._tournament_seed_order(int)
--         — recursive standard seed order, UNCHANGED, reused.
--         SOURCE: 20261101000002_double_elim_server.sql §1
--     * public.tournament_start_ko_phase(uuid, jsonb)
--         — latest body REPLACED here (shoot-out gate/resolve preserved verbatim).
--         SOURCE: 20261202000000_tournament_shootout_server.sql §8 (latest def).
--     * public.tournament_advance_ko_winner() (+ TRIGGER)
--         — latest body REPLACED here (single- + double-elim branches verbatim).
--         SOURCE: 20261101000002_double_elim_server.sql §5 (latest def).
--     * public._tournament_compute_de_bracket / _tournament_compute_pool_cut /
--       _tournament_detect_shootout_groups / _tournament_notify_shootout_group /
--       _tournament_assign_pitches / _tournament_notify_participants /
--       tournament_caller_can_manage — all UNCHANGED, called by the preserved body.
--   TABLES / COLUMNS:
--     * public.tournament_matches(tournament_id, round_number, match_number_in_round,
--         bracket_position, participant_a, participant_b, phase, status,
--         winner_participant, pitch_number, finalized_at)
--         — phase CHECK widened here to include the two consolation values.
--     * public.tournaments(id, created_by, ko_config jsonb, bracket_type text,
--         consolation_bracket jsonb)
--         — consolation_bracket from 20261001000001 §5; carries enabled (+the
--           ConsolationConfig fields). bracket_type stays 'single_elimination'
--           for Model B (detection is via consolation_bracket->>'enabled').
-- ==========================================================================


-- ======================================================================
-- 1. phase CHECK — widen idempotently to the two consolation values.
--    Keeps ALL existing 8 values. ADR-0028 §7.3 (analog ADR-0027 §2).
-- ======================================================================
ALTER TABLE public.tournament_matches
  DROP CONSTRAINT IF EXISTS tournament_matches_phase_check;
ALTER TABLE public.tournament_matches
  ADD CONSTRAINT tournament_matches_phase_check
    CHECK (phase IN (
      'group','ko','third_place','final',
      'wb','lb','grand_final','grand_final_reset',
      'consolation','consolation_third_place'));

COMMENT ON COLUMN public.tournament_matches.phase IS
  'Per-match phase discriminator. `group` round-robin; `ko`/`third_place`/'
  '`final` single-elim; `wb`/`lb`/`grand_final`/`grand_final_reset` '
  'double-elim (ADR-0027); `consolation`/`consolation_third_place` '
  'consolation bracket (Trostturnier, ADR-0028). Defaults to `group`.';


-- ======================================================================
-- 2. _tournament_cons_drop_target — pure target-round mapping.
--    Mirror of Dart consolationDropTarget (bracket.dart §2.2).
--    Sentinels: -1 (kConsolationThirdPlace, semifinal -> 3rd-place playoff),
--                0 (kConsolationNone, final / out of range).
--    Feeding rounds 1..mainRounds-2 map 1:1 onto consolation rounds.
-- ======================================================================
CREATE OR REPLACE FUNCTION public._tournament_cons_drop_target(
  p_main_round int,
  p_main_size  int
)
RETURNS int
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_main_rounds int := 0;
  v_x           int := p_main_size;
BEGIN
  WHILE v_x > 1 LOOP
    v_main_rounds := v_main_rounds + 1;
    v_x := v_x / 2;
  END LOOP;
  IF p_main_round >= v_main_rounds THEN
    RETURN 0;                 -- kConsolationNone (final)
  END IF;
  IF p_main_round = v_main_rounds - 1 THEN
    RETURN -1;                -- kConsolationThirdPlace (semifinal)
  END IF;
  RETURN p_main_round;        -- consolation round (1-based)
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_cons_drop_target(int, int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_cons_drop_target(int, int) FROM authenticated;

COMMENT ON FUNCTION public._tournament_cons_drop_target(int, int) IS
  'Mirror of Dart consolationDropTarget (ADR-0028 §2.2). Returns the target '
  'consolation ROUND a main-bracket round-r loser enters; sentinel -1 = '
  'semifinal (3rd-place playoff), 0 = final / no feed. Pure, deterministic.';


-- ======================================================================
-- 3. _tournament_cons_drop_slot — pure B-slot reflection (mirror of Dart
--    consolationDropSlot, §3.3). Returns the 0-based slot (pairing*2 + side)
--    inside the target consolation round into which a staggered main-round
--    (r >= 2) loser of 1-based bracket_position [mainPosition] docks. The loser
--    always lands on the B-slot (+1); A = consolation survivor. [consMatches] =
--    P_r/2 pairings of the target round. Anti-rematch reflection like lbDropTarget.
-- ======================================================================
CREATE OR REPLACE FUNCTION public._tournament_cons_drop_slot(
  p_main_position int,
  p_cons_matches  int
)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  -- i = mainPosition-1 ; consPairing = (consMatches-1) - i ; slot = consPairing*2 + 1.
  SELECT ((p_cons_matches - 1) - (p_main_position - 1)) * 2 + 1;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_cons_drop_slot(int, int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_cons_drop_slot(int, int) FROM authenticated;

COMMENT ON FUNCTION public._tournament_cons_drop_slot(int, int) IS
  'Mirror of Dart consolationDropSlot (ADR-0028 §3.3). 0-based B-slot reflection '
  'for a staggered main-round (r>=2) loser into its target consolation round. '
  'Pure, deterministic; property-parity asserted vs. the Dart impl.';


-- ======================================================================
-- 4. _tournament_cons_shape — staggered-aware recurrence (ADR-0028 §3.3).
--    Mirror of Dart consolationShape. One row per consolation round r (1-based):
--      L_r       = mainSize/2^r for r in 1..mainRounds-2, else 0
--      E_1       = directCount + L_1 ;  E_r = S_{r-1} + L_r (r>=2)
--      P_r       = next_pow2(E_r) ;  S_r = P_r/2 ;  matches = P_r/2 ;  byes = P_r-E_r
--    Stops at the smallest r with S_r == 1 (consRounds), with the same early-exit
--    guards as the Dart loop (lone survivor / no population).
-- ======================================================================
CREATE OR REPLACE FUNCTION public._tournament_cons_shape(
  p_main_size    int,
  p_direct_count int
)
RETURNS TABLE (
  round     int,
  entrants  int,
  padded    int,
  byes      int,
  survivors int,
  matches   int
)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_main_rounds int := 0;
  v_x           int := p_main_size;
  v_surv_prev   int := 0;   -- S_{r-1}
  v_r           int := 1;
  v_lr          int;
  v_entrants    int;
  v_padded      int;
  v_survivors   int;
BEGIN
  IF p_main_size < 2 OR (p_main_size & (p_main_size - 1)) <> 0 THEN
    RAISE EXCEPTION 'main_size must be a power of two, got %', p_main_size
      USING ERRCODE = '22023';
  END IF;
  IF p_direct_count < 0 THEN
    RAISE EXCEPTION 'direct_count must be >= 0, got %', p_direct_count
      USING ERRCODE = '22023';
  END IF;

  WHILE v_x > 1 LOOP
    v_main_rounds := v_main_rounds + 1;
    v_x := v_x / 2;
  END LOOP;

  LOOP
    -- L_r = mainSize/2^r for feeding rounds 1..mainRounds-2, else 0.
    IF v_r >= 1 AND v_r <= v_main_rounds - 2 THEN
      v_lr := p_main_size >> v_r;
    ELSE
      v_lr := 0;
    END IF;

    IF v_r = 1 THEN
      v_entrants := p_direct_count + v_lr;
    ELSE
      v_entrants := v_surv_prev + v_lr;
    END IF;

    IF v_entrants <= 0 THEN
      EXIT;  -- no population at all
    END IF;
    IF v_entrants = 1 AND v_lr = 0 THEN
      EXIT;  -- lone survivor with no fresh feed = already the consolation winner
    END IF;

    -- next_pow2(entrants)
    v_padded := 1;
    WHILE v_padded < v_entrants LOOP
      v_padded := v_padded * 2;
    END LOOP;
    v_survivors := v_padded / 2;

    round     := v_r;
    entrants  := v_entrants;
    padded    := v_padded;
    byes      := v_padded - v_entrants;
    survivors := v_survivors;
    matches   := v_padded / 2;
    RETURN NEXT;

    -- L_{r+1} == 0 check for the stop condition (mirror of Dart losersFrom(r+1)).
    IF v_survivors <= 1
       AND NOT (v_r + 1 >= 1 AND v_r + 1 <= v_main_rounds - 2) THEN
      EXIT;
    END IF;
    v_surv_prev := v_survivors;
    v_r := v_r + 1;
  END LOOP;

  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_cons_shape(int, int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_cons_shape(int, int) FROM authenticated;

COMMENT ON FUNCTION public._tournament_cons_shape(int, int) IS
  'Mirror of Dart consolationShape (ADR-0028 §3.3). Staggered-aware recurrence: '
  'one row per consolation round (E_r/P_r/S_r/byes/matches); the tree size comes '
  'from the earliest-round population, NEVER next_pow2(total). consRounds = #rows.';


-- ======================================================================
-- 5. _tournament_cons_seed_slot — 0-based consolation-R1 slot for the j-th
--    seeded entry (0-based j). Inverse of the recursive seed order: the entry
--    with seed number s=j+1 sits at the linear position L where seed_order[L]=s;
--    pairing = ceil(L/2), side A (L odd) / B (L even). Used to route main-R1
--    losers into the slot reserved for r1LoserIds[p-1] (§3.3 step 2) and to seed
--    the direct starters identically to Bracket.consolation. [p1] = P_1 (padded).
-- ======================================================================
CREATE OR REPLACE FUNCTION public._tournament_cons_seed_slot(
  p_seed_index int,   -- 0-based index into the seeded list
  p_p1         int    -- P_1, padded power-of-two round-1 size
)
RETURNS int           -- 0-based R1 slot (pairing_index*2 + side)
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_order int[];
  v_seed  int := p_seed_index + 1;   -- 1-based seed number
  v_lin   int;
  i       int;
BEGIN
  v_order := public._tournament_seed_order(p_p1);  -- 1-indexed linear order
  v_lin := NULL;
  FOR i IN 1 .. array_length(v_order, 1) LOOP
    IF v_order[i] = v_seed THEN
      v_lin := i;                    -- linear position of this seed
      EXIT;
    END IF;
  END LOOP;
  IF v_lin IS NULL THEN
    RAISE EXCEPTION 'seed % not found in order of size %', v_seed, p_p1
      USING ERRCODE = '22023';
  END IF;
  -- pairing = ceil(v_lin/2); side = 0 (A) if v_lin odd, 1 (B) if even.
  RETURN ((v_lin - 1) / 2) * 2 + ((v_lin - 1) % 2);
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_cons_seed_slot(int, int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_cons_seed_slot(int, int) FROM authenticated;

COMMENT ON FUNCTION public._tournament_cons_seed_slot(int, int) IS
  'Inverse of the recursive seed order: 0-based consolation-R1 slot for the '
  'j-th seeded entry (direct starters then main-R1 losers, ADR-0028 §3.3 step 2). '
  'Pure, deterministic. Used at start (direct seeding) and at routing (R1 loser).';


-- ======================================================================
-- 6. _tournament_compute_cons_bracket — consolation topology generator.
--    Mirror of Dart Bracket.consolation (ADR-0028). The MAIN bracket is NOT
--    built here. Emits, in deterministic order:
--      * consolation R1 : direct starters seeded via _tournament_cons_seed_slot,
--        EMPTY slots reserved for main-R1 losers (filled by the trigger), byes
--        at the bottom seeds (so via recursive order they face the top seeds,
--        FR-FMT-11). A pairing with a bye real-opponent is is_bye_pairing=true.
--      * consolation R2..consRounds : bare placeholder pairings (count from the
--        shape) — A = consolation survivor, B = staggered loser, both filled by
--        the trigger at runtime (mirror of the LB-R2+ placeholders in DE).
--      * consolation_third_place : a single placeholder pairing, ONLY when
--        consRounds >= 2 (there is a consolation semifinal to rank 7/8).
--    [p_r1_loser_ids] is normally empty at start (the trigger fills R1 losers);
--    when given they are seeded after the direct starters (parity with Dart).
-- ======================================================================
CREATE OR REPLACE FUNCTION public._tournament_compute_cons_bracket(
  p_main_size    int,
  p_direct_ids   jsonb,           -- array of uuid-strings (direct starters)
  p_r1_loser_ids jsonb DEFAULT '[]'::jsonb
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
  v_direct_n   int;
  v_loser_n    int;
  v_direct_cnt int;
  v_p1         int;
  v_cons_rounds int;
  v_seeded     uuid[];     -- 1-indexed seeded list (direct then r1 losers)
  v_slots      uuid[];     -- 1-indexed R1 slot participant (NULL = bye / empty)
  v_is_bye     boolean[];  -- 1-indexed: is this R1 slot a structural bye?
  v_slot0      int;
  v_a          uuid;
  v_b          uuid;
  v_a_bye      boolean;
  v_b_bye      boolean;
  v_sh         record;
  v_first      boolean := true;
  i            int;
  bp           int;
BEGIN
  v_direct_n := coalesce(jsonb_array_length(p_direct_ids), 0);
  v_loser_n  := coalesce(jsonb_array_length(p_r1_loser_ids), 0);
  v_direct_cnt := v_direct_n;

  -- Build the seeded list: direct starters first, then the R1 losers.
  v_seeded := ARRAY[]::uuid[];
  FOR i IN 0 .. v_direct_n - 1 LOOP
    v_seeded := v_seeded || (p_direct_ids ->> i)::uuid;
  END LOOP;
  FOR i IN 0 .. v_loser_n - 1 LOOP
    v_seeded := v_seeded || (p_r1_loser_ids ->> i)::uuid;
  END LOOP;

  -- Pull the shape; consRounds = #rows. R1 padded P_1 = first row's padded.
  v_cons_rounds := 0;
  v_p1 := NULL;
  FOR v_sh IN
    SELECT * FROM public._tournament_cons_shape(p_main_size, v_direct_cnt)
             ORDER BY round
  LOOP
    v_cons_rounds := v_cons_rounds + 1;
    IF v_first THEN
      v_p1 := v_sh.padded;
      v_first := false;
    END IF;
  END LOOP;

  -- Empty tree (e.g. mainSize=2, D=0): nothing to materialise.
  IF v_cons_rounds = 0 OR v_p1 IS NULL THEN
    RETURN;
  END IF;

  -- ---- R1 slot population. Seeded entries occupy their recursive-order slot;
  --      every slot beyond E_1 entrants is a structural bye. Slots reserved for
  --      not-yet-known main-R1 losers stay NULL but are NOT byes (they fill via
  --      the trigger). We mark a slot as bye iff its seed index >= E_1.
  --      E_1 = directCount + L_1 (the round-1 entrant population from the shape).
  --      The seeded list we actually have here is direct starters (+ optional
  --      pre-known R1 losers); the remaining (E_1 - length) entrants are the
  --      main-R1 losers the trigger will fill — those slots are NULL non-bye.
  v_slots  := ARRAY[]::uuid[];
  v_is_bye := ARRAY[]::boolean[];
  FOR i IN 1 .. v_p1 LOOP
    v_slots  := v_slots  || NULL::uuid;
    v_is_bye := v_is_bye || false;
  END LOOP;

  DECLARE
    v_e1 int;
  BEGIN
    -- E_1 from the shape (round=1 entrants).
    SELECT entrants INTO v_e1
      FROM public._tournament_cons_shape(p_main_size, v_direct_cnt)
     WHERE round = 1;

    -- Place each seeded participant at its recursive-order slot (0-based).
    -- v_seeded is empty at start when direct_count = 0 and no R1 losers are
    -- pre-known (the common case): the trigger fills R1 later.
    IF array_length(v_seeded, 1) IS NOT NULL THEN
      FOR i IN 1 .. array_length(v_seeded, 1) LOOP
        v_slot0 := public._tournament_cons_seed_slot(i - 1, v_p1);
        v_slots[v_slot0 + 1] := v_seeded[i];
      END LOOP;
    END IF;

    -- Byes pad the slots whose seed index (0-based) >= E_1. Via the recursive
    -- order these high-index seeds face the top seeds (FR-FMT-11). Slots with
    -- seed index in [length(seeded) .. E_1-1] are the reserved (NULL, non-bye)
    -- main-R1-loser slots; slots with seed index >= E_1 are structural byes.
    FOR i IN 0 .. v_p1 - 1 LOOP
      IF i >= v_e1 THEN
        v_slot0 := public._tournament_cons_seed_slot(i, v_p1);
        v_is_bye[v_slot0 + 1] := true;
      END IF;
    END LOOP;
  END;

  -- ---- Emit R1 pairings. is_bye_pairing iff one slot is a structural bye.
  bp := 0;
  FOR i IN 1 .. (v_p1 / 2) LOOP
    bp := bp + 1;
    v_a     := v_slots[2 * i - 1];
    v_b     := v_slots[2 * i];
    v_a_bye := v_is_bye[2 * i - 1];
    v_b_bye := v_is_bye[2 * i];
    round_number     := 1;
    bracket_position := bp;
    participant_a    := v_a;
    participant_b    := v_b;
    phase            := 'consolation';
    is_bye_pairing   := (v_a_bye OR v_b_bye);
    RETURN NEXT;
  END LOOP;

  -- ---- Emit R2..consRounds placeholder pairings (count from the shape). ----
  FOR v_sh IN
    SELECT * FROM public._tournament_cons_shape(p_main_size, v_direct_cnt)
     WHERE round >= 2
     ORDER BY round
  LOOP
    FOR bp IN 1 .. v_sh.matches LOOP
      round_number     := v_sh.round;
      bracket_position := bp;
      participant_a    := NULL;
      participant_b    := NULL;
      phase            := 'consolation';
      is_bye_pairing   := false;
      RETURN NEXT;
    END LOOP;
  END LOOP;

  -- ---- Consolation 3rd-place playoff (own phase), only when consRounds >= 2.
  IF v_cons_rounds >= 2 THEN
    round_number     := 1;
    bracket_position := 1;
    participant_a    := NULL;
    participant_b    := NULL;
    phase            := 'consolation_third_place';
    is_bye_pairing   := false;
    RETURN NEXT;
  END IF;

  RETURN;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_compute_cons_bracket(int, jsonb, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_compute_cons_bracket(int, jsonb, jsonb) FROM authenticated;

COMMENT ON FUNCTION public._tournament_compute_cons_bracket(int, jsonb, jsonb) IS
  'Mirror of Dart Bracket.consolation (ADR-0028). Generates the consolation '
  'tree match rows (phase consolation / consolation_third_place) from the '
  'staggered-aware shape; direct starters seeded via recursive order, byes at '
  'top seeds, R2+ bare placeholders for the trigger. Main bracket NOT built here.';


-- ======================================================================
-- 7. tournament_start_ko_phase — latest body (20261202000000 §8, shoot-out
--    gate/resolve, per-tournament manage gate) re-stated VERBATIM, with two
--    clearly-marked additions:
--      * idempotency guard widened to the two consolation phases,
--      * CONSOLATION-MATERIALISE after the main single-elim INSERT, when
--        tournaments.consolation_bracket->>'enabled' = true (Model B detection;
--        NOT via bracket_type, which stays single_elimination).
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
  v_bracket_type      text;
  v_with_reset        boolean;
  v_round             smallint;   -- PITCH-PLAN loop variable
  v_name              text;       -- GO-LIVE-NOTIFY
  v_grp               record;     -- SHOOTOUT-GATE
  v_pending_shootouts int := 0;   -- SHOOTOUT-GATE
  v_full_order        uuid[];     -- SHOOTOUT-RESOLVE
  v_chain             text[];     -- SHOOTOUT-RESOLVE
  v_so                record;     -- SHOOTOUT-RESOLVE
  v_k                 int;        -- SHOOTOUT-RESOLVE
  -- CONSOLATION (E2):
  v_cons_cfg          jsonb;      -- tournaments.consolation_bracket
  v_cons_enabled      boolean;
  v_cons_main_size    int;
  v_cons_direct_cnt   int;
  v_cons_direct_ids   jsonb := '[]'::jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, bracket_type,
         coalesce((ko_config ->> 'with_bracket_reset')::boolean, true),
         display_name, consolation_bracket
    INTO v_creator, v_bracket_type, v_with_reset, v_name, v_cons_cfg
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id
  -- (20261201000032 §12 — the actual latest auth gate). Keeps the
  -- delegation capability intact; do NOT regress to created_by-only.
  IF v_creator IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
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

  -- CONSOLATION (E2) detection — via consolation_bracket->>'enabled', NOT
  -- bracket_type. Model B uses bracket_type='single_elimination'.
  v_cons_enabled := coalesce((v_cons_cfg ->> 'enabled')::boolean, false)
                    AND v_bracket_type <> 'double_elimination';

  -- Idempotency guard widened to the consolation phases (DOD-12).
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
  -- SHOOTOUT-GATE (P6 D2a, docs/P6_SHOOTOUT_TIEBREAK.md). VERBATIM.
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

  -- ==================================================================
  -- SHOOTOUT-RESOLVE (resolveWithShootouts). VERBATIM.
  -- ==================================================================
  IF NOT v_has_pool_phase AND EXISTS (
    SELECT 1 FROM public.tournament_shootouts
     WHERE tournament_id = p_tournament_id AND status = 'resolved'
  ) THEN
    SELECT tiebreaker_order INTO v_chain
      FROM public.tournaments WHERE id = p_tournament_id;

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
      FROM public._tournament_compute_ko_bracket(v_seeds_jsonb, v_with_third_place) b;
  END IF;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  -- ==================================================================
  -- CONSOLATION-MATERIALISE (E2, ADR-0028 §1.1/§3/§4). Runs ONLY when the
  -- consolation bracket is enabled and the main bracket is single-elim. The
  -- main single-elim INSERT above is left BIT-IDENTICAL (no extra slots, no
  -- changed seed order, no main byes). mainSize for the shape is the padded
  -- power-of-two of the seed count handed to the main helper — i.e. the size
  -- of the just-materialised main bracket. direct_count is read defensively
  -- from consolation_bracket->>'direct_count' (absent in the current wire =>
  -- 0; see the file-header DOD-09 note). Direct starters would be seeded from
  -- the prelim ranking that did NOT enter the main bracket; with direct_count
  -- defaulting to 0 there are none, so R1 is seeded entirely by the staggered
  -- main-R1 losers the trigger fills. The bye rows (if any) are inserted as
  -- finalized with their real participant as winner (auto-advance, §4).
  -- ==================================================================
  IF v_cons_enabled THEN
    -- mainSize = next_pow2(qualifier_count) == size of the main bracket.
    v_cons_main_size := 1;
    WHILE v_cons_main_size < v_qualifier_count LOOP
      v_cons_main_size := v_cons_main_size * 2;
    END LOOP;

    -- direct_count (defensive read; not in the current wire => 0).
    v_cons_direct_cnt := coalesce((v_cons_cfg ->> 'direct_count')::int, 0);
    -- Direct starters are not persisted in the current wire; with direct_count
    -- = 0 the list is empty. (When a future wire carries them, they would be
    -- the top prelim ranks not in the main bracket; left empty here for parity
    -- with the current persisted config.)
    v_cons_direct_ids := '[]'::jsonb;

    -- Bye pairings are inserted NOT-yet-finalized (status 'awaiting_results',
    -- winner_participant already set) and then promoted to 'finalized' by a
    -- follow-up UPDATE below, so the AFTER-UPDATE advance trigger FIRES and the
    -- bye winner is pushed into the next consolation round (ADR-0028 §4 / DOD-05
    -- "beim Start sofort finalisiert (Auto-Advance)"). Inserting them directly as
    -- 'finalized' would NOT fire the AFTER-UPDATE trigger (no OLD->NEW status
    -- transition), leaving the bye winner stranded. Non-bye rows stay 'scheduled'.
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

    -- Promote the consolation bye rows to 'finalized'. This UPDATE crosses the
    -- 'awaiting_results' -> 'finalized' boundary, so the advance trigger fires
    -- once per bye row and auto-advances the bye winner (kampflos) into the next
    -- consolation round. Ordered by round_number so an early-round bye winner is
    -- in place before any later-round dependency would read it.
    UPDATE public.tournament_matches
      SET status = 'finalized',
          finalized_at = now()
      WHERE tournament_id = p_tournament_id
        AND phase = 'consolation'
        AND winner_participant IS NOT NULL
        AND status = 'awaiting_results';

    -- Recompute the total match count to include the consolation rows.
    SELECT count(*) INTO v_match_count
      FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND phase IN ('ko','third_place','final',
                      'consolation','consolation_third_place');
  END IF;

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

  -- GO-LIVE-NOTIFY: KO bracket published — new round for everyone.
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
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start_ko_phase(uuid, jsonb)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_start_ko_phase(uuid, jsonb) IS
  'KO-Start (latest body 20261202000000: shoot-out gate/resolve + per-tournament '
  'manage gate) re-stated verbatim + E2 CONSOLATION-MATERIALISE: wenn '
  'consolation_bracket->>enabled = true (Modell B, bracket_type bleibt '
  'single_elimination) wird parallel zum unveraenderten Single-Elim-Hauptbaum der '
  'Trostturnier-Baum (phase consolation / consolation_third_place) ueber '
  '_tournament_compute_cons_bracket materialisiert (ADR-0028). Idempotency-Guard '
  'inkl. consolation-Phasen.';


-- ======================================================================
-- 8. tournament_advance_ko_winner — latest body (20261101000002 §5,
--    single- + double-elim) re-stated VERBATIM + a CONSOLATION-ROUTING block.
--    Single-elim ('ko'/'third_place'/'final') and double-elim ('wb'/'lb'/
--    'grand_final'/'grand_final_reset') branches are byte-for-byte the existing
--    behaviour. Added (ADR-0028 §7.4):
--      (A) MAIN-LOSER FEED: on finalising a main 'ko'/'final' match of round r,
--          route the loser via _tournament_cons_drop_target(r, mainSize):
--            r==1  -> consolation R1 seeded slot (via _tournament_cons_seed_slot,
--                     reserved B/A slot of the R1 loser),
--            2<=r<=mainRounds-2 -> consolation round r, B-slot reflected via
--                     _tournament_cons_drop_slot,
--            r==mainRounds-1 (semifinal) -> sentinel -1: NO consolation feed
--                     (the existing third_place logic above already handled it),
--            r==mainRounds (final) / sentinel 0 -> no drop.
--          Only runs when a consolation tree exists for this tournament.
--      (B) CONSOLATION-INTERNAL: on finalising a 'consolation' match, advance the
--          winner to round+1 (ceil(bp/2); odd->A, even->B); the two consolation
--          semifinal (round consRounds-1) losers are mirrored into the
--          consolation_third_place match (own phase). consRounds = max(round_number
--          over phase='consolation'). recursion-safe (only sets participant_a/b +
--          status), walkover/forfeit-compatible (reads winner_participant only).
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
  v_wb_count        int;
  v_size            int;
  v_lb_count        int;
  v_lb_target_round int;
  v_lb_slot0        int;
  v_lb_target_pos   int;
  v_lb_side_b       boolean;
  v_with_reset      boolean;
  v_gf_round        int;
  -- CONSOLATION (E2) locals:
  v_cons_exists     int;
  v_main_rounds     int;
  v_main_size       int;
  v_cons_target     int;       -- _tournament_cons_drop_target result
  v_cons_matches    int;       -- pairings in target consolation round
  v_cons_slot0      int;       -- 0-based slot
  v_cons_pos        int;       -- 1-based pairing
  v_cons_side_b     boolean;
  v_cons_rounds     int;       -- max consolation round_number
  v_cons_p1         int;       -- P_1 (R1 padded size)
  v_e1              int;       -- E_1 entrants
BEGIN
  IF NEW.winner_participant IS NULL THEN
    RETURN NEW;
  END IF;

  v_loser_part := CASE
    WHEN NEW.winner_participant = NEW.participant_a THEN NEW.participant_b
    WHEN NEW.winner_participant = NEW.participant_b THEN NEW.participant_a
    ELSE NULL
  END;

  v_next_round    := NEW.round_number + 1;
  v_next_position := (NEW.bracket_position + 1) / 2;  -- ceil(x/2) for x>=1
  v_is_odd        := (NEW.bracket_position % 2) = 1;

  -- =====================================================================
  -- SINGLE-ELIMINATION PATH (verbatim from 20260601000016 / 20261101000002).
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
  -- DOUBLE-ELIMINATION PATH (verbatim from 20261101000002 §5).
  -- =====================================================================
  IF NEW.phase IN ('wb','lb','grand_final','grand_final_reset') THEN
    SELECT MAX(round_number) INTO v_wb_count
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND phase = 'wb';
    v_size := (1 << v_wb_count);
    v_lb_count := 2 * (v_wb_count - 1);
  END IF;

  IF NEW.phase = 'wb' THEN
    IF NEW.round_number < v_wb_count THEN
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

    IF v_loser_part IS NOT NULL AND v_lb_count > 0 THEN
      IF NEW.round_number = 1 THEN
        v_lb_target_round := 1;
        v_lb_target_pos   := ((v_size >> 2) - 1) - ((NEW.bracket_position - 1) / 2) + 1;
        v_lb_side_b       := ((NEW.bracket_position - 1) % 2) = 1;
      ELSE
        v_lb_target_round := 2 * NEW.round_number - 2;
        v_lb_slot0        := public._tournament_de_lb_target(
                               NEW.round_number, NEW.bracket_position, v_size);
        v_lb_target_pos   := (v_lb_slot0 / 2) + 1;
        v_lb_side_b       := (v_lb_slot0 % 2) = 1;
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

  IF NEW.phase = 'lb' THEN
    IF NEW.round_number < v_lb_count THEN
      IF (NEW.round_number % 2) = 1 THEN
        v_lb_target_round := NEW.round_number + 1;
        v_lb_target_pos   := NEW.bracket_position;
        v_lb_side_b       := false;
      ELSE
        v_lb_target_round := NEW.round_number + 1;
        v_lb_target_pos   := (NEW.bracket_position + 1) / 2;
        v_lb_side_b       := (NEW.bracket_position % 2) = 0;
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

  IF NEW.phase = 'grand_final' THEN
    SELECT coalesce((t.ko_config ->> 'with_bracket_reset')::boolean, true)
      INTO v_with_reset
      FROM public.tournaments t
      WHERE t.id = NEW.tournament_id;

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
          SET participant_a = NEW.participant_a,
              participant_b = NEW.participant_b,
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'grand_final_reset'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;
  END IF;

  -- =====================================================================
  -- CONSOLATION ROUTING (E2, ADR-0028 §7.4).
  -- =====================================================================

  -- (A) MAIN-LOSER FEED. A main 'ko'/'final' loser may drop into the
  -- consolation tree. Only act when a consolation tree exists.
  IF NEW.phase IN ('ko','final') AND v_loser_part IS NOT NULL THEN
    SELECT count(*) INTO v_cons_exists
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND phase = 'consolation';

    IF v_cons_exists > 0 THEN
      -- mainSize = 2 ^ max(round_number over phase IN ('ko','final')).
      SELECT MAX(round_number) INTO v_main_rounds
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase IN ('ko','final');
      v_main_size := (1 << v_main_rounds);

      v_cons_target := public._tournament_cons_drop_target(
                         NEW.round_number, v_main_size);

      -- Sentinels: 0 (final/no feed) and -1 (semifinal -> third_place, already
      -- handled above) => no consolation drop.
      IF v_cons_target >= 1 THEN
        IF v_cons_target = 1 THEN
          -- R1 loser: seeded into the consolation-R1 slot reserved for the
          -- j-th seeded entry, j = directCount + (mainPosition-1) (§3.3 step 2:
          -- direct starters first, then the main-R1 losers by main seed). The
          -- main-R1 pairings are in seed order, so the loser of main pairing p
          -- is the p-th R1 loser => seeded index directCount + (p-1).
          -- directCount = E_1 - L_1, with L_1 = #main-R1 matches (mainSize/2)
          -- and E_1 = #consolation-R1 entrant slots = P_1 - #R1 byes. With the
          -- current persisted wire direct_count is 0 (see file header DOD-09),
          -- so directCount = 0 and j = p-1. We derive directCount generically
          -- from the shape to stay correct should a future wire carry it.
          -- P_1 = #consolation-R1 pairings * 2.
          SELECT count(*) * 2 INTO v_cons_p1
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = 1;
          -- E_1 from the shape (entrants of round 1); directCount = E_1 - L_1.
          SELECT entrants INTO v_e1
            FROM public._tournament_cons_shape(
                   v_main_size,
                   greatest(0,
                     coalesce((SELECT (consolation_bracket ->> 'direct_count')::int
                                 FROM public.tournaments
                                WHERE id = NEW.tournament_id), 0)))
           WHERE round = 1;
          -- j = directCount + (p-1) = (E_1 - L_1) + (p-1) = (E_1 - mainSize/2) + (p-1).
          v_cons_slot0 := public._tournament_cons_seed_slot(
                            (v_e1 - (v_main_size / 2)) + (NEW.bracket_position - 1),
                            v_cons_p1);
          v_cons_pos    := (v_cons_slot0 / 2) + 1;
          v_cons_side_b := (v_cons_slot0 % 2) = 1;

          SELECT participant_a, participant_b, status
            INTO v_next_a, v_next_b, v_next_status
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = 1
              AND bracket_position = v_cons_pos
            FOR UPDATE;
          IF FOUND THEN
            IF v_cons_side_b THEN v_next_b := v_loser_part;
            ELSE                  v_next_a := v_loser_part; END IF;
            IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
               AND v_next_status = 'scheduled' THEN
              v_next_status := 'awaiting_results';
            END IF;
            UPDATE public.tournament_matches
              SET participant_a = v_next_a,
                  participant_b = v_next_b,
                  status        = v_next_status
              WHERE tournament_id = NEW.tournament_id
                AND phase = 'consolation'
                AND round_number = 1
                AND bracket_position = v_cons_pos;
          END IF;
        ELSE
          -- r >= 2 staggered loser: B-slot of target consolation round, the
          -- A-slot is reserved for the consolation survivor of round r-1.
          SELECT count(*) INTO v_cons_matches
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = v_cons_target;
          v_cons_slot0 := public._tournament_cons_drop_slot(
                            NEW.bracket_position, v_cons_matches);
          v_cons_pos    := (v_cons_slot0 / 2) + 1;
          v_cons_side_b := (v_cons_slot0 % 2) = 1;

          SELECT participant_a, participant_b, status
            INTO v_next_a, v_next_b, v_next_status
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = v_cons_target
              AND bracket_position = v_cons_pos
            FOR UPDATE;
          IF FOUND THEN
            IF v_cons_side_b THEN v_next_b := v_loser_part;
            ELSE                  v_next_a := v_loser_part; END IF;
            IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
               AND v_next_status = 'scheduled' THEN
              v_next_status := 'awaiting_results';
            END IF;
            UPDATE public.tournament_matches
              SET participant_a = v_next_a,
                  participant_b = v_next_b,
                  status        = v_next_status
              WHERE tournament_id = NEW.tournament_id
                AND phase = 'consolation'
                AND round_number = v_cons_target
                AND bracket_position = v_cons_pos;
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

  -- (B) CONSOLATION-INTERNAL progression + consolation 3rd-place mirror.
  IF NEW.phase = 'consolation' THEN
    SELECT MAX(round_number) INTO v_cons_rounds
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND phase = 'consolation';

    -- Winner advances to the next consolation round (unless this is the final).
    -- STAGGER-AWARE (ADR-0028 §3.3 / consolation_test.dart:194): the next round
    -- may receive a FRESH main-loser feed (L_{r+1} > 0). In that case the round
    -- is a major round whose A-slots hold the prior-round survivors 1:1 (A-slot,
    -- bracket_position = NEW.bracket_position) and whose B-slots are reserved for
    -- the freshly-fed main-round-(r+1) losers (filled by branch (A) via
    -- _tournament_cons_drop_slot). A naive halving (ceil(bp/2), odd->A/even->B)
    -- would collapse N survivors into N/2 matches and DESTROY half of them on a
    -- staggered round (e.g. 16er cons-R1 -> cons-R2: 4 survivors must occupy all
    -- 4 A-slots, NOT 2 matches). A fresh feed exists for round r+1 iff
    -- _tournament_cons_drop_target(r+1, mainSize) >= 1 (equivalently L_{r+1} > 0):
    -- that round is a 1:1 feeding (= "major") round. Otherwise (no fresh feed,
    -- L_{next}=0, e.g. the consolation semifinal/final) the classic halving maps
    -- survivors into half as many matches, exactly like a plain single-elim.
    IF NEW.round_number < v_cons_rounds THEN
      -- mainSize = 2 ^ max(round_number over phase IN ('ko','final')).
      SELECT MAX(round_number) INTO v_main_rounds
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase IN ('ko','final');
      v_main_size := (1 << v_main_rounds);

      IF public._tournament_cons_drop_target(v_next_round, v_main_size) >= 1 THEN
        -- MAJOR (fresh-feed) round: survivor maps 1:1 into the A-slot of the same
        -- bracket_position; the B-slot stays reserved for the staggered loser.
        v_next_position := NEW.bracket_position;
        v_is_odd        := true;  -- A-slot
      END IF;
      -- else: keep the halving values (v_next_position = ceil(bp/2),
      --       v_is_odd = (bp odd)) computed at the top of the function.

      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'consolation'
          AND round_number = v_next_round
          AND bracket_position = v_next_position
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
            AND phase = 'consolation'
            AND round_number = v_next_round
            AND bracket_position = v_next_position;
      END IF;
    END IF;

    -- Consolation semifinal (round consRounds-1) losers -> consolation_third_place.
    -- The semifinal feeds the consolation final (round consRounds); its two
    -- losers play for places 7/8 under the OWN phase (no third_place collision).
    IF v_loser_part IS NOT NULL
       AND v_cons_rounds >= 2
       AND NEW.round_number = v_cons_rounds - 1 THEN
      SELECT participant_a, participant_b, status
        INTO v_tp_a, v_tp_b, v_tp_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'consolation_third_place'
          AND round_number = 1
          AND bracket_position = 1
        FOR UPDATE;
      IF FOUND THEN
        -- Use the consolation semifinal's OWN bracket_position parity (not the
        -- possibly-mutated v_is_odd from the progression block above): the two
        -- semifinal pairings (bp 1/2) seed the 7/8 playoff A/B by pairing index.
        IF (NEW.bracket_position % 2) = 1 THEN
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
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'consolation_third_place'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- WHEN-Clause widened to the two consolation phases (in addition to the single-
-- and double-elim ones). All other trigger attributes unchanged.
DROP TRIGGER IF EXISTS tournament_advance_ko_winner ON public.tournament_matches;
CREATE TRIGGER tournament_advance_ko_winner
  AFTER UPDATE ON public.tournament_matches
  FOR EACH ROW
  WHEN (
    OLD.status NOT IN ('finalized','overridden')
    AND NEW.status     IN ('finalized','overridden')
    AND NEW.phase      IN ('ko','third_place','final',
                           'wb','lb','grand_final','grand_final_reset',
                           'consolation','consolation_third_place')
  )
  EXECUTE FUNCTION public.tournament_advance_ko_winner();

COMMENT ON FUNCTION public.tournament_advance_ko_winner() IS
  'AFTER-UPDATE-Trigger (ADR-0017 §5, ADR-0027 §3.3, ADR-0028 §7.4). Single-elim '
  'und Double-elim Zweige verbatim. Consolation (E2): Hauptbaum-ko/final-Verlierer '
  'der Runde r -> _tournament_cons_drop_target(r) (r==1 Seeding-Slot, 2..mainRounds-2 '
  'B-Slot via _tournament_cons_drop_slot, HF -1 -> third_place unveraendert, Final 0 '
  'kein Drop); consolation-intern Sieger->Folge-Runde, consRounds-1-Verlierer -> '
  'consolation_third_place (eigene Phase). Walkover/Forfeit-kompatibel, recursion-sicher.';
