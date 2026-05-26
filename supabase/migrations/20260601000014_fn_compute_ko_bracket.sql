-- Tournament feature — M2 KO-bracket helper function.
--
-- `_tournament_compute_ko_bracket(seeds, third_place)` spiegelt den
-- Recursive-Standard-Seeding-Algorithmus aus
-- `packages/kubb_domain/lib/src/tournament/bracket.dart`
-- (`Bracket.singleElimination` + `_standardBracketOrder`) 1:1 in
-- plpgsql nach. Wird von `tournament_start_ko_phase` (T3b) konsumiert
-- und durch Property-Paritäts-Tests (T5) gegen die Dart-Domain
-- abgesichert. Wiederverwendbar fuer M5 Schweizer System.
--
-- Bezug: ADR-0017 §7, docs/plans/m2-ko-bracket/architecture.md §3.2.
--
-- Input:
--   p_seeds       jsonb  — Array von uuid-Strings, Index 0 = top seed.
--                          Laenge n in [2, 64].
--   p_third_place bool   — true → zusaetzliche Third-Place-Match-Row.
--
-- Output-Row pro Match-Slot:
--   round_number      int   — 1-based; Final-Runde = log2(size).
--   bracket_position  int   — 1-based Slot innerhalb der Runde.
--                              Konvention: Third-Place-Match nutzt
--                              `bracket_position = 1`. Phase-Spalte
--                              disambiguiert gegen die Final-Row.
--   participant_a     uuid  — Teilnehmer A (oder NULL bei BYE / Placeholder).
--   participant_b     uuid  — Teilnehmer B (oder NULL bei BYE / Placeholder).
--   phase             text  — 'ko' | 'final' | 'third_place'.
--   is_bye_pairing    bool  — true falls einer der beiden Slots BYE ist
--                              (R1 only). Impliziert dass der reale
--                              Teilnehmer ohne Match in R2 advanced —
--                              das schreibt aber T3b/T4, nicht dieser
--                              Helper.
--
-- Determinismus: Rows werden via `RETURN NEXT` in der konstruierten
-- Reihenfolge emittiert (R1 bottom-up nach bracket_position, dann R2,
-- ..., dann Final, dann optional Third-Place). Zweimal aufgerufen →
-- identische Row-Reihenfolge garantiert.

CREATE OR REPLACE FUNCTION public._tournament_compute_ko_bracket(
  p_seeds       jsonb,
  p_third_place boolean
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
  bp := 0;
  FOR i IN 1 .. (v_size / 2) LOOP
    bp := bp + 1;
    v_a := v_slots[v_order[2 * i - 1]];
    v_b := v_slots[v_order[2 * i]];
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

REVOKE EXECUTE ON FUNCTION public._tournament_compute_ko_bracket(jsonb, boolean) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_compute_ko_bracket(jsonb, boolean) FROM authenticated;

COMMENT ON FUNCTION public._tournament_compute_ko_bracket(jsonb, boolean) IS
  'Mirror of Dart Bracket.singleElimination (kubb_domain). Generates '
  'KO-match rows from a seed-ordered participant list. Consumed by '
  'tournament_start_ko_phase (M2.2-T3b). Property-parity asserted '
  'against the Dart impl in M2.2-T5. See ADR-0017 §7.';
