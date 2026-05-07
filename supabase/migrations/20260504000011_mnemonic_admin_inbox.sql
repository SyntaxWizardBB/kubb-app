-- ADR-0011 cutover migration — drop the encrypted-backup path, replace
-- keypair_attach with the simpler keypair_register, add the in-app
-- inbox + admin RPCs.
--
-- This migration is destructive: anyone with rows in
-- user_keypair_backups loses them. Per ADR-0011 §Migration strategy
-- the auth branch has no production users yet, so a clean cut is the
-- explicit choice.

-- ---- 1. Drop the backup-related schema --------------------------------

DROP FUNCTION IF EXISTS public.keypair_rotate_backup(text, text, text, jsonb);
DROP FUNCTION IF EXISTS public.keypair_attach(text, text, text, text, jsonb, text);
DROP FUNCTION IF EXISTS public.compute_nickname_hash(text);

DROP TABLE IF EXISTS public.user_keypair_backups;

-- auth_server_salt is now unreferenced. Keep the table empty/around so
-- a separate cleanup migration can drop it cleanly later.


-- ---- 2. Replace keypair_attach with keypair_register ------------------
--
-- keypair_register registers a public key + nickname for the current
-- anonymous Supabase session. No ciphertext, no kdf params — the
-- public key is now derived deterministically from the BIP-39 mnemonic
-- on the client and the mnemonic itself never leaves the device.

CREATE OR REPLACE FUNCTION public.keypair_register(
  p_nickname     text,
  p_public_key   text,
  p_avatar_color text DEFAULT NULL
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

  INSERT INTO user_profiles(user_id, nickname, avatar_color)
    VALUES (v_user_id, p_nickname, p_avatar_color)
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

COMMENT ON FUNCTION public.keypair_register IS
  'Attach a BIP-39-derived keypair credential to the current anonymous '
  'Supabase session. Caller must signInAnonymously() first.';

GRANT EXECUTE ON FUNCTION public.keypair_register TO anon, authenticated;


-- ---- 3. In-app inbox --------------------------------------------------

CREATE TABLE IF NOT EXISTS public.user_inbox_messages (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind           text        NOT NULL CHECK (kind IN (
                               'notice',
                               'verification_request',
                               'system'
                             )),
  subject        text        NOT NULL,
  body           text        NOT NULL,
  action_payload jsonb       NULL,
  sent_at        timestamptz NOT NULL DEFAULT now(),
  read_at        timestamptz NULL,
  replied_at     timestamptz NULL,
  reply_payload  jsonb       NULL,
  archived_at    timestamptz NULL
);

CREATE INDEX IF NOT EXISTS user_inbox_messages_user_id_idx
  ON public.user_inbox_messages(user_id, sent_at DESC);

CREATE INDEX IF NOT EXISTS user_inbox_messages_unread_idx
  ON public.user_inbox_messages(user_id)
  WHERE read_at IS NULL AND archived_at IS NULL;

ALTER TABLE public.user_inbox_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY user_inbox_messages_owner_read
  ON public.user_inbox_messages FOR SELECT
  USING (user_id = auth.uid());

-- Owners can update only the read/replied/archived bookkeeping columns
-- on their own messages. Postgres doesn't let RLS pin per-column, so
-- we trust the client and rely on the API surface — direct SQL access
-- is service-role anyway.
CREATE POLICY user_inbox_messages_owner_update
  ON public.user_inbox_messages FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- No INSERT or DELETE policy. Inserts go through admin_inbox_send
-- (SECURITY DEFINER, service-role only). Deletes never happen — users
-- archive instead.


-- ---- 4. Admin RPCs ----------------------------------------------------
--
-- All three guard on the calling role. PostgREST sets the GUC
-- `request.jwt.claims` and exposes the role at `auth.role()`. We
-- accept service_role only — never the authenticated user role.

CREATE OR REPLACE FUNCTION public.admin_purge_account(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller text;
  v_existed boolean;
BEGIN
  v_caller := auth.role();
  IF v_caller IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'admin_purge_account requires the service role'
      USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id)
    INTO v_existed;

  -- Cascade deletes everything keyed off auth.users(id).
  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'user_id', p_user_id,
    'existed', v_existed,
    'purged_at', now()
  );
END;
$$;

COMMENT ON FUNCTION public.admin_purge_account IS
  'Hard-delete a user and all cascade-linked rows. Service-role only.';

GRANT EXECUTE ON FUNCTION public.admin_purge_account TO service_role;


CREATE OR REPLACE FUNCTION public.admin_inbox_send(
  p_user_id        uuid,
  p_kind           text,
  p_subject        text,
  p_body           text,
  p_action_payload jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller text;
  v_id uuid;
BEGIN
  v_caller := auth.role();
  IF v_caller IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'admin_inbox_send requires the service role'
      USING ERRCODE = '42501';
  END IF;

  IF p_kind NOT IN ('notice', 'verification_request', 'system') THEN
    RAISE EXCEPTION 'invalid inbox kind: %', p_kind
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO user_inbox_messages(user_id, kind, subject, body, action_payload)
    VALUES (p_user_id, p_kind, p_subject, p_body, p_action_payload)
    RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

COMMENT ON FUNCTION public.admin_inbox_send IS
  'Insert an in-app inbox message for a specific user. Service-role only.';

GRANT EXECUTE ON FUNCTION public.admin_inbox_send TO service_role;


CREATE OR REPLACE FUNCTION public.admin_inbox_list_for_user(p_user_id uuid)
RETURNS SETOF public.user_inbox_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller text;
BEGIN
  v_caller := auth.role();
  IF v_caller IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'admin_inbox_list_for_user requires the service role'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT * FROM user_inbox_messages
    WHERE user_id = p_user_id
    ORDER BY sent_at DESC;
END;
$$;

COMMENT ON FUNCTION public.admin_inbox_list_for_user IS
  'List inbox messages for a specific user (admin debug). Service-role only.';

GRANT EXECUTE ON FUNCTION public.admin_inbox_list_for_user TO service_role;
