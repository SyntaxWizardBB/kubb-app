-- P9 BUG-2 — Name uniqueness checks for profiles, teams and clubs.
--
-- Goal: when a user creates or renames a profile nickname, a team name or a
-- club name, the chosen name must be checked for uniqueness against the DB and
-- the user blocked with a clear message if it is taken.
--
-- This migration is purely ADDITIVE:
--   1. A unique index on clubs(display_name) mirroring the existing team index
--      (20260901000005). The local DB has no duplicate club names (verified),
--      so the index builds without a backfill conflict.
--   2. Three SECURITY DEFINER availability-check RPCs (boolean, true = free),
--      case- and whitespace-insensitive, that the client calls before submit.
--   3. CREATE OR REPLACE on club_create / team_create / team_update so each
--      raises a clean, mappable ERRCODE 23505 with a clear message BEFORE the
--      insert/update when the name is already taken — instead of letting the
--      bare unique-index violation bubble up. All existing logic is preserved
--      verbatim (diffed against the latest defining migrations:
--      20261001000003 for club_create, 20260615000002 for team_create,
--      20260901000011 for team_update).
--
-- Profile nicknames already carry `user_profiles.nickname citext UNIQUE`
-- (20260504000001) which raises 23505 on conflict from keypair_register /
-- fn_profile_update_with_hash — no redeclaration needed there.


-- ---- 1. Unique club names --------------------------------------------
-- Case- and whitespace-insensitive, mirroring teams_display_name_unique_idx.

CREATE UNIQUE INDEX IF NOT EXISTS clubs_display_name_unique_idx
  ON public.clubs (lower(btrim(display_name)));

COMMENT ON INDEX public.clubs_display_name_unique_idx IS
  'Club display names are globally unique, case- and whitespace-insensitive.';


-- ---- 2. Availability-check RPCs --------------------------------------
-- Each returns true when the name is free for the caller. Blank/empty is
-- treated as not-available (false); the client still length-validates. All
-- comparisons trim + lower so they match the unique indexes exactly.

-- 2a. Profile nickname. Excludes the caller's own row so re-saving an
-- unchanged name is allowed. nickname is citext, so equality is already
-- case-insensitive; we still trim for whitespace tolerance.
CREATE OR REPLACE FUNCTION public.profile_nickname_available(p_nickname text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
BEGIN
  IF p_nickname IS NULL OR length(btrim(p_nickname)) = 0 THEN
    RETURN false;
  END IF;
  v_caller := auth.uid();
  RETURN NOT EXISTS (
    SELECT 1 FROM public.user_profiles up
     WHERE up.nickname = btrim(p_nickname)::citext
       AND (v_caller IS NULL OR up.user_id <> v_caller)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.profile_nickname_available(text)
  TO anon, authenticated;

-- 2b. Team name. Optionally excludes a team id (for rename).
CREATE OR REPLACE FUNCTION public.team_name_available(
  p_display_name   text,
  p_exclude_team_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF p_display_name IS NULL OR length(btrim(p_display_name)) = 0 THEN
    RETURN false;
  END IF;
  RETURN NOT EXISTS (
    SELECT 1 FROM public.teams t
     WHERE lower(btrim(t.display_name)) = lower(btrim(p_display_name))
       AND (p_exclude_team_id IS NULL OR t.id <> p_exclude_team_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_name_available(text, uuid)
  TO authenticated;

-- 2c. Club name. Optionally excludes a club id (for a future rename).
CREATE OR REPLACE FUNCTION public.club_name_available(
  p_display_name   text,
  p_exclude_club_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF p_display_name IS NULL OR length(btrim(p_display_name)) = 0 THEN
    RETURN false;
  END IF;
  RETURN NOT EXISTS (
    SELECT 1 FROM public.clubs c
     WHERE lower(btrim(c.display_name)) = lower(btrim(p_display_name))
       AND (p_exclude_club_id IS NULL OR c.id <> p_exclude_club_id)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.club_name_available(text, uuid)
  TO authenticated;


-- ---- 3. Clean 23505 on conflict in the create/rename RPCs ------------
-- The unique indexes already reject duplicates, but a raw index violation
-- carries an opaque message. Add an explicit pre-insert guard that raises a
-- readable message with ERRCODE 23505 (the pattern established by
-- tournament_create in 20260901000005). All other logic is unchanged.

-- 3a. club_create (base: 20261001000003_early_access_gate.sql).
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

  IF p_display_name IS NULL OR length(btrim(p_display_name)) = 0 THEN
    RAISE EXCEPTION 'INVALID_NAME' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.clubs c
     WHERE lower(btrim(c.display_name)) = lower(btrim(p_display_name))
  ) THEN
    RAISE EXCEPTION 'a club named "%" already exists', btrim(p_display_name)
      USING ERRCODE = '23505';
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


-- 3b. team_create (base: 20260615000002_team_rpcs_a.sql).
CREATE OR REPLACE FUNCTION public.team_create(
  p_display_name      text,
  p_league_membership text,
  p_logo_url          text DEFAULT NULL,
  p_country           text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller  uuid;
  v_team_id uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF p_display_name IS NULL OR length(btrim(p_display_name)) = 0 THEN
    RAISE EXCEPTION 'INVALID_NAME' USING ERRCODE = '22023';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.teams t
     WHERE lower(btrim(t.display_name)) = lower(btrim(p_display_name))
  ) THEN
    RAISE EXCEPTION 'a team named "%" already exists', btrim(p_display_name)
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.teams(display_name, league_membership, logo_url, country, created_by)
    VALUES (p_display_name, COALESCE(p_league_membership, 'B'), p_logo_url, p_country, v_caller)
    RETURNING id INTO v_team_id;

  INSERT INTO public.team_memberships(team_id, user_id)
    VALUES (v_team_id, v_caller);

  INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
    VALUES (v_team_id, 'team_created', v_caller,
            jsonb_build_object('display_name', p_display_name));

  RETURN v_team_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_create(text, text, text, text) TO authenticated;


-- 3c. team_update (base: 20260901000011_team_edit_and_notify.sql).
CREATE OR REPLACE FUNCTION public.team_update(
  p_team_id      uuid,
  p_display_name text,
  p_country      text
)
RETURNS void
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
  IF NOT public.is_active_team_member(p_team_id, v_caller) OR NOT EXISTS (
    SELECT 1 FROM public.team_memberships
     WHERE team_id = p_team_id AND user_id = v_caller
       AND removed_at IS NULL AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'NOT_ADMIN' USING ERRCODE = '42501';
  END IF;
  IF p_display_name IS NULL OR length(trim(p_display_name)) NOT BETWEEN 1 AND 60 THEN
    RAISE EXCEPTION 'INVALID_NAME' USING ERRCODE = '22023';
  END IF;
  IF p_country IS NOT NULL AND length(p_country) <> 2 THEN
    RAISE EXCEPTION 'INVALID_COUNTRY' USING ERRCODE = '22023';
  END IF;

  -- Duplicate guard: reject a rename onto another team's name (the unique
  -- index would otherwise raise an opaque error). Excludes this team's own row.
  IF EXISTS (
    SELECT 1 FROM public.teams t
     WHERE lower(btrim(t.display_name)) = lower(btrim(p_display_name))
       AND t.id <> p_team_id
  ) THEN
    RAISE EXCEPTION 'a team named "%" already exists', btrim(p_display_name)
      USING ERRCODE = '23505';
  END IF;

  UPDATE public.teams
     SET display_name = trim(p_display_name),
         country      = p_country,
         updated_at   = now()
   WHERE id = p_team_id AND dissolved_at IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.team_update(uuid, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.team_update(uuid, text, text) TO authenticated;
