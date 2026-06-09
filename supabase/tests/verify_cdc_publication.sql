-- SRV-08 (ADR-0029, messaging-framework-plan §(d) + Phase P7): read-only assertion
-- of the supabase_realtime publication end-state. Run with:
--   docker exec supabase_db_kubb-app-local psql -U postgres -d postgres \
--     -f supabase/tests/verify_cdc_publication.sql
-- (or `psql -f`). On any divergence it RAISEs an exception and exits non-zero.
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
DO $$
DECLARE
  expected text[] := ARRAY[
    'user_inbox_messages',
    'friend_edges',
    'tournament_matches',
    'team_memberships',
    'tournament_participants',
    'matches',
    'tournament_round_schedule'
  ];
  actual   text[];
  full_ri  text[];
  cnt      int;
BEGIN
  -- 1. Exact publication membership (order-independent set comparison).
  SELECT array_agg(tablename ORDER BY tablename)
    INTO actual
    FROM pg_publication_tables
   WHERE pubname = 'supabase_realtime'
     AND schemaname = 'public';

  SELECT count(*) INTO cnt
    FROM pg_publication_tables
   WHERE pubname = 'supabase_realtime'
     AND schemaname = 'public';

  IF cnt <> 7 THEN
    RAISE EXCEPTION 'supabase_realtime must publish exactly 7 tables, found %: %',
      cnt, actual;
  END IF;

  IF NOT (actual @> expected AND expected @> actual) THEN
    RAISE EXCEPTION 'supabase_realtime published set mismatch. expected %, actual %',
      (SELECT array_agg(t ORDER BY t) FROM unnest(expected) t), actual;
  END IF;

  -- 2. tournaments must NOT be published (broadcast-only transport).
  IF EXISTS (
    SELECT 1 FROM pg_publication_tables
     WHERE pubname = 'supabase_realtime'
       AND schemaname = 'public'
       AND tablename = 'tournaments'
  ) THEN
    RAISE EXCEPTION 'tournaments must NOT be in supabase_realtime (broadcast-only)';
  END IF;

  -- 3. Every published table must be REPLICA IDENTITY DEFAULT ('d'), never FULL.
  SELECT array_agg(c.relname ORDER BY c.relname)
    INTO full_ri
    FROM pg_publication_tables pt
    JOIN pg_class c ON c.relname = pt.tablename
    JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = pt.schemaname
   WHERE pt.pubname = 'supabase_realtime'
     AND pt.schemaname = 'public'
     AND c.relreplident <> 'd';

  IF full_ri IS NOT NULL THEN
    RAISE EXCEPTION 'published tables must be REPLICA IDENTITY DEFAULT, these are not: %',
      full_ri;
  END IF;

  RAISE NOTICE 'verify_cdc_publication: OK — exactly 7 tables, all REPLICA IDENTITY DEFAULT, tournaments excluded';
END $$;
