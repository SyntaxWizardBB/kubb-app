-- Phase E (ADR-0031 §3b) Block E0 — enable the pg_cron extension.
--
-- The timed tournament runner needs an in-DB tick (no pg_net/HTTP) as the
-- foundation for the autonomous 1-minute schedule tick (E1-E3). This migration
-- is PURELY ADDITIVE and IDEMPOTENT: it only installs the pg_cron extension,
-- which implicitly creates the `cron` schema and its `cron.job` table. No
-- existing object is altered or dropped; there is no CREATE OR REPLACE of any
-- layered function here.
--
-- Preconditions (verified locally): pg_cron 1.6 is available and listed in
-- shared_preload_libraries; cron.database_name = postgres (the app DB), so the
-- cron jobs run in-database against application data.

CREATE EXTENSION IF NOT EXISTS pg_cron;
