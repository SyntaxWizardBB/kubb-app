-- RLS-Tests fuer das Seasons-Schema (TASK-M5.2-T9, R-M5.2-2).
--
-- Verifiziert die Policy-Kontrakte aus TASK-M5.2-T7:
--   * anon liest `v_season_standings` einer open-Saison.
--   * anon liest `seasons` mit Status `open` oder `closed`.
--   * anon sieht keine `seasons` mit Status `draft` (Liga-Admin-only).
--   * anon-INSERT in `season_standings_awards` → 42501.
--   * league_admin-INSERT in `season_standings_awards` ist erlaubt.
--
-- Rollen-Switch: `set_config('role', ...)` plus JWT-Claims-Override fuer
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
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'season-' || v_uid::text || '@test.local',
            '', now(), now(), now());

  INSERT INTO public.seasons(id, display_name, league_id, status,
                             start_date, end_date, created_by)
    VALUES (v_sid, 'Season-' || p_status, 'B', p_status,
            '2026-01-01', '2026-12-31', v_uid);

  INSERT INTO public.season_standings_awards(
      id, season_id, league_id, participant_id, tournament_id,
      placement, base_points, final_points, breakdown)
    VALUES (gen_random_uuid(), v_sid, 'B', v_pid, NULL,
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

  CREATE TEMP TABLE _t7_ctx ON COMMIT DROP AS
    SELECT v_draft AS draft_sid, v_open AS open_sid,
           v_closed AS closed_sid, v_admin AS admin_uid;
END $$;

-- 1. anon CAN SELECT von `v_season_standings` einer open-Saison.
SELECT _t7_as_anon();

SELECT cmp_ok(
  (SELECT count(*)::int FROM public.v_season_standings
     WHERE season_id = (SELECT open_sid FROM _t7_ctx)),
  '>=', 1,
  'v_season_standings: anon liest open-Saison-Standings');

-- 2. anon CAN SELECT `seasons` mit Status open oder closed.
SELECT is(
  (SELECT count(*)::int FROM public.seasons
     WHERE id IN ((SELECT open_sid FROM _t7_ctx),
                  (SELECT closed_sid FROM _t7_ctx))),
  2,
  'seasons: anon sieht open- und closed-Saisonen');

-- 3. anon CANNOT SELECT `seasons` mit Status draft.
SELECT is(
  (SELECT count(*)::int FROM public.seasons
     WHERE id = (SELECT draft_sid FROM _t7_ctx)),
  0,
  'seasons: anon sieht draft-Saison NICHT (Liga-Admin-only)');

-- 4. anon CANNOT INSERT in `season_standings_awards` → 42501.
SELECT throws_ok(
  format($$
    INSERT INTO public.season_standings_awards(
      id, season_id, league_id, participant_id, tournament_id,
      placement, base_points, final_points, breakdown)
    VALUES (gen_random_uuid(), %L::uuid, 'B', gen_random_uuid(), NULL,
            1, 10, 15.0, 'hijack')
  $$, (SELECT open_sid FROM _t7_ctx)),
  '42501', NULL,
  'season_standings_awards: anon-INSERT → 42501 (FR-POINTS-11)');

-- 5. league_admin CAN INSERT in `season_standings_awards`.
SELECT _t7_as_league_admin((SELECT admin_uid FROM _t7_ctx));

SELECT lives_ok(
  format($$
    INSERT INTO public.season_standings_awards(
      id, season_id, league_id, participant_id, tournament_id,
      placement, base_points, final_points, breakdown)
    VALUES (gen_random_uuid(), %L::uuid, 'B', gen_random_uuid(), NULL,
            2, 8, 12.0, 'league_admin-write')
  $$, (SELECT open_sid FROM _t7_ctx)),
  'season_standings_awards: league_admin-INSERT erlaubt (FR-POINTS-11)');

SELECT * FROM finish();

ROLLBACK;
