-- Team member roles (admin/guest) + invite-by-nickname + guest registration
-- guard (P-team debugging round).
--
-- Background: members were invited by raw UUID and team_get returned only the
-- user_id, so the UI showed UUIDs. Player nicknames are already unique
-- (user_profiles.nickname citext UNIQUE), so we invite by name. Every member
-- is an admin by default; an admin may demote a member to 'guest'. Guests can
-- be selected into a roster but cannot administer the team or register it for
-- tournaments.

-- 1) Role column. Default 'admin' keeps all existing/new members as admins.
ALTER TABLE public.team_memberships
  ADD COLUMN IF NOT EXISTS role text NOT NULL DEFAULT 'admin'
    CHECK (role IN ('admin', 'guest'));

-- 2) team_get resolves pool nicknames and exposes each member's role so the UI
--    shows names + roles instead of raw UUIDs.
CREATE OR REPLACE FUNCTION public.team_get(p_team_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_team   public.teams%ROWTYPE;
  v_pool   jsonb;
  v_guests jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_team FROM public.teams WHERE id = p_team_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'team not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'membership_id', m.id,
           'user_id',       m.user_id,
           'display_name',  p.nickname,
           'role',          m.role,
           'joined_at',     m.joined_at
         ) ORDER BY m.joined_at), '[]'::jsonb)
    INTO v_pool
    FROM public.team_memberships m
    LEFT JOIN public.user_profiles p ON p.user_id = m.user_id
   WHERE m.team_id = p_team_id AND m.removed_at IS NULL;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'guest_id',     g.id,
           'display_name', g.display_name,
           'added_at',     g.added_at
         ) ORDER BY g.added_at), '[]'::jsonb)
    INTO v_guests
    FROM public.team_guest_players g
   WHERE g.team_id = p_team_id AND g.removed_at IS NULL;

  RETURN jsonb_build_object(
    'team_id',           v_team.id,
    'display_name',      v_team.display_name,
    'league_membership', v_team.league_membership,
    'logo_url',          v_team.logo_url,
    'country',           v_team.country,
    'home_club_id',      v_team.home_club_id,
    'created_by',        v_team.created_by,
    'dissolved_at',      v_team.dissolved_at,
    'created_at',        v_team.created_at,
    'updated_at',        v_team.updated_at,
    'pool',              v_pool,
    'guests',            v_guests
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_get(uuid) TO authenticated;

-- 3) Invite by nickname. Resolves the unique, case-insensitive nickname to a
--    user id, then delegates to the existing team_invite (which keeps the
--    pool-member + duplicate-invite guards). auth.uid() is preserved across
--    the nested SECURITY DEFINER call.
CREATE OR REPLACE FUNCTION public.team_invite_by_nickname(
  p_team_id  uuid,
  p_nickname text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_nickname IS NULL OR length(trim(p_nickname)) = 0 THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  SELECT user_id INTO v_user_id
    FROM public.user_profiles
   WHERE nickname = trim(p_nickname)::citext;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'USER_NOT_FOUND' USING ERRCODE = 'P0002';
  END IF;

  RETURN public.team_invite(p_team_id, v_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.team_invite_by_nickname(uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.team_invite_by_nickname(uuid, text)
  TO authenticated;

-- 4) Set a member's role. Only an admin pool member may change roles, and the
--    last admin cannot be demoted (would orphan team administration).
CREATE OR REPLACE FUNCTION public.team_set_member_role(
  p_team_id        uuid,
  p_member_user_id uuid,
  p_role           text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_admins int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_role NOT IN ('admin', 'guest') THEN
    RAISE EXCEPTION 'INVALID_ROLE' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.team_memberships
     WHERE team_id = p_team_id AND user_id = v_caller
       AND removed_at IS NULL AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'NOT_ADMIN' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.team_memberships
     WHERE team_id = p_team_id AND user_id = p_member_user_id
       AND removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'TARGET_NOT_MEMBER' USING ERRCODE = 'P0002';
  END IF;

  IF p_role = 'guest' THEN
    SELECT count(*) INTO v_admins
      FROM public.team_memberships
     WHERE team_id = p_team_id AND removed_at IS NULL AND role = 'admin';
    IF v_admins <= 1 AND EXISTS (
      SELECT 1 FROM public.team_memberships
       WHERE team_id = p_team_id AND user_id = p_member_user_id
         AND removed_at IS NULL AND role = 'admin'
    ) THEN
      RAISE EXCEPTION 'LAST_ADMIN' USING ERRCODE = '22023';
    END IF;
  END IF;

  UPDATE public.team_memberships
     SET role = p_role
   WHERE team_id = p_team_id AND user_id = p_member_user_id
     AND removed_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.team_set_member_role(uuid, uuid, text) FROM public;
GRANT EXECUTE ON FUNCTION public.team_set_member_role(uuid, uuid, text)
  TO authenticated;

-- 5) Guests cannot register a team for tournaments. Enforced additively via a
--    BEFORE INSERT trigger so the large tournament_register_team function is
--    not rewritten. Fires only for team registrations (team_id set) where the
--    registering caller is a guest of that team.
CREATE OR REPLACE FUNCTION public.trg_block_guest_team_registration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NEW.team_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.team_memberships
     WHERE team_id = NEW.team_id
       AND user_id = NEW.user_id
       AND removed_at IS NULL
       AND role = 'guest'
  ) THEN
    RAISE EXCEPTION 'GUEST_CANNOT_REGISTER' USING ERRCODE = '42501';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS block_guest_team_registration
  ON public.tournament_participants;
CREATE TRIGGER block_guest_team_registration
  BEFORE INSERT ON public.tournament_participants
  FOR EACH ROW EXECUTE FUNCTION public.trg_block_guest_team_registration();
