-- A KO match format must carry an odd max_sets (20261339000000).
--
-- Even N can end level, and a KO bracket has no draw to award. The solo-match
-- path has enforced this since 20260507000007; this is the tournament-side
-- equivalent, as a table CHECK so it holds whichever RPC writes the row.
--
-- The prelim is deliberately out of scope: a draw is a legitimate group/Schoch
-- result (K14) and pays a point (ADR-0024 §2), so match_format may stay even.
--
-- pgTAP is installed transiently inside the BEGIN..ROLLBACK; nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(8);

-- ---- the helper on its own ----
SELECT ok(public._tournament_ko_sets_all_odd('{"max_sets": 3}'::jsonb, '[]'::jsonb),
  'a best-of-three KO format passes');

SELECT ok(NOT public._tournament_ko_sets_all_odd('{"max_sets": 4}'::jsonb, '[]'::jsonb),
  'a best-of-four KO format is rejected');

SELECT ok(public._tournament_ko_sets_all_odd(NULL, NULL),
  'no KO format configured is fine');

SELECT ok(public._tournament_ko_sets_all_odd(
    NULL, '[{"max_sets": 5}, {"max_sets": 3}]'::jsonb),
  'per-round overrides pass when every one of them is odd');

SELECT ok(NOT public._tournament_ko_sets_all_odd(
    NULL, '[{"max_sets": 5}, {"max_sets": 2}]'::jsonb),
  'a single even per-round override fails the whole set');

-- ---- the constraint on the table ----
SELECT has_check('public', 'tournaments', 'tournaments carries a check constraint');

SELECT ok(
  EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.tournaments'::regclass
       AND conname  = 'tournaments_ko_max_sets_odd'
  ),
  'the KO odd-sets constraint is installed');

-- The prelim column is not covered by the constraint, on purpose: the check
-- reads ko_match_format and ko_round_formats and nothing else, so an even
-- match_format keeps passing.
SELECT is(
  (SELECT pg_get_constraintdef(oid) FROM pg_constraint
    WHERE conrelid = 'public.tournaments'::regclass
      AND conname  = 'tournaments_ko_max_sets_odd'),
  'CHECK (_tournament_ko_sets_all_odd(ko_match_format, ko_round_formats)) NOT VALID',
  'the constraint reads only the KO columns, never the prelim match_format');

SELECT * FROM finish();
ROLLBACK;
