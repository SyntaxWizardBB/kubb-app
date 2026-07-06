-- Auth-Redesign M1 (Block 1) — admin capability model + caller-gated admin RPCs.
--
-- Spec: docs/specs/auth-redesign-admin-onboarding-spec.md §2.1/§2.4.
-- Adds the platform-admin flag + account suspension to user_profiles, an
-- append-only admin audit trail, and the five caller-gated RPCs the in-app
-- admin dashboard uses. The existing service-role-only admin_* RPCs
-- (20260504000011) stay untouched; these are the authenticated-facing
-- counterparts, every one gated on public.caller_is_admin().
--
-- NOT part of the capability surface: user_profiles.is_organizer — that is a
-- legacy block-flag (DEFAULT true, only consulted as an explicit-false veto
-- by a superseded helper). The organizer right is can_found_clubs.


-- ---- 1. Capability + suspension columns --------------------------------

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS is_admin     boolean     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS suspended_at timestamptz NULL;

COMMENT ON COLUMN public.user_profiles.is_admin IS
  'Platform admin (M1). Grants the in-app admin dashboard + admin_* RPCs. '
  'Bootstrap: set once via SQL for the owner; afterwards admins grant it '
  'through admin_set_capability.';
COMMENT ON COLUMN public.user_profiles.suspended_at IS
  'Account suspension (M1). Non-NULL blocks every login/token mint '
  '(keypair-verify, password, oauth-reconcile) and revokes admin power.';


-- ---- 2. caller_is_admin() ----------------------------------------------

CREATE OR REPLACE FUNCTION public.caller_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT coalesce((
    SELECT up.is_admin AND up.suspended_at IS NULL
      FROM public.user_profiles up
     WHERE up.user_id = auth.uid()
  ), false);
$$;

REVOKE ALL ON FUNCTION public.caller_is_admin() FROM public;
GRANT EXECUTE ON FUNCTION public.caller_is_admin() TO authenticated;

COMMENT ON FUNCTION public.caller_is_admin() IS
  'M1: TRUE iff the calling user is a non-suspended platform admin. Gate '
  'for all caller-facing admin_* RPCs and the admin_audit_events RLS.';


-- ---- 3. Append-only audit trail ----------------------------------------
--
-- No FKs on the user columns: audit rows must survive account purges.

CREATE TABLE IF NOT EXISTS public.admin_audit_events (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id  uuid        NOT NULL,
  target_user_id uuid        NULL,
  kind           text        NOT NULL,
  payload        jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_events_created_at
  ON public.admin_audit_events (created_at DESC);

ALTER TABLE public.admin_audit_events ENABLE ROW LEVEL SECURITY;

-- Admins read; nobody writes directly (inserts happen inside the SECURITY
-- DEFINER RPCs below). No UPDATE/DELETE policy: append-only.
CREATE POLICY admin_audit_events_admin_select
  ON public.admin_audit_events FOR SELECT
  USING (public.caller_is_admin());

COMMENT ON TABLE public.admin_audit_events IS
  'M1: append-only audit trail of every admin mutation (capability change, '
  'suspension, deletion, inbox message, impersonation). Admin-read only; '
  'written exclusively by the admin_* SECURITY DEFINER RPCs.';

-- Internal write helper — deliberately NOT granted to any client role.
CREATE OR REPLACE FUNCTION public._admin_audit_write(
  p_actor  uuid,
  p_target uuid,
  p_kind   text,
  p_payload jsonb
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.admin_audit_events (actor_user_id, target_user_id, kind, payload)
  VALUES (p_actor, p_target, p_kind, coalesce(p_payload, '{}'::jsonb));
$$;

REVOKE ALL ON FUNCTION public._admin_audit_write(uuid, uuid, text, jsonb) FROM public;


-- ---- 4. admin_list_users ------------------------------------------------
--
-- V1 lists PROFILES (a pre-M2 OAuth user without a profile does not appear;
-- M2 makes profiles mandatory, closing that gap).

CREATE OR REPLACE FUNCTION public.admin_list_users(
  p_query  text DEFAULT NULL,
  p_limit  int  DEFAULT 50,
  p_offset int  DEFAULT 0
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NOT public.caller_is_admin() THEN
    RAISE EXCEPTION 'admin only' USING ERRCODE = '42501';
  END IF;
  IF p_limit < 1 OR p_limit > 200 OR p_offset < 0 THEN
    RAISE EXCEPTION 'limit/offset out of range' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
    SELECT jsonb_build_object(
             'user_id',         up.user_id,
             'nickname',        up.nickname,
             'avatar_color',    up.avatar_color,
             'created_at',      up.created_at,
             'is_admin',        up.is_admin,
             'can_found_clubs', up.can_found_clubs,
             'suspended_at',    up.suspended_at,
             'auth_kinds',      (
               SELECT coalesce(jsonb_agg(DISTINCT uc.kind), '[]'::jsonb)
                 FROM public.user_credentials uc
                WHERE uc.user_id = up.user_id
             )
           )
      FROM public.user_profiles up
     WHERE p_query IS NULL
        OR btrim(p_query) = ''
        OR up.nickname ILIKE '%' || btrim(p_query) || '%'
     ORDER BY up.created_at DESC
     LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_users(text, int, int) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_list_users(text, int, int) TO authenticated;


-- ---- 5. admin_set_capability ---------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_set_capability(
  p_user_id    uuid,
  p_capability text,
  p_value      boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_old    boolean;
BEGIN
  IF NOT public.caller_is_admin() THEN
    RAISE EXCEPTION 'admin only' USING ERRCODE = '42501';
  END IF;
  v_caller := auth.uid();

  IF p_capability NOT IN ('can_found_clubs', 'is_admin') THEN
    RAISE EXCEPTION 'unknown capability %', p_capability USING ERRCODE = '22023';
  END IF;
  -- Self-lockout protection: an admin cannot demote themself.
  IF p_capability = 'is_admin' AND p_user_id = v_caller AND p_value = false THEN
    RAISE EXCEPTION 'cannot revoke your own admin capability'
      USING ERRCODE = '22023';
  END IF;

  IF p_capability = 'can_found_clubs' THEN
    SELECT can_found_clubs INTO v_old
      FROM public.user_profiles WHERE user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'user not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_old = p_value THEN RETURN; END IF;  -- idempotent, no audit noise
    UPDATE public.user_profiles
       SET can_found_clubs = p_value WHERE user_id = p_user_id;
  ELSE
    SELECT is_admin INTO v_old
      FROM public.user_profiles WHERE user_id = p_user_id FOR UPDATE;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'user not found' USING ERRCODE = 'P0002';
    END IF;
    IF v_old = p_value THEN RETURN; END IF;
    UPDATE public.user_profiles
       SET is_admin = p_value WHERE user_id = p_user_id;
  END IF;

  PERFORM public._admin_audit_write(
    v_caller, p_user_id, 'capability_change',
    jsonb_build_object('capability', p_capability, 'old', v_old, 'new', p_value));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_capability(uuid, text, boolean) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_set_capability(uuid, text, boolean) TO authenticated;


-- ---- 6. admin_set_account_status ------------------------------------------

CREATE OR REPLACE FUNCTION public.admin_set_account_status(
  p_user_id uuid,
  p_status  text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_old    timestamptz;
BEGIN
  IF NOT public.caller_is_admin() THEN
    RAISE EXCEPTION 'admin only' USING ERRCODE = '42501';
  END IF;
  v_caller := auth.uid();

  IF p_status NOT IN ('active', 'suspended') THEN
    RAISE EXCEPTION 'unknown status %', p_status USING ERRCODE = '22023';
  END IF;
  IF p_user_id = v_caller THEN
    RAISE EXCEPTION 'cannot change your own account status'
      USING ERRCODE = '22023';
  END IF;

  SELECT suspended_at INTO v_old
    FROM public.user_profiles WHERE user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'user not found' USING ERRCODE = 'P0002';
  END IF;

  IF p_status = 'suspended' THEN
    IF v_old IS NOT NULL THEN RETURN; END IF;  -- already suspended
    UPDATE public.user_profiles
       SET suspended_at = now() WHERE user_id = p_user_id;
  ELSE
    IF v_old IS NULL THEN RETURN; END IF;      -- already active
    UPDATE public.user_profiles
       SET suspended_at = NULL WHERE user_id = p_user_id;
  END IF;

  PERFORM public._admin_audit_write(
    v_caller, p_user_id, 'account_status_change',
    jsonb_build_object('status', p_status));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_account_status(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_set_account_status(uuid, text) TO authenticated;


-- ---- 7. admin_delete_account -----------------------------------------------
--
-- Mirrors service-role admin_purge_account (20260504000011): auth.users
-- cascade wipes everything. Duplicated here because that RPC gates on
-- auth.role() = service_role, which stays 'authenticated' even inside a
-- SECURITY DEFINER call — delegation is impossible by design.

CREATE OR REPLACE FUNCTION public.admin_delete_account(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller   uuid;
  v_nickname text;
  v_existed  boolean;
BEGIN
  IF NOT public.caller_is_admin() THEN
    RAISE EXCEPTION 'admin only' USING ERRCODE = '42501';
  END IF;
  v_caller := auth.uid();
  IF p_user_id = v_caller THEN
    RAISE EXCEPTION 'cannot delete your own account here'
      USING ERRCODE = '22023';
  END IF;

  SELECT nickname INTO v_nickname
    FROM public.user_profiles WHERE user_id = p_user_id;
  SELECT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) INTO v_existed;

  -- Audit BEFORE the cascade wipes the profile (nickname snapshot).
  PERFORM public._admin_audit_write(
    v_caller, p_user_id, 'account_delete',
    jsonb_build_object('nickname', v_nickname, 'existed', v_existed));

  DELETE FROM auth.users WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'user_id', p_user_id, 'existed', v_existed, 'purged_at', now());
END;
$$;

REVOKE ALL ON FUNCTION public.admin_delete_account(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_delete_account(uuid) TO authenticated;


-- ---- 8. admin_send_inbox -----------------------------------------------------
--
-- Kind is fixed to 'notice' (the generic admin/system message). The inbox
-- insert rides the full messaging spine: CDC wake + push-outbox enqueue.

CREATE OR REPLACE FUNCTION public.admin_send_inbox(
  p_user_id uuid,
  p_subject text,
  p_body    text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_id     uuid;
BEGIN
  IF NOT public.caller_is_admin() THEN
    RAISE EXCEPTION 'admin only' USING ERRCODE = '42501';
  END IF;
  v_caller := auth.uid();

  IF p_subject IS NULL OR length(btrim(p_subject)) = 0 OR length(p_subject) > 200 THEN
    RAISE EXCEPTION 'subject required (max 200 chars)' USING ERRCODE = '22023';
  END IF;
  IF p_body IS NULL OR length(btrim(p_body)) = 0 OR length(p_body) > 2000 THEN
    RAISE EXCEPTION 'body required (max 2000 chars)' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.user_profiles WHERE user_id = p_user_id) THEN
    RAISE EXCEPTION 'user not found' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.user_inbox_messages (user_id, kind, subject, body)
  VALUES (p_user_id, 'notice', p_subject, p_body)
  RETURNING id INTO v_id;

  PERFORM public._admin_audit_write(
    v_caller, p_user_id, 'inbox_message_sent',
    jsonb_build_object('subject', p_subject, 'message_id', v_id));

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_send_inbox(uuid, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.admin_send_inbox(uuid, text, text) TO authenticated;
