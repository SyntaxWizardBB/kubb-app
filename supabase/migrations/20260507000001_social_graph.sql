-- ADR-0012 Phase 1 — Social graph: friendships, groups, group_members,
-- plus the SECURITY DEFINER RPCs the client uses for every social
-- operation.
--
-- The friendship row is stored canonically as (low_user_id, high_user_id)
-- so the relation is naturally unique regardless of which side sent the
-- request. The `requested_by` column tracks who initiated, which is what
-- the receiver's inbox prompt needs to render correctly.

-- ---- 1. Tables --------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.friendships (
  low_user_id  uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  high_user_id uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status       text        NOT NULL CHECK (status IN (
                              'pending', 'accepted', 'rejected', 'blocked'
                            )),
  requested_by uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  requested_at timestamptz NOT NULL DEFAULT now(),
  accepted_at  timestamptz NULL,
  PRIMARY KEY (low_user_id, high_user_id),
  CONSTRAINT friendships_canonical CHECK (low_user_id < high_user_id)
);

CREATE INDEX IF NOT EXISTS friendships_high_user_id_idx
  ON public.friendships(high_user_id);


CREATE TABLE IF NOT EXISTS public.groups (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_user_id uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name          text        NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT groups_name_length CHECK (length(name) BETWEEN 1 AND 50)
);

CREATE INDEX IF NOT EXISTS groups_owner_idx ON public.groups(owner_user_id);


CREATE TABLE IF NOT EXISTS public.group_members (
  group_id  uuid        NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id   uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role      text        NOT NULL CHECK (role IN ('owner', 'member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);

CREATE INDEX IF NOT EXISTS group_members_user_idx
  ON public.group_members(user_id);


-- ---- 2. RLS policies --------------------------------------------------
--
-- friendships: a row is visible to either side of the relation.
-- Mutation goes through the SECURITY DEFINER RPCs, so we grant only
-- SELECT to authenticated users.
ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
CREATE POLICY friendships_owner_read
  ON public.friendships FOR SELECT
  USING (auth.uid() IN (low_user_id, high_user_id));

-- groups + group_members: members can read; the owner can also write.
-- All membership mutations go through RPCs (no direct INSERT/DELETE
-- from clients) for atomicity.
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
CREATE POLICY groups_member_read
  ON public.groups FOR SELECT
  USING (
    auth.uid() = owner_user_id
    OR EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.group_id = id AND gm.user_id = auth.uid()
    )
  );

ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
CREATE POLICY group_members_member_read
  ON public.group_members FOR SELECT
  USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM public.group_members gm2
      WHERE gm2.group_id = group_members.group_id
        AND gm2.user_id = auth.uid()
    )
  );


-- ---- 3. Friendship RPCs ----------------------------------------------

CREATE OR REPLACE FUNCTION public.friend_search_by_username(p_query text)
RETURNS TABLE (
  user_id      uuid,
  nickname     text,
  relationship text   -- 'none' | 'pending_outgoing' | 'pending_incoming' | 'accepted'
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF length(coalesce(p_query, '')) < 2 THEN
    RETURN; -- empty / too short queries return zero rows
  END IF;

  RETURN QUERY
    SELECT
      up.user_id,
      up.nickname::text,
      CASE
        WHEN f.status = 'accepted' THEN 'accepted'
        WHEN f.status = 'pending' AND f.requested_by = v_caller THEN 'pending_outgoing'
        WHEN f.status = 'pending' AND f.requested_by <> v_caller THEN 'pending_incoming'
        ELSE 'none'
      END AS relationship
    FROM public.user_profiles up
    LEFT JOIN public.friendships f
      ON ((f.low_user_id = least(up.user_id, v_caller)
           AND f.high_user_id = greatest(up.user_id, v_caller)))
    WHERE up.user_id <> v_caller
      AND up.nickname IS NOT NULL
      AND up.nickname ILIKE p_query || '%'
      AND coalesce(f.status, 'none') <> 'blocked'
    ORDER BY up.nickname
    LIMIT 20;
END;
$$;

GRANT EXECUTE ON FUNCTION public.friend_search_by_username TO authenticated;


CREATE OR REPLACE FUNCTION public.friend_request_send(p_target_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_low    uuid;
  v_high   uuid;
  v_caller_nick text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_target_user_id = v_caller THEN
    RAISE EXCEPTION 'cannot friend yourself' USING ERRCODE = '22023';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_target_user_id) THEN
    RAISE EXCEPTION 'target user does not exist' USING ERRCODE = '23503';
  END IF;

  v_low  := least(v_caller, p_target_user_id);
  v_high := greatest(v_caller, p_target_user_id);

  INSERT INTO public.friendships(
      low_user_id, high_user_id, status, requested_by)
    VALUES (v_low, v_high, 'pending', v_caller)
    ON CONFLICT (low_user_id, high_user_id) DO NOTHING;

  -- Drop a verification_request inbox message for the target so they
  -- can accept/reject directly from the inbox surface.
  SELECT nickname::text INTO v_caller_nick
    FROM public.user_profiles WHERE user_id = v_caller;

  INSERT INTO public.user_inbox_messages(
      user_id, kind, subject, body, action_payload)
    VALUES (
      p_target_user_id,
      'verification_request',
      'Freundschaftsanfrage',
      coalesce(v_caller_nick, 'Ein Spieler') ||
        ' möchte dich als Freund hinzufügen.',
      jsonb_build_object(
        'kind', 'friend_request',
        'from_user_id', v_caller,
        'from_nickname', v_caller_nick
      )
    );

  RETURN jsonb_build_object('status', 'sent');
END;
$$;

GRANT EXECUTE ON FUNCTION public.friend_request_send TO authenticated;


CREATE OR REPLACE FUNCTION public.friend_request_accept(p_other_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_low    uuid;
  v_high   uuid;
  v_updated int;
  v_caller_nick text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  v_low  := least(v_caller, p_other_user_id);
  v_high := greatest(v_caller, p_other_user_id);

  UPDATE public.friendships
    SET status = 'accepted', accepted_at = now()
    WHERE low_user_id = v_low AND high_user_id = v_high
      AND status = 'pending'
      AND requested_by = p_other_user_id;
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RAISE EXCEPTION 'no pending request to accept' USING ERRCODE = 'P0002';
  END IF;

  -- Notice to the original sender so they see the accept in their inbox.
  SELECT nickname::text INTO v_caller_nick
    FROM public.user_profiles WHERE user_id = v_caller;

  INSERT INTO public.user_inbox_messages(
      user_id, kind, subject, body, action_payload)
    VALUES (
      p_other_user_id,
      'notice',
      'Freundschaftsanfrage angenommen',
      coalesce(v_caller_nick, 'Ein Spieler') ||
        ' hat deine Freundschaftsanfrage angenommen.',
      jsonb_build_object(
        'kind', 'friend_request_accepted',
        'by_user_id', v_caller
      )
    );

  RETURN jsonb_build_object('status', 'accepted');
END;
$$;

GRANT EXECUTE ON FUNCTION public.friend_request_accept TO authenticated;


CREATE OR REPLACE FUNCTION public.friend_request_reject(p_other_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_low    uuid;
  v_high   uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  v_low  := least(v_caller, p_other_user_id);
  v_high := greatest(v_caller, p_other_user_id);

  -- Reject just deletes the row — keeps the table clean and lets the
  -- requester re-attempt later if they want.
  DELETE FROM public.friendships
    WHERE low_user_id = v_low AND high_user_id = v_high
      AND status = 'pending'
      AND requested_by = p_other_user_id;

  RETURN jsonb_build_object('status', 'rejected');
END;
$$;

GRANT EXECUTE ON FUNCTION public.friend_request_reject TO authenticated;


CREATE OR REPLACE FUNCTION public.friend_remove(p_other_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_low    uuid;
  v_high   uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  v_low  := least(v_caller, p_other_user_id);
  v_high := greatest(v_caller, p_other_user_id);

  DELETE FROM public.friendships
    WHERE low_user_id = v_low AND high_user_id = v_high;

  RETURN jsonb_build_object('status', 'removed');
END;
$$;

GRANT EXECUTE ON FUNCTION public.friend_remove TO authenticated;


CREATE OR REPLACE FUNCTION public.friend_list_for_caller()
RETURNS TABLE (
  user_id      uuid,
  nickname     text,
  status       text,
  requested_by uuid,
  since_at     timestamptz   -- accepted_at if accepted, otherwise requested_at
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT
      CASE WHEN f.low_user_id = v_caller THEN f.high_user_id
           ELSE f.low_user_id END AS user_id,
      up.nickname::text,
      f.status,
      f.requested_by,
      coalesce(f.accepted_at, f.requested_at) AS since_at
    FROM public.friendships f
    JOIN public.user_profiles up
      ON up.user_id = CASE WHEN f.low_user_id = v_caller
                           THEN f.high_user_id
                           ELSE f.low_user_id END
    WHERE v_caller IN (f.low_user_id, f.high_user_id)
      AND f.status IN ('accepted', 'pending')
    ORDER BY
      -- pending_incoming first (action needed), then accepted, then pending_outgoing
      CASE
        WHEN f.status = 'pending' AND f.requested_by <> v_caller THEN 0
        WHEN f.status = 'accepted' THEN 1
        ELSE 2
      END,
      since_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.friend_list_for_caller TO authenticated;


-- ---- 4. Group RPCs ----------------------------------------------------

CREATE OR REPLACE FUNCTION public.group_create(p_name text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_id     uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF length(coalesce(p_name, '')) NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'group name length must be 1..50 chars'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.groups(owner_user_id, name)
    VALUES (v_caller, p_name)
    RETURNING id INTO v_id;

  -- Owner is also a member-with-role-owner, so the same listing query
  -- handles both roles uniformly.
  INSERT INTO public.group_members(group_id, user_id, role)
    VALUES (v_id, v_caller, 'owner');

  RETURN v_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.group_create TO authenticated;


CREATE OR REPLACE FUNCTION public.group_rename(
  p_group_id uuid,
  p_name     text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_owner  uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF length(coalesce(p_name, '')) NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'group name length must be 1..50 chars'
      USING ERRCODE = '22023';
  END IF;

  SELECT owner_user_id INTO v_owner
    FROM public.groups WHERE id = p_group_id;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'group not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_owner <> v_caller THEN
    RAISE EXCEPTION 'only the owner can rename' USING ERRCODE = '42501';
  END IF;

  UPDATE public.groups SET name = p_name WHERE id = p_group_id;
  RETURN jsonb_build_object('status', 'renamed');
END;
$$;

GRANT EXECUTE ON FUNCTION public.group_rename TO authenticated;


CREATE OR REPLACE FUNCTION public.group_delete(p_group_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_owner  uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT owner_user_id INTO v_owner
    FROM public.groups WHERE id = p_group_id;
  IF v_owner IS NULL THEN
    RETURN jsonb_build_object('status', 'noop');
  END IF;
  IF v_owner <> v_caller THEN
    RAISE EXCEPTION 'only the owner can delete' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.groups WHERE id = p_group_id;  -- cascades to members
  RETURN jsonb_build_object('status', 'deleted');
END;
$$;

GRANT EXECUTE ON FUNCTION public.group_delete TO authenticated;


CREATE OR REPLACE FUNCTION public.group_invite_member(
  p_group_id uuid,
  p_user_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_owner      uuid;
  v_group_name text;
  v_caller_nick text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT owner_user_id, name INTO v_owner, v_group_name
    FROM public.groups WHERE id = p_group_id;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'group not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_owner <> v_caller THEN
    RAISE EXCEPTION 'only the owner can invite' USING ERRCODE = '42501';
  END IF;

  -- Adding requires an accepted friendship — keeps random invites out
  -- of strangers' inboxes. The hub's "Gruppen → Mitglied hinzufügen"
  -- picker only shows accepted friends anyway; this is the server-side
  -- enforcement.
  IF NOT EXISTS (
    SELECT 1 FROM public.friendships
     WHERE status = 'accepted'
       AND ((low_user_id = v_caller AND high_user_id = p_user_id) OR
            (low_user_id = p_user_id AND high_user_id = v_caller))
  ) THEN
    RAISE EXCEPTION 'can only add accepted friends to a group'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.group_members(group_id, user_id, role)
    VALUES (p_group_id, p_user_id, 'member')
    ON CONFLICT (group_id, user_id) DO NOTHING;

  SELECT nickname::text INTO v_caller_nick
    FROM public.user_profiles WHERE user_id = v_caller;

  INSERT INTO public.user_inbox_messages(
      user_id, kind, subject, body, action_payload)
    VALUES (
      p_user_id,
      'notice',
      'Gruppen-Einladung',
      coalesce(v_caller_nick, 'Ein Spieler') ||
        ' hat dich zur Gruppe „' || v_group_name || '" hinzugefügt.',
      jsonb_build_object(
        'kind', 'group_member_added',
        'group_id', p_group_id,
        'group_name', v_group_name,
        'by_user_id', v_caller
      )
    );

  RETURN jsonb_build_object('status', 'added');
END;
$$;

GRANT EXECUTE ON FUNCTION public.group_invite_member TO authenticated;


CREATE OR REPLACE FUNCTION public.group_remove_member(
  p_group_id uuid,
  p_user_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_owner  uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT owner_user_id INTO v_owner
    FROM public.groups WHERE id = p_group_id;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'group not found' USING ERRCODE = 'P0002';
  END IF;

  -- Self-leave is allowed for non-owners. Otherwise only owner can kick.
  IF p_user_id <> v_caller AND v_owner <> v_caller THEN
    RAISE EXCEPTION 'only the owner can remove other members'
      USING ERRCODE = '42501';
  END IF;
  IF p_user_id = v_owner THEN
    RAISE EXCEPTION 'owner cannot leave — delete the group instead'
      USING ERRCODE = '22023';
  END IF;

  DELETE FROM public.group_members
    WHERE group_id = p_group_id AND user_id = p_user_id;

  RETURN jsonb_build_object('status', 'removed');
END;
$$;

GRANT EXECUTE ON FUNCTION public.group_remove_member TO authenticated;


CREATE OR REPLACE FUNCTION public.group_list_for_caller()
RETURNS TABLE (
  group_id      uuid,
  name          text,
  owner_user_id uuid,
  is_owner      boolean,
  member_count  int,
  joined_at     timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT
      g.id,
      g.name,
      g.owner_user_id,
      g.owner_user_id = v_caller AS is_owner,
      (SELECT count(*)::int FROM public.group_members gm2
        WHERE gm2.group_id = g.id) AS member_count,
      gm.joined_at
    FROM public.groups g
    JOIN public.group_members gm
      ON gm.group_id = g.id AND gm.user_id = v_caller
    ORDER BY gm.joined_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.group_list_for_caller TO authenticated;


CREATE OR REPLACE FUNCTION public.group_members_for(p_group_id uuid)
RETURNS TABLE (
  user_id   uuid,
  nickname  text,
  role      text,
  joined_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.group_members
     WHERE group_id = p_group_id AND user_id = v_caller
  ) THEN
    RAISE EXCEPTION 'not a member of this group' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT gm.user_id, up.nickname::text, gm.role, gm.joined_at
      FROM public.group_members gm
      JOIN public.user_profiles up ON up.user_id = gm.user_id
     WHERE gm.group_id = p_group_id
     ORDER BY (gm.role = 'owner') DESC, gm.joined_at;
END;
$$;

GRANT EXECUTE ON FUNCTION public.group_members_for TO authenticated;
