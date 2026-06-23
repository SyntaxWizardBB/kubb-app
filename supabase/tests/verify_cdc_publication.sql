-- SRV-08 (ADR-0029, messaging-framework-plan §(d) + Phase P7): read-only assertion
-- of the supabase_realtime publication end-state. Run with:
--   docker exec supabase_db_kubb-app-local psql -U postgres -d postgres \
--     -f supabase/tests/verify_cdc_publication.sql
-- (or `psql -f`). On any divergence the pgTAP-Assertions fail and the run is red.
-- This script is strictly read-only: no INSERT/UPDATE/DELETE/ALTER/DROP/TRUNCATE.
--
-- End-state contract:
--   * EXACTLY 7 tables are published on supabase_realtime:
--       user_inbox_messages, friend_edges, tournament_matches,
--       team_memberships, tournament_participants, matches,
--       tournament_round_schedule
--     (tournament_round_schedule added by ADR-0031 Phase A Block A1
--      migration 20261251000000 — the timed-runner per-round CDC channel.)
--   * every published table has REPLICA IDENTITY DEFAULT ('d') — none is FULL
--   * tournaments is NOT published (broadcast-only transport)
SELECT plan(4);

-- 1. Exact publication count.
SELECT is(
  (SELECT count(*)::int
     FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'),
  7,
  'supabase_realtime publiziert genau 7 Tabellen'
);

-- 2. Exact publication membership (order-independent set comparison).
SELECT is(
  (SELECT array_agg(tablename::text ORDER BY tablename)
     FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'),
  (SELECT array_agg(t ORDER BY t) FROM unnest(ARRAY[
     'user_inbox_messages',
     'friend_edges',
     'tournament_matches',
     'team_memberships',
     'tournament_participants',
     'matches',
     'tournament_round_schedule'
   ]) t),
  'supabase_realtime publiziert genau den erwarteten Satz Tabellen'
);

-- 3. tournaments must NOT be published (broadcast-only transport).
SELECT ok(
  NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime'
       AND schemaname = 'public'
       AND tablename = 'tournaments'
  ),
  'tournaments ist NICHT publiziert (broadcast-only)'
);

-- 4. Every published table must be REPLICA IDENTITY DEFAULT ('d'), never FULL.
SELECT is(
  (SELECT count(*)::int
     FROM pg_publication_tables pt
     JOIN pg_class c ON c.relname = pt.tablename
     JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = pt.schemaname
    WHERE pt.pubname = 'supabase_realtime'
      AND pt.schemaname = 'public'
      AND c.relreplident <> 'd'),
  0,
  'alle publizierten Tabellen sind REPLICA IDENTITY DEFAULT'
);

SELECT * FROM finish();
