-- Tournament feature — P6 Double-Elimination phase-enum extension (ADR-0027 §2).
--
-- Extends the `tournament_matches.phase` CHECK constraint to allow the four
-- double-elimination phase values introduced by ADR-0027:
--   'wb'                — winner-bracket round
--   'lb'                — loser-bracket round (major + minor)
--   'grand_final'       — grand final game 1
--   'grand_final_reset' — grand final game 2 (only materialised when
--                          with_bracket_reset = true)
--
-- CRITICAL: keeps ALL existing allowed values ('group','ko','third_place',
-- 'final'). Existing single-elim rows stay valid. Idempotent: DROP … IF EXISTS
-- + re-ADD, so re-running the migration is a no-op.
--
-- Bezug: ADR-0027 §2, P6_RULES_DECISIONS.md §D.
--
-- DEPENDENCIES (verify without a DB):
--   * TABLE  public.tournament_matches
--       — column `phase text NOT NULL DEFAULT 'group'`
--       — constraint `tournament_matches_phase_check`
--       SOURCE: supabase/migrations/20260601000010_tournament_ko_phase.sql
--               (Z. 21-29, original CHECK with the 4 single-elim values).
--   * COLUMN public.tournaments.bracket_type
--       — already exists (CHECK single_elimination|double_elimination),
--         NO new column added here.
--       SOURCE: supabase/migrations/20261001000001_tournament_setup_fields.sql
--               (Z. 134-135).
--   * COLUMN public.tournaments.ko_config (jsonb) — carries
--       `with_bracket_reset` (default true), NO schema change needed.
--       SOURCE: supabase/migrations/20260601000010_tournament_ko_phase.sql
--               (Z. 44-46).

ALTER TABLE public.tournament_matches
  DROP CONSTRAINT IF EXISTS tournament_matches_phase_check;
ALTER TABLE public.tournament_matches
  ADD CONSTRAINT tournament_matches_phase_check
    CHECK (phase IN (
      'group','ko','third_place','final',
      'wb','lb','grand_final','grand_final_reset'));

COMMENT ON COLUMN public.tournament_matches.phase IS
  'Per-match phase discriminator. `group` for round-robin matches, '
  '`ko`/`third_place`/`final` for single-elimination matches, '
  '`wb`/`lb`/`grand_final`/`grand_final_reset` for double-elimination '
  '(ADR-0027). Defaults to `group` so M1-Rows (round-robin only) bleiben gültig.';
