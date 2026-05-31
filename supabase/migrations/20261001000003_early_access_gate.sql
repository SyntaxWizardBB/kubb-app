-- Early-access gate (P7): no profile without a valid code.
--
-- Two fixed, hard-to-guess codes (XXXX-XXXX). The player code grants a normal
-- account; the organizer code additionally sets `can_found_clubs`, which now
-- gates club founding (replacing the old global club_founding_code). Both are
-- validated server-side inside keypair_register so the gate can't be bypassed
-- by a tampered client.

-- ---- 1. Capability flag -----------------------------------------------

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS can_found_clubs boolean NOT NULL DEFAULT false;


-- ---- 2. Code constants + validation -----------------------------------

CREATE OR REPLACE FUNCTION public.early_access_player_code()
RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT 'MH2K-WKDE'::text $$;

CREATE OR REPLACE FUNCTION public.early_access_organizer_code()
RETURNS text LANGUAGE sql IMMUTABLE AS $$ SELECT 'JH5U-QZ4L'::text $$;

-- Returns 'player' | 'organizer' | NULL (invalid). Case-insensitive, trimmed.
CREATE OR REPLACE FUNCTION public.validate_early_access_code(p_code text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public
AS $$
  SELECT CASE
           WHEN p_code IS NULL THEN NULL
           WHEN upper(trim(p_code)) = public.early_access_organizer_code()
             THEN 'organizer'
           WHEN upper(trim(p_code)) = public.early_access_player_code()
             THEN 'player'
           ELSE NULL
         END;
$$;

GRANT EXECUTE ON FUNCTION public.validate_early_access_code(text)
  TO anon, authenticated;


-- ---- 3. keypair_register now requires a valid early-access code --------

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
  v_kind    text;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'keypair_register requires an authenticated session'
      USING ERRCODE = '42501';
  END IF;

  v_kind := public.validate_early_access_code(p_early_access_code);
  IF v_kind IS NULL THEN
    RAISE EXCEPTION 'INVALID_EARLY_ACCESS_CODE' USING ERRCODE = '22023';
  END IF;

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

  INSERT INTO user_profiles(user_id, nickname, avatar_color, can_found_clubs)
    VALUES (v_user_id, p_nickname, p_avatar_color, v_kind = 'organizer')
    ON CONFLICT (user_id) DO UPDATE
      SET nickname        = EXCLUDED.nickname,
          avatar_color    = EXCLUDED.avatar_color,
          can_found_clubs = EXCLUDED.can_found_clubs;

  RETURN jsonb_build_object(
    'user_id',  v_user_id,
    'nickname', p_nickname,
    'kind',     'keypair'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION
  public.keypair_register(text, text, text, text) TO anon, authenticated;

-- Drop the legacy 3-arg signature so the client can't accidentally register
-- without a code through the old overload.
DROP FUNCTION IF EXISTS public.keypair_register(text, text, text);


-- ---- 4. club_create now gates on can_found_clubs ----------------------

DROP FUNCTION IF EXISTS public.club_create(text, text);

CREATE OR REPLACE FUNCTION public.club_create(p_display_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller  uuid;
  v_club_id uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.user_profiles
     WHERE user_id = v_caller AND can_found_clubs = true
  ) THEN
    RAISE EXCEPTION 'CLUB_FOUNDING_NOT_ALLOWED' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.clubs(display_name, created_by)
    VALUES (p_display_name, v_caller)
    RETURNING id INTO v_club_id;

  INSERT INTO public.club_memberships(club_id, user_id, roles)
    VALUES (v_club_id, v_caller, ARRAY['owner']::text[]);

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (v_club_id, 'club_created', v_caller,
            jsonb_build_object('display_name', p_display_name));

  RETURN v_club_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.club_create(text) TO authenticated;
