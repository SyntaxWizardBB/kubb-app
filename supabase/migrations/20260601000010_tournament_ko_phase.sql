-- Tournament feature — M2 KO-phase schema extension.
--
-- Adds the four columns the M2 KO-bracket slice needs on top of the M1
-- tournament tables:
--
--   * tournament_matches.phase            — per-match phase discriminator
--   * tournament_matches.bracket_position — KO-round slot (1..N), NULL for group
--   * tournaments.ko_config               — KO-config bag (qualifier_count etc.)
--   * tournaments.league_eligible         — owner-flag: turnier wertet für die Liga
--
-- Bezug: docs/plans/m2-ko-bracket/architecture.md §3.2,
--        docs/adr/0017-ko-phase-semantics.md §4 (`league_eligible`).
--
-- Idempotent: every column add uses IF NOT EXISTS; CHECK-constraint is
-- (re-)created via DROP IF EXISTS + ADD so re-running the migration is
-- a no-op. Bestehende M1-Rows behalten den DEFAULT (`phase='group'`,
-- `bracket_position=NULL`, `ko_config=NULL`, `league_eligible=false`).

-- ---- 1. tournament_matches: phase + bracket_position -----------------

ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS phase            text NOT NULL DEFAULT 'group',
  ADD COLUMN IF NOT EXISTS bracket_position int  NULL;

ALTER TABLE public.tournament_matches
  DROP CONSTRAINT IF EXISTS tournament_matches_phase_check;
ALTER TABLE public.tournament_matches
  ADD CONSTRAINT tournament_matches_phase_check
    CHECK (phase IN ('group','ko','third_place','final'));

COMMENT ON COLUMN public.tournament_matches.phase IS
  'Per-match phase discriminator. `group` for round-robin matches, '
  '`ko`/`third_place`/`final` for single-elimination matches. '
  'Defaults to `group` so M1-Rows (round-robin only) bleiben gültig.';

COMMENT ON COLUMN public.tournament_matches.bracket_position IS
  'Slot inside the KO round (1..N, 1-based). Drives Sieger-Fortschreibung '
  'via `tournament_advance_ko_winner` (ADR-0017 §5). NULL for group-phase '
  'matches.';


-- ---- 2. tournaments: ko_config + league_eligible ---------------------

ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS ko_config       jsonb   NULL,
  ADD COLUMN IF NOT EXISTS league_eligible boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.tournaments.ko_config IS
  'KO-spezifische Konfig (`qualifier_count`, `with_third_place_playoff`, '
  '`seeding_mode`). NULL bei reinen Vorrunden-Formaten. Wird beim Wizard '
  'gesetzt und von `tournament_start_ko_phase` gelesen.';

COMMENT ON COLUMN public.tournaments.league_eligible IS
  'Owner-Flag: dieses Turnier wertet für die Liga (ADR-0017 §4). Steuert '
  'den vorgeschlagenen Default für `with_third_place_playoff` im Wizard. '
  'Default false — Veranstalter muss aktiv markieren.';
