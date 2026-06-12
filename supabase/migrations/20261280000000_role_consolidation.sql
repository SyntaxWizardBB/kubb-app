-- Role consolidation: club roles 8 -> {owner, admin, referee}.
-- ADR-0032 / docs/plans/permissions-organizer-teams PLAN P1-S.
--
-- Consolidates the legacy 8-role set (owner, admin, member, referee,
-- timemaster, organizer, scorekeeper, treasurer) down to
-- {owner, admin, referee}. Statement order is mandatory:
--
--   1. Audit insert BEFORE remap — one club_audit_events row
--      (kind 'roles_consolidated') per affected membership, with the OLD
--      roles array in the payload.
--   2. Remap UPDATE BEFORE the CHECK narrowing — strip removed roles
--      (member, timemaster, scorekeeper, treasurer), map organizer -> admin,
--      dedupe, and fall back to ARRAY['admin'] when nothing remains.
--      Deliberately NO removed_at filter so soft-deleted rows satisfy the
--      narrowed CHECK as well.
--   3. CHECK narrowing — the anonymous inline CHECK from 20260901000012 is
--      resolved by name via pg_constraint (never guessed), dropped, and
--      replaced by a named, narrowed constraint.
--   4. DEFAULT drop — roles had DEFAULT ARRAY['member']; callers must now
--      set roles explicitly.
--   5. CREATE OR REPLACE of the role-writing RPCs, each based on its latest
--      on-disk body (stale-body rule, grep-verified):
--        * club_set_member_roles    (base 20260901000013) — allowed role set
--          narrowed to {owner, admin, referee};
--        * club_invitation_respond  (base 20260901000013) — accept now grants
--          ARRAY['admin'] instead of ARRAY['member'];
--        * club_respond_join_request (base 20260901000016) — accept now grants
--          ARRAY['admin'] instead of ARRAY['member'].
--      Note: club_caller_can_publish and the tournament manage gate are
--      intentionally NOT touched in P1 — organizer rows are remapped to
--      admin above, so those gates keep working unchanged (gate split is P2).


-- ---- 1. Audit insert (BEFORE remap) ------------------------------------
-- Record the old roles of every membership the remap below will touch.
-- Same WHERE condition as the remap UPDATE; actor is NULL (system migration).

INSERT INTO public.club_audit_events (club_id, kind, actor_user_id, payload)
SELECT m.club_id,
       'roles_consolidated',
       NULL,
       jsonb_build_object(
         'user_id', m.user_id,
         'roles',   to_jsonb(m.roles)
       )
  FROM public.club_memberships m
 WHERE NOT (m.roles <@ ARRAY['owner','admin','referee']::text[]);


-- ---- 2. Remap UPDATE (BEFORE CHECK narrowing) ---------------------------
-- Keep owner/admin/referee, map organizer -> admin, drop everything else,
-- dedupe via array_agg(DISTINCT ...), and fall back to ARRAY['admin'] when
-- the stripped result would be empty. No removed_at filter on purpose:
-- soft-deleted rows must satisfy the narrowed CHECK too.

UPDATE public.club_memberships
   SET roles = COALESCE(
         (SELECT array_agg(DISTINCT
                   CASE WHEN r = 'organizer' THEN 'admin' ELSE r END)
            FROM unnest(roles) AS r
           WHERE r IN ('owner', 'admin', 'referee', 'organizer')),
         ARRAY['admin']::text[])
 WHERE NOT (roles <@ ARRAY['owner','admin','referee']::text[]);


-- ---- 3. CHECK narrowing -------------------------------------------------
-- The roles CHECK was declared inline (anonymous) in 20260901000012, so its
-- name is resolved from pg_constraint at runtime instead of being guessed.
-- club_memberships carries exactly one CHECK constraint; INTO STRICT guards
-- that assumption (fails loudly on 0 or >1 matches).

DO $$
DECLARE
  v_conname text;
BEGIN
  SELECT conname
    INTO STRICT v_conname
    FROM pg_constraint
   WHERE conrelid = 'public.club_memberships'::regclass
     AND contype = 'c';

  EXECUTE format(
    'ALTER TABLE public.club_memberships DROP CONSTRAINT %I', v_conname);
END
$$;

ALTER TABLE public.club_memberships
  ADD CONSTRAINT club_memberships_roles_check
  CHECK (
    array_length(roles, 1) >= 1
    AND roles <@ ARRAY['owner','admin','referee']::text[]
  );


-- ---- 4. DEFAULT drop ----------------------------------------------------
-- roles defaulted to ARRAY['member'] (a role that no longer exists). All
-- writers must state roles explicitly from now on.

ALTER TABLE public.club_memberships
  ALTER COLUMN roles DROP DEFAULT;


-- ---- 5. club_set_member_roles (base: 20260901000013) --------------------
-- Stale-body verified: latest on-disk definition is 20260901000013_club_rpcs.sql.
-- Only change vs. that body: the allowed-role validation array is narrowed
-- from the legacy 8-role set to ARRAY['owner','admin','referee'].

CREATE OR REPLACE FUNCTION public.club_set_member_roles(
  p_club_id        uuid,
  p_member_user_id uuid,
  p_roles          text[]
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_was_owner    boolean;
  v_will_owner   boolean;
  v_other_owners int;
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

  IF p_roles IS NULL OR array_length(p_roles, 1) IS NULL THEN
    RAISE EXCEPTION 'EMPTY_ROLES' USING ERRCODE = 'P0001';
  END IF;
  IF NOT (p_roles <@ ARRAY['owner','admin','referee']::text[]) THEN
    RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = 'P0001';
  END IF;

  SELECT (roles && ARRAY['owner']::text[]) INTO v_was_owner
    FROM public.club_memberships
   WHERE club_id = p_club_id AND user_id = p_member_user_id
     AND removed_at IS NULL;
  IF v_was_owner IS NULL THEN
    RAISE EXCEPTION 'member not found' USING ERRCODE = 'P0002';
  END IF;

  v_will_owner := p_roles && ARRAY['owner']::text[];

  -- Block demoting the final owner.
  IF v_was_owner AND NOT v_will_owner THEN
    SELECT count(*) INTO v_other_owners
      FROM public.club_memberships
     WHERE club_id = p_club_id
       AND removed_at IS NULL
       AND user_id <> p_member_user_id
       AND (roles && ARRAY['owner']::text[]);
    IF v_other_owners = 0 THEN
      RAISE EXCEPTION 'LAST_OWNER' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.club_memberships
     SET roles = p_roles
   WHERE club_id = p_club_id AND user_id = p_member_user_id
     AND removed_at IS NULL;

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_roles_set', v_caller,
            jsonb_build_object('member_user_id', p_member_user_id,
                               'roles', to_jsonb(p_roles)));
END;
$$;

REVOKE ALL ON FUNCTION public.club_set_member_roles(uuid, uuid, text[]) FROM public;
GRANT EXECUTE ON FUNCTION public.club_set_member_roles(uuid, uuid, text[])
  TO authenticated;


-- ---- 6. club_invitation_respond (base: 20260901000013) ------------------
-- Stale-body verified: latest on-disk definition is 20260901000013_club_rpcs.sql.
-- Only change vs. that body: accepting an invitation now grants
-- ARRAY['admin'] instead of the removed ARRAY['member'].

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
      VALUES (v_inv.club_id, v_caller, ARRAY['admin']::text[])
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


-- ---- 7. club_respond_join_request (base: 20260901000016) ----------------
-- Stale-body verified: latest on-disk definition is
-- 20260901000016_club_membership_ops.sql. Only change vs. that body:
-- accepting a join request now grants ARRAY['admin'] instead of the removed
-- ARRAY['member'].

CREATE OR REPLACE FUNCTION public.club_respond_join_request(
  p_request_id uuid,
  p_accept     boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_req    public.club_join_requests%ROWTYPE;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_req FROM public.club_join_requests WHERE id = p_request_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'request not found' USING ERRCODE = 'P0002';
  END IF;
  IF NOT public.is_club_manager(v_req.club_id, v_caller) THEN
    RAISE EXCEPTION 'caller is not a club manager' USING ERRCODE = '42501';
  END IF;
  IF v_req.state <> 'pending' THEN
    RAISE EXCEPTION 'request already resolved' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.club_join_requests
     SET state        = CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
         responded_at = now(),
         responded_by = v_caller
   WHERE id = p_request_id;

  IF p_accept THEN
    INSERT INTO public.club_memberships(club_id, user_id, roles)
      VALUES (v_req.club_id, v_req.user_id, ARRAY['admin']::text[])
      ON CONFLICT DO NOTHING;
  END IF;

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (v_req.club_id,
            CASE WHEN p_accept THEN 'join_accepted' ELSE 'join_declined' END,
            v_caller,
            jsonb_build_object('request_id', p_request_id,
                               'user_id', v_req.user_id));
END;
$$;

GRANT EXECUTE ON FUNCTION public.club_respond_join_request(uuid, boolean)
  TO authenticated;
