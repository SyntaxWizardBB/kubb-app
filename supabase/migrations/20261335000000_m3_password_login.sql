-- Auth-Redesign M3 (Block A) — username+password login (GoTrue-native).
--
-- Spec docs/specs/auth-redesign-admin-onboarding-spec.md §4. Password auth
-- runs through GoTrue email+password with a SYNTHETIC, user_id-bound address
-- `<user_id>@login.kubbclub.ch` (D3: rename-safe; no real inbox — email
-- confirmations MUST stay off, see config.toml). The user only ever types a
-- nickname; the client resolves it to the synthetic email via the RPC below.
--
-- This migration:
--   1. widens user_credentials to allow a 'password' credential kind (for the
--      admin auth-kinds inventory; the actual secret lives in GoTrue),
--   2. adds password_login_email_for_nickname() — the pre-login lookup.
-- Additive; existing keypair/oauth rows satisfy the re-based constraints.


-- ---- 1. user_credentials: allow the 'password' kind -------------------
--
-- A password row carries neither public_key nor oauth_subject (the secret is
-- GoTrue's). Re-base both CHECKs (constraints can't be altered in place).

ALTER TABLE public.user_credentials
  DROP CONSTRAINT IF EXISTS user_credentials_kind_check;
ALTER TABLE public.user_credentials
  ADD CONSTRAINT user_credentials_kind_check
  CHECK (kind = ANY (ARRAY['oauth_google', 'oauth_apple', 'keypair', 'password']));

ALTER TABLE public.user_credentials
  DROP CONSTRAINT IF EXISTS user_credentials_shape;
ALTER TABLE public.user_credentials
  ADD CONSTRAINT user_credentials_shape CHECK (
    (kind = 'keypair'  AND public_key IS NOT NULL AND oauth_subject IS NULL)
    OR (kind IN ('oauth_google', 'oauth_apple')
        AND oauth_subject IS NOT NULL AND public_key IS NULL)
    OR (kind = 'password' AND public_key IS NULL AND oauth_subject IS NULL)
  );


-- ---- 2. password_login_email_for_nickname() --------------------------
--
-- Maps a nickname to its synthetic GoTrue login address so the client can
-- call signInWithPassword without the user ever seeing an email. Returns
-- NULL for an unknown nickname. citext nickname → case-insensitive.
--
-- Exposure: this reveals a nickname's user_id (embedded in the address).
-- That is acceptable — the id is an opaque uuid, no password/existence-of-
-- password signal leaks, and GoTrue rejects the sign-in if no password is set.

CREATE OR REPLACE FUNCTION public.password_login_email_for_nickname(
  p_nickname text
)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT up.user_id::text || '@login.kubbclub.ch'
    FROM public.user_profiles up
   WHERE up.nickname = p_nickname
   LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.password_login_email_for_nickname(text) FROM public;
GRANT EXECUTE ON FUNCTION public.password_login_email_for_nickname(text)
  TO anon, authenticated;

COMMENT ON FUNCTION public.password_login_email_for_nickname(text) IS
  'M3: nickname -> synthetic GoTrue login address <user_id>@login.kubbclub.ch. '
  'anon-callable (pre-login). NULL for unknown nicknames.';


-- ---- 3. password_credential_mark() -----------------------------------
--
-- Records a 'password' credential row for the CURRENT user so the admin
-- auth-kinds inventory reflects it (the secret itself is in GoTrue). Called
-- by the client right after updateUser sets the password. Idempotent.

CREATE OR REPLACE FUNCTION public.password_credential_mark()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user uuid;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.user_credentials
     WHERE user_id = v_user AND kind = 'password'
  ) THEN
    INSERT INTO public.user_credentials (user_id, kind)
    VALUES (v_user, 'password');
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.password_credential_mark() FROM public;
GRANT EXECUTE ON FUNCTION public.password_credential_mark() TO authenticated;
