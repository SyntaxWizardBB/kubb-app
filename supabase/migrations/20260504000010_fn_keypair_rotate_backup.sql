-- M5-T10 follow-up — Rotate the encrypted keypair backup blob for the
-- current user (passphrase change). Mirrors the bytea-decoding pattern
-- of `keypair_attach` so the ciphertext column lands in the table as
-- raw binary, not as the literal bytes of a base64 string.
--
-- The previous implementation went through PostgREST's table upsert
-- with `base64Encode(...)` strings for the bytea columns. PostgREST
-- does NOT auto-decode base64 for bytea inputs, so the column ended up
-- holding the ASCII bytes of the base64 representation (~172 B for a
-- 128 B ciphertext). Restore then read those ASCII bytes back as the
-- ciphertext and the AEAD MAC failed — surfaced to the user as
-- "passphrase mismatch" right after a successful change.
--
-- The session ownership is enforced via auth.uid(); the function is
-- SECURITY DEFINER so it can write the row without depending on the
-- caller's RLS policy on user_keypair_backups (the policy still
-- requires user_id = auth.uid(), which we satisfy here).

CREATE OR REPLACE FUNCTION public.keypair_rotate_backup(
  p_nickname    text,
  p_ciphertext  text,
  p_kdf_salt    text,
  p_kdf_params  jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id       uuid;
  v_nickname_hash text;
  v_ciphertext    bytea;
  v_kdf_salt      bytea;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'keypair_rotate_backup requires an authenticated session'
      USING ERRCODE = '42501';
  END IF;

  v_ciphertext := decode(p_ciphertext, 'base64');
  v_kdf_salt   := decode(p_kdf_salt, 'base64');
  v_nickname_hash := public.compute_nickname_hash(p_nickname);

  INSERT INTO user_keypair_backups(
      user_id, nickname_hash, ciphertext, kdf_salt, kdf_params, updated_at)
    VALUES (
      v_user_id, v_nickname_hash, v_ciphertext, v_kdf_salt, p_kdf_params, now())
    ON CONFLICT (user_id) DO UPDATE
      SET nickname_hash = EXCLUDED.nickname_hash,
          ciphertext    = EXCLUDED.ciphertext,
          kdf_salt      = EXCLUDED.kdf_salt,
          kdf_params    = EXCLUDED.kdf_params,
          updated_at    = now();
END;
$$;

COMMENT ON FUNCTION public.keypair_rotate_backup IS
  'Replace the keypair backup blob for the current authenticated user. '
  'Used by passphrase rotation; signup uses keypair_attach instead.';

GRANT EXECUTE ON FUNCTION public.keypair_rotate_backup TO authenticated;
