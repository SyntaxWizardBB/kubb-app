-- Schema-Smoke-Tests fuer die Team-Migration (TASK-M3.1-T3).
--
-- Verifiziert die fuenf Team-Tabellen aus `architecture.md` §3.2 plus
-- UNIQUE-Partial-Index auf `team_memberships` und die zwei RLS-Pfade
-- auf `teams` (anon-SELECT erlaubt fuer FR-PUB-9, anon-INSERT abgelehnt
-- mit 42501 — Mutationen ausschliesslich via SECURITY-DEFINER-RPCs).
--
-- Helper `_seedTeam(...)` ist Contract fuer TASK-M3.1-T7 (RPC-Tests):
-- ein Aufruf legt Auth-User, Team und Creator-Membership an und
-- retourniert die `team_id`. Wiederverwendung verhindert Drift bei
-- Fixture-Setup zwischen den beiden Test-Suiten.

BEGIN;

SELECT plan(8);

-- ---------------------------------------------------------------------
-- Helpers: Auth-Rollen-Switch (Pattern aus `tournament_ko_rpcs.sql`).
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _team_as_anon() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
END;
$$;

-- Contract-Helper fuer T7: legt User + Team + Creator-Membership an
-- (Direct-Insert, umgeht RLS via aktueller Role). Produktiv laeuft das
-- via `team_create`-RPC (T4); fuer Tests-Fixtures ist Direct-Insert OK.
CREATE OR REPLACE FUNCTION _seedTeam(
  p_creator uuid, p_display_name text DEFAULT 'Hammer-Crew')
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_team_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
    VALUES (p_creator, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'team-' || p_creator::text || '@test.local',
            '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.teams(id, display_name, league_membership, created_by)
    VALUES (v_team_id, p_display_name, 'B', p_creator);

  INSERT INTO public.team_memberships(id, team_id, user_id)
    VALUES (gen_random_uuid(), v_team_id, p_creator);

  RETURN v_team_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 1. Tabellen-Existenz (architecture.md §3.2, 5 Tabellen).
-- ---------------------------------------------------------------------

SELECT has_table('public', 'teams',              'Tabelle teams existiert');
SELECT has_table('public', 'team_memberships',   'Tabelle team_memberships existiert');
SELECT has_table('public', 'team_guest_players', 'Tabelle team_guest_players existiert');
SELECT has_table('public', 'team_invitations',   'Tabelle team_invitations existiert');
SELECT has_table('public', 'team_audit_events',  'Tabelle team_audit_events existiert');

-- ---------------------------------------------------------------------
-- 2. Fixture-Seed: ein Team mit Creator-Membership.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_team_id uuid;
BEGIN
  v_team_id := _seedTeam(v_creator, 'Schema-Test-Crew');
  CREATE TEMP TABLE _team_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_team_id AS team_id;
END $$;

-- ---------------------------------------------------------------------
-- 3. UNIQUE-Partial-Index `(team_id, user_id) WHERE removed_at IS NULL`
--    blockiert zweite offene Membership fuer dieselbe Person.
-- ---------------------------------------------------------------------

SELECT throws_ok(
  format($$
    INSERT INTO public.team_memberships(id, team_id, user_id)
      VALUES (gen_random_uuid(), %L::uuid, %L::uuid)
  $$, (SELECT team_id FROM _team_ctx), (SELECT creator FROM _team_ctx)),
  '23505', NULL,
  'team_memberships: zweite offene Membership → unique_violation');

-- ---------------------------------------------------------------------
-- 4. RLS `teams`: anonymer SELECT liefert Rows (FR-PUB-9).
-- ---------------------------------------------------------------------

SELECT _team_as_anon();

SELECT cmp_ok(
  (SELECT count(*)::int FROM public.teams),
  '>=', 1,
  'teams: anonymer SELECT liefert Rows (FR-PUB-9, Team-Suche oeffentlich)');

-- ---------------------------------------------------------------------
-- 5. RLS `teams`: anonymer INSERT → ERRCODE 42501.
-- ---------------------------------------------------------------------

SELECT throws_ok(
  $$ INSERT INTO public.teams(id, display_name, league_membership, created_by)
       VALUES (gen_random_uuid(), 'Forbidden-Crew', 'B', NULL) $$,
  '42501', NULL,
  'teams: anonymer INSERT → 42501 (RLS, Mutation nur via RPC)');

SELECT * FROM finish();

ROLLBACK;
