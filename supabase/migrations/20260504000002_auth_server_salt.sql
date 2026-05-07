-- M2-T01 — Server-side salt for nickname hashing.
--
-- The salt is read by every keypair-auth function via
-- current_setting('auth.nickname_hash_salt', true) which falls back to
-- the value baked in below if the runtime setting is not present.
-- Production (Hetzner) overrides the setting via postgresql.conf or
-- ALTER DATABASE ... SET so the salt does not live in source.

-- Reference value used by local dev. The function below returns this
-- if the runtime setting is empty so dev environments work out of the
-- box. PROD MUST OVERRIDE.
CREATE OR REPLACE FUNCTION public.nickname_hash_salt() RETURNS text
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  configured text;
BEGIN
  configured := current_setting('auth.nickname_hash_salt', true);
  IF configured IS NULL OR length(configured) = 0 THEN
    -- Local-dev fallback. Fixed value so test fixtures are reproducible.
    -- The Hetzner deployment script sets `ALTER DATABASE ... SET
    -- auth.nickname_hash_salt = '<32-byte-base64>'` to a per-instance
    -- random secret.
    RETURN 'kubb-app-local-dev-nickname-salt-do-not-use-in-prod';
  END IF;
  RETURN configured;
END;
$$;

-- Helper used by the keypair endpoints (M2-T03 / M2-T04) to compute
-- the nickname_hash for inserts and lookups. Identical formula on both
-- the server and the Dart client (KeypairBackupRepository hashes the
-- nickname with the same salt fetched once on app start).
CREATE OR REPLACE FUNCTION public.compute_nickname_hash(p_nickname text)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = public, extensions
AS $$
BEGIN
  RETURN encode(
    digest(p_nickname || public.nickname_hash_salt(), 'sha256'),
    'base64'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.compute_nickname_hash(text)
  TO anon, authenticated;
