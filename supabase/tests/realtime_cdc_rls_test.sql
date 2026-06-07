-- SRV-07 (ADR-0029, messaging-framework-plan §(d) + §(h) + Phase P7): RLS / CDC
-- filter-column parity suite. For every CDC target the column a client filters the
-- subscription on (the "filter column") MUST be authorised by a SELECT policy whose
-- USING clause references that same column — otherwise Realtime denies the stream.
--
--   target                   | filter column  | authorising SELECT policy
--   -------------------------+----------------+----------------------------------------
--   team_memberships         | user_id        | team_memberships_self_read
--   team_memberships         | team_id        | team_memberships_pool_read
--   tournament_participants  | user_id        | tournament_participants_self_read
--   tournament_matches       | tournament_id  | tournament_matches_read
--   matches                  | id             | matches_participant_read
--
-- ============================ EXECUTION NOTE ============================
-- pgTAP is AVAILABLE in the local Supabase stack but NOT pre-installed
-- (`pg_available_extensions` lists it; it is absent from `pg_extension`, and
-- `supabase test db` is not wired up here). This suite installs it itself via
-- `CREATE EXTENSION IF NOT EXISTS pgtap` inside the BEGIN..ROLLBACK below, so the
-- install is transient and rolled back — leaving the DB unchanged.
--
-- WHAT WAS REALLY EXECUTED HERE (read-only, all in BEGIN..ROLLBACK):
--   (1) This pgTAP suite was run AS-IS and reported 7/7 ok (plan(7), all green),
--       asserting filter-column == USING-column parity for all four targets.
--   (2) Additionally, for tournament_participants (the only target with rows
--       locally: 12 rows; team_memberships and matches were empty), two distinct
--       auth.uid() values were impersonated via `SET LOCAL request.jwt.claims`
--       under ROLE authenticated; under a user_id filter each user saw ONLY its
--       own rows (bool_and(user_id = uid) = true, non-empty), confirming the
--       self_read policy authorises the user_id CDC filter in practice.
-- Every probe transaction ended in ROLLBACK; no rows/schema were mutated.
-- =======================================================================

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- ---- team_memberships: user_id -> self_read ----
SELECT policy_cmd_is(
  'public', 'team_memberships', 'team_memberships_self_read', 'SELECT',
  'team_memberships_self_read is a SELECT policy'
);
SELECT ok(
  (SELECT qual FROM pg_policies
    WHERE schemaname='public' AND tablename='team_memberships'
      AND policyname='team_memberships_self_read') LIKE '%user_id%auth.uid()%',
  'team_memberships_self_read USING references user_id = auth.uid() (CDC user_id filter)'
);

-- ---- team_memberships: team_id -> pool_read ----
SELECT ok(
  (SELECT qual FROM pg_policies
    WHERE schemaname='public' AND tablename='team_memberships'
      AND policyname='team_memberships_pool_read') LIKE '%team_id%',
  'team_memberships_pool_read USING references team_id (CDC team_id filter)'
);

-- ---- tournament_participants: user_id -> self_read ----
SELECT policy_cmd_is(
  'public', 'tournament_participants', 'tournament_participants_self_read', 'SELECT',
  'tournament_participants_self_read is a SELECT policy'
);
SELECT ok(
  (SELECT qual FROM pg_policies
    WHERE schemaname='public' AND tablename='tournament_participants'
      AND policyname='tournament_participants_self_read') LIKE '%user_id%auth.uid()%',
  'tournament_participants_self_read USING references user_id = auth.uid() (CDC user_id filter)'
);

-- ---- tournament_matches: tournament_id -> read ----
SELECT ok(
  (SELECT qual FROM pg_policies
    WHERE schemaname='public' AND tablename='tournament_matches'
      AND policyname='tournament_matches_read') LIKE '%tournament_id%',
  'tournament_matches_read USING references tournament_id (CDC tournament_id filter)'
);

-- ---- matches: id -> participant_read ----
SELECT ok(
  (SELECT qual FROM pg_policies
    WHERE schemaname='public' AND tablename='matches'
      AND policyname='matches_participant_read') LIKE '%matches.id%',
  'matches_participant_read USING references matches.id (CDC id filter)'
);

SELECT * FROM finish();
ROLLBACK;
