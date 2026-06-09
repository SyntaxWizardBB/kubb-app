-- Phase E (ADR-0031 §Runner / §3b) Block E3 — register the pg_cron schedule tick job.
--
-- This migration registers the once-a-minute pg_cron job that drives the pure
-- TIME transitions of the round-clock automaton by calling the E2 function
-- public.tournament_schedule_tick(). pg_cron (1.6, in-DB, runs as postgres,
-- cron.database_name = postgres) executes the command every minute.
--
-- IDEMPOTENCY (R7 / R1): a FIXED jobname literal 'tournament_schedule_tick' is the
-- idempotency key. The DO-block uses the unschedule-then-schedule pattern: if a
-- job with that name already exists (e.g. on a re-apply or after a prior register
-- run), it is unscheduled FIRST, then re-scheduled. A double-apply therefore never
-- yields a duplicate cron.job row — the count for that jobname stays exactly 1.
--
-- COMMAND (K7): the command is 'SELECT public.tournament_schedule_tick();' WITHOUT
-- an argument, so the function's DEFAULT now() applies in production (the explicit
-- p_now parameter exists only so pgTAP can inject a fixed instant in tests). The
-- call is schema-qualified (public.) and carries no p_now literal.
--
-- PURELY ADDITIVE: this migration contains NO CREATE OR REPLACE of any layered
-- function (in particular NOT tournament_schedule_tick or _tournament_round_anchor)
-- and NO other schema or data mutation. Its only effect is the cron-job
-- registration via cron.unschedule / cron.schedule — so no stale-body diff is
-- required here. No supabase db reset; no destructive command.

DO $$
BEGIN
  -- R7: drop a pre-existing job with the same fixed name before (re-)scheduling,
  -- so applying this block twice keeps exactly one 'tournament_schedule_tick' job.
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'tournament_schedule_tick') THEN
    PERFORM cron.unschedule('tournament_schedule_tick');
  END IF;

  -- Register the 1-minute tick. Command has no argument so the function's
  -- DEFAULT now() applies in production (K7). Schema-qualified call (public.).
  PERFORM cron.schedule(
    'tournament_schedule_tick',
    '* * * * *',
    'SELECT public.tournament_schedule_tick();');
END $$;
