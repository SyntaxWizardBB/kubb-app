-- Phase E (ADR-0031 §Runner / §3b) Block E3 — schedule-tick cron-job pgTAP suite.
--
-- Verifies the E3 cron-job registration (migration 20261273000000):
--   * after applying the unschedule-then-schedule register block, EXACTLY ONE
--     cron.job exists with jobname 'tournament_schedule_tick' (count = 1)
--   * that job has schedule '* * * * *' and command
--     'SELECT public.tournament_schedule_tick();'  (K7: no p_now argument)
--   * IDEMPOTENCY (R7/R1): running the SAME register block a SECOND time
--     (double-apply) still leaves exactly one such job — no duplicate row.
--
-- pgTAP is installed transiently inside BEGIN..ROLLBACK; everything rolls back,
-- so the cron job registered here does NOT persist (the real registration is the
-- migration). The register block below mirrors the migration's DO-block verbatim.
-- Comments/code in English, consistent with enable_pg_cron_test.sql.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- Establish a deterministic clean slate inside this rolled-back TX. cron.job is a
-- real (non-fixture) table, so the row registered by the E3 migration is visible
-- here; we unschedule it so the precondition below is independent of apply order.
-- (The ROLLBACK at the end restores the migration's persistent registration.)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'tournament_schedule_tick') THEN
    PERFORM cron.unschedule('tournament_schedule_tick');
  END IF;
END $$;

-- Precondition: after the cleanup the schedule-tick job does not exist. This is
-- the state the migration's EXISTS-guard handles on a first apply.
SELECT is(
  (SELECT count(*)::int FROM cron.job WHERE jobname = 'tournament_schedule_tick'),
  0,
  'precondition: no tournament_schedule_tick cron job before E3 register');

-- ====================================================================
-- First apply of the E3 register block (verbatim copy of the migration DO-block).
-- ====================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'tournament_schedule_tick') THEN
    PERFORM cron.unschedule('tournament_schedule_tick');
  END IF;
  PERFORM cron.schedule(
    'tournament_schedule_tick',
    '* * * * *',
    'SELECT public.tournament_schedule_tick();');
END $$;

-- E3-6: exactly one job with this jobname after the first apply.
SELECT is(
  (SELECT count(*)::int FROM cron.job WHERE jobname = 'tournament_schedule_tick'),
  1,
  'exactly one tournament_schedule_tick cron job after register');

-- E3-6: that job runs every minute.
SELECT is(
  (SELECT schedule FROM cron.job WHERE jobname = 'tournament_schedule_tick'),
  '* * * * *',
  'cron job schedule is every minute (* * * * *)');

-- E3-6 / K7: command calls the schema-qualified function WITHOUT an argument,
-- so the DEFAULT now() applies in production.
SELECT is(
  (SELECT command FROM cron.job WHERE jobname = 'tournament_schedule_tick'),
  'SELECT public.tournament_schedule_tick();',
  'cron job command is SELECT public.tournament_schedule_tick(); (no p_now arg)');

-- ====================================================================
-- Second apply of the SAME register block (double-apply) — must stay idempotent.
-- ====================================================================
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'tournament_schedule_tick') THEN
    PERFORM cron.unschedule('tournament_schedule_tick');
  END IF;
  PERFORM cron.schedule(
    'tournament_schedule_tick',
    '* * * * *',
    'SELECT public.tournament_schedule_tick();');
END $$;

-- E3-7 / R7: still exactly one job after the double-apply (no duplicate).
SELECT is(
  (SELECT count(*)::int FROM cron.job WHERE jobname = 'tournament_schedule_tick'),
  1,
  'double-apply keeps exactly one tournament_schedule_tick cron job (idempotent)');

-- E3-7: schedule and command are unchanged after the re-apply.
SELECT is(
  (SELECT schedule FROM cron.job WHERE jobname = 'tournament_schedule_tick'),
  '* * * * *',
  'schedule unchanged after double-apply');

SELECT is(
  (SELECT command FROM cron.job WHERE jobname = 'tournament_schedule_tick'),
  'SELECT public.tournament_schedule_tick();',
  'command unchanged after double-apply');

SELECT * FROM finish();
ROLLBACK;
