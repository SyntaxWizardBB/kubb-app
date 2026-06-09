-- Phase E (ADR-0031 §3b) Block E0 — pg_cron extension pgTAP suite.
--
-- Covers (E0-DoD):
--   * has_extension('pg_cron') — extension installed
--   * has_schema('cron')       — the cron schema exists (created by the ext)
--   * has_table('cron','job')  — the cron.job table exists
--
-- pgTAP is installed transiently inside the BEGIN..ROLLBACK (see
-- round_schedule_test.sql note); everything rolls back, nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(3);

SELECT has_extension('pg_cron', 'pg_cron extension is installed');
SELECT has_schema('cron', 'cron schema exists');
SELECT has_table('cron', 'job', 'cron.job table exists');

SELECT * FROM finish();
ROLLBACK;
