-- W3-T3 (Sprint-A): pgTAP-Tests fuer den anon-Spectator-RPC-Pfad nach
-- ADR-0026 Strategie A. Primaerer Read-Pfad fuer anon ist seit dieser
-- Wave `public_tournament_get` / `public_tournament_match_get` aus
-- Migration 20260901000001.
--
-- Cases:
--   1. public_tournament_get(<public-id>) als anon → jsonb nicht-null.
--   2. public_tournament_get(<non-public-id>) als anon → NULL.
--   3. public_tournament_get(<draft-id>) als anon → NULL.
--   4. Envelope-Inhalt: matches[] ist ein Array, roster vorhanden, kein
--      audit_tail, kein created_by im tournament-Header.
--   5. public_tournament_match_get(<public-match-id>) als anon →
--      jsonb nicht-null, kein set_score_proposals.
--   6. public_tournament_match_get(<non-public-match-id>) als anon →
--      NULL.
--   7. public_tournament_get als postgres-Superuser funktioniert (Sanity).
--   8. Envelope enthaelt keinen der Strings `user_id`, `email`,
--      `created_by` (Privacy-Grep auf der jsonb-Textform).
--
-- Rollen-Switch: `set_config('role', 'anon', true)`. Die Helper sind
-- bewusst aus `public_rls_test.sql` dupliziert — beide Test-Files laufen
-- in eigenen BEGIN/ROLLBACK-Transaktionen, in denen die `CREATE OR
-- REPLACE FUNCTION ...`-Eintraege isoliert sind.
--
-- Sources: ADR-0026, docs/plans/sprint-a-bug-fix/anon-rls-plan.md T5.

BEGIN;

SELECT plan(8);

-- ---------------------------------------------------------------------
-- Helpers (kopiert aus public_rls_test.sql).
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _pubrpc_as_anon() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
END;
$$;

CREATE OR REPLACE FUNCTION _pubrpc_as_postgres() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
END;
$$;

-- Legt ein Tournament mit einstellbarem `public`-Flag und `status` an,
-- inklusive einem Participant + einem `live`-Match.
CREATE OR REPLACE FUNCTION _pubrpc_seed_tournament(
  p_public boolean,
  p_status text DEFAULT 'live'
)
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
            'pubrpc-' || v_uid::text || '@test.local',
            '', now(), now(), now());

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, v_uid, 'Public-RPC-Test', 1, 2, 16,
            'round_robin', 'ekc', '{"format":"best_of_1"}'::jsonb,
            p_status, p_public);

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
-- Fixtures: public-live, non-public-live, public-draft.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_pub_tid     uuid;
  v_non_pub_tid uuid;
  v_draft_tid   uuid;
  v_pub_match   uuid;
  v_non_pub_mid uuid;
BEGIN
  v_pub_tid     := _pubrpc_seed_tournament(true,  'live');
  v_non_pub_tid := _pubrpc_seed_tournament(false, 'live');
  v_draft_tid   := _pubrpc_seed_tournament(true,  'draft');

  SELECT id INTO v_pub_match
    FROM public.tournament_matches
   WHERE tournament_id = v_pub_tid
   LIMIT 1;

  SELECT id INTO v_non_pub_mid
    FROM public.tournament_matches
   WHERE tournament_id = v_non_pub_tid
   LIMIT 1;

  CREATE TEMP TABLE _pubrpc_ctx ON COMMIT DROP AS
    SELECT v_pub_tid     AS pub_tid,
           v_non_pub_tid AS non_pub_tid,
           v_draft_tid   AS draft_tid,
           v_pub_match   AS pub_mid,
           v_non_pub_mid AS non_pub_mid;
END $$;

-- ---------------------------------------------------------------------
-- 1. anon: public_tournament_get(<public>) → jsonb nicht-null.
-- ---------------------------------------------------------------------

SELECT _pubrpc_as_anon();

SELECT isnt(
  public.public_tournament_get((SELECT pub_tid FROM _pubrpc_ctx)),
  NULL,
  'public_tournament_get: anon bekommt envelope fuer public, live tournament');

-- ---------------------------------------------------------------------
-- 2. anon: public_tournament_get(<non-public>) → NULL.
-- ---------------------------------------------------------------------

SELECT is(
  public.public_tournament_get((SELECT non_pub_tid FROM _pubrpc_ctx)),
  NULL,
  'public_tournament_get: anon bekommt NULL fuer non-public tournament');

-- ---------------------------------------------------------------------
-- 3. anon: public_tournament_get(<draft>) → NULL.
-- ---------------------------------------------------------------------

SELECT is(
  public.public_tournament_get((SELECT draft_tid FROM _pubrpc_ctx)),
  NULL,
  'public_tournament_get: anon bekommt NULL fuer draft tournament');

-- ---------------------------------------------------------------------
-- 4. Envelope-Inhalt: matches[] ist Array, roster vorhanden, kein
--    audit_tail, kein created_by im tournament-Header.
-- ---------------------------------------------------------------------

SELECT ok(
  (
    WITH env AS (
      SELECT public.public_tournament_get((SELECT pub_tid FROM _pubrpc_ctx))
               AS j
    )
    SELECT jsonb_typeof((SELECT j FROM env) -> 'matches') = 'array'
       AND ((SELECT j FROM env) ? 'roster')
       AND NOT ((SELECT j FROM env) ? 'audit_tail')
       AND NOT ((SELECT j -> 'tournament' FROM env) ? 'created_by')
  ),
  'public_tournament_get: envelope hat matches[]+roster, kein audit_tail / created_by');

-- ---------------------------------------------------------------------
-- 5. anon: public_tournament_match_get(<public-match>) → jsonb nicht-
--    null, kein set_score_proposals.
-- ---------------------------------------------------------------------

SELECT ok(
  (
    WITH env AS (
      SELECT public.public_tournament_match_get(
               (SELECT pub_mid FROM _pubrpc_ctx)) AS j
    )
    SELECT (SELECT j FROM env) IS NOT NULL
       AND NOT ((SELECT j FROM env) ? 'set_score_proposals')
  ),
  'public_tournament_match_get: anon bekommt envelope ohne set_score_proposals');

-- ---------------------------------------------------------------------
-- 6. anon: public_tournament_match_get(<non-public-match>) → NULL.
-- ---------------------------------------------------------------------

SELECT is(
  public.public_tournament_match_get((SELECT non_pub_mid FROM _pubrpc_ctx)),
  NULL,
  'public_tournament_match_get: anon bekommt NULL fuer match of non-public tournament');

-- ---------------------------------------------------------------------
-- 7. Sanity: postgres-Superuser kann die RPC ebenfalls aufrufen.
-- ---------------------------------------------------------------------

SELECT _pubrpc_as_postgres();

SELECT isnt(
  public.public_tournament_get((SELECT pub_tid FROM _pubrpc_ctx)),
  NULL,
  'public_tournament_get: postgres-Superuser bekommt envelope (sanity)');

-- ---------------------------------------------------------------------
-- 8. Privacy-Grep: envelope-Text enthaelt keine PII-Strings.
--    Wir suchen nach den Spalten-Strings im jsonb::text — wenn der
--    Decoder z.B. created_by jemals hinzufuegen wuerde, schlaegt das
--    hier auf.
-- ---------------------------------------------------------------------

SELECT _pubrpc_as_anon();

SELECT ok(
  (
    WITH env AS (
      SELECT public.public_tournament_get((SELECT pub_tid FROM _pubrpc_ctx))::text
               AS t
    )
    SELECT position('"user_id"'    IN (SELECT t FROM env)) = 0
       AND position('"created_by"' IN (SELECT t FROM env)) = 0
       AND position('"email"'      IN (SELECT t FROM env)) = 0
       AND position('"audit_tail"' IN (SELECT t FROM env)) = 0
  ),
  'public_tournament_get: envelope-Text enthaelt keine user_id / created_by / email / audit_tail Keys');

SELECT * FROM finish();

ROLLBACK;
