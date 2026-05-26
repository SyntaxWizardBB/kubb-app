-- Property-Paritaet-Test: Dart `Bracket.singleElimination` ↔ plpgsql
-- `_tournament_compute_ko_bracket`. Merge-Gate fuer ADR-0017 §7.
--
-- Strategie: Inline-Snapshots + Invarianten-Sweep.
--   - Inline-Snapshot fuer n=5 (BYE-Mix) und n=8 (no-BYE) verifiziert
--     die exakten Pairings 1:1 gegen die Dart-Referenz, die aus
--     `packages/kubb_domain/lib/src/tournament/bracket.dart`
--     (`_standardBracketOrder`) deterministisch ableitbar ist.
--   - Invarianten-Sweep ueber n ∈ {2, 4, 5, 8, 16, 32, 64} ×
--     third_place ∈ {true, false} sichert structure properties:
--     1) Total row count = (bracket_size - 1) + (third_place ? 1 : 0).
--     2) R1 hat genau bracket_size / 2 Pairings.
--     3) BYE-Count in R1 = bracket_size - n; nur in R1.
--     4) BYE-Allokation: in jedem R1-BYE-Pair ist der nicht-NULL-Slot
--        eine Top-Seed (Seed-Index in [1, n]); FR-FMT-11 / ADR-0017 §3.
--     5) third_place-Row existiert genau dann, wenn p_third_place=true,
--        mit phase='third_place' und round_number=log2(size).
--
-- Test-Seeds: `00000000-0000-0000-0000-NNNNNNNNNNNN` (N = seed_index,
-- 1-based, zero-padded auf 12 Stellen). Damit ist Slot↔Seed reversibel
-- — eine UUID laesst sich per `to_number(right(uuid::text, 12), ...)`
-- zurueck in den Seed-Index mappen, was die BYE-Allokations-Pruefung
-- (welche Seed bekommt den BYE) ermoeglicht.

BEGIN;

SELECT plan(49);

-- ---------------------------------------------------------------------
-- Helper: Konstruiere `p_seeds`-Array fuer gegebenes n als jsonb.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _test_seeds(p_n int)
RETURNS jsonb
LANGUAGE sql
AS $$
  SELECT jsonb_agg(format('00000000-0000-0000-0000-%s', lpad(i::text, 12, '0')))
    FROM generate_series(1, p_n) AS i;
$$;

-- ---------------------------------------------------------------------
-- Helper: Map UUID → seed_index (NULL → NULL).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _test_seed_of(p_uuid uuid)
RETURNS int
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN p_uuid IS NULL THEN NULL
              ELSE to_number(right(p_uuid::text, 12), '999999999999')::int
         END;
$$;

-- ---------------------------------------------------------------------
-- Inline-Snapshot 1: n=8, third_place=true. Exakte Pairings.
-- ---------------------------------------------------------------------
SELECT results_eq(
  $$
    SELECT round_number, bracket_position,
           _test_seed_of(participant_a), _test_seed_of(participant_b),
           phase, is_bye_pairing
      FROM public._tournament_compute_ko_bracket(_test_seeds(8), true)
  $$,
  $$
    VALUES
      (1, 1, 1,    8,    'ko',          false),
      (1, 2, 5,    4,    'ko',          false),
      (1, 3, 3,    6,    'ko',          false),
      (1, 4, 7,    2,    'ko',          false),
      (2, 1, NULL::int, NULL::int, 'ko',          false),
      (2, 2, NULL::int, NULL::int, 'ko',          false),
      (3, 1, NULL::int, NULL::int, 'final',       false),
      (3, 1, NULL::int, NULL::int, 'third_place', false)
  $$,
  'n=8, third_place=true → exakte Dart-Paritaet (rounds + pairings + phase)'
);

-- ---------------------------------------------------------------------
-- Inline-Snapshot 2: n=5, third_place=false. BYE-Mix.
-- ---------------------------------------------------------------------
SELECT results_eq(
  $$
    SELECT round_number, bracket_position,
           _test_seed_of(participant_a), _test_seed_of(participant_b),
           phase, is_bye_pairing
      FROM public._tournament_compute_ko_bracket(_test_seeds(5), false)
  $$,
  $$
    VALUES
      (1, 1, 1,    NULL::int, 'ko',    true),
      (1, 2, 5,    4,         'ko',    false),
      (1, 3, 3,    NULL::int, 'ko',    true),
      (1, 4, NULL::int, 2,    'ko',    true),
      (2, 1, NULL::int, NULL::int, 'ko',    false),
      (2, 2, NULL::int, NULL::int, 'ko',    false),
      (3, 1, NULL::int, NULL::int, 'final', false)
  $$,
  'n=5, third_place=false → exakte Dart-Paritaet inkl. BYE-Slots'
);

-- ---------------------------------------------------------------------
-- Inline-Snapshot 3: n=2 → R1 ist gleichzeitig Finale (phase='final').
-- ---------------------------------------------------------------------
SELECT results_eq(
  $$
    SELECT round_number, bracket_position,
           _test_seed_of(participant_a), _test_seed_of(participant_b),
           phase, is_bye_pairing
      FROM public._tournament_compute_ko_bracket(_test_seeds(2), true)
  $$,
  $$
    VALUES
      (1, 1, 1, 2,                 'final',       false),
      (1, 1, NULL::int, NULL::int, 'third_place', false)
  $$,
  'n=2, third_place=true → R1 als Finale + Third-Place-Row'
);

-- ---------------------------------------------------------------------
-- Invarianten-Sweep ueber n × third_place.
-- Pro Case: 4 Invarianten-Checks (row count, R1 size, BYE count,
-- third_place presence). BYE-Allokations-Check separat pro n mit BYEs.
-- ---------------------------------------------------------------------

-- n=2, tp=false
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(2), false)),
  1, 'n=2/tp=false: total rows = bracket_size-1');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(2), false) WHERE round_number = 1),
  1, 'n=2/tp=false: R1 pairings = size/2');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(2), false) WHERE is_bye_pairing),
  0, 'n=2/tp=false: BYE count = size - n');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(2), false) WHERE phase = 'third_place'),
  0, 'n=2/tp=false: kein Third-Place-Row');

-- n=2, tp=true
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(2), true)),
  2, 'n=2/tp=true: total rows = bracket_size-1+1');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(2), true) WHERE phase = 'third_place' AND round_number = 1),
  1, 'n=2/tp=true: Third-Place-Row in round=log2(2)=1');

-- n=4, tp=false
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(4), false)),
  3, 'n=4/tp=false: total rows');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(4), false) WHERE round_number = 1),
  2, 'n=4/tp=false: R1 pairings');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(4), false) WHERE is_bye_pairing),
  0, 'n=4/tp=false: keine BYEs');

-- n=4, tp=true
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(4), true)),
  4, 'n=4/tp=true: total rows inkl. third_place');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(4), true) WHERE phase = 'third_place' AND round_number = 2),
  1, 'n=4/tp=true: Third-Place-Row in round=log2(4)=2');

-- n=5, tp=false
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(5), false)),
  7, 'n=5/tp=false: total rows = 7');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(5), false) WHERE round_number = 1),
  4, 'n=5/tp=false: R1 pairings = 4');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(5), false) WHERE is_bye_pairing AND round_number = 1),
  3, 'n=5/tp=false: BYE-Count = size(8) - n(5) = 3');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(5), false) WHERE is_bye_pairing AND round_number > 1),
  0, 'n=5/tp=false: BYEs nur in R1');
-- FR-FMT-11: BYE geht an Top-Seeds (Index in [1..n]).
SELECT is(
  (SELECT bool_and(
            (_test_seed_of(participant_a) BETWEEN 1 AND 5
             AND participant_b IS NULL)
            OR
            (_test_seed_of(participant_b) BETWEEN 1 AND 5
             AND participant_a IS NULL))
     FROM public._tournament_compute_ko_bracket(_test_seeds(5), false)
    WHERE is_bye_pairing),
  true, 'n=5: BYE-Allokation an Top-Seeds (FR-FMT-11)');

-- n=8, tp=false
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(8), false)),
  7, 'n=8/tp=false: total rows = 7');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(8), false) WHERE round_number = 1),
  4, 'n=8/tp=false: R1 pairings = 4');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(8), false) WHERE is_bye_pairing),
  0, 'n=8/tp=false: keine BYEs');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(8), false) WHERE phase = 'final'),
  1, 'n=8/tp=false: genau eine Final-Row');

-- n=8, tp=true (full snapshot oben — hier nur die Counts)
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(8), true)),
  8, 'n=8/tp=true: total rows = 8');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(8), true) WHERE phase = 'third_place' AND round_number = 3),
  1, 'n=8/tp=true: Third-Place-Row in round=log2(8)=3');

-- n=16, tp=false (volle Besetzung, keine BYEs)
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(16), false)),
  15, 'n=16/tp=false: total rows = 15');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(16), false) WHERE round_number = 1),
  8, 'n=16/tp=false: R1 pairings = 8');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(16), false) WHERE is_bye_pairing),
  0, 'n=16/tp=false: keine BYEs');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(16), false) WHERE phase = 'final'),
  1, 'n=16/tp=false: genau eine Final-Row');

-- n=16, tp=true
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(16), true)),
  16, 'n=16/tp=true: total rows inkl. third_place');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(16), true) WHERE phase = 'third_place' AND round_number = 4),
  1, 'n=16/tp=true: Third-Place-Row in round=log2(16)=4');

-- n=32, tp=false
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(32), false)),
  31, 'n=32/tp=false: total rows = 31');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(32), false) WHERE round_number = 1),
  16, 'n=32/tp=false: R1 pairings = 16');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(32), false) WHERE is_bye_pairing),
  0, 'n=32/tp=false: keine BYEs');

-- n=32, tp=true
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(32), true)),
  32, 'n=32/tp=true: total rows');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(32), true) WHERE phase = 'third_place' AND round_number = 5),
  1, 'n=32/tp=true: Third-Place-Row in round=log2(32)=5');

-- n=64, tp=false
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(64), false)),
  63, 'n=64/tp=false: total rows = 63');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(64), false) WHERE round_number = 1),
  32, 'n=64/tp=false: R1 pairings = 32');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(64), false) WHERE is_bye_pairing),
  0, 'n=64/tp=false: keine BYEs (volle Besetzung)');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(64), false) WHERE phase = 'final'),
  1, 'n=64/tp=false: genau eine Final-Row');

-- n=64, tp=true
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(64), true)),
  64, 'n=64/tp=true: total rows = 64');
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(64), true) WHERE phase = 'third_place' AND round_number = 6),
  1, 'n=64/tp=true: Third-Place-Row in round=log2(64)=6');

-- ---------------------------------------------------------------------
-- Zusaetzlicher BYE-Allokations-Sweep: n=33 (size=64, 31 BYEs).
-- FR-FMT-11: BYE wird Top-Seeds zugeteilt, niemals dem schwaechsten
-- Seed-Bereich (n+1..size existieren ja gar nicht — semantisch BYE
-- als "fehlender Gegner" steht beim Top-Seed). Pruefung: in jedem
-- BYE-Pair ist der nicht-NULL-Slot eine Seed in [1, n].
-- ---------------------------------------------------------------------
SELECT is(
  (SELECT count(*)::int FROM public._tournament_compute_ko_bracket(_test_seeds(33), false) WHERE is_bye_pairing),
  31, 'n=33: BYE-Count = size(64) - n(33) = 31');
SELECT is(
  (SELECT bool_and(
            (_test_seed_of(participant_a) BETWEEN 1 AND 33
             AND participant_b IS NULL)
            OR
            (_test_seed_of(participant_b) BETWEEN 1 AND 33
             AND participant_a IS NULL))
     FROM public._tournament_compute_ko_bracket(_test_seeds(33), false)
    WHERE is_bye_pairing),
  true, 'n=33: BYE-Allokation an Top-Seeds (FR-FMT-11)');
-- Zusaetzlich: die top-1 seed bekommt definitiv einen BYE bei size>>n.
SELECT is(
  (SELECT count(*)::int
     FROM public._tournament_compute_ko_bracket(_test_seeds(33), false)
    WHERE is_bye_pairing
      AND (_test_seed_of(participant_a) = 1 OR _test_seed_of(participant_b) = 1)),
  1, 'n=33: Top-Seed 1 hat genau einen BYE');

-- ---------------------------------------------------------------------
-- Determinismus: zweimal aufrufen → identische Row-Reihenfolge.
-- ---------------------------------------------------------------------
SELECT results_eq(
  $$
    SELECT round_number, bracket_position, participant_a, participant_b, phase, is_bye_pairing
      FROM public._tournament_compute_ko_bracket(_test_seeds(16), true)
  $$,
  $$
    SELECT round_number, bracket_position, participant_a, participant_b, phase, is_bye_pairing
      FROM public._tournament_compute_ko_bracket(_test_seeds(16), true)
  $$,
  'Determinismus: zweimaliger Aufruf liefert identische Row-Sequenz'
);

-- ---------------------------------------------------------------------
-- Eingabe-Validierung (Defense-in-Depth, ergaenzt T3a-RPC-Layer).
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT * FROM public._tournament_compute_ko_bracket(_test_seeds(1), false) $$,
  '22023', NULL,
  'n=1: function lehnt mit ERRCODE 22023 ab');

SELECT throws_ok(
  $$ SELECT * FROM public._tournament_compute_ko_bracket(_test_seeds(65), false) $$,
  '22023', NULL,
  'n=65: function lehnt mit ERRCODE 22023 ab');

SELECT throws_ok(
  $$ SELECT * FROM public._tournament_compute_ko_bracket('"not-an-array"'::jsonb, false) $$,
  '22023', NULL,
  'p_seeds kein Array → ERRCODE 22023');

SELECT * FROM finish();

ROLLBACK;
