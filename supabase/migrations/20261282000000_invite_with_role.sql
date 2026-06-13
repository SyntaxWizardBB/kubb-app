-- P3-S (ADR-0032 / docs/plans/permissions-organizer-teams PLAN) — invite
-- with role.
--
-- Adds a role to club invitations so the inviter picks the role the invitee
-- will receive on accept (owner / admin / referee, default admin):
--
--   1. club_invitations.role — text NOT NULL DEFAULT 'admin', named CHECK
--      role IN ('owner','admin','referee'). Pending pre-migration rows get
--      'admin' via the DEFAULT (PLAN risk R5).
--   2. club_invite gains p_role text DEFAULT 'admin' (validated, written to
--      the invitation row and into the inbox action_payload).
--   3. club_invite_by_nickname gains p_role and forwards it (delegation).
--   4. club_invitation_respond accept grants ARRAY[v_inv.role] instead of
--      the P1 hardcode ARRAY['admin'].
--
-- PURELY ADDITIVE: one ADD COLUMN, function re-definitions and grants. The
-- DROP FUNCTION statements below remove only the two old RPC signatures
-- that are superseded in this same file — keeping them would make a
-- two-argument call ambiguous against the new DEFAULT parameter.
--
-- Stale-body rule (PLAN, verified via
--   grep -rln "FUNCTION public.<fn>(" supabase/migrations/ | sort | tail -1):
--   * club_invite              base 20260901000015_club_invite_by_id.sql —
--     only changes: p_role parameter + validation (ERRCODE 22023), role in
--     the invitation INSERT, 'role' key in the inbox action_payload.
--   * club_invite_by_nickname  base 20260901000015_club_invite_by_id.sql —
--     only changes: p_role parameter + forwarding to club_invite.
--   * club_invitation_respond  base 20261280000000_role_consolidation.sql
--     (P1-S stand, NOT 20260901000013) — only change: accept grants
--     ARRAY[v_inv.role] instead of ARRAY['admin']. Signature unchanged,
--     hence CREATE OR REPLACE without DROP.


-- ---- 1. club_invitations.role ------------------------------------------

ALTER TABLE public.club_invitations
  ADD COLUMN role text NOT NULL DEFAULT 'admin'
    CONSTRAINT club_invitations_role_check
    CHECK (role IN ('owner','admin','referee'));


-- ---- 2. club_invite (base: 20260901000015) -------------------------------
-- The old 2-parameter signature must go: with the new DEFAULT parameter a
-- call club_invite(uuid, uuid) would otherwise be ambiguous.

DROP FUNCTION public.club_invite(uuid, uuid);

CREATE FUNCTION public.club_invite(
  p_club_id         uuid,
  p_invitee_user_id uuid,
  p_role            text DEFAULT 'admin'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_invitation uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.club_memberships m
     WHERE m.club_id = p_club_id
       AND m.user_id = v_caller
       AND m.removed_at IS NULL
       AND (m.roles && ARRAY['owner','admin']::text[])
  ) THEN
    RAISE EXCEPTION 'caller is not a club manager' USING ERRCODE = '42501';
  END IF;

  IF p_invitee_user_id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  IF p_role IS NULL OR p_role NOT IN ('owner','admin','referee') THEN
    RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.club_memberships m
     WHERE m.club_id = p_club_id
       AND m.user_id = p_invitee_user_id
       AND m.removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'invitee already a member' USING ERRCODE = '23505';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.club_invitations i
     WHERE i.club_id = p_club_id
       AND i.invitee_user_id = p_invitee_user_id
       AND i.state = 'pending'
  ) THEN
    RAISE EXCEPTION 'INVITATION_ALREADY_PENDING' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.club_invitations(club_id, invitee_user_id, invited_by, role)
    VALUES (p_club_id, p_invitee_user_id, v_caller, p_role)
    RETURNING id INTO v_invitation;

  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    VALUES (
      p_invitee_user_id,
      'club_invitation',
      'Vereins-Einladung',
      'Du wurdest in einen Verein eingeladen.',
      jsonb_build_object('club_id', p_club_id, 'invitation_id', v_invitation,
                         'role', p_role)
    );

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_invited', v_caller,
            jsonb_build_object('invitee_user_id', p_invitee_user_id,
                               'invitation_id', v_invitation));

  RETURN v_invitation;
END;
$$;

REVOKE ALL ON FUNCTION public.club_invite(uuid, uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.club_invite(uuid, uuid, text) TO authenticated;


-- ---- 3. club_invite_by_nickname (base: 20260901000015) -------------------
-- Same ambiguity argument: drop the old 2-parameter signature first.

DROP FUNCTION public.club_invite_by_nickname(uuid, text);

CREATE FUNCTION public.club_invite_by_nickname(
  p_club_id  uuid,
  p_nickname text,
  p_role     text DEFAULT 'admin'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_invitee uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_nickname IS NULL OR length(trim(p_nickname)) = 0 THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT user_id INTO v_invitee
    FROM public.user_profiles
   WHERE nickname = trim(p_nickname)::citext;

  IF v_invitee IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  RETURN public.club_invite(p_club_id, v_invitee, p_role);
END;
$$;

REVOKE ALL ON FUNCTION public.club_invite_by_nickname(uuid, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.club_invite_by_nickname(uuid, text, text)
  TO authenticated;


-- ---- 4. club_invitation_respond (base: 20261280000000, P1-S) -------------
-- Stale-body verified: latest on-disk definition is
-- 20261280000000_role_consolidation.sql. Only change vs. that body: accept
-- grants ARRAY[v_inv.role] (the role chosen at invite time) instead of the
-- P1 hardcode ARRAY['admin']. v_inv is %ROWTYPE, so it picks up the new
-- role column automatically. Signature unchanged — no DROP needed.

CREATE OR REPLACE FUNCTION public.club_invitation_respond(
  p_invitation_id uuid,
  p_accept        boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_inv    public.club_invitations%ROWTYPE;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_inv FROM public.club_invitations WHERE id = p_invitation_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'invitation not found' USING ERRCODE = 'P0002';
  END IF;

  IF v_inv.invitee_user_id <> v_caller THEN
    RAISE EXCEPTION 'caller is not the invitee' USING ERRCODE = '42501';
  END IF;

  IF v_inv.state <> 'pending' THEN
    RAISE EXCEPTION 'invitation already resolved' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.club_invitations
     SET state        = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
         responded_at = now()
   WHERE id = p_invitation_id;

  IF p_accept THEN
    INSERT INTO public.club_memberships(club_id, user_id, roles)
      VALUES (v_inv.club_id, v_caller, ARRAY[v_inv.role]::text[])
      ON CONFLICT DO NOTHING;

    INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
      VALUES (v_inv.club_id, 'invitation_accepted', v_caller,
              jsonb_build_object('invitation_id', p_invitation_id));
  ELSE
    INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
      VALUES (v_inv.club_id, 'invitation_declined', v_caller,
              jsonb_build_object('invitation_id', p_invitation_id));
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.club_invitation_respond(uuid, boolean)
  TO authenticated;
