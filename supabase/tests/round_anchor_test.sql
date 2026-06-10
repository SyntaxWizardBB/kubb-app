-- ADR-0031 Block E1 — _tournament_round_anchor(p_starts_at, p_now) pgTAP suite.
--
-- The helper is the single source of truth for the play-ready clock anchor:
-- greatest(p_starts_at, p_now). It is IMMUTABLE and takes p_now EXPLICITLY, so
-- these assertions inject FIXED timestamptz values and never depend on now()
-- (pgTAP freezes now() inside the transaction — README K7). Covers:
--   * Vergangenheit: p_starts_at < p_now  => result = p_now        (clamp up)
--   * Zukunft:       p_starts_at > p_now  => result = p_starts_at  (future kept)
--   * Gleichstand:   p_starts_at = p_now  => result = that instant
--
-- pgTAP is installed transiently inside BEGIN..ROLLBACK (see
-- match_autostart_test.sql); everything rolls back, nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(5);

SELECT has_function('public', '_tournament_round_anchor',
  ARRAY['timestamptz', 'timestamptz'],
  '_tournament_round_anchor(timestamptz, timestamptz) helper exists');

-- Assert LANGUAGE sql + IMMUTABLE straight from the catalog. (pgTAP's
-- function_lang_is with the timestamptz[] overload mis-resolves this helper, so
-- the contract is checked directly: l.lanname = 'sql', p.provolatile = 'i'.)
SELECT is(
  (SELECT l.lanname || '/' || p.provolatile::text
     FROM pg_proc p
     JOIN pg_language l ON l.oid = p.prolang
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname = '_tournament_round_anchor'
      AND p.pronargs = 2),
  'sql/i',
  '_tournament_round_anchor is LANGUAGE sql and IMMUTABLE');

-- ---- Vergangenheit: starts_at strictly before now => anchor = p_now ----
SELECT is(
  public._tournament_round_anchor(
    '2026-01-01 10:00:00+00'::timestamptz,   -- p_starts_at (past)
    '2026-01-01 12:00:00+00'::timestamptz),  -- p_now
  '2026-01-01 12:00:00+00'::timestamptz,
  'PAST starts_at => anchor clamped up to p_now (greatest)');

-- ---- Zukunft: starts_at strictly after now => anchor = p_starts_at ----
SELECT is(
  public._tournament_round_anchor(
    '2026-01-01 15:00:00+00'::timestamptz,   -- p_starts_at (future)
    '2026-01-01 12:00:00+00'::timestamptz),  -- p_now
  '2026-01-01 15:00:00+00'::timestamptz,
  'FUTURE starts_at => anchor = p_starts_at (future kept)');

-- ---- Gleichstand: starts_at == now => anchor = that instant ----
SELECT is(
  public._tournament_round_anchor(
    '2026-01-01 12:00:00+00'::timestamptz,
    '2026-01-01 12:00:00+00'::timestamptz),
  '2026-01-01 12:00:00+00'::timestamptz,
  'EQUAL starts_at = p_now => anchor = that instant');

SELECT * FROM finish();
ROLLBACK;
