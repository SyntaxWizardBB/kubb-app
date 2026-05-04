-- M7-Fix-HIGH-1 — Expose the auth-schema RPCs through the public schema.
--
-- PostgREST is configured with `schemas = ["public", "graphql_public"]`
-- in supabase/config.toml. The keypair flow (M2-T03 / M2-T04 / M5-Polish-T04)
-- defines its functions in the auth schema, so a Dart-side
-- `_client.rpc('keypair_attach', ...)` resolves to public.keypair_attach
-- and fails with PGRST404 in production. Adding `auth` to the exposed
-- schemas list would also expose every internal GoTrue function — not
-- acceptable.
--
-- The fix is a thin wrapper in the public schema for each of the five
-- RPCs the Dart client calls. The wrappers run as SECURITY DEFINER so
-- they can reach the auth-schema implementations without needing extra
-- EXECUTE grants on the inner functions. They take the same parameter
-- names as the originals so the Dart `params` map is unchanged.
--
-- Inner functions in the auth schema stay as they are. Only the surface
-- area exposed to PostgREST changes.

CREATE OR REPLACE FUNCTION public.compute_nickname_hash(p_nickname text)
RETURNS text
LANGUAGE sql
SECURITY DEFINER
SET search_path = auth, public
AS $$
  SELECT auth.compute_nickname_hash(p_nickname);
$$;

GRANT EXECUTE ON FUNCTION public.compute_nickname_hash(text)
  TO anon, authenticated;


CREATE OR REPLACE FUNCTION public.keypair_attach(
  p_nickname        text,
  p_public_key      text,
  p_ciphertext      bytea,
  p_kdf_salt        bytea,
  p_kdf_params      jsonb,
  p_avatar_color    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = auth, public
AS $$
  SELECT auth.keypair_attach(
    p_nickname, p_public_key, p_ciphertext, p_kdf_salt, p_kdf_params, p_avatar_color
  );
$$;

GRANT EXECUTE ON FUNCTION public.keypair_attach(text, text, bytea, bytea, jsonb, text)
  TO anon, authenticated;


CREATE OR REPLACE FUNCTION public.keypair_challenge(p_public_key text)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = auth, public
AS $$
  SELECT auth.keypair_challenge(p_public_key);
$$;

GRANT EXECUTE ON FUNCTION public.keypair_challenge(text)
  TO anon, authenticated;


CREATE OR REPLACE FUNCTION public.keypair_verify(
  p_public_key    text,
  p_challenge_b64 text,
  p_signature_b64 text
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = auth, public
AS $$
  SELECT auth.keypair_verify(p_public_key, p_challenge_b64, p_signature_b64);
$$;

GRANT EXECUTE ON FUNCTION public.keypair_verify(text, text, text)
  TO anon, authenticated;


CREATE OR REPLACE FUNCTION public.fn_profile_update_with_hash(
  p_nickname        text DEFAULT NULL,
  p_avatar_color    text DEFAULT NULL,
  p_onboarding_done boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE sql
SECURITY DEFINER
SET search_path = auth, public
AS $$
  SELECT auth.fn_profile_update_with_hash(p_nickname, p_avatar_color, p_onboarding_done);
$$;

GRANT EXECUTE ON FUNCTION public.fn_profile_update_with_hash(text, text, boolean)
  TO authenticated;
