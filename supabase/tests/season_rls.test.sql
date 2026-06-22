-- RLS-Tests für das Seasons-Schema (TASK-M5.2-T9, R-M5.2-2).
--
-- Verifiziert die Policy-Kontrakte aus TASK-M5.2-T7. Lese-Pfad läuft
-- über die einzig grantete öffentliche Fläche: die View
-- `public.v_season_standings` (GRANT SELECT an anon/authenticated in
-- 20260801000003). Die Basis-Tabellen `seasons` und
-- `season_standings_awards` haben in dieser lokalen DB KEINEN
-- anon/authenticated-Grant — Supabase würde die Default-Grants normal
-- mitliefern, hier fehlen sie. Das ist eine Grant-Vertrags-Lücke und
-- wird NICHT per Test-Grant überpapert (sonst wäre dieser Test
-- inkonsistent mit public_rls_test/team_schema_test, die an derselben
-- Lücke ehrlich rot bleiben).
--
-- Cases:
--   1. anon liest open-Saison-Standings über v_season_standings (grün).
--   2. anon sieht open+closed über v_season_standings = 2 (grün).
--   3. anon sieht draft-Standings NICHT (= 0). EHRLICH ROT in dieser DB:
--      die View ist postgres-owned und läuft als SECURITY INVOKER OHNE
--      FORCE ROW LEVEL SECURITY, der Owner umgeht also die RLS der
--      Basis-Tabellen — draft leckt durch (= 1). Über die Basis-Tabelle
--      wäre der anon-Read grant-denied (42501), also auch dort nicht
--      beobachtbar. Der RLS-Draft-Ausschluss ist über keinen granteten
--      anon-Pfad in dieser DB prüfbar.
--   4. anon-INSERT in season_standings_awards → 42501. ACHTUNG: das 42501
--      kommt aus der Grant-Denial (anon hat KEIN INSERT-Grant), NICHT aus
--      dem RLS-WITH-CHECK. Teil des Grant-Vertrags-Clusters, kein
--      WITH-CHECK-Test — bleibt unverändert, aber ehrlich dokumentiert.
--   5. league_admin-INSERT in season_standings_awards. EHRLICH ROT:
--      authenticated hat ebenfalls KEIN INSERT-Grant → 42501, lives_ok
--      schlägt fehl. Teil des Grant-Vertrags-Clusters.
--
-- Rollen-Switch: `set_config('role', ...)` plus JWT-Claims-Override für
-- `auth.jwt() ->> 'role' = 'league_admin'` (FR-POINTS-11, R-M5-G1).

BEGIN;

SELECT plan(5);

CREATE OR REPLACE FUNCTION _t7_as_anon() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
END;
$$;

CREATE OR REPLACE FUNCTION _t7_as_league_admin(p_uid uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_uid::text,
                       'role', 'league_admin')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _t7_as_postgres() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
END;
$$;

-- Seedet eine Saison mit gegebenem Status (draft|open|closed) plus eine
-- Award-Row fuer die Standings-View. Direct-Insert als `postgres`
-- umgeht RLS (Fixture-Pattern aus `public_rls_test.sql`).
CREATE OR REPLACE FUNCTION _t7_seed_season(p_status text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_sid uuid := gen_random_uuid();
  v_uid uuid := gen_random_uuid();
  v_pid uuid := gen_random_uuid();
  v_tid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'season-' || v_uid::text || '@test.local',
            '', now(), now(), now());

  -- season_standings_awards.tournament_id is NOT NULL REFERENCES
  -- tournaments, so a real tournament has to exist before the award row.
  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status)
    VALUES (v_tid, v_uid, 'Season-Turnier-' || p_status, 1, 2, 16,
            'round_robin', 'ekc', '{"format":"best_of_1"}'::jsonb, 'draft');

  INSERT INTO public.seasons(id, name, league_id, status,
                             starts_at, ends_at)
    VALUES (v_sid, 'Season-' || p_status, NULL, p_status,
            '2026-01-01', '2026-12-31');

  INSERT INTO public.season_standings_awards(
      id, season_id, league_id, participant_id, tournament_id,
      placement, base_points, final_points, breakdown)
    VALUES (gen_random_uuid(), v_sid, NULL, v_pid, v_tid,
            1, 10, 15.0, 'seed');

  RETURN v_sid;
END;
$$;

DO $$
DECLARE
  v_draft  uuid;
  v_open   uuid;
  v_closed uuid;
  v_admin  uuid := gen_random_uuid();
  v_otid   uuid := gen_random_uuid();
BEGIN
  v_draft  := _t7_seed_season('draft');
  v_open   := _t7_seed_season('open');
  v_closed := _t7_seed_season('closed');

  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    VALUES (v_admin, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'admin-' || v_admin::text || '@test.local',
            '', now(), now(), now());

  -- Echtes Turnier für die Award-INSERT-Tests (tournament_id NOT NULL FK).
  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status)
    VALUES (v_otid, v_admin, 'Award-Write-Turnier', 1, 2, 16,
            'round_robin', 'ekc', '{"format":"best_of_1"}'::jsonb, 'draft');

  CREATE TEMP TABLE _t7_ctx ON COMMIT DROP AS
    SELECT v_draft AS draft_sid, v_open AS open_sid,
           v_closed AS closed_sid, v_admin AS admin_uid,
           v_otid AS open_tid;
  -- `set_config('role', ...)` hard-switches the effective role, so the
  -- anon/league_admin assertions below cannot read this postgres-owned
  -- context table without an explicit grant. Das ist eine test-interne
  -- TEMP-Tabelle (kein Produktions-Objekt) — derselbe Fixture-Grant wie
  -- `_pub_ctx` in public_rls_test.sql. KEIN Grant auf Basis-Tabellen.
  GRANT SELECT ON _t7_ctx TO anon, authenticated;
END $$;

-- 1. anon CAN SELECT von `v_season_standings` einer open-Saison.
SELECT _t7_as_anon();

SELECT cmp_ok(
  (SELECT count(*)::int FROM public.v_season_standings
     WHERE season_id = (SELECT open_sid FROM _t7_ctx)),
  '>=', 1,
  'v_season_standings: anon liest open-Saison-Standings');

-- 2. anon sieht open- und closed-Standings über die grantete View.
SELECT is(
  (SELECT count(*)::int FROM public.v_season_standings
     WHERE season_id IN ((SELECT open_sid FROM _t7_ctx),
                         (SELECT closed_sid FROM _t7_ctx))),
  2,
  'v_season_standings: anon sieht open- und closed-Saisonen');

-- 3. anon darf draft-Standings NICHT sehen (= 0). EHRLICH ROT:
--    die View umgeht die RLS der Basis-Tabellen (postgres-owned, kein
--    FORCE RLS), draft leckt durch (= 1). Über die Basis-Tabelle wäre
--    der Read grant-denied. Der Draft-Ausschluss ist über keinen
--    granteten anon-Pfad in dieser DB beobachtbar — Assertion bleibt als
--    echter RLS-Vertrag stehen und schlägt sichtbar fehl statt einen
--    anderen Check (Grant-Denial) vorzutäuschen.
SELECT is(
  (SELECT count(*)::int FROM public.v_season_standings
     WHERE season_id = (SELECT draft_sid FROM _t7_ctx)),
  0,
  'v_season_standings: anon sieht draft-Standings NICHT (Liga-Admin-only)');

-- 4. anon-INSERT in `season_standings_awards` → 42501. Das 42501 kommt
--    in dieser DB aus der Grant-Denial (anon hat KEIN INSERT-Grant),
--    NICHT aus dem RLS-WITH-CHECK — Teil des Grant-Vertrags-Clusters,
--    kein WITH-CHECK-Test. tournament_id muss eine echte Turnier-id sein
--    (NOT NULL FK); league_id ist uuid NULL.
SELECT throws_ok(
  format($$
    INSERT INTO public.season_standings_awards(
      id, season_id, league_id, participant_id, tournament_id,
      placement, base_points, final_points, breakdown)
    VALUES (gen_random_uuid(), %L::uuid, NULL, gen_random_uuid(), %L::uuid,
            1, 10, 15.0, 'hijack')
  $$, (SELECT open_sid FROM _t7_ctx), (SELECT open_tid FROM _t7_ctx)),
  '42501', NULL,
  'season_standings_awards: anon-INSERT → 42501 (FR-POINTS-11)');

-- 5. league_admin-INSERT in `season_standings_awards`. EHRLICH ROT:
--    authenticated hat KEIN INSERT-Grant auf die Basis-Tabelle → 42501,
--    lives_ok schlägt fehl. Teil des Grant-Vertrags-Clusters; wird NICHT
--    per Test-Grant grün gemacht. Greent erst, wenn der fehlende
--    Supabase-Default-Grant in einer Migration nachgezogen ist.
SELECT _t7_as_league_admin((SELECT admin_uid FROM _t7_ctx));

SELECT lives_ok(
  format($$
    INSERT INTO public.season_standings_awards(
      id, season_id, league_id, participant_id, tournament_id,
      placement, base_points, final_points, breakdown)
    VALUES (gen_random_uuid(), %L::uuid, NULL, gen_random_uuid(), %L::uuid,
            2, 8, 12.0, 'league_admin-write')
  $$, (SELECT open_sid FROM _t7_ctx), (SELECT open_tid FROM _t7_ctx)),
  'season_standings_awards: league_admin-INSERT erlaubt (FR-POINTS-11)');

SELECT * FROM finish();

ROLLBACK;
