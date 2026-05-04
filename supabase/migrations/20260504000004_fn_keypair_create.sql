-- M2-T03 — Create a new keypair-backed account.
--
-- Caller flow (per ADR-0010 §AK-1):
--   1. Client calls supabase.auth.signInAnonymously() → obtains an
--      auth.uid() session for the anonymous user that GoTrue created.
--   2. Client locally generates the Ed25519 keypair and Argon2id-derives
--      the backup-encryption key from the user-chosen passphrase.
--   3. Client calls this RPC, passing nickname, public_key (base64), and
--      the encrypted private-key blob (ciphertext, kdf_salt, kdf_params).
--   4. This function attaches the credential row, registers the
--      keypair backup, and seeds the user_profiles row in one
--      transaction.
--
-- The session token returned to the caller is the one GoTrue issued
-- in step 1. We do not mint a new JWT here — that would require
-- access to the JWT secret, which is owned by GoTrue, not the
-- database. The "anonymous-then-attach" pattern keeps token issuance
-- inside Supabase's own auth path.
--
-- TODO(hetzner-integration): if Supabase rejects an anonymous session
-- being upgraded by attaching credentials, we fall back to an edge
-- function that uses the service-role key to create the auth.users
-- row and mint the JWT in one shot.

CREATE OR REPLACE FUNCTION auth.keypair_attach(
  p_nickname        text,
  p_public_key      text,
  p_ciphertext      bytea,
  p_kdf_salt        bytea,
  p_kdf_params      jsonb,
  p_avatar_color    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_nickname_hash text;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'keypair_attach requires an authenticated session'
      USING ERRCODE = '42501';
  END IF;

  -- Server-side validation. The client validates too but we are the
  -- authority for the unique constraints.
  IF length(p_nickname) < 3 OR length(p_nickname) > 30 THEN
    RAISE EXCEPTION 'nickname length must be between 3 and 30 chars'
      USING ERRCODE = '22023';
  END IF;
  IF p_nickname !~ '^[A-Za-z0-9_-]+$' THEN
    RAISE EXCEPTION 'nickname may only contain alphanumerics, _ and -'
      USING ERRCODE = '22023';
  END IF;

  v_nickname_hash := auth.compute_nickname_hash(p_nickname);

  -- All three inserts in one transaction so a partial registration
  -- never leaves orphan rows. Postgres functions are transactional
  -- by default unless they explicitly call COMMIT.
  INSERT INTO user_credentials(user_id, kind, public_key)
    VALUES (v_user_id, 'keypair', p_public_key);

  INSERT INTO user_keypair_backups(
      user_id, nickname_hash, ciphertext, kdf_salt, kdf_params)
    VALUES (
      v_user_id, v_nickname_hash, p_ciphertext, p_kdf_salt, p_kdf_params);

  INSERT INTO user_profiles(user_id, nickname, avatar_color)
    VALUES (v_user_id, p_nickname, p_avatar_color)
    ON CONFLICT (user_id) DO UPDATE
      SET nickname = EXCLUDED.nickname,
          avatar_color = EXCLUDED.avatar_color;

  RETURN jsonb_build_object(
    'user_id', v_user_id,
    'nickname', p_nickname,
    'kind', 'keypair'
  );
END;
$$;

COMMENT ON FUNCTION auth.keypair_attach IS
  'Attach a keypair credential and encrypted backup to the current '
  'anonymous Supabase session. Caller must signInAnonymously() first.';

-- Anyone with a valid (anonymous or authenticated) Supabase session
-- may call this RPC. RLS on the underlying tables is bypassed via
-- SECURITY DEFINER but only for the rows scoped to auth.uid().
GRANT EXECUTE ON FUNCTION auth.keypair_attach TO anon, authenticated;
