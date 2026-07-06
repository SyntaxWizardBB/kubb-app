-- Auth-Redesign M4 — open registration (remove the early-access gate).
--
-- Spec §5 (valid now that M1 admin exists). keypair_register no longer
-- requires a valid early-access code: anyone can create an account, and
-- can_found_clubs always starts false — an admin grants the organizer
-- capability afterwards. The p_early_access_code param is KEPT (ignored) so
-- the client contract is unchanged; the early_access_* helper functions stay
-- as harmless, now-dead artifacts.
--
-- Body copied from the live definition (pg_get_functiondef of 20261001000003)
-- with exactly two changes: the validate_early_access_code enforcement is
-- dropped, and can_found_clubs is hard-set to false. Also: the ON CONFLICT
-- branch no longer writes can_found_clubs, so a re-register never clobbers an
-- admin-granted capability. Additive (CREATE OR REPLACE).

CREATE OR REPLACE FUNCTION public.keypair_register(
  p_nickname          text,
  p_public_key        text,
  p_early_access_code text,
  p_avatar_color      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'keypair_register requires an authenticated session'
      USING ERRCODE = '42501';
  END IF;

  -- M4: no early-access code enforcement — registration is open. The
  -- p_early_access_code argument is retained (ignored) for client
  -- compatibility.

  IF length(p_nickname) < 3 OR length(p_nickname) > 30 THEN
    RAISE EXCEPTION 'nickname length must be between 3 and 30 chars'
      USING ERRCODE = '22023';
  END IF;
  IF p_nickname !~ '^[A-Za-z0-9_-]+$' THEN
    RAISE EXCEPTION 'nickname may only contain alphanumerics, _ and -'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO user_credentials(user_id, kind, public_key)
    VALUES (v_user_id, 'keypair', p_public_key);

  -- can_found_clubs always starts false; an admin grants it later. On a
  -- re-register (ON CONFLICT) we deliberately do NOT touch can_found_clubs,
  -- so an admin-granted capability survives.
  INSERT INTO user_profiles(user_id, nickname, avatar_color, can_found_clubs)
    VALUES (v_user_id, p_nickname, p_avatar_color, false)
    ON CONFLICT (user_id) DO UPDATE
      SET nickname     = EXCLUDED.nickname,
          avatar_color = EXCLUDED.avatar_color;

  RETURN jsonb_build_object(
    'user_id',  v_user_id,
    'nickname', p_nickname,
    'kind',     'keypair'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION
  public.keypair_register(text, text, text, text) TO anon, authenticated;
