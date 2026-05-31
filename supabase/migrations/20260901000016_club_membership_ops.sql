-- Club membership operations (P5): remove member, leave, join requests, and
-- the tournament-publish capability check.
--
-- Builds on 20260901000012/13/15. Adds a manager helper, a join-requests table
-- with RLS, and SECURITY DEFINER RPCs for: removing a member, leaving a club,
-- requesting to join, listing/responding to join requests, plus a boolean the
-- client uses to gate tournament publishing on club ownership.


-- ---- 1. Manager helper (owner/admin), non-recursive --------------------

CREATE OR REPLACE FUNCTION public.is_club_manager(
  p_club_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.club_memberships
     WHERE club_id = p_club_id
       AND user_id = p_user_id
       AND removed_at IS NULL
       AND (roles && ARRAY['owner','admin']::text[])
  );
$$;

REVOKE ALL ON FUNCTION public.is_club_manager(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.is_club_manager(uuid, uuid)
  TO authenticated, anon;


-- ---- 2. Join-requests table + RLS -------------------------------------

CREATE TABLE public.club_join_requests (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id       uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  state         text NOT NULL DEFAULT 'pending'
                  CHECK (state IN ('pending','accepted','declined')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  responded_at  timestamptz NULL,
  responded_by  uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE UNIQUE INDEX club_join_requests_unique_pending_idx
  ON public.club_join_requests(club_id, user_id)
  WHERE state = 'pending';
CREATE INDEX club_join_requests_club_state_idx
  ON public.club_join_requests(club_id, state);

ALTER TABLE public.club_join_requests ENABLE ROW LEVEL SECURITY;

-- The requester sees their own requests; club managers see their club's.
CREATE POLICY club_join_requests_read
  ON public.club_join_requests FOR SELECT
  USING (
    user_id = auth.uid()
    OR public.is_club_manager(club_join_requests.club_id, auth.uid())
  );


-- ---- 3. Inbox kind for join requests ----------------------------------

ALTER TABLE public.user_inbox_messages
  DROP CONSTRAINT IF EXISTS user_inbox_messages_kind_check;
ALTER TABLE public.user_inbox_messages
  ADD CONSTRAINT user_inbox_messages_kind_check
    CHECK (kind IN (
      'notice','verification_request','system',
      'team_invitation','team_member_removed','team_dissolved',
      'club_invitation','club_member_removed','club_join_request'
    ));


-- ---- 4. club_remove_member --------------------------------------------
-- Owner/admin removes another member (soft delete). Cannot remove the last
-- owner, and cannot target yourself (use club_leave).

CREATE OR REPLACE FUNCTION public.club_remove_member(
  p_club_id        uuid,
  p_member_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_is_owner     boolean;
  v_other_owners int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_club_manager(p_club_id, v_caller) THEN
    RAISE EXCEPTION 'caller is not a club manager' USING ERRCODE = '42501';
  END IF;
  IF p_member_user_id = v_caller THEN
    RAISE EXCEPTION 'USE_LEAVE' USING ERRCODE = 'P0001';
  END IF;

  SELECT (roles && ARRAY['owner']::text[]) INTO v_is_owner
    FROM public.club_memberships
   WHERE club_id = p_club_id AND user_id = p_member_user_id
     AND removed_at IS NULL;
  IF v_is_owner IS NULL THEN
    RAISE EXCEPTION 'member not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_is_owner THEN
    SELECT count(*) INTO v_other_owners
      FROM public.club_memberships
     WHERE club_id = p_club_id AND removed_at IS NULL
       AND user_id <> p_member_user_id
       AND (roles && ARRAY['owner']::text[]);
    IF v_other_owners = 0 THEN
      RAISE EXCEPTION 'LAST_OWNER' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.club_memberships
     SET removed_at = now(), removed_by = v_caller
   WHERE club_id = p_club_id AND user_id = p_member_user_id
     AND removed_at IS NULL;

  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    VALUES (p_member_user_id, 'club_member_removed', 'Vereins-Mitgliedschaft beendet',
            'Du wurdest aus einem Verein entfernt.',
            jsonb_build_object('club_id', p_club_id));

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_removed', v_caller,
            jsonb_build_object('member_user_id', p_member_user_id));
END;
$$;

GRANT EXECUTE ON FUNCTION public.club_remove_member(uuid, uuid) TO authenticated;


-- ---- 5. club_leave ----------------------------------------------------
-- Self-removal. The last owner may only leave when no other members remain
-- (which dissolves the club); otherwise they must hand over ownership first.

CREATE OR REPLACE FUNCTION public.club_leave(p_club_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_is_owner     boolean;
  v_other_members int;
  v_other_owners  int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT (roles && ARRAY['owner']::text[]) INTO v_is_owner
    FROM public.club_memberships
   WHERE club_id = p_club_id AND user_id = v_caller AND removed_at IS NULL;
  IF v_is_owner IS NULL THEN
    RAISE EXCEPTION 'not a member' USING ERRCODE = 'P0002';
  END IF;

  SELECT count(*) INTO v_other_members
    FROM public.club_memberships
   WHERE club_id = p_club_id AND removed_at IS NULL AND user_id <> v_caller;

  IF v_is_owner THEN
    SELECT count(*) INTO v_other_owners
      FROM public.club_memberships
     WHERE club_id = p_club_id AND removed_at IS NULL
       AND user_id <> v_caller AND (roles && ARRAY['owner']::text[]);
    IF v_other_owners = 0 AND v_other_members > 0 THEN
      RAISE EXCEPTION 'LAST_OWNER' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.club_memberships
     SET removed_at = now(), removed_by = v_caller
   WHERE club_id = p_club_id AND user_id = v_caller AND removed_at IS NULL;

  -- Sole member leaving dissolves the club.
  IF v_other_members = 0 THEN
    UPDATE public.clubs SET dissolved_at = now()
     WHERE id = p_club_id AND dissolved_at IS NULL;
  END IF;

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_left', v_caller, '{}'::jsonb);
END;
$$;

GRANT EXECUTE ON FUNCTION public.club_leave(uuid) TO authenticated;


-- ---- 6. club_request_join ---------------------------------------------
-- Any authenticated user asks to join a (public) club. Notifies every manager.

CREATE OR REPLACE FUNCTION public.club_request_join(p_club_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller  uuid;
  v_request uuid;
  v_name    text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.club_memberships
     WHERE club_id = p_club_id AND user_id = v_caller AND removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'ALREADY_MEMBER' USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.club_join_requests
     WHERE club_id = p_club_id AND user_id = v_caller AND state = 'pending'
  ) THEN
    RAISE EXCEPTION 'REQUEST_ALREADY_PENDING' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.club_join_requests(club_id, user_id)
    VALUES (p_club_id, v_caller)
    RETURNING id INTO v_request;

  SELECT nickname INTO v_name FROM public.user_profiles WHERE user_id = v_caller;

  -- Fan-out an inbox message to every active owner/admin of the club.
  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    SELECT m.user_id, 'club_join_request', 'Beitrittsanfrage',
           COALESCE(v_name, 'Ein Spieler') || ' möchte deinem Verein beitreten.',
           jsonb_build_object('club_id', p_club_id, 'request_id', v_request)
      FROM public.club_memberships m
     WHERE m.club_id = p_club_id AND m.removed_at IS NULL
       AND (m.roles && ARRAY['owner','admin']::text[]);

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'join_requested', v_caller,
            jsonb_build_object('request_id', v_request));

  RETURN v_request;
END;
$$;

GRANT EXECUTE ON FUNCTION public.club_request_join(uuid) TO authenticated;


-- ---- 7. club_list_join_requests (manager) -----------------------------

CREATE OR REPLACE FUNCTION public.club_list_join_requests(p_club_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_out    jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_club_manager(p_club_id, v_caller) THEN
    RAISE EXCEPTION 'caller is not a club manager' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'request_id',   r.id,
           'user_id',      r.user_id,
           'display_name', p.nickname,
           'created_at',   r.created_at
         ) ORDER BY r.created_at), '[]'::jsonb)
    INTO v_out
    FROM public.club_join_requests r
    LEFT JOIN public.user_profiles p ON p.user_id = r.user_id
   WHERE r.club_id = p_club_id AND r.state = 'pending';

  RETURN v_out;
END;
$$;

GRANT EXECUTE ON FUNCTION public.club_list_join_requests(uuid) TO authenticated;


-- ---- 8. club_respond_join_request (manager) ---------------------------

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
      VALUES (v_req.club_id, v_req.user_id, ARRAY['member']::text[])
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


-- ---- 9. club_caller_can_publish ---------------------------------------
-- True when the caller is an owner/admin/organizer of ANY active club. The
-- client uses this to gate tournament publishing on club role (P5).

CREATE OR REPLACE FUNCTION public.club_caller_can_publish()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.club_memberships
     WHERE user_id = auth.uid()
       AND removed_at IS NULL
       AND (roles && ARRAY['owner','admin','organizer']::text[])
  );
$$;

GRANT EXECUTE ON FUNCTION public.club_caller_can_publish() TO authenticated;
