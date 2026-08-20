-- ADR-0044 (P8) block P1, PN-02: the two token-registry write RPCs.
--
-- Both are SECURITY DEFINER and derive user_id from auth.uid(), never from a
-- parameter — so a signed-in user can only ever register or delete a token
-- against their own id. This is the same guard rationale as keypair_register
-- (20260504000011): the identity comes from the session, not the caller.
--
-- GRANT EXECUTE ... TO authenticated is the whole client write surface for
-- push_tokens; the table itself has no client-facing INSERT/UPDATE/DELETE
-- policy (see 20261330000000).

-- ---- push_token_upsert -------------------------------------------------
--
-- Upsert on (user_id, device_id): the stable target across token rotation.
-- Before writing, it steals the token from any OTHER user's row that still
-- carries it — the account-switch case where the same physical device was
-- previously signed into a different account. Without that steal the
-- UNIQUE(token) index would reject the upsert. The steal is scoped to a
-- different user_id so a plain rotation on the same account never deletes
-- the row it is about to update.

CREATE OR REPLACE FUNCTION public.push_token_upsert(
  p_device_id text,
  p_token     text,
  p_platform  text DEFAULT 'android'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_id      uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'push_token_upsert requires an authenticated session'
      USING ERRCODE = '42501';
  END IF;

  IF p_platform NOT IN ('android', 'ios') THEN
    RAISE EXCEPTION 'invalid push platform: %', p_platform
      USING ERRCODE = '22023';
  END IF;

  -- Account switch on the same device: reclaim the token from a foreign user.
  DELETE FROM push_tokens
    WHERE token = p_token
      AND user_id <> v_user_id;

  INSERT INTO push_tokens(user_id, device_id, token, platform)
    VALUES (v_user_id, p_device_id, p_token, p_platform)
    ON CONFLICT (user_id, device_id) DO UPDATE
      SET token      = EXCLUDED.token,
          platform   = EXCLUDED.platform,
          updated_at = now()
    RETURNING id INTO v_id;

  RETURN v_id;
END;
$$
;

COMMENT ON FUNCTION public.push_token_upsert IS
  'ADR-0044 P8 (PN-02): register/rotate the current device''s FCM token. '
  'user_id from auth.uid(); upsert on (user_id, device_id); steals the token '
  'from a foreign user on the same device (account switch).'
;

GRANT EXECUTE ON FUNCTION public.push_token_upsert TO authenticated
;

-- ---- push_token_delete -------------------------------------------------
--
-- Deletes only the caller's own device row. Called best-effort at sign-out
-- while the session (and thus auth.uid()) still stands. A device_id that
-- belongs to another user is untouched: the WHERE pins user_id = auth.uid().

CREATE OR REPLACE FUNCTION public.push_token_delete(
  p_device_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'push_token_delete requires an authenticated session'
      USING ERRCODE = '42501';
  END IF;

  DELETE FROM push_tokens
    WHERE user_id = v_user_id
      AND device_id = p_device_id;
END;
$$
;

COMMENT ON FUNCTION public.push_token_delete IS
  'ADR-0044 P8 (PN-02): delete the caller''s own device token row at sign-out. '
  'Scoped to user_id = auth.uid() AND device_id — never touches a foreign '
  'device.'
;

GRANT EXECUTE ON FUNCTION public.push_token_delete TO authenticated
;

