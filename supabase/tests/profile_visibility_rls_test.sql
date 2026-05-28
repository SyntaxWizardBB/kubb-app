-- Sprint-C Worker W2-T1: Test-First-Spec fuer das geplante
-- `user_profiles.profile_visibility`-Feld plus die zugehoerigen
-- RLS-Policies. Implementation folgt in W2-T2 (Migration +
-- Policy-Refactor).
--
-- Refs: docs/bug-hunt-2026-q3/master-report.md
--   - R20-F-02 (Profile-Visibility-Settings fehlen komplett, FR-AUTH-5,
--     DSGVO Art. 25 Privacy-by-Default)
--   - R20-F-10 (Friends-only-Privacy nirgends umgesetzt, FR-SOCIAL-4,
--     Re-Hit aus R18-F-05)
--
-- Spec (zu liefern in W2-T2):
--   ALTER TABLE public.user_profiles
--     ADD COLUMN profile_visibility text NOT NULL DEFAULT 'friends_only'
--     CHECK (profile_visibility IN ('public','friends_only','private'));
--
--   - SELECT auf user_profiles richtet sich nach profile_visibility:
--       'public'        => jeder authenticated User darf lesen
--       'friends_only'  => Owner + accepted-friends duerfen lesen
--       'private'       => nur der Owner darf lesen
--   - anon-Caller bekommt direkt KEINE Profile (auch nicht 'public');
--     der Spectator-Pfad laeuft ausschliesslich ueber die `public_*`-RPCs
--     (ADR-0026 Strategie A).
--   - Match-Stats-Aggregat (Anzahl gespielter Matches eines Spielers)
--     respektiert die Visibility: Observer ohne Friend-Beziehung sieht
--     fuer 'friends_only'-User keinen Detail-Datensatz.
--
-- HINWEIS: Diese Tests sind RED gegen das aktuelle Schema. Die zugehoerige
-- Migration kommt in W2-T2 — siehe Commit-Message.
--
-- Pattern fuer Role-Switch + Fixture-Seed analog zu
-- `public_rls_test.sql` (das DDL-Skript laeuft als `postgres`-Superuser,
-- direkte INSERTs umgehen RLS).

BEGIN;

SELECT plan(5);

-- ---------------------------------------------------------------------
-- Helpers: Role-Switch.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _pv_as_user(p_uid uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _pv_as_anon() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
END;
$$;

CREATE OR REPLACE FUNCTION _pv_as_postgres() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
END;
$$;

-- Seed: legt einen auth.users-Eintrag plus user_profiles-Zeile an.
-- p_visibility wird in das (in W2-T2 zu liefernde) Feld geschrieben.
CREATE OR REPLACE FUNCTION _pv_seed_user(
  p_nick text,
  p_visibility text
) RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_uid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'pv-' || v_uid::text || '@test.local',
            '', now(), now(), now());

  -- profile_visibility kommt erst mit W2-T2 — der Insert ist hier so
  -- formuliert, dass er nach der Migration valide bleibt und vorher
  -- (rot) failed.
  INSERT INTO public.user_profiles(user_id, nickname, profile_visibility)
    VALUES (v_uid, p_nick, p_visibility);

  RETURN v_uid;
END;
$$;

-- Macht aus zwei Usern ein 'accepted'-Friends-Paar (kanonisch sortiert).
CREATE OR REPLACE FUNCTION _pv_make_friends(p_a uuid, p_b uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.friendships(
      low_user_id, high_user_id, status, requested_by,
      requested_at, accepted_at)
    VALUES (least(p_a, p_b), greatest(p_a, p_b),
            'accepted', p_a, now(), now());
END;
$$;

-- ---------------------------------------------------------------------
-- Fixtures.
--
--   private_user:     profile_visibility = 'private'
--   friends_user:     profile_visibility = 'friends_only'
--   public_user:      profile_visibility = 'public'
--   friend_of_friends_user:  accepted-friend von friends_user
--   stranger_user:    keine Friendship zu irgendwem
-- ---------------------------------------------------------------------

SELECT _pv_as_postgres();

DO $$
DECLARE
  v_private   uuid;
  v_friends   uuid;
  v_public    uuid;
  v_friend_of uuid;
  v_stranger  uuid;
BEGIN
  v_private   := _pv_seed_user('pv_private',   'private');
  v_friends   := _pv_seed_user('pv_friends',   'friends_only');
  v_public    := _pv_seed_user('pv_public',    'public');
  v_friend_of := _pv_seed_user('pv_friend_of', 'friends_only');
  v_stranger  := _pv_seed_user('pv_stranger',  'friends_only');

  PERFORM _pv_make_friends(v_friends, v_friend_of);

  CREATE TEMP TABLE _pv_ctx ON COMMIT DROP AS
    SELECT v_private   AS private_uid,
           v_friends   AS friends_uid,
           v_public    AS public_uid,
           v_friend_of AS friend_of_uid,
           v_stranger  AS stranger_uid;
END $$;

-- ---------------------------------------------------------------------
-- Test 1: profile_visibility = 'private'
--   Ein fremder authenticated-User darf das Profil NICHT lesen.
-- ---------------------------------------------------------------------

SELECT _pv_as_user((SELECT stranger_uid FROM _pv_ctx));

SELECT is(
  (SELECT count(*)::int FROM public.user_profiles
     WHERE user_id = (SELECT private_uid FROM _pv_ctx)),
  0,
  'private: fremder User sieht kein private-Profil');

-- ---------------------------------------------------------------------
-- Test 2: profile_visibility = 'friends_only'
--   - accepted-friend sieht die Row
--   - Nicht-Friend sieht die Row NICHT
-- ---------------------------------------------------------------------

-- Wir messen beide Beobachtungen (Friend sieht Row, Stranger nicht) und
-- aggregieren sie zu EINEM Plan-Datensatz: 1 + 0 = 1. Die Counts kommen
-- in eine TEMP-Tabelle, die noch unter `postgres` angelegt wird (damit
-- die `authenticated`-Rolle keine TEMP-Schema-Privilegien braucht); die
-- INSERTs laufen dann jeweils im richtigen Rollen-Kontext.

SELECT _pv_as_postgres();

CREATE TEMP TABLE _pv_t2_counts (label text PRIMARY KEY, n int)
  ON COMMIT DROP;
GRANT INSERT, SELECT ON _pv_t2_counts TO authenticated, anon;

-- Friend liest erfolgreich (count = 1).
SELECT _pv_as_user((SELECT friend_of_uid FROM _pv_ctx));

INSERT INTO _pv_t2_counts(label, n)
  SELECT 'friend',
         (SELECT count(*)::int FROM public.user_profiles
            WHERE user_id = (SELECT friends_uid FROM _pv_ctx));

-- Stranger liest dieselbe Row und sieht NICHTS (count = 0).
SELECT _pv_as_user((SELECT stranger_uid FROM _pv_ctx));

INSERT INTO _pv_t2_counts(label, n)
  SELECT 'stranger',
         (SELECT count(*)::int FROM public.user_profiles
            WHERE user_id = (SELECT friends_uid FROM _pv_ctx));

SELECT _pv_as_postgres();

SELECT is(
  (SELECT sum(n)::int FROM _pv_t2_counts),
  1,
  'friends_only: Friend sieht Row (1), Nicht-Friend sieht sie nicht (0)');

-- ---------------------------------------------------------------------
-- Test 3: profile_visibility = 'public'
--   Jeder authenticated-User (auch ohne Friendship) darf das Profil lesen.
-- ---------------------------------------------------------------------

SELECT _pv_as_user((SELECT stranger_uid FROM _pv_ctx));

SELECT is(
  (SELECT count(*)::int FROM public.user_profiles
     WHERE user_id = (SELECT public_uid FROM _pv_ctx)),
  1,
  'public: jeder authenticated User sieht ein public-Profil');

-- ---------------------------------------------------------------------
-- Test 4: anon-Caller
--   Direkter SELECT auf user_profiles ist fuer anon IMMER deny —
--   auch bei profile_visibility = 'public'. Der oeffentliche Lesepfad
--   laeuft ausschliesslich ueber die `public_*`-RPC-Schiene
--   (ADR-0026 Strategie A).
-- ---------------------------------------------------------------------

SELECT _pv_as_anon();

SELECT is(
  (SELECT count(*)::int FROM public.user_profiles
     WHERE user_id IN (
       (SELECT private_uid FROM _pv_ctx),
       (SELECT friends_uid FROM _pv_ctx),
       (SELECT public_uid  FROM _pv_ctx)
     )),
  0,
  'anon: direkter Table-Read auf user_profiles bleibt deny, '
  'auch fuer public-Profile (RPC-Pfad ist die einzige Quelle)');

-- ---------------------------------------------------------------------
-- Test 5: Match-Stats-Aggregat respektiert profile_visibility
--
--   Setup: ein finalized Match mit DREI Participants im selben Spiel —
--     - friends_uid (profile_visibility = 'friends_only')
--     - friend_of_uid (accepted-friend von friends_uid)
--     - stranger_uid (Observer, kein Friend von friends_uid)
--   Stranger ist also selbst Match-Participant und darf die matches-Row
--   sowie alle match_participants-Rows sehen (matches_participant_read-
--   Policy). Aber: der Detail-Datensatz fuer die Stats-Anzeige des
--   friends_uid haengt am JOIN auf user_profiles, und diese Row ist
--   fuer stranger_uid durch die Visibility-Policy geblockt.
--
--   Erwartung: das Aggregat enthaelt 0 Detail-Records fuer friends_uid,
--   obwohl der Match an sich sichtbar ist.
-- ---------------------------------------------------------------------

SELECT _pv_as_postgres();

DO $$
DECLARE
  v_match uuid := gen_random_uuid();
  v_friends  uuid := (SELECT friends_uid   FROM _pv_ctx);
  v_other    uuid := (SELECT friend_of_uid FROM _pv_ctx);
  v_observer uuid := (SELECT stranger_uid  FROM _pv_ctx);
BEGIN
  INSERT INTO public.matches(
      id, created_by, format, scoring, status, current_round,
      winner_team_id, final_score_a, final_score_b,
      started_at, completed_at)
    VALUES (v_match, v_friends, 'bo1', 'wins', 'finalized', 1,
            'A', 1, 0, now(), now());

  INSERT INTO public.match_teams(match_id, team_id, display_name)
    VALUES (v_match, 'A', 'Team-A'),
           (v_match, 'B', 'Team-B');

  -- 2v1-Splitting: friends + friend_of bilden Team A, stranger Team B.
  -- Das macht den Test robust unabhaengig vom konkreten Match-Format.
  INSERT INTO public.match_participants(
      match_id, team_id, kind, user_id,
      invitation_status, joined_at, responded_at)
    VALUES (v_match, 'A', 'in_app', v_friends,
            'accepted', now(), now()),
           (v_match, 'A', 'in_app', v_other,
            'accepted', now(), now()),
           (v_match, 'B', 'in_app', v_observer,
            'accepted', now(), now());
END $$;

-- Observer = stranger_uid. Aggregat = Detail-Datensaetze pro Spieler,
-- joined ueber user_profiles fuer den Display-Pfad (so wie die Match-
-- Stats-Surfaces sie heute lesen — Nickname kommt aus user_profiles).
-- Erwartung: friends_uid taucht NICHT auf, weil seine user_profiles-Row
-- fuer stranger_uid durch die Visibility-Policy geblockt wird.
SELECT _pv_as_user((SELECT stranger_uid FROM _pv_ctx));

SELECT is(
  (SELECT count(*)::int
     FROM public.matches m
     JOIN public.match_participants mp ON mp.match_id = m.id
     JOIN public.user_profiles up      ON up.user_id  = mp.user_id
    WHERE m.status = 'finalized'
      AND up.user_id = (SELECT friends_uid FROM _pv_ctx)),
  0,
  'match-stats: Observer ohne Friend-Beziehung sieht keinen '
  'Match-Stats-Detail eines friends_only-Users');

SELECT * FROM finish();

ROLLBACK;
