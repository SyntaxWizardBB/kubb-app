-- M5-Polish-T04 — Atomar das Profil patchen und den nickname_hash mitziehen.
--
-- Ohne diese RPC führt eine Nick-Änderung zu einem Self-Lockout: das
-- Profil wird umbenannt, aber user_keypair_backups.nickname_hash bleibt
-- auf dem alten Hash stehen. Auf einem frischen Gerät sucht der Restore
-- über `nickname_hash = compute_nickname_hash(neuer_name)` und findet
-- nichts mehr — der User kann sich selbst nicht mehr einloggen.
--
-- Die Funktion läuft mit SECURITY DEFINER, damit der Update auf
-- user_keypair_backups nicht an der Owner-Update-Policy scheitert
-- (die Policy ist owner-only — passt für reguläre Sessions, aber wir
-- wollen das Hash-Recompute hier in einer Transaktion mit dem
-- Profile-Update einschliessen). Zugriff ist trotzdem auf den eigenen
-- User beschränkt: der Funktionsbody arbeitet ausschliesslich auf
-- auth.uid() und liefert nichts an einen fremden user_id zurück.

CREATE OR REPLACE FUNCTION auth.fn_profile_update_with_hash(
  p_nickname           text DEFAULT NULL,
  p_avatar_color       text DEFAULT NULL,
  p_onboarding_done    boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
  v_row     user_profiles%ROWTYPE;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_profile_update_with_hash requires an authenticated session'
      USING ERRCODE = '42501';
  END IF;

  -- Server-side validation matches keypair_attach so a rename cannot
  -- bypass the rules the original signup enforced.
  IF p_nickname IS NOT NULL THEN
    IF length(p_nickname) < 3 OR length(p_nickname) > 30 THEN
      RAISE EXCEPTION 'nickname length must be between 3 and 30 chars'
        USING ERRCODE = '22023';
    END IF;
    IF p_nickname !~ '^[A-Za-z0-9_-]+$' THEN
      RAISE EXCEPTION 'nickname may only contain alphanumerics, _ and -'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  -- No-op: nothing to patch — return the existing row so the caller
  -- always gets a fresh CloudProfile back.
  IF p_nickname IS NULL
     AND p_avatar_color IS NULL
     AND p_onboarding_done IS NULL THEN
    SELECT * INTO v_row FROM user_profiles WHERE user_id = v_user_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'no profile exists for current user'
        USING ERRCODE = '42704';
    END IF;
    RETURN to_jsonb(v_row);
  END IF;

  UPDATE user_profiles
    SET nickname             = COALESCE(p_nickname,        nickname),
        avatar_color         = COALESCE(p_avatar_color,    avatar_color),
        onboarding_completed = COALESCE(p_onboarding_done, onboarding_completed)
    WHERE user_id = v_user_id
    RETURNING * INTO v_row;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'no profile exists for current user'
      USING ERRCODE = '42704';
  END IF;

  -- The whole point of this RPC: keep the keypair-backup hash in sync
  -- with the new nickname. Only touched when the caller actually
  -- changed the nickname AND the user has a keypair backup row (OAuth
  -- users without keypair fallback do not have a row here — UPDATE
  -- with no match is a no-op).
  IF p_nickname IS NOT NULL THEN
    UPDATE user_keypair_backups
      SET nickname_hash = auth.compute_nickname_hash(p_nickname),
          updated_at    = now()
      WHERE user_id = v_user_id;
  END IF;

  RETURN to_jsonb(v_row);
END;
$$;

COMMENT ON FUNCTION auth.fn_profile_update_with_hash IS
  'Patch user_profiles for the current session and, when the nickname '
  'changes, recompute user_keypair_backups.nickname_hash in the same '
  'transaction so cross-device restore stays consistent.';

GRANT EXECUTE ON FUNCTION auth.fn_profile_update_with_hash
  TO authenticated;
