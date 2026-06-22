-- Defense-in-Depth-Layer fuer den anon-Spectator-Pfad (urspruenglich
-- TASK-M4.2-T2, seit Sprint-A W3-T3 / ADR-0026 sekundaerer Pfad).
--
-- HINWEIS: Der primaere anon-Read-Pfad laeuft seit ADR-0026 Strategie A
-- ueber die `public_*_get`-RPCs (siehe `public_rpc_test.sql`). Diese
-- Datei testet die Tabellen-Policies aus
-- `20260701000002_tournaments_public_flag.sql`, die nur noch als
-- Sekundaer-Schutz gegen direkte PostgREST-Tablezugriffe bestehen
-- bleiben (z.B. Mis-Konfiguration eines Realtime-Channels).
--
-- Merge-Gate fuer M4.2 (R-M4.2-1): verifiziert, dass die Policies
-- (`tournaments.public bool DEFAULT true NOT NULL` plus die vier
-- `FOR SELECT TO anon`-Policies auf `tournaments`, `tournament_matches`,
-- `tournament_participants`, `tournament_set_score_proposals`) das
-- erwartete Lese- und Schreibverhalten gegenueber einem anon-Caller
-- zeigen.
--
-- Pflicht-Cases aus tasks.md §M4.2-T2:
--   1. public=true  → SELECT erfolgreich
--   2. public=false → SELECT leer
--   3. UPDATE als anon → 42501
--   4. View `public_tournament_roster_view` exponiert keine PII
--      (keine `email`/`user_id`-Spalte)
--   5. Backfill: bestehende Rows haben `public=true`
--
-- Rollen-Switch via `set_config('role', 'anon', true)`, identisch zum
-- Pattern in `team_schema_test.sql`. JWT-Claim leer = anon-Caller.

BEGIN;

SELECT plan(9);

-- ---------------------------------------------------------------------
-- Helpers: Role-Switch + Fixture-Seed (Direct-Insert umgeht RLS, weil
-- das DDL-Skript als `postgres`-Superuser laeuft; analog `team_schema_-
-- test.sql`).
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _pub_as_anon() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
END;
$$;

CREATE OR REPLACE FUNCTION _pub_as_postgres() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
END;
$$;

-- Legt Tournament mit gegebenem `public`-Flag und einem `live`-Match
-- plus einem `confirmed`-Participant an. `live` wird gewaehlt, damit
-- die T1-Status-Whitelist (`published|registration_*|live|finalized`)
-- erfuellt ist.
CREATE OR REPLACE FUNCTION _pub_seed_tournament(p_public boolean)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_tid uuid := gen_random_uuid();
  v_uid uuid := gen_random_uuid();
  v_pid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'pub-' || v_uid::text || '@test.local',
            '', now(), now(), now());

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, v_uid, 'Public-RLS-Test-' || v_tid::text, 1, 2, 16,
            'round_robin', 'ekc', '{"format":"best_of_1"}'::jsonb,
            'live', p_public);

  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status)
    VALUES (v_pid, v_tid, v_uid, 'confirmed');

  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, status)
    VALUES (gen_random_uuid(), v_tid, 1, 1, v_pid, 'scheduled');

  RETURN v_tid;
END;
$$;

-- ---------------------------------------------------------------------
-- 1. Fixtures: ein public- und ein non-public-Turnier.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_pub_tid     uuid;
  v_non_pub_tid uuid;
BEGIN
  v_pub_tid     := _pub_seed_tournament(true);
  v_non_pub_tid := _pub_seed_tournament(false);
  CREATE TEMP TABLE _pub_ctx ON COMMIT DROP AS
    SELECT v_pub_tid AS pub_tid, v_non_pub_tid AS non_pub_tid;
  -- Die Fixture-IDs werden in den anon-Cases gelesen, nachdem die Rolle
  -- auf `anon` umgeschaltet wurde. Ohne dieses GRANT scheitert der Lese-
  -- zugriff auf die postgres-eigene TEMP-Tabelle mit 42501.
  GRANT SELECT ON _pub_ctx TO anon;
END $$;

-- ---------------------------------------------------------------------
-- 2. Backfill-Check (T1-Acceptance: alle existierenden Rows = public=true).
--    Wir asserten gegen die Faelle, die T1 vor seinem `ALTER ... ADD
--    COLUMN public bool DEFAULT true NOT NULL` schon hatte: nur das
--    von uns frisch geseedete non-public-Turnier darf public=false sein.
-- ---------------------------------------------------------------------

SELECT _pub_as_postgres();

SELECT is(
  (SELECT count(*)::int FROM public.tournaments
     WHERE public = false
       AND id <> (SELECT non_pub_tid FROM _pub_ctx)),
  0,
  'Backfill: keine pre-existierende Row hat public=false');

-- ---------------------------------------------------------------------
-- 3. anon-SELECT: public=true → Row sichtbar.
-- ---------------------------------------------------------------------

SELECT _pub_as_anon();

SELECT is(
  (SELECT count(*)::int FROM public.tournaments
     WHERE id = (SELECT pub_tid FROM _pub_ctx)),
  1,
  'tournaments: anon sieht public=true Row');

-- ---------------------------------------------------------------------
-- 4. anon-SELECT: public=false → leer.
-- ---------------------------------------------------------------------

SELECT is(
  (SELECT count(*)::int FROM public.tournaments
     WHERE id = (SELECT non_pub_tid FROM _pub_ctx)),
  0,
  'tournaments: anon sieht public=false Row NICHT');

-- ---------------------------------------------------------------------
-- 5. anon-SELECT: tournament_matches fuer public-Turnier → Rows.
-- ---------------------------------------------------------------------

SELECT cmp_ok(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = (SELECT pub_tid FROM _pub_ctx)),
  '>=', 1,
  'tournament_matches: anon sieht Matches eines public-Turniers');

-- ---------------------------------------------------------------------
-- 6. anon-SELECT: tournament_matches fuer non-public-Turnier → leer.
-- ---------------------------------------------------------------------

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
     WHERE tournament_id = (SELECT non_pub_tid FROM _pub_ctx)),
  0,
  'tournament_matches: anon sieht Matches eines non-public-Turniers NICHT');

-- ---------------------------------------------------------------------
-- 7. anon-UPDATE auf tournaments → ERRCODE 42501.
-- ---------------------------------------------------------------------

SELECT throws_ok(
  format($$
    UPDATE public.tournaments SET display_name = 'Hijack' WHERE id = %L::uuid
  $$, (SELECT pub_tid FROM _pub_ctx)),
  '42501', NULL,
  'tournaments: anon-UPDATE → 42501 (RLS-Block, Mutation nur via RPC)');

-- ---------------------------------------------------------------------
-- 8. anon-INSERT auf tournament_matches → ERRCODE 42501.
-- ---------------------------------------------------------------------

SELECT throws_ok(
  format($$
    INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round, status)
    VALUES (gen_random_uuid(), %L::uuid, 1, 99, 'scheduled')
  $$, (SELECT pub_tid FROM _pub_ctx)),
  '42501', NULL,
  'tournament_matches: anon-INSERT → 42501');

-- ---------------------------------------------------------------------
-- 9. View public_tournament_roster_view: existiert und exponiert keine
--    PII-Spalten (kein `email`, kein `user_id`, kein `nickname_hash`).
--    `pg_attribute` ist die Wahrheit fuer die View-Spaltenliste, weil
--    pg_views.viewdef nur den DDL-Text liefert.
-- ---------------------------------------------------------------------

SELECT _pub_as_postgres();

SELECT has_view('public', 'public_tournament_roster_view',
  'View public_tournament_roster_view existiert');

SELECT is(
  (SELECT count(*)::int
     FROM pg_attribute a
     JOIN pg_class c   ON c.oid = a.attrelid
     JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relname = 'public_tournament_roster_view'
      AND a.attnum > 0
      AND NOT a.attisdropped
      AND a.attname IN ('email','user_id','encrypted_password',
                        'nickname_hash','phone')),
  0,
  'public_tournament_roster_view: exponiert KEINE PII-Spalten');

SELECT * FROM finish();

ROLLBACK;
