-- Roster-View Publicity-Filter + security_invoker (Migration 20261311000000).
--
-- Schliesst das Leck aus 20260701000002: public_tournament_roster_view zeigte
-- anon die display_names aller Roster-Slots, auch von draft-/private-Turnieren.
-- Nach dem Fix:
--   A1 — draft ODER public=false mit aktivem Slot 'X' → anon sieht 'X' NICHT.
--   A2 — public=true + status='live' mit Slot 'Y' → 'Y' erscheint.
--   A3 — Slot mit replaced_at IS NOT NULL in public/live → erscheint NICHT.
--   A4 — pg_class.reloptions der View enthaelt 'security_invoker=true'.
--   A5 — public_tournament_get(public/live tid) als anon → roster[] enthaelt
--        die Slots wie vorher (keine Regression durch security_invoker).
--   B1 — player_ratings: anon sieht 'tournament'-Rating, NICHT 'personal'.
--
-- Lese-Pfad fuer A1/A2/A3: security_invoker = true sperrt den direkten
-- anon-View-Read (kein SELECT-Grant auf tournament_roster_slots), daher wird
-- ueber die SECURITY DEFINER RPC public_tournament_get gelesen — exakt der
-- Soll-Pfad nach ADR-0026. Rollen-Switch via set_config('role', ...), Pattern
-- aus public_rls_test.sql.

BEGIN;

SELECT plan(8);

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _rv_as_anon() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
END;
$$;

CREATE OR REPLACE FUNCTION _rv_as_postgres() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
END;
$$;

-- Seedet ein Turnier mit gegebenem public-Flag + status, einen Team-
-- Participant und einen aktiven Roster-Slot, dessen display_name aus
-- user_profiles.nickname = p_name aufgeloest wird. Gibt die tournament_id
-- zurueck. Direct-Insert laeuft als postgres und umgeht RLS.
CREATE OR REPLACE FUNCTION _rv_seed(p_public boolean, p_status text, p_name text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_tid  uuid := gen_random_uuid();
  v_uid  uuid := gen_random_uuid();
  v_team uuid := gen_random_uuid();
  v_pid  uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'rv-' || v_uid::text || '@test.local',
            '', now(), now(), now());

  INSERT INTO public.user_profiles(user_id, nickname)
    VALUES (v_uid, p_name)
    ON CONFLICT (user_id) DO UPDATE SET nickname = excluded.nickname;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, v_uid, 'RV-' || v_tid::text, 2, 2, 16,
            'round_robin', 'ekc', '{"format":"best_of_1"}'::jsonb,
            p_status, p_public);

  INSERT INTO public.teams(id, display_name, created_by)
    VALUES (v_team, 'RV-Team-' || v_team::text, v_uid);

  INSERT INTO public.tournament_participants(
      id, tournament_id, team_id, registration_status)
    VALUES (v_pid, v_tid, v_team, 'confirmed');

  INSERT INTO public.tournament_roster_slots(
      participant_id, slot_index, member_user_id)
    VALUES (v_pid, 1, v_uid);

  RETURN v_tid;
END;
$$;

-- ---------------------------------------------------------------------
-- Fixtures
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_draft   uuid;
  v_private uuid;
  v_live    uuid;
  v_replaced uuid;
  v_repl_pid uuid;
BEGIN
  -- draft: niemals sichtbar
  v_draft   := _rv_seed(true,  'draft', 'DRAFT_X');
  -- public=false, status live: niemals sichtbar
  v_private := _rv_seed(false, 'live',  'PRIVATE_X');
  -- public=true, live: sichtbar
  v_live    := _rv_seed(true,  'live',  'LIVE_Y');

  -- public=true, live, aber Slot ist replaced_at IS NOT NULL → nicht sichtbar.
  v_replaced := _rv_seed(true, 'live',  'REPLACED_Z');
  SELECT tp.id INTO v_repl_pid
    FROM public.tournament_participants tp
   WHERE tp.tournament_id = v_replaced
   LIMIT 1;
  UPDATE public.tournament_roster_slots
     SET replaced_at = now()
   WHERE participant_id = v_repl_pid;

  CREATE TEMP TABLE _rv_ctx ON COMMIT DROP AS
    SELECT v_draft AS draft_tid, v_private AS private_tid,
           v_live AS live_tid, v_replaced AS replaced_tid;
  GRANT SELECT ON _rv_ctx TO anon;
END $$;

-- ---------------------------------------------------------------------
-- A1 — Leck zu: draft → anon sieht 'DRAFT_X' NICHT (via RPC roster[]).
--      public=false → anon sieht 'PRIVATE_X' NICHT.
-- ---------------------------------------------------------------------

SELECT _rv_as_anon();

SELECT is(
  (SELECT count(*)::int
     FROM jsonb_array_elements(
            public.public_tournament_get((SELECT draft_tid FROM _rv_ctx)) -> 'roster'
          ) elem
    WHERE elem ->> 'display_name' = 'DRAFT_X'),
  0,
  'A1a: anon sieht Roster-Slot eines draft-Turniers NICHT');

SELECT is(
  public.public_tournament_get((SELECT private_tid FROM _rv_ctx)),
  NULL,
  'A1b: public_tournament_get fuer public=false-Turnier → NULL (kein Roster-Leck)');

-- ---------------------------------------------------------------------
-- A2 — public=true + live: 'LIVE_Y' erscheint im roster[].
-- ---------------------------------------------------------------------

SELECT is(
  (SELECT count(*)::int
     FROM jsonb_array_elements(
            public.public_tournament_get((SELECT live_tid FROM _rv_ctx)) -> 'roster'
          ) elem
    WHERE elem ->> 'display_name' = 'LIVE_Y'),
  1,
  'A2: anon sieht Roster-Slot eines public/live-Turniers');

-- ---------------------------------------------------------------------
-- A3 — replaced_at IS NOT NULL in public/live → erscheint NICHT.
-- ---------------------------------------------------------------------

SELECT is(
  (SELECT count(*)::int
     FROM jsonb_array_elements(
            public.public_tournament_get((SELECT replaced_tid FROM _rv_ctx)) -> 'roster'
          ) elem
    WHERE elem ->> 'display_name' = 'REPLACED_Z'),
  0,
  'A3: replaced_at-Slot erscheint NICHT im Roster');

-- ---------------------------------------------------------------------
-- A4 — security_invoker = true ist auf der View gesetzt.
-- ---------------------------------------------------------------------

SELECT _rv_as_postgres();

SELECT ok(
  EXISTS (
    SELECT 1
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public'
       AND c.relname = 'public_tournament_roster_view'
       AND c.reloptions @> ARRAY['security_invoker=true']
  ),
  'A4: View reloptions enthaelt security_invoker=true');

-- ---------------------------------------------------------------------
-- A5 — RPC-Regression: public_tournament_get(public/live) liefert ein
--      nicht-leeres roster[] (keine Regression durch security_invoker).
-- ---------------------------------------------------------------------

SELECT _rv_as_anon();

SELECT cmp_ok(
  (SELECT jsonb_array_length(
            public.public_tournament_get((SELECT live_tid FROM _rv_ctx)) -> 'roster'
          )),
  '>=', 1,
  'A5: public_tournament_get(public/live) liefert nicht-leeres roster[]');

-- ---------------------------------------------------------------------
-- B1 — player_ratings: anon sieht 'tournament'-Rating, NICHT 'personal'.
--      Disziplin-RLS aus 20261221000000 unveraendert.
-- ---------------------------------------------------------------------

SELECT _rv_as_postgres();

DO $$
DECLARE v_uid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'rvrate-' || v_uid::text || '@test.local',
            '', now(), now(), now());
  INSERT INTO public.player_ratings(user_id, discipline, elo)
    VALUES (v_uid, 'tournament', 1500),
           (v_uid, 'personal',   1700);
  CREATE TEMP TABLE _rv_rate ON COMMIT DROP AS SELECT v_uid AS uid;
  GRANT SELECT ON _rv_rate TO anon;
END $$;

SELECT _rv_as_anon();

SELECT is(
  (SELECT count(*)::int FROM public.player_ratings
     WHERE user_id = (SELECT uid FROM _rv_rate)
       AND discipline = 'tournament'),
  1,
  'B1a: anon sieht die tournament-ELO');

SELECT is(
  (SELECT count(*)::int FROM public.player_ratings
     WHERE user_id = (SELECT uid FROM _rv_rate)
       AND discipline = 'personal'),
  0,
  'B1b: anon sieht die personal-ELO NICHT');

SELECT * FROM finish();

ROLLBACK;
