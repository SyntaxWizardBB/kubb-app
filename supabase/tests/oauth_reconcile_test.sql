-- pgTAP für die OAuth-Reconcile-Migration (ADR-0042, TASK-M01).
--
-- Deckt die DB-Invarianten aus
-- docs/plans/oauth-account-link/architecture.md §Migration ab:
--   1. Partieller Unique-Index (user_id, kind) weist eine zweite
--      oauth_google-Zeile für denselben User ab (23505).
--   2. reconcile_link_oauth raised 22023 bei ungültigem kind.
--   3. reconcile_link_oauth raised 23505/OAUTH_SUBJECT_IN_USE, wenn das
--      Subject schon an einen ANDEREN User gebunden ist, und löscht
--      dabei NICHTS.
--   4. Happy-Path: INSERT der oauth-Credential gegen den Keypair-User
--      UND DELETE der geforkten auth.users-Zeile in einem Call,
--      forked_user_deleted = true.
--   5. EXECUTE ist anon/authenticated NICHT gewährt.
--
-- auth.users-Fixtures werden direkt als postgres geseedet
-- (Fixture-Pattern aus season_rls.test.sql).

CREATE EXTENSION IF NOT EXISTS pgtap;

BEGIN;

SELECT plan(9);

-- Seedet eine auth.users-Zeile und liefert ihre id zurück.
CREATE OR REPLACE FUNCTION _ore_seed_user(p_label text)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE
  v_uid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            p_label || '-' || v_uid::text || '@test.local',
            '', now(), now(), now());
  RETURN v_uid;
END;
$$;

DO $$
DECLARE
  v_keypair uuid;
  v_forked  uuid;
  v_other   uuid;
BEGIN
  v_keypair := _ore_seed_user('keypair');
  v_forked  := _ore_seed_user('forked');
  v_other   := _ore_seed_user('other');

  -- Keypair-Credential für den Ziel-User.
  INSERT INTO public.user_credentials(user_id, kind, public_key)
    VALUES (v_keypair, 'keypair', 'pubkey-' || v_keypair::text);

  CREATE TEMP TABLE _ore_ctx ON COMMIT DROP AS
    SELECT v_keypair AS keypair_uid,
           v_forked  AS forked_uid,
           v_other   AS other_uid;
  GRANT SELECT ON _ore_ctx TO anon, authenticated;
END $$;

-- 1. Partieller Unique-Index: erste oauth_google-Zeile geht durch.
SELECT lives_ok(
  format($$
    INSERT INTO public.user_credentials(user_id, kind, oauth_subject)
    VALUES (%L::uuid, 'oauth_google', 'sub-one')
  $$, (SELECT keypair_uid FROM _ore_ctx)),
  'erste oauth_google-Zeile pro User ist erlaubt');

-- 2. Zweite oauth_google-Zeile für denselben User wird abgewiesen (23505).
SELECT throws_ok(
  format($$
    INSERT INTO public.user_credentials(user_id, kind, oauth_subject)
    VALUES (%L::uuid, 'oauth_google', 'sub-two')
  $$, (SELECT keypair_uid FROM _ore_ctx)),
  '23505', NULL,
  'zweite oauth_google-Zeile pro User wird vom Partial-Index abgewiesen');

-- Aufräumen, damit die RPC-Happy-Path-Cases auf sauberem Stand starten.
DELETE FROM public.user_credentials
  WHERE user_id = (SELECT keypair_uid FROM _ore_ctx)
    AND kind = 'oauth_google';

-- 3. RPC raised 22023 bei ungültigem kind.
SELECT throws_ok(
  format($$
    SELECT public.reconcile_link_oauth(%L::uuid, 'oauth_github',
                                       'sub-bad', %L::uuid)
  $$, (SELECT keypair_uid FROM _ore_ctx),
      (SELECT forked_uid FROM _ore_ctx)),
  '22023', NULL,
  'reconcile_link_oauth raised 22023 bei unbekanntem kind');

-- 4. Subject schon an anderen User gebunden -> 23505, kein Delete.
--    Vorbedingung: other_uid hält sub-shared.
INSERT INTO public.user_credentials(user_id, kind, oauth_subject)
  SELECT other_uid, 'oauth_google', 'sub-shared' FROM _ore_ctx;

SELECT throws_ok(
  format($$
    SELECT public.reconcile_link_oauth(%L::uuid, 'oauth_google',
                                       'sub-shared', %L::uuid)
  $$, (SELECT keypair_uid FROM _ore_ctx),
      (SELECT forked_uid FROM _ore_ctx)),
  '23505', NULL,
  'reconcile_link_oauth raised 23505, wenn Subject einem anderen User gehört');

-- 4b. Der Collision-Block hat NICHTS gelöscht: forked_uid lebt noch.
SELECT is(
  (SELECT count(*)::int FROM auth.users
     WHERE id = (SELECT forked_uid FROM _ore_ctx)),
  1,
  'Collision-Block löscht den geforkten User NICHT');

-- 4c. Es wurde keine Credential gegen den Keypair-User geschrieben.
SELECT is(
  (SELECT count(*)::int FROM public.user_credentials
     WHERE user_id = (SELECT keypair_uid FROM _ore_ctx)
       AND kind = 'oauth_google'),
  0,
  'Collision-Block schreibt keine Credential gegen den Keypair-User');

-- 5. Happy-Path: Credential gegen Keypair-User + Delete des geforkten
--    Users in einem Call, forked_user_deleted = true.
SELECT is(
  (SELECT public.reconcile_link_oauth(
            (SELECT keypair_uid FROM _ore_ctx), 'oauth_google',
            'sub-happy', (SELECT forked_uid FROM _ore_ctx))
   ->> 'forked_user_deleted'),
  'true',
  'Happy-Path: reconcile gibt forked_user_deleted=true zurück');

-- 5b. Nach dem Happy-Path: Credential existiert gegen den Keypair-User
--     UND die geforkte auth.users-Zeile ist weg.
SELECT is(
  (SELECT count(*)::int FROM public.user_credentials
     WHERE user_id = (SELECT keypair_uid FROM _ore_ctx)
       AND kind = 'oauth_google'
       AND oauth_subject = 'sub-happy')
  +
  (SELECT count(*)::int FROM auth.users
     WHERE id = (SELECT forked_uid FROM _ore_ctx)),
  1,
  'Happy-Path: Credential gegen Keypair-User da, geforkte auth.users-Zeile weg');

-- 6. EXECUTE ist anon/authenticated NICHT gewährt (nur service_role).
SELECT ok(
  NOT has_function_privilege('anon',
    'public.reconcile_link_oauth(uuid,text,text,uuid)', 'EXECUTE')
  AND NOT has_function_privilege('authenticated',
    'public.reconcile_link_oauth(uuid,text,text,uuid)', 'EXECUTE'),
  'reconcile_link_oauth ist anon/authenticated nicht grantet');

SELECT * FROM finish();

ROLLBACK;
