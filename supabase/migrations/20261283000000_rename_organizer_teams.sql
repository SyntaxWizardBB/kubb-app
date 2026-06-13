-- 20261283000000_rename_organizer_teams.sql
-- P6a (ADR-0032, plan docs/plans/permissions-organizer-teams/PLAN.md):
-- BEHAVIOUR-NEUTRAL rename of the "Verein" (club) construct to
-- "Veranstalterteam" (organizer team). DB layer only — the Dart side is
-- intentionally NOT touched here and is expected to be temporarily red
-- until P6b (expected failure class: unknown RPC names / wire keys; see
-- the mapping tables below — P6b must mirror them exactly).
--
-- Strictly non-destructive: ALTER TABLE ... RENAME [COLUMN],
-- ALTER FUNCTION ... RENAME TO, CREATE OR REPLACE FUNCTION with
-- token-only identifier replacements (machine-verified: every new body
-- reverse-mapped onto the last applied body is byte-identical). No DROP,
-- no TRUNCATE, no data-changing UPDATE/INSERT/DELETE, no ALTER PUBLICATION
-- (none of the renamed tables is in supabase_realtime — verified count 0).
--
-- ============================ TABLE / COLUMN MAP ============================
--   clubs                                     -> organizer_teams
--   club_memberships                          -> team_members
--   club_memberships.club_id                  -> team_members.organizer_team_id
--   tournaments.club_id                       -> tournaments.organizer_team_id
--   tournament_stage_graph_templates.club_id  -> ...organizer_team_id
--     (column-only rename; required so that NO function body keeps a live
--      "club_id" column reference outside the three legacy tables below)
--   NOT renamed (out of scope, keep their club_id FK columns):
--     club_invitations, club_join_requests, club_audit_events
--   NOT touched at all: 1vs1 team feature tables teams / team_memberships,
--     user_profiles.can_found_clubs, teams.home_club_id.
--   Constraint/index names (clubs_pkey, club_memberships_*_fkey,
--     clubs_display_name_unique_idx, club_memberships_roles_check, ...) are
--     deliberately NOT renamed (PostgreSQL keeps them on table rename;
--     renaming them is cosmetic and would widen the diff).
--
-- ============================ FUNCTION RENAME MAP ===========================
-- The plan's literal scheme club_* -> team_* COLLIDES with the existing
-- 1vs1 team feature for at least 10 names (team_create, team_get,
-- team_invite, team_invite_by_nickname, team_invitation_respond, team_leave,
-- team_list_for_caller, team_name_available, team_remove_member,
-- team_set_member_role(s), is_active_team_member). Deterministic,
-- collision-free scheme used instead (pre-checked: NO existing public
-- function starts with 'organizer_'):
--   prefix 'club_'          -> 'organizer_team_'
--   is_active_club_member   -> is_active_organizer_team_member
--   is_club_manager         -> is_organizer_team_manager
-- Complete map (old -> new, identity signature, no overloads existed):
--   club_caller_can_publish()                  -> organizer_team_caller_can_publish()
--   club_caller_is_organizer()                 -> organizer_team_caller_is_organizer()
--   club_create(text)                          -> organizer_team_create(text)
--   club_founding_code()                       -> organizer_team_founding_code()
--   club_get(uuid)                             -> organizer_team_get(uuid)
--   club_invitation_respond(uuid, boolean)     -> organizer_team_invitation_respond(uuid, boolean)
--   club_invite(uuid, uuid, text)              -> organizer_team_invite(uuid, uuid, text)
--   club_invite_by_nickname(uuid, text, text)  -> organizer_team_invite_by_nickname(uuid, text, text)
--   club_leave(uuid)                           -> organizer_team_leave(uuid)
--   club_list_for_caller()                     -> organizer_team_list_for_caller()
--   club_list_join_requests(uuid)              -> organizer_team_list_join_requests(uuid)
--   club_name_available(text, uuid)            -> organizer_team_name_available(text, uuid)
--   club_remove_member(uuid, uuid)             -> organizer_team_remove_member(uuid, uuid)
--   club_request_join(uuid)                    -> organizer_team_request_join(uuid)
--   club_respond_join_request(uuid, boolean)   -> organizer_team_respond_join_request(uuid, boolean)
--   club_set_member_roles(uuid, uuid, text[])  -> organizer_team_set_member_roles(uuid, uuid, text[])
--   is_active_club_member(uuid, uuid)          -> is_active_organizer_team_member(uuid, uuid)
--   is_club_manager(uuid, uuid)                -> is_organizer_team_manager(uuid, uuid)
-- Parameter NAMES are kept (p_club_id etc.) — CREATE OR REPLACE cannot
-- rename parameters; P6b keeps passing the same named args.
-- tournament_caller_can_manage stays as the deprecated alias of
-- tournament_caller_can_administer (OE-4) and is NOT touched here.
--
-- ====================== RPC JSON / WIRE KEY MAP (for P6b) ==================
-- OUTPUT keys renamed 'club_id' -> 'organizer_team_id':
--   organizer_team_get           (top-level result key)
--   organizer_team_invite        (user_inbox_messages.action_payload key)
--   organizer_team_remove_member (user_inbox_messages.action_payload key)
--   organizer_team_request_join  (user_inbox_messages.action_payload key)
--   tournament_get               (result.tournament.organizer_team_id)
-- INPUT keys renamed 'club_id' -> 'organizer_team_id' (p_setup JSON):
--   tournament_create, tournament_update
-- NOT changed (behaviour-neutral; kinds are P7 scope): inbox kinds
--   'club_invitation', 'club_join_request', 'club_member_removed';
--   club_audit_events kinds; error codes; stage-graph template visibility
--   value 'club'. PostgREST direct reads of team_members / tournaments /
--   tournament_stage_graph_templates now serve organizer_team_id.
--
-- ============================ BODY UPDATE BASIS ============================
-- Every CREATE OR REPLACE below was generated from the LAST APPLIED body
-- (pg_get_functiondef of the fully migrated local stack, migration list
-- clean at 20261282500000 = last on-disk definition; per-function on-disk
-- anchors in docs/plans/permissions-organizer-teams/P6_BASELINE.md). The
-- diff of each body against its basis contains ONLY these token
-- replacements (machine-verified by reverse-mapping, see P6_BASELINE.md):
--   clubs -> organizer_teams, club_memberships -> team_members,
--   club_id -> organizer_team_id (renamed columns + JSON wire keys only;
--   club_id columns of club_invitations / club_join_requests /
--   club_audit_events are preserved), old -> new function names.
-- club_founding_code is renamed but NOT re-created (its body references
-- none of the renamed identifiers).
--
-- Pre-migration probes (read-only psql, 2026-06-13, stack at
-- 20261282500000): pg_policies count clubs = 1, club_memberships = 1;
-- row counts clubs = 1, club_memberships = 1; pg_publication_tables rows
-- for clubs/club_memberships/tournaments = 0; no public function named
-- organizer_* / is_active_organizer_team_member / is_organizer_team_manager.

-- ---- 1. table renames (policies/indexes/constraints/triggers follow) ----
ALTER TABLE public.clubs RENAME TO organizer_teams;
ALTER TABLE public.club_memberships RENAME TO team_members;

-- ---- 2. column renames ---------------------------------------------------
ALTER TABLE public.team_members RENAME COLUMN club_id TO organizer_team_id;
ALTER TABLE public.tournaments RENAME COLUMN club_id TO organizer_team_id;
ALTER TABLE public.tournament_stage_graph_templates
  RENAME COLUMN club_id TO organizer_team_id;

-- ---- 3. function renames (exact identity signatures, no overloads) ------
ALTER FUNCTION public.club_caller_can_publish() RENAME TO organizer_team_caller_can_publish;
ALTER FUNCTION public.club_caller_is_organizer() RENAME TO organizer_team_caller_is_organizer;
ALTER FUNCTION public.club_create(text) RENAME TO organizer_team_create;
ALTER FUNCTION public.club_founding_code() RENAME TO organizer_team_founding_code;
ALTER FUNCTION public.club_get(uuid) RENAME TO organizer_team_get;
ALTER FUNCTION public.club_invitation_respond(uuid, boolean) RENAME TO organizer_team_invitation_respond;
ALTER FUNCTION public.club_invite(uuid, uuid, text) RENAME TO organizer_team_invite;
ALTER FUNCTION public.club_invite_by_nickname(uuid, text, text) RENAME TO organizer_team_invite_by_nickname;
ALTER FUNCTION public.club_leave(uuid) RENAME TO organizer_team_leave;
ALTER FUNCTION public.club_list_for_caller() RENAME TO organizer_team_list_for_caller;
ALTER FUNCTION public.club_list_join_requests(uuid) RENAME TO organizer_team_list_join_requests;
ALTER FUNCTION public.club_name_available(text, uuid) RENAME TO organizer_team_name_available;
ALTER FUNCTION public.club_remove_member(uuid, uuid) RENAME TO organizer_team_remove_member;
ALTER FUNCTION public.club_request_join(uuid) RENAME TO organizer_team_request_join;
ALTER FUNCTION public.club_respond_join_request(uuid, boolean) RENAME TO organizer_team_respond_join_request;
ALTER FUNCTION public.club_set_member_roles(uuid, uuid, text[]) RENAME TO organizer_team_set_member_roles;
ALTER FUNCTION public.is_active_club_member(uuid, uuid) RENAME TO is_active_organizer_team_member;
ALTER FUNCTION public.is_club_manager(uuid, uuid) RENAME TO is_organizer_team_manager;

-- ---- 4. body updates (token-only; basis = last applied body each) -------
-- ---- body update (basis: last applied body of club_caller_can_publish) ----
CREATE OR REPLACE FUNCTION public.organizer_team_caller_can_publish()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.team_members
     WHERE user_id = auth.uid()
       AND removed_at IS NULL
       AND (roles && ARRAY['owner','admin','organizer']::text[])
  );
$function$

;

-- ---- body update (basis: last applied body of club_caller_is_organizer) ----
CREATE OR REPLACE FUNCTION public.organizer_team_caller_is_organizer()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.user_profiles
     WHERE user_id = auth.uid()
       AND can_found_clubs = true
  )
  OR EXISTS (
    SELECT 1 FROM public.team_members
     WHERE user_id = auth.uid()
       AND removed_at IS NULL
       AND roles && ARRAY['owner','admin','referee']::text[]
  );
$function$

;

-- ---- body update (basis: last applied body of club_create) ----
CREATE OR REPLACE FUNCTION public.organizer_team_create(p_display_name text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
    SELECT 1 FROM public.organizer_teams c
     WHERE lower(btrim(c.display_name)) = lower(btrim(p_display_name))
  ) THEN
    RAISE EXCEPTION 'a club named "%" already exists', btrim(p_display_name)
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.organizer_teams(display_name, created_by)
    VALUES (p_display_name, v_caller)
    RETURNING id INTO v_club_id;

  INSERT INTO public.team_members(organizer_team_id, user_id, roles)
    VALUES (v_club_id, v_caller, ARRAY['owner']::text[]);

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (v_club_id, 'club_created', v_caller,
            jsonb_build_object('display_name', p_display_name));

  RETURN v_club_id;
END;
$function$

;

-- ---- body update (basis: last applied body of club_get) ----
CREATE OR REPLACE FUNCTION public.organizer_team_get(p_club_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller uuid;
  v_club   public.organizer_teams%ROWTYPE;
  v_members jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_club FROM public.organizer_teams WHERE id = p_club_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'club not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'membership_id', m.id,
           'user_id',       m.user_id,
           'display_name',  p.nickname,
           'roles',         to_jsonb(m.roles),
           'joined_at',     m.joined_at
         ) ORDER BY m.joined_at), '[]'::jsonb)
    INTO v_members
    FROM public.team_members m
    LEFT JOIN public.user_profiles p ON p.user_id = m.user_id
   WHERE m.organizer_team_id = p_club_id AND m.removed_at IS NULL;

  RETURN jsonb_build_object(
    'organizer_team_id',      v_club.id,
    'display_name', v_club.display_name,
    'created_by',   v_club.created_by,
    'dissolved_at', v_club.dissolved_at,
    'created_at',   v_club.created_at,
    'updated_at',   v_club.updated_at,
    'members',      v_members
  );
END;
$function$

;

-- ---- body update (basis: last applied body of club_invitation_respond) ----
CREATE OR REPLACE FUNCTION public.organizer_team_invitation_respond(p_invitation_id uuid, p_accept boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
    INSERT INTO public.team_members(organizer_team_id, user_id, roles)
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
$function$

;

-- ---- body update (basis: last applied body of club_invite) ----
CREATE OR REPLACE FUNCTION public.organizer_team_invite(p_club_id uuid, p_invitee_user_id uuid, p_role text DEFAULT 'admin'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller     uuid;
  v_invitation uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.team_members m
     WHERE m.organizer_team_id = p_club_id
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
    SELECT 1 FROM public.team_members m
     WHERE m.organizer_team_id = p_club_id
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
      jsonb_build_object('organizer_team_id', p_club_id, 'invitation_id', v_invitation,
                         'role', p_role)
    );

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_invited', v_caller,
            jsonb_build_object('invitee_user_id', p_invitee_user_id,
                               'invitation_id', v_invitation));

  RETURN v_invitation;
END;
$function$

;

-- ---- body update (basis: last applied body of club_invite_by_nickname) ----
CREATE OR REPLACE FUNCTION public.organizer_team_invite_by_nickname(p_club_id uuid, p_nickname text, p_role text DEFAULT 'admin'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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

  RETURN public.organizer_team_invite(p_club_id, v_invitee, p_role);
END;
$function$

;

-- ---- body update (basis: last applied body of club_leave) ----
CREATE OR REPLACE FUNCTION public.organizer_team_leave(p_club_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
    FROM public.team_members
   WHERE organizer_team_id = p_club_id AND user_id = v_caller AND removed_at IS NULL;
  IF v_is_owner IS NULL THEN
    RAISE EXCEPTION 'not a member' USING ERRCODE = 'P0002';
  END IF;

  SELECT count(*) INTO v_other_members
    FROM public.team_members
   WHERE organizer_team_id = p_club_id AND removed_at IS NULL AND user_id <> v_caller;

  IF v_is_owner THEN
    SELECT count(*) INTO v_other_owners
      FROM public.team_members
     WHERE organizer_team_id = p_club_id AND removed_at IS NULL
       AND user_id <> v_caller AND (roles && ARRAY['owner']::text[]);
    IF v_other_owners = 0 AND v_other_members > 0 THEN
      RAISE EXCEPTION 'LAST_OWNER' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.team_members
     SET removed_at = now(), removed_by = v_caller
   WHERE organizer_team_id = p_club_id AND user_id = v_caller AND removed_at IS NULL;

  -- Sole member leaving dissolves the club.
  IF v_other_members = 0 THEN
    UPDATE public.organizer_teams SET dissolved_at = now()
     WHERE id = p_club_id AND dissolved_at IS NULL;
  END IF;

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_left', v_caller, '{}'::jsonb);
END;
$function$

;

-- ---- body update (basis: last applied body of club_list_for_caller) ----
CREATE OR REPLACE FUNCTION public.organizer_team_list_for_caller()
 RETURNS SETOF organizer_teams
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT c.*
      FROM public.organizer_teams c
      JOIN public.team_members m ON m.organizer_team_id = c.id
     WHERE m.user_id = v_caller
       AND m.removed_at IS NULL
     ORDER BY c.created_at DESC;
END;
$function$

;

-- ---- body update (basis: last applied body of club_list_join_requests) ----
CREATE OR REPLACE FUNCTION public.organizer_team_list_join_requests(p_club_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller uuid;
  v_out    jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_organizer_team_manager(p_club_id, v_caller) THEN
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
$function$

;

-- ---- body update (basis: last applied body of club_name_available) ----
CREATE OR REPLACE FUNCTION public.organizer_team_name_available(p_display_name text, p_exclude_club_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF p_display_name IS NULL OR length(btrim(p_display_name)) = 0 THEN
    RETURN false;
  END IF;
  RETURN NOT EXISTS (
    SELECT 1 FROM public.organizer_teams c
     WHERE lower(btrim(c.display_name)) = lower(btrim(p_display_name))
       AND (p_exclude_club_id IS NULL OR c.id <> p_exclude_club_id)
  );
END;
$function$

;

-- ---- body update (basis: last applied body of club_remove_member) ----
CREATE OR REPLACE FUNCTION public.organizer_team_remove_member(p_club_id uuid, p_member_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller       uuid;
  v_is_owner     boolean;
  v_other_owners int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_organizer_team_manager(p_club_id, v_caller) THEN
    RAISE EXCEPTION 'caller is not a club manager' USING ERRCODE = '42501';
  END IF;
  IF p_member_user_id = v_caller THEN
    RAISE EXCEPTION 'USE_LEAVE' USING ERRCODE = 'P0001';
  END IF;

  SELECT (roles && ARRAY['owner']::text[]) INTO v_is_owner
    FROM public.team_members
   WHERE organizer_team_id = p_club_id AND user_id = p_member_user_id
     AND removed_at IS NULL;
  IF v_is_owner IS NULL THEN
    RAISE EXCEPTION 'member not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_is_owner THEN
    SELECT count(*) INTO v_other_owners
      FROM public.team_members
     WHERE organizer_team_id = p_club_id AND removed_at IS NULL
       AND user_id <> p_member_user_id
       AND (roles && ARRAY['owner']::text[]);
    IF v_other_owners = 0 THEN
      RAISE EXCEPTION 'LAST_OWNER' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.team_members
     SET removed_at = now(), removed_by = v_caller
   WHERE organizer_team_id = p_club_id AND user_id = p_member_user_id
     AND removed_at IS NULL;

  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    VALUES (p_member_user_id, 'club_member_removed', 'Vereins-Mitgliedschaft beendet',
            'Du wurdest aus einem Verein entfernt.',
            jsonb_build_object('organizer_team_id', p_club_id));

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_removed', v_caller,
            jsonb_build_object('member_user_id', p_member_user_id));
END;
$function$

;

-- ---- body update (basis: last applied body of club_request_join) ----
CREATE OR REPLACE FUNCTION public.organizer_team_request_join(p_club_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
    SELECT 1 FROM public.team_members
     WHERE organizer_team_id = p_club_id AND user_id = v_caller AND removed_at IS NULL
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
           jsonb_build_object('organizer_team_id', p_club_id, 'request_id', v_request)
      FROM public.team_members m
     WHERE m.organizer_team_id = p_club_id AND m.removed_at IS NULL
       AND (m.roles && ARRAY['owner','admin']::text[]);

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'join_requested', v_caller,
            jsonb_build_object('request_id', v_request));

  RETURN v_request;
END;
$function$

;

-- ---- body update (basis: last applied body of club_respond_join_request) ----
CREATE OR REPLACE FUNCTION public.organizer_team_respond_join_request(p_request_id uuid, p_accept boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
  IF NOT public.is_organizer_team_manager(v_req.club_id, v_caller) THEN
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
    INSERT INTO public.team_members(organizer_team_id, user_id, roles)
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
$function$

;

-- ---- body update (basis: last applied body of club_set_member_roles) ----
CREATE OR REPLACE FUNCTION public.organizer_team_set_member_roles(p_club_id uuid, p_member_user_id uuid, p_roles text[])
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
    SELECT 1 FROM public.team_members m
     WHERE m.organizer_team_id = p_club_id
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
    FROM public.team_members
   WHERE organizer_team_id = p_club_id AND user_id = p_member_user_id
     AND removed_at IS NULL;
  IF v_was_owner IS NULL THEN
    RAISE EXCEPTION 'member not found' USING ERRCODE = 'P0002';
  END IF;

  v_will_owner := p_roles && ARRAY['owner']::text[];

  -- Block demoting the final owner.
  IF v_was_owner AND NOT v_will_owner THEN
    SELECT count(*) INTO v_other_owners
      FROM public.team_members
     WHERE organizer_team_id = p_club_id
       AND removed_at IS NULL
       AND user_id <> p_member_user_id
       AND (roles && ARRAY['owner']::text[]);
    IF v_other_owners = 0 THEN
      RAISE EXCEPTION 'LAST_OWNER' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  UPDATE public.team_members
     SET roles = p_roles
   WHERE organizer_team_id = p_club_id AND user_id = p_member_user_id
     AND removed_at IS NULL;

  INSERT INTO public.club_audit_events(club_id, kind, actor_user_id, payload)
    VALUES (p_club_id, 'member_roles_set', v_caller,
            jsonb_build_object('member_user_id', p_member_user_id,
                               'roles', to_jsonb(p_roles)));
END;
$function$

;

-- ---- body update (basis: last applied body of is_active_club_member) ----
CREATE OR REPLACE FUNCTION public.is_active_organizer_team_member(p_club_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.team_members
     WHERE organizer_team_id = p_club_id
       AND user_id = p_user_id
       AND removed_at IS NULL
  );
$function$

;

-- ---- body update (basis: last applied body of is_club_manager) ----
CREATE OR REPLACE FUNCTION public.is_organizer_team_manager(p_club_id uuid, p_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.team_members
     WHERE organizer_team_id = p_club_id
       AND user_id = p_user_id
       AND removed_at IS NULL
       AND (roles && ARRAY['owner','admin']::text[])
  );
$function$

;

-- ---- body update (basis: last applied body of tournament_caller_can_setup) ----
CREATE OR REPLACE FUNCTION public.tournament_caller_can_setup(p_tournament_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.tournaments t
     WHERE t.id = p_tournament_id
       AND (
         -- Creator: unchanged behaviour.
         t.created_by = auth.uid()
         OR
         -- Club owner/admin/organizer of THIS tournament's club.
         (t.organizer_team_id IS NOT NULL AND EXISTS (
            SELECT 1
              FROM public.team_members cm
             WHERE cm.organizer_team_id = t.organizer_team_id
               AND cm.user_id = auth.uid()
               AND cm.removed_at IS NULL
               AND (cm.roles && ARRAY['owner','admin']::text[])
         ))
       )
  );
$function$

;

-- ---- body update (basis: last applied body of tournament_caller_can_administer) ----
CREATE OR REPLACE FUNCTION public.tournament_caller_can_administer(p_tournament_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.tournaments t
     WHERE t.id = p_tournament_id
       AND (
         -- Creator: unchanged behaviour.
         t.created_by = auth.uid()
         OR
         -- Club owner/admin/organizer of THIS tournament's club.
         (t.organizer_team_id IS NOT NULL AND EXISTS (
            SELECT 1
              FROM public.team_members cm
             WHERE cm.organizer_team_id = t.organizer_team_id
               AND cm.user_id = auth.uid()
               AND cm.removed_at IS NULL
               AND (cm.roles && ARRAY['owner','admin','referee']::text[])
         ))
       )
  );
$function$

;

-- ---- body update (basis: last applied body of tournament_caller_is_organizer) ----
CREATE OR REPLACE FUNCTION public.tournament_caller_is_organizer()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT
    -- Profile organizer flag: default true, blocks only an explicit false.
    NOT EXISTS (
      SELECT 1 FROM public.user_profiles up
       WHERE up.user_id = auth.uid()
         AND up.is_organizer = false
    )
    OR
    -- Club owner/admin/organizer of any active membership.
    EXISTS (
      SELECT 1 FROM public.team_members cm
       WHERE cm.user_id = auth.uid()
         AND cm.removed_at IS NULL
         AND (cm.roles && ARRAY['owner','admin','organizer']::text[])
    );
$function$

;

-- ---- body update (basis: last applied body of tournament_create) ----
CREATE OR REPLACE FUNCTION public.tournament_create(p_display_name text, p_team_size integer, p_min_participants integer, p_max_participants integer, p_format text, p_match_format_config jsonb, p_tiebreaker_order text[], p_setup jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller        uuid;
  v_tournament_id uuid;
  v_scoring       text;
  v_setup         jsonb;
  v_club_id       uuid;   -- CLUB-LINK
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  v_setup := coalesce(p_setup, '{}'::jsonb);
  IF jsonb_typeof(v_setup) <> 'object' THEN
    RAISE EXCEPTION 'setup must be a JSON object' USING ERRCODE = '22023';
  END IF;

  IF p_display_name IS NULL OR length(p_display_name) < 1 OR length(p_display_name) > 60 THEN
    RAISE EXCEPTION 'display_name length must be 1..60' USING ERRCODE = '22023';
  END IF;
  IF p_team_size IS NULL OR p_team_size < 1 OR p_team_size > 6 THEN
    RAISE EXCEPTION 'team_size must be 1..6' USING ERRCODE = '22023';
  END IF;
  IF p_min_participants IS NULL OR p_min_participants < 2 THEN
    RAISE EXCEPTION 'min_participants must be >= 2' USING ERRCODE = '22023';
  END IF;
  IF p_max_participants IS NULL
     OR p_max_participants < p_min_participants
     OR p_max_participants > 200 THEN
    RAISE EXCEPTION 'max_participants must be in [min_participants, 200]'
      USING ERRCODE = '22023';
  END IF;
  IF p_format IS NULL OR p_format NOT IN (
       'round_robin','single_elimination','round_robin_then_ko',
       'schoch','swiss','schoch_then_ko','swiss_then_ko') THEN
    RAISE EXCEPTION 'invalid format' USING ERRCODE = '22023';
  END IF;
  IF p_match_format_config IS NULL OR jsonb_typeof(p_match_format_config) <> 'object' THEN
    RAISE EXCEPTION 'match_format_config must be a JSON object' USING ERRCODE = '22023';
  END IF;
  IF p_tiebreaker_order IS NULL OR array_length(p_tiebreaker_order, 1) IS NULL THEN
    RAISE EXCEPTION 'tiebreaker_order must be a non-empty array' USING ERRCODE = '22023';
  END IF;

  v_scoring := coalesce(v_setup->>'scoring', 'ekc');
  IF v_scoring NOT IN ('ekc','classic') THEN
    RAISE EXCEPTION 'scoring must be ekc or classic' USING ERRCODE = '22023';
  END IF;

  -- CLUB-LINK: optional organizing club from p_setup. If supplied, the
  -- caller must be an active owner/admin/organizer of it (defence in depth
  -- — the same role the manage helper later trusts).
  v_club_id := NULLIF(v_setup->>'organizer_team_id', '')::uuid;
  IF v_club_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.team_members cm
       WHERE cm.organizer_team_id = v_club_id
         AND cm.user_id = v_caller
         AND cm.removed_at IS NULL
         AND (cm.roles && ARRAY['owner','admin','organizer']::text[])
    ) THEN
      RAISE EXCEPTION 'not authorised for the requested club'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  INSERT INTO public.tournaments(
      created_by, organizer_team_id, display_name, team_size, min_participants, max_participants,
      format, scoring, match_format, tiebreaker_order, status,
      -- P6 setup fields
      location, venue_address, event_starts_at, checkin_until,
      registration_closes_at, weather_note, info_food, info_travel,
      info_accommodation, contact_name, contact_phone, entry_fee_cents,
      currency, payment_methods, rules_pdf_url, site_map_pdf_url,
      league_categories, rule_variants, ko_match_format, ko_round_formats,
      pitch_plan, mighty_finisher_quali, consolation_bracket, max_team_size,
      bracket_type, ko_matchup, ko_tiebreak_method,
      pool_phase_config, ko_config)
    VALUES (
      v_caller, v_club_id, p_display_name, p_team_size::smallint,
      p_min_participants::smallint, p_max_participants::smallint,
      p_format, v_scoring, p_match_format_config, p_tiebreaker_order, 'draft',
      v_setup->>'location',
      v_setup->>'venue_address',
      (v_setup->>'event_starts_at')::timestamptz,
      (v_setup->>'checkin_until')::timestamptz,
      (v_setup->>'registration_closes_at')::timestamptz,
      v_setup->>'weather_note',
      v_setup->>'info_food',
      v_setup->>'info_travel',
      v_setup->>'info_accommodation',
      v_setup->>'contact_name',
      v_setup->>'contact_phone',
      (v_setup->>'entry_fee_cents')::int,
      coalesce(v_setup->>'currency', 'CHF'),
      coalesce(
        array(SELECT jsonb_array_elements_text(v_setup->'payment_methods')),
        '{}'::text[]),
      v_setup->>'rules_pdf_url',
      v_setup->>'site_map_pdf_url',
      coalesce(
        array(SELECT jsonb_array_elements_text(v_setup->'league_categories')),
        '{}'::text[]),
      coalesce(v_setup->'rule_variants', jsonb_build_object(
        'sureshot', false, 'diggy', false,
        'opening_rule', '2-4-6', 'strafkubb_off_baseline', true)),
      v_setup->'ko_match_format',
      coalesce(v_setup->'ko_round_formats', '[]'::jsonb),
      v_setup->'pitch_plan',
      v_setup->'mighty_finisher_quali',
      v_setup->'consolation_bracket',
      (v_setup->>'max_team_size')::smallint,
      coalesce(v_setup->>'bracket_type', 'single_elimination'),
      coalesce(v_setup->>'ko_matchup', 'seed_high_vs_low'),
      coalesce(v_setup->>'ko_tiebreak_method', 'classic_kingtoss_removal'),
      v_setup->'pool_phase_config',
      v_setup->'ko_config')
    RETURNING id INTO v_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'created',
      v_caller,
      jsonb_build_object(
        'display_name',     p_display_name,
        'team_size',        p_team_size,
        'min_participants', p_min_participants,
        'max_participants', p_max_participants,
        'format',           p_format,
        'scoring',          v_scoring,
        'league_categories', coalesce(v_setup->'league_categories', '[]'::jsonb)
      )
    );

  RETURN jsonb_build_object('tournament_id', v_tournament_id);
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_update) ----
CREATE OR REPLACE FUNCTION public.tournament_update(p_tournament_id uuid, p_display_name text, p_team_size integer, p_min_participants integer, p_max_participants integer, p_format text, p_match_format_config jsonb, p_tiebreaker_order text[], p_setup jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_created_by uuid;
  v_scoring    text;
  v_setup      jsonb;
  v_club_id    uuid;   -- CLUB-LINK
  -- V2-B1 live-edit / recompute state:
  v_is_live          boolean;
  -- old (stored) structural values:
  v_old_format       text;
  v_old_bracket_type text;
  v_old_ko_matchup   text;
  v_old_pool_cfg     jsonb;
  v_old_ko_cfg       jsonb;
  -- new (incoming) structural values, computed exactly like the UPDATE below:
  v_new_bracket_type text;
  v_new_ko_matchup   text;
  v_new_pool_cfg     jsonb;
  v_new_ko_cfg       jsonb;
  -- per-phase change flags:
  v_group_changed    boolean;
  v_ko_changed       boolean;
  -- phase state:
  v_grp_generated    boolean;
  v_grp_played       boolean;
  v_ko_generated     boolean;
  v_ko_played        boolean;
  -- recompute flags:
  v_recompute_group  boolean := false;
  v_recompute_ko     boolean := false;
  -- recompute side-effect suppression: snapshots of pre-existing row ids so
  -- only the generator's freshly-inserted rows are cleaned up (created_at /
  -- sent_at default to now() = transaction start, so a timestamp marker is
  -- unreliable inside one transaction — we diff by id instead).
  v_pre_audit_ids    uuid[];
  v_pre_inbox_ids    uuid[];
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by,
         format, bracket_type, ko_matchup, pool_phase_config, ko_config
    INTO v_status, v_created_by,
         v_old_format, v_old_bracket_type, v_old_ko_matchup,
         v_old_pool_cfg, v_old_ko_cfg
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the organizer_team_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  -- V2-B1 status gate: pre-start statuses AND 'live' may be edited.
  -- 'finalized' and 'aborted' stay frozen.
  IF v_status NOT IN (
       'draft','published','registration_open','registration_closed',
       'live') THEN
    RAISE EXCEPTION 'tournament can only be edited before it is finalized'
      USING ERRCODE = '22023', HINT = 'TOURNAMENT_LOCKED';
  END IF;

  v_is_live := (v_status = 'live');

  v_setup := coalesce(p_setup, '{}'::jsonb);
  IF jsonb_typeof(v_setup) <> 'object' THEN
    RAISE EXCEPTION 'setup must be a JSON object' USING ERRCODE = '22023';
  END IF;

  IF p_display_name IS NULL OR length(p_display_name) < 1
     OR length(p_display_name) > 60 THEN
    RAISE EXCEPTION 'display_name length must be 1..60' USING ERRCODE = '22023';
  END IF;
  IF p_team_size IS NULL OR p_team_size < 1 OR p_team_size > 6 THEN
    RAISE EXCEPTION 'team_size must be 1..6' USING ERRCODE = '22023';
  END IF;
  IF p_min_participants IS NULL OR p_min_participants < 2 THEN
    RAISE EXCEPTION 'min_participants must be >= 2' USING ERRCODE = '22023';
  END IF;
  IF p_max_participants IS NULL
     OR p_max_participants < p_min_participants
     OR p_max_participants > 200 THEN
    RAISE EXCEPTION 'max_participants must be in [min_participants, 200]'
      USING ERRCODE = '22023';
  END IF;
  IF p_format IS NULL OR p_format NOT IN (
       'round_robin','single_elimination','round_robin_then_ko',
       'schoch','swiss','schoch_then_ko','swiss_then_ko') THEN
    RAISE EXCEPTION 'invalid format' USING ERRCODE = '22023';
  END IF;
  IF p_match_format_config IS NULL
     OR jsonb_typeof(p_match_format_config) <> 'object' THEN
    RAISE EXCEPTION 'match_format_config must be a JSON object'
      USING ERRCODE = '22023';
  END IF;
  IF p_tiebreaker_order IS NULL
     OR array_length(p_tiebreaker_order, 1) IS NULL THEN
    RAISE EXCEPTION 'tiebreaker_order must be a non-empty array'
      USING ERRCODE = '22023';
  END IF;

  v_scoring := coalesce(v_setup->>'scoring', 'ekc');
  IF v_scoring NOT IN ('ekc','classic') THEN
    RAISE EXCEPTION 'scoring must be ekc or classic' USING ERRCODE = '22023';
  END IF;

  -- CLUB-LINK: re-target / clear the organizing club. If a new organizer_team_id is
  -- supplied, the caller must be an active owner/admin/organizer of it
  -- (defence in depth — same role the manage helper trusts). A NULL/absent
  -- key clears the link.
  v_club_id := NULLIF(v_setup->>'organizer_team_id', '')::uuid;
  IF v_club_id IS NOT NULL
     AND v_club_id IS DISTINCT FROM (
       SELECT organizer_team_id FROM public.tournaments WHERE id = p_tournament_id) THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.team_members cm
       WHERE cm.organizer_team_id = v_club_id
         AND cm.user_id = v_caller
         AND cm.removed_at IS NULL
         AND (cm.roles && ARRAY['owner','admin','organizer']::text[])
    ) THEN
      RAISE EXCEPTION 'not authorised for the requested club'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  -- ==================================================================
  -- V2-B1 STRUCTURAL SAFETY (live only). Pre-start edits skip this block
  -- entirely and behave exactly like the 20261201000032 baseline: no
  -- phase exists yet, the UPDATE just persists everything.
  --
  -- Future-format fields (match_format, ko_match_format, ko_round_formats,
  -- ko_tiebreak_method) are NOT inspected here — they are always-allowed
  -- live and never trigger regeneration (matches read their round format
  -- at evaluation time). Always-safe fields likewise pass through.
  -- ==================================================================
  IF v_is_live THEN
    -- New structural values, mirrored from the UPDATE column expressions
    -- below so the comparison is exact.
    v_new_bracket_type := coalesce(v_setup->>'bracket_type', 'single_elimination');
    v_new_ko_matchup   := coalesce(v_setup->>'ko_matchup', 'seed_high_vs_low');
    v_new_pool_cfg     := v_setup->'pool_phase_config';
    v_new_ko_cfg       := v_setup->'ko_config';

    -- FORMAT-FAMILY consistency (live only). A live format switch must stay
    -- within the same phase family. The generators read the format implicitly
    -- (pool generator always builds a group phase; pure-KO is generated by a
    -- different path), so crossing families while a phase already exists would
    -- regenerate the WRONG kind of phase and leave an inconsistent tournament
    -- (e.g. a pure-KO format carrying group matches). Reject such a switch with
    -- a clear German message rather than blindly regenerating. Families:
    --   pool-based / hybrid (has a group phase): round_robin, schoch, swiss and
    --   their *_then_ko variants -> _tournament_format_family() = 'pool'
    --   pure KO: single_elimination -> 'ko'
    IF p_format IS DISTINCT FROM v_old_format
       AND public._tournament_format_family(p_format)
           IS DISTINCT FROM public._tournament_format_family(v_old_format) THEN
      RAISE EXCEPTION
        'Formatwechsel nicht moeglich, das gewaehlte Format passt nicht zur '
        'laufenden Turnierstruktur'
        USING ERRCODE = '22023', HINT = 'STRUCTURE_LOCKED';
    END IF;

    -- GROUP-phase structural inputs: format, pool_phase_config.
    v_group_changed :=
         (p_format        IS DISTINCT FROM v_old_format)
      OR (v_new_pool_cfg  IS DISTINCT FROM v_old_pool_cfg);

    -- KO-phase structural inputs: format, bracket_type, ko_matchup, ko_config.
    v_ko_changed :=
         (p_format          IS DISTINCT FROM v_old_format)
      OR (v_new_bracket_type IS DISTINCT FROM v_old_bracket_type)
      OR (v_new_ko_matchup   IS DISTINCT FROM v_old_ko_matchup)
      OR (v_new_ko_cfg       IS DISTINCT FROM v_old_ko_cfg);

    IF v_group_changed THEN
      SELECT generated, has_played
        INTO v_grp_generated, v_grp_played
        FROM public._tournament_phase_state(p_tournament_id, 'group');
      IF v_grp_played THEN
        RAISE EXCEPTION
          'Strukturaenderung nicht moeglich, Phase laeuft bereits'
          USING ERRCODE = '22023', HINT = 'STRUCTURE_LOCKED';
      END IF;
      -- generated + fully unplayed -> safe recompute of the group phase.
      IF v_grp_generated THEN
        v_recompute_group := true;
      END IF;
    END IF;

    IF v_ko_changed THEN
      SELECT generated, has_played
        INTO v_ko_generated, v_ko_played
        FROM public._tournament_phase_state(p_tournament_id, 'ko');
      IF v_ko_played THEN
        RAISE EXCEPTION
          'Strukturaenderung nicht moeglich, Phase laeuft bereits'
          USING ERRCODE = '22023', HINT = 'STRUCTURE_LOCKED';
      END IF;
      -- generated + fully unplayed -> safe recompute of the ko phase.
      IF v_ko_generated THEN
        v_recompute_ko := true;
      END IF;
    END IF;
  END IF;

  UPDATE public.tournaments SET
      organizer_team_id                = v_club_id,
      display_name           = p_display_name,
      team_size              = p_team_size::smallint,
      min_participants       = p_min_participants::smallint,
      max_participants       = p_max_participants::smallint,
      format                 = p_format,
      scoring                = v_scoring,
      match_format           = p_match_format_config,
      tiebreaker_order       = p_tiebreaker_order,
      location               = v_setup->>'location',
      venue_address          = v_setup->>'venue_address',
      event_starts_at        = (v_setup->>'event_starts_at')::timestamptz,
      checkin_until          = (v_setup->>'checkin_until')::timestamptz,
      registration_closes_at = (v_setup->>'registration_closes_at')::timestamptz,
      weather_note           = v_setup->>'weather_note',
      info_food              = v_setup->>'info_food',
      info_travel            = v_setup->>'info_travel',
      info_accommodation     = v_setup->>'info_accommodation',
      contact_name           = v_setup->>'contact_name',
      contact_phone          = v_setup->>'contact_phone',
      entry_fee_cents        = (v_setup->>'entry_fee_cents')::int,
      currency               = coalesce(v_setup->>'currency', 'CHF'),
      payment_methods        = coalesce(
        array(SELECT jsonb_array_elements_text(v_setup->'payment_methods')),
        '{}'::text[]),
      rules_pdf_url          = v_setup->>'rules_pdf_url',
      site_map_pdf_url       = v_setup->>'site_map_pdf_url',
      league_categories      = coalesce(
        array(SELECT jsonb_array_elements_text(v_setup->'league_categories')),
        '{}'::text[]),
      rule_variants          = coalesce(v_setup->'rule_variants', jsonb_build_object(
        'sureshot', false, 'diggy', false,
        'opening_rule', '2-4-6', 'strafkubb_off_baseline', true)),
      ko_match_format        = v_setup->'ko_match_format',
      ko_round_formats       = coalesce(v_setup->'ko_round_formats', '[]'::jsonb),
      pitch_plan             = v_setup->'pitch_plan',
      mighty_finisher_quali  = v_setup->'mighty_finisher_quali',
      consolation_bracket    = v_setup->'consolation_bracket',
      max_team_size          = (v_setup->>'max_team_size')::smallint,
      bracket_type           = coalesce(v_setup->>'bracket_type', 'single_elimination'),
      ko_matchup             = coalesce(v_setup->>'ko_matchup', 'seed_high_vs_low'),
      ko_tiebreak_method     = coalesce(
        v_setup->>'ko_tiebreak_method', 'classic_kingtoss_removal'),
      pool_phase_config      = v_setup->'pool_phase_config',
      ko_config              = v_setup->'ko_config',
      invite_only            = coalesce((v_setup->>'invite_only')::boolean,
                                        public.tournaments.invite_only)
    WHERE id = p_tournament_id;

  -- ==================================================================
  -- V2-B1 RECOMPUTE (safe, unplayed-only). Reached ONLY when a structural
  -- field changed AND the affected phase is generated + fully unplayed.
  -- We delete only the 'scheduled' (unplayed) matches of that phase and
  -- re-run the EXISTING generation RPC. Finalised / played matches are
  -- never deleted (none exist in a fully-unplayed phase, but the DELETE is
  -- scoped to status 'scheduled' as defence in depth).
  --
  -- SIDE-EFFECT SUPPRESSION: the canonical generators were written for the
  -- FIRST start of a phase and, as a side effect, push a 'Turnier gestartet'
  -- inbox notification to every participant and emit a 'pool_phase_started' /
  -- 'ko_phase_started' audit event. A pure structural correction of an
  -- UNPLAYED phase must not spam participants ("the tournament already
  -- started") nor pollute the audit trail with a fake start. We must keep
  -- REUSING the generators verbatim (no new pairing logic, no signature
  -- change that would ripple into other callers), so instead we mark the
  -- transaction time before the call and, after it returns, remove exactly
  -- the inbox messages it just sent and relabel the start audit event to the
  -- dedicated 'phase_recomputed' kind. All within this transaction; on
  -- ROLLBACK nothing leaks. We diff by row id (not timestamp) because the
  -- defaults stamp now() = transaction start.
  -- ==================================================================
  IF v_recompute_group THEN
    DELETE FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND phase = 'group'
        AND status = 'scheduled';

    SELECT coalesce(array_agg(id), '{}')
      INTO v_pre_audit_ids
      FROM public.tournament_audit_events
      WHERE tournament_id = p_tournament_id;
    SELECT coalesce(array_agg(id), '{}')
      INTO v_pre_inbox_ids
      FROM public.user_inbox_messages
      WHERE (action_payload->>'tournament_id')::uuid = p_tournament_id;

    -- Re-uses the canonical pool-phase generator with the freshly stored
    -- pool_phase_config. It re-asserts the manage gate, re-builds pools and
    -- round-1 group matches and keeps status='live'/started_at.
    PERFORM public.tournament_start_pool_phase(
      p_tournament_id, coalesce(v_new_pool_cfg, '{}'::jsonb));

    -- Suppress the generator's "started" notifications (newly inserted only).
    DELETE FROM public.user_inbox_messages
      WHERE kind = 'tournament_started'
        AND (action_payload->>'tournament_id')::uuid = p_tournament_id
        AND NOT (id = ANY (v_pre_inbox_ids));
    -- Relabel the generator's start audit event into a recompute event.
    UPDATE public.tournament_audit_events
      SET kind = 'phase_recomputed',
          payload = coalesce(payload, '{}'::jsonb)
            || jsonb_build_object('phase', 'group', 'recompute', true)
      WHERE tournament_id = p_tournament_id
        AND kind = 'pool_phase_started'
        AND NOT (id = ANY (v_pre_audit_ids));
  END IF;

  IF v_recompute_ko THEN
    DELETE FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND phase IN ('ko','third_place','final','wb','lb','grand_final',
                      'grand_final_reset','consolation','consolation_third_place')
        AND status = 'scheduled';

    SELECT coalesce(array_agg(id), '{}')
      INTO v_pre_audit_ids
      FROM public.tournament_audit_events
      WHERE tournament_id = p_tournament_id;
    SELECT coalesce(array_agg(id), '{}')
      INTO v_pre_inbox_ids
      FROM public.user_inbox_messages
      WHERE (action_payload->>'tournament_id')::uuid = p_tournament_id;

    -- Re-uses the canonical KO-phase generator with the freshly stored
    -- ko_config. It re-asserts the manage gate, requires the group phase to
    -- be complete (untouched here) and that no KO match exists (the unplayed
    -- bracket was just deleted), and rebuilds the bracket.
    PERFORM public.tournament_start_ko_phase(
      p_tournament_id, coalesce(v_new_ko_cfg, '{}'::jsonb));

    -- Suppress the generator's "new round / started" notifications.
    DELETE FROM public.user_inbox_messages
      WHERE kind IN ('tournament_started', 'tournament_round')
        AND (action_payload->>'tournament_id')::uuid = p_tournament_id
        AND NOT (id = ANY (v_pre_inbox_ids));
    -- Relabel the generator's start audit event into a recompute event.
    UPDATE public.tournament_audit_events
      SET kind = 'phase_recomputed',
          payload = coalesce(payload, '{}'::jsonb)
            || jsonb_build_object('phase', 'ko', 'recompute', true)
      WHERE tournament_id = p_tournament_id
        AND kind = 'ko_phase_started'
        AND NOT (id = ANY (v_pre_audit_ids));
  END IF;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'updated',
      v_caller,
      jsonb_build_object(
        'display_name',     p_display_name,
        'team_size',        p_team_size,
        'min_participants', p_min_participants,
        'max_participants', p_max_participants,
        'format',           p_format,
        'scoring',          v_scoring,
        'league_categories', coalesce(v_setup->'league_categories', '[]'::jsonb),
        'live_edit',         v_is_live,
        'recompute_group',   v_recompute_group,
        'recompute_ko',      v_recompute_ko
      )
    );

  RETURN jsonb_build_object(
    'tournament_id',   p_tournament_id,
    'recompute_group', v_recompute_group,
    'recompute_ko',    v_recompute_ko);
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_get) ----
CREATE OR REPLACE FUNCTION public.tournament_get(p_tournament_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller       uuid;
  v_status       text;
  v_created_by   uuid;
  v_tournament   jsonb;
  v_participants jsonb;
  v_matches      jsonb;
  v_audit        jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments WHERE id = p_tournament_id;
  IF v_status IS NULL THEN
    RETURN NULL;
  END IF;
  IF v_status = 'draft' AND v_created_by IS DISTINCT FROM v_caller THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
           'tournament_id',        t.id,
           'created_by',           t.created_by,
           -- CF5 (K28): organizing club so the detail screen can render the
           -- Verein / Spasstournier category. NULL = personal tournament.
           'organizer_team_id',              t.organizer_team_id,
           'display_name',         t.display_name,
           'team_size',            t.team_size,
           'max_team_size',        t.max_team_size,
           'min_participants',     t.min_participants,
           'max_participants',     t.max_participants,
           'format',               t.format,
           'scoring',              t.scoring,
           'match_format_config',  t.match_format,
           'tiebreaker_order',     t.tiebreaker_order,
           'bye_points',           t.bye_points,
           'forfeit_points',       t.forfeit_points,
           'status',               t.status,
           'registration_opens_at',  t.registration_opens_at,
           'registration_closes_at', t.registration_closes_at,
           'started_at',           t.started_at,
           'completed_at',         t.completed_at,
           'published_at',         t.published_at,
           'created_at',           t.created_at,
           'updated_at',           t.updated_at,
           -- P7: P6 setup fields, projected so the edit screen can
           -- pre-fill the wizard from the current values.
           'location',             t.location,
           'venue_address',        t.venue_address,
           'event_starts_at',      t.event_starts_at,
           'checkin_until',        t.checkin_until,
           'weather_note',         t.weather_note,
           'info_food',            t.info_food,
           'info_travel',          t.info_travel,
           'info_accommodation',   t.info_accommodation,
           'contact_name',         t.contact_name,
           'contact_phone',        t.contact_phone,
           'entry_fee_cents',      t.entry_fee_cents,
           'currency',             t.currency,
           'payment_methods',      to_jsonb(t.payment_methods),
           'rules_pdf_url',        t.rules_pdf_url,
           'site_map_pdf_url',     t.site_map_pdf_url,
           'league_categories',    to_jsonb(t.league_categories),
           'rule_variants',        t.rule_variants,
           'ko_match_format',      t.ko_match_format,
           'ko_round_formats',     t.ko_round_formats,
           'pitch_plan',           t.pitch_plan,
           'mighty_finisher_quali', t.mighty_finisher_quali,
           'consolation_bracket',  t.consolation_bracket,
           'bracket_type',         t.bracket_type,
           'ko_matchup',           t.ko_matchup,
           'ko_tiebreak_method',   t.ko_tiebreak_method,
           'pool_phase_config',    t.pool_phase_config,
           'ko_config',            t.ko_config
         )
    INTO v_tournament
    FROM public.tournaments t WHERE t.id = p_tournament_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'participant_id',      p.id,
           'tournament_id',       p.tournament_id,
           'user_id',             p.user_id,
           'nickname',            up.nickname,
           'display_name',        COALESCE(up.nickname, tm.display_name),
           'checked_in_at',       p.checked_in_at,
           'registration_status', p.registration_status,
           'seed',                p.seed,
           'registered_at',       p.registered_at,
           'responded_at',        p.responded_at,
           'withdrew_at',         p.withdrew_at
         ) ORDER BY p.registered_at), '[]'::jsonb)
    INTO v_participants
    FROM public.tournament_participants p
    LEFT JOIN public.user_profiles up ON up.user_id = p.user_id
    LEFT JOIN public.teams         tm ON tm.id = p.team_id
    WHERE p.tournament_id = p_tournament_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'match_id',              m.id,
           'tournament_id',         m.tournament_id,
           'round_number',          m.round_number,
           'match_number_in_round', m.match_number_in_round,
           'participant_a_id',      m.participant_a,
           'participant_b_id',      m.participant_b,
           'participant_a_display_name',
             COALESCE(upa.nickname, tma.display_name),
           'participant_b_display_name',
             COALESCE(upb.nickname, tmb.display_name),
           'status',                m.status,
           'consensus_round',       m.consensus_round,
           'started_at',            m.started_at,
           'completed_at',          m.finalized_at,
           'winner_participant_id', m.winner_participant,
           'final_score_a',         m.final_score_a,
           'final_score_b',         m.final_score_b
         ) ORDER BY m.round_number, m.match_number_in_round), '[]'::jsonb)
    INTO v_matches
    FROM public.tournament_matches m
    LEFT JOIN public.tournament_participants pa ON pa.id = m.participant_a
    LEFT JOIN public.user_profiles            upa ON upa.user_id = pa.user_id
    LEFT JOIN public.teams                    tma ON tma.id      = pa.team_id
    LEFT JOIN public.tournament_participants pb ON pb.id = m.participant_b
    LEFT JOIN public.user_profiles            upb ON upb.user_id = pb.user_id
    LEFT JOIN public.teams                    tmb ON tmb.id      = pb.team_id
    WHERE m.tournament_id = p_tournament_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'kind',          e.kind,
           'actor_user_id', e.actor_user_id,
           'payload',       e.payload,
           'at',            e.created_at
         ) ORDER BY e.created_at DESC), '[]'::jsonb)
    INTO v_audit
    FROM (
      SELECT kind, actor_user_id, payload, created_at
        FROM public.tournament_audit_events
       WHERE tournament_id = p_tournament_id
       ORDER BY created_at DESC
       LIMIT 50
    ) e;

  RETURN jsonb_build_object(
    'tournament',   v_tournament,
    'participants', v_participants,
    'matches',      v_matches,
    'audit_tail',   v_audit
  );
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_is_rated) ----
CREATE OR REPLACE FUNCTION public.tournament_is_rated(p_tournament_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- A tournament is rated (league-/ranking-relevant) exactly when it has
  -- an organizing club. "Spasstournier – ohne Wertung" leaves organizer_team_id
  -- NULL and is therefore never rated. league_categories is intentionally
  -- NOT part of the criterion: the EINZEL bucket has no categories yet is
  -- still rated whenever a club is present.
  SELECT EXISTS (
    SELECT 1
      FROM public.tournaments t
     WHERE t.id = p_tournament_id
       AND t.organizer_team_id IS NOT NULL
  );
$function$

;

-- ---- body update (basis: last applied body of tournament_write_skv_awards) ----
CREATE OR REPLACE FUNCTION public.tournament_write_skv_awards()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- RATED gate (CF1): unrated (no club) tournaments earn no season awards.
  if new.organizer_team_id is null then
    return new;
  end if;

  -- Idempotency: awards are written only here (append-only table, no client
  -- INSERT path), so an existing row for this tournament means we already ran.
  if exists (
    select 1
    from public.season_standings_awards
    where tournament_id = new.id
  ) then
    return new;
  end if;

  -- Persist the read-only computation. The compute function maps DB phases
  -- ko/final -> winners/finals and applies tournament_factor * league_factor.
  insert into public.season_standings_awards (
    season_id, league_id, tournament_id, participant_id,
    placement, base_points, final_points, breakdown
  )
  select a.season_id,
         a.league_id,
         new.id,
         a.participant_id,
         a.placement,
         a.base_points,
         a.final_points,
         'skv:auto placement=' || a.placement
  from public.tournament_skv_compute_awards(new.id) a;

  return new;
end;
$function$

;

-- ---- body update (basis: last applied body of apply_stage_graph_template) ----
CREATE OR REPLACE FUNCTION public.apply_stage_graph_template(p_tournament_id uuid, p_template_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_uid          uuid;
  v_status       text;
  v_created_by   uuid;
  v_graph        jsonb;
  v_node_count   int;
  v_edge_count   int;
BEGIN
  -- 1. Auth gate.
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- 2. Load + lock the tournament. Not-found OR not-authorised collapse into
  --    one 42501 (no existence oracle) — same idiom as tournament_start_stage_graph.
  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;

  -- 3. Status gate: only a pre-start tournament may receive a stage graph.
  --    Formulated as the same ALLOWLIST as the sister RPC
  --    tournament_start_stage_graph (non-terminal pre-live stati of
  --    tournaments_status_check) so the two RPCs stay in lock-step: a future
  --    pre-start status added to the CHECK would NOT be silently admitted here
  --    by a stale denylist. Equivalent to the prior denylist over today's
  --    7-value CHECK {draft, published, registration_open, registration_closed,
  --    live, finalized, aborted}.
  IF v_status NOT IN ('published', 'registration_open', 'registration_closed', 'draft') THEN
    RAISE EXCEPTION 'TOURNAMENT_NOT_PRE_START: tournament is not in a pre-start status'
      USING ERRCODE = '22023';
  END IF;

  -- 4. Template visibility check. SECURITY DEFINER bypasses RLS, so we re-apply
  --    the B5 read predicate explicitly. Not readable / not existent ->
  --    TEMPLATE_NOT_FOUND.
  SELECT t.graph INTO v_graph
    FROM public.tournament_stage_graph_templates t
    WHERE t.id = p_template_id
      AND (
        t.visibility = 'public'
        OR t.owner_user_id = v_uid
        OR (
          t.visibility = 'club'
          AND t.organizer_team_id IS NOT NULL
          AND public.is_active_organizer_team_member(t.organizer_team_id, v_uid)
        )
      );

  IF v_graph IS NULL THEN
    RAISE EXCEPTION 'TEMPLATE_NOT_FOUND: template not found or not readable'
      USING ERRCODE = '22023';
  END IF;

  -- 5. Conflict gate (copy semantics, no merge): the tournament must have no
  --    stages yet.
  IF EXISTS (
    SELECT 1 FROM public.tournament_stages
     WHERE tournament_id = p_tournament_id
  ) THEN
    RAISE EXCEPTION 'ALREADY_HAS_STAGES: tournament already has stages'
      USING ERRCODE = '22023';
  END IF;

  -- 6. Materialize nodes. Wire keys map 1:1 onto the L1b columns; config
  --    defaults to {} and seeding to 'as_routed' when the node omits them.
  INSERT INTO public.tournament_stages (tournament_id, node_id, type, config, seeding)
  SELECT
    p_tournament_id,
    node ->> 'id',
    node ->> 'type',
    coalesce(node -> 'config', '{}'::jsonb),
    coalesce(node ->> 'seeding', 'as_routed')
  FROM jsonb_array_elements(v_graph -> 'nodes') AS node;
  GET DIAGNOSTICS v_node_count = ROW_COUNT;

  -- 7. Materialize edges. `selector` is jsonb NOT NULL — a well-formed template
  --    carries a selector object; a missing one would fail the NOT NULL cleanly.
  INSERT INTO public.tournament_stage_edges
    (tournament_id, from_node_id, to_node_id, selector, seeding_in)
  SELECT
    p_tournament_id,
    edge ->> 'from_node_id',
    edge ->> 'to_node_id',
    edge -> 'selector',
    coalesce(edge ->> 'seeding_in', 'order_preserving')
  FROM jsonb_array_elements(v_graph -> 'edges') AS edge;
  GET DIAGNOSTICS v_edge_count = ROW_COUNT;

  -- 8. Return total rows materialized (#nodes + #edges).
  RETURN v_node_count + v_edge_count;
END;
$function$

;

-- ---- body update (basis: last applied body of save_stage_graph_template) ----
CREATE OR REPLACE FUNCTION public.save_stage_graph_template(p_name text, p_description text, p_visibility text, p_graph jsonb, p_club_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_uid uuid;
  v_id  uuid;
BEGIN
  -- 1. Auth gate.
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- 2. Visibility domain.
  IF p_visibility NOT IN ('private','club','public') THEN
    RAISE EXCEPTION 'INVALID_VISIBILITY: % is not a valid visibility', p_visibility
      USING ERRCODE = '22023';
  END IF;

  -- 3. A 'club' template must carry a club id (mirrors the table CHECK, but
  --    raised here as a stable domain error rather than a raw constraint).
  IF p_visibility = 'club' AND p_club_id IS NULL THEN
    RAISE EXCEPTION 'CLUB_REQUIRED: club visibility needs a organizer_team_id'
      USING ERRCODE = '22023';
  END IF;

  -- 4. Graph validation: both top-level keys present and array-typed.
  IF NOT (p_graph ? 'nodes')
     OR NOT (p_graph ? 'edges')
     OR jsonb_typeof(p_graph -> 'nodes') <> 'array'
     OR jsonb_typeof(p_graph -> 'edges') <> 'array' THEN
    RAISE EXCEPTION 'INVALID_GRAPH: graph must have array keys nodes and edges'
      USING ERRCODE = '22023';
  END IF;

  -- 5. Insert (owner is always the caller — never owner-NULL).
  INSERT INTO public.tournament_stage_graph_templates
    (name, description, owner_user_id, organizer_team_id, visibility, graph)
  VALUES
    (p_name, p_description, v_uid, p_club_id, p_visibility, p_graph)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_abort) ----
CREATE OR REPLACE FUNCTION public.tournament_abort(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_created_by uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the organizer_team_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status NOT IN (
       'draft','published','registration_open','registration_closed','live') THEN
    RAISE EXCEPTION 'tournament cannot be aborted in its current state'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status = 'aborted', completed_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'aborted', v_caller, '{}'::jsonb);
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_close_registration) ----
CREATE OR REPLACE FUNCTION public.tournament_close_registration(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_created_by uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the organizer_team_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'registration_open' THEN
    RAISE EXCEPTION 'tournament must be in status registration_open'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status                 = 'registration_closed',
        registration_closes_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'registration_closed', v_caller, '{}'::jsonb);
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_detect_shootouts) ----
CREATE OR REPLACE FUNCTION public.tournament_detect_shootouts(p_tournament_id uuid, p_qualifier_count integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller   uuid;
  v_creator  uuid;
  v_name     text;
  v_grp      record;
  v_created  int := 0;
  v_groups   jsonb := '[]'::jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, display_name INTO v_creator, v_name
    FROM public.tournaments
   WHERE id = p_tournament_id
   FOR UPDATE;

  -- PER-TOURNAMENT manage gate (20261201000032 §12): creator OR
  -- owner/admin/organizer of the organizer_team_id, same as tournament_start_ko_phase.
  IF v_creator IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  FOR v_grp IN
    SELECT * FROM public._tournament_detect_shootout_groups(
                     p_tournament_id, p_qualifier_count)
  LOOP
    INSERT INTO public.tournament_shootouts(
        tournament_id, start_rank, tied_participant_ids)
      VALUES (p_tournament_id, v_grp.start_rank, v_grp.participant_ids)
      ON CONFLICT (tournament_id, tie_key) DO NOTHING;

    IF FOUND THEN
      v_created := v_created + 1;
      PERFORM public._tournament_notify_shootout_group(
        p_tournament_id,
        v_grp.participant_ids,
        'Shoot-Out nötig',
        'Turnier "' || coalesce(v_name, '')
          || '": Gleichstand an der Qualifikations-Grenze — tragt den '
          || 'Shoot-Out-Sieger ein.',
        jsonb_build_object(
          'tournament_id', p_tournament_id,
          'kind',          'shootout',
          'start_rank',    v_grp.start_rank,
          'tied',          to_jsonb(v_grp.participant_ids)));
    END IF;

    v_groups := v_groups || jsonb_build_object(
      'start_rank', v_grp.start_rank,
      'tied',       to_jsonb(v_grp.participant_ids));
  END LOOP;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'shootouts_detected',
      v_caller,
      jsonb_build_object(
        'qualifier_count', p_qualifier_count,
        'created',         v_created,
        'groups',          v_groups));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'created',       v_created,
    'groups',        v_groups);
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_finalize) ----
CREATE OR REPLACE FUNCTION public.tournament_finalize(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_created_by uuid;
  v_total      int;
  v_terminal   int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the organizer_team_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'live' THEN
    RAISE EXCEPTION 'tournament must be in status live' USING ERRCODE = '22023';
  END IF;

  SELECT count(*) INTO v_total
    FROM public.tournament_matches WHERE tournament_id = p_tournament_id;

  SELECT count(*) INTO v_terminal
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND status IN ('finalized', 'overridden', 'voided');

  IF v_total = 0 THEN
    RAISE EXCEPTION 'tournament has no matches to finalize' USING ERRCODE = '22023';
  END IF;
  IF v_terminal < v_total THEN
    RAISE EXCEPTION 'cannot finalize: % of % matches are not yet terminal',
      v_total - v_terminal, v_total USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status = 'finalized', completed_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'finalized',
      v_caller,
      jsonb_build_object('match_count', v_total)
    );
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_open_registration) ----
CREATE OR REPLACE FUNCTION public.tournament_open_registration(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller         uuid;
  v_status         text;
  v_created_by     uuid;
  v_existing_opens timestamptz;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by, registration_opens_at
    INTO v_status, v_created_by, v_existing_opens
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the organizer_team_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status NOT IN ('published', 'registration_closed') THEN
    RAISE EXCEPTION 'tournament must be in status published or registration_closed'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status                = 'registration_open',
        registration_opens_at = coalesce(v_existing_opens, now())
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'registration_opened', v_caller, '{}'::jsonb);
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_pair_round) ----
CREATE OR REPLACE FUNCTION public.tournament_pair_round(p_tournament_id uuid, p_strategy text, p_pairings jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller        uuid;
  v_creator       uuid;
  v_status        text;
  v_next_round    int;
  v_inserted      int := 0;
  v_current_round int;
  v_open_count    int;
  v_name          text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, status, display_name INTO v_creator, v_status, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the organizer_team_id.
  IF NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'live' THEN
    RAISE EXCEPTION 'tournament must be in status live' USING ERRCODE = '22023';
  END IF;

  IF p_strategy IS DISTINCT FROM 'swiss_system' OR p_pairings IS NULL THEN
    RETURN;
  END IF;

  SELECT max(round_number) INTO v_current_round
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id;

  IF v_current_round IS NOT NULL THEN
    SELECT count(*) INTO v_open_count
      FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND round_number  = v_current_round
        AND status NOT IN ('finalized','overridden','voided');

    IF v_open_count > 0 THEN
      RAISE EXCEPTION
        'round_not_complete: round % still has % open match(es); finalize them before pairing the next round',
        v_current_round, v_open_count
        USING ERRCODE = '22023';
    END IF;
  END IF;

  PERFORM public.validate_swiss_pairing(p_tournament_id, p_pairings);

  SELECT coalesce(max(round_number), 0) + 1
    INTO v_next_round
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id;

  WITH ins AS (
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        participant_a, participant_b, pitch_number, status)
    SELECT
      p_tournament_id,
      v_next_round::smallint,
      (row_number() OVER ())::smallint,
      (elem ->> 'participant_a')::uuid,
      NULLIF(elem ->> 'participant_b','')::uuid,
      1,
      'scheduled'
    FROM jsonb_array_elements(p_pairings) AS elem
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM ins;

  PERFORM public._tournament_assign_pitches(p_tournament_id, v_next_round::smallint);

  -- ADR-0031 A1: materialise the newly paired swiss round (phase 'group').
  PERFORM public._tournament_upsert_round_schedule(
    p_tournament_id, NULL, v_next_round, 'group',
    (public._tournament_schedule_prelim_seconds(p_tournament_id)).match_seconds,
    (public._tournament_schedule_prelim_seconds(p_tournament_id)).break_seconds,
    NULL, now());

  -- ADR-0031 C1 (E1): per-pitch publish-notify of the newly paired round
  -- (v_next_round, phase 'group'). After pitches + schedule exist.
  PERFORM public._tournament_notify_round_per_pitch(
    p_tournament_id, v_next_round, 'group', 'round_published',
    'Runde ' || v_next_round || ' veröffentlicht',
    'Turnier "' || coalesce(v_name, '') || '": Runde ' || v_next_round
      || ' ist da.');

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'swiss_round_paired',
      v_caller,
      jsonb_build_object(
        'round_number', v_next_round,
        'match_count',  v_inserted,
        'strategy',     p_strategy
      )
    );

  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_round',
    'Neue Runde',
    'Turnier "' || coalesce(v_name, '') || '": Runde ' || v_next_round
      || ' — dein Platz ist da, leg los!',
    jsonb_build_object(
      'tournament_id', p_tournament_id,
      'round_number',  v_next_round));
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_publish) ----
CREATE OR REPLACE FUNCTION public.tournament_publish(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_created_by uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the organizer_team_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'tournament must be in status draft' USING ERRCODE = '22023';
  END IF;

  -- NEW MODEL: publishing opens registration immediately (no separate
  -- manual 'Anmeldung öffnen' step). registration_opens_at is stamped now.
  UPDATE public.tournaments
    SET status                = 'registration_open',
        published_at          = now(),
        registration_opens_at = coalesce(registration_opens_at, now())
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'published', v_caller, '{}'::jsonb);
  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'registration_opened', v_caller, '{}'::jsonb);
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_ranking_get) ----
CREATE OR REPLACE FUNCTION public.tournament_ranking_get(p_bucket text)
 RETURNS TABLE(participant_id uuid, display_name text, total_points numeric, tournament_count bigint, rank bigint)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  -- Defined behaviour for an invalid bucket: return an empty result set
  -- rather than raising, so the UI can render a uniform "no data" state.
  IF p_bucket IS NULL OR p_bucket NOT IN ('A', 'B', 'C', 'EINZEL') THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH valid_awards AS (
    -- Awards joined to their tournament. The bucket filter lives here:
    -- awards do not carry team_size / league_categories themselves, so
    -- visibility is derived via the tournaments join. Only finalized
    -- tournaments are ever considered.
    --
    -- CF1: every bucket additionally requires the tournament to be rated
    -- (public.tournament_is_rated -> organizer_team_id IS NOT NULL). For A/B/C this
    -- is already implied by the non-empty league_categories match, but is
    -- stated explicitly for a uniform, future-proof criterion. For EINZEL
    -- it is the substantive guard that keeps unrated singles
    -- "Spasstournier" tournaments out of the leaderboard.
    SELECT
      a.participant_id,
      a.tournament_id,
      a.final_points
    FROM public.season_standings_awards a
    JOIN public.tournaments t
      ON t.id = a.tournament_id
    WHERE t.status = 'finalized'
      AND public.tournament_is_rated(t.id)
      AND (
        (p_bucket = 'EINZEL' AND t.team_size = 1)
        OR (
          p_bucket IN ('A', 'B', 'C')
          AND t.team_size > 1
          AND t.league_categories @> ARRAY[p_bucket]
        )
      )
  ),
  aggregated AS (
    SELECT
      va.participant_id,
      SUM(va.final_points)              AS total_points,
      COUNT(DISTINCT va.tournament_id)  AS tournament_count
    FROM valid_awards va
    GROUP BY va.participant_id
  ),
  named AS (
    SELECT
      ag.participant_id,
      -- For team buckets the participant_id is a team id; for the
      -- singles bucket it is a user id. Resolve the appropriate name
      -- and fall back to the raw id only if no name row exists.
      CASE
        WHEN p_bucket = 'EINZEL'
          THEN COALESCE(up.nickname::text, ag.participant_id::text)
        ELSE COALESCE(tm.display_name, ag.participant_id::text)
      END                               AS display_name,
      ag.total_points,
      ag.tournament_count
    FROM aggregated ag
    LEFT JOIN public.teams tm
      ON p_bucket IN ('A', 'B', 'C') AND tm.id = ag.participant_id
    LEFT JOIN public.user_profiles up
      ON p_bucket = 'EINZEL' AND up.user_id = ag.participant_id
  )
  SELECT
    n.participant_id,
    n.display_name,
    n.total_points,
    n.tournament_count,
    ROW_NUMBER() OVER (
      ORDER BY n.total_points DESC,
               n.tournament_count DESC,
               n.display_name ASC
    ) AS rank
  FROM named n
  ORDER BY rank;
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_skv_compute_awards) ----
CREATE OR REPLACE FUNCTION public.tournament_skv_compute_awards(p_tournament_id uuid)
 RETURNS TABLE(season_id uuid, league_id uuid, participant_id uuid, placement integer, base_points integer, final_points numeric)
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_team_size        smallint;
  v_league_cats      text[];
  v_league           text;            -- 'einzel' | 'c' | 'a'
  v_prelim           text[];          -- confirmed participant ids, deterministic order
  v_ko_matches       jsonb;           -- mapped KO matches as jsonb array
  v_db_phases        text[];          -- distinct DB KO phases present
  v_is_double        boolean;
  v_is_consolation   boolean;
begin
  -- 1. Load tournament. (No rated / organizer_team_id gate here -- that is the finalize
  --    step's responsibility, B2c2.)
  select t.team_size, t.league_categories
    into v_team_size, v_league_cats
  from public.tournaments t
  where t.id = p_tournament_id;

  if not found then
    -- Unknown tournament: nothing to compute.
    return;
  end if;

  -- 2. Derive the league text (case-insensitive on league_categories).
  --    team_size = 1                                  -> 'einzel'
  --    contains 'C' and neither 'A' nor 'B'           -> 'c'
  --    otherwise                                      -> 'a'
  if v_team_size = 1 then
    v_league := 'einzel';
  elsif exists (
          select 1 from unnest(coalesce(v_league_cats, '{}'::text[])) c
          where lower(c) = 'c'
        )
    and not exists (
          select 1 from unnest(coalesce(v_league_cats, '{}'::text[])) c
          where lower(c) in ('a', 'b')
        )
  then
    v_league := 'c';
  else
    v_league := 'a';
  end if;

  -- 3. Participant set + deterministic preliminary ranking.
  --    All confirmed/approved participants, ordered by seed ASC NULLS LAST,
  --    then id. ('approved' is tolerated for forward-compat; the current
  --    registration_status check constraint only emits 'confirmed'.)
  select array_agg(tp.id::text order by tp.seed asc nulls last, tp.id)
    into v_prelim
  from public.tournament_participants tp
  where tp.tournament_id = p_tournament_id
    and tp.registration_status in ('confirmed', 'approved');

  v_prelim := coalesce(v_prelim, array[]::text[]);

  -- 4. Build the KO-match jsonb array. Only KO phases; 'group'/NULL excluded.
  --    DB phase -> helper phase: ko -> winners, final -> finals, rest passthrough.
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'round',  m.round_number,
               'phase',  case m.phase
                           when 'ko'    then 'winners'
                           when 'final' then 'finals'
                           else m.phase
                         end,
               'a',      m.participant_a::text,
               'b',      m.participant_b::text,
               'winner', m.winner_participant::text,
               'bye',    (m.participant_a is null or m.participant_b is null)
             )
           ),
           '[]'::jsonb
         )
    into v_ko_matches
  from public.tournament_matches m
  where m.tournament_id = p_tournament_id
    and m.phase in (
      'ko', 'final', 'third_place',
      'wb', 'lb', 'grand_final', 'grand_final_reset',
      'consolation', 'consolation_third_place'
    );

  -- 6. No KO matches -> empty result. SKV scoring requires a KO phase; a pure
  --    preliminary-round tournament without a bracket is a later extension.
  if jsonb_array_length(v_ko_matches) = 0 then
    return;
  end if;

  -- 5. Detect bracket type from the DB phases actually present.
  select array_agg(distinct m.phase)
    into v_db_phases
  from public.tournament_matches m
  where m.tournament_id = p_tournament_id
    and m.phase in (
      'ko', 'final', 'third_place',
      'wb', 'lb', 'grand_final', 'grand_final_reset',
      'consolation', 'consolation_third_place'
    );

  v_is_double := v_db_phases && array['wb', 'lb', 'grand_final', 'grand_final_reset']::text[];
  v_is_consolation := v_db_phases && array['consolation', 'consolation_third_place']::text[];

  -- 7 + 8. Resolve a stable award participant id (team_id for team tournaments,
  -- user_id for singles) and project onto every season assignment, applying the
  -- per-assignment factors. The placement helper is chosen by bracket type.
  return query
  with placements as (
    select * from public.skv_double_elim_placements(v_ko_matches, v_prelim, v_league, false)
      where v_is_double
    union all
    select * from public.skv_consolation_placements(v_ko_matches, v_prelim, v_league, false)
      where (not v_is_double) and v_is_consolation
    union all
    select * from public.skv_single_elim_placements(v_ko_matches, v_prelim, v_league, false)
      where (not v_is_double) and (not v_is_consolation)
  ),
  resolved as (
    -- Stable award id: team_id for team tournaments, else user_id.
    select coalesce(tp.team_id, tp.user_id) as award_participant_id,
           pl.rank   as placement,
           pl.points as base_points
    from placements pl
    join public.tournament_participants tp
      on tp.id = pl.participant_id::uuid
  )
  select st.season_id,
         s.league_id,
         r.award_participant_id,
         r.placement,
         r.base_points,
         (r.base_points * st.tournament_factor * st.league_factor)::numeric as final_points
  from resolved r
  cross join public.season_tournaments st
  join public.seasons s on s.id = st.season_id
  where st.tournament_id = p_tournament_id;
end;
$function$

;

-- ---- body update (basis: last applied body of tournament_start) ----
CREATE OR REPLACE FUNCTION public.tournament_start(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller         uuid;
  v_status         text;
  v_format         text;
  v_pool_config    jsonb;
  v_confirmed      int;
  v_slot_count     int;
  v_round_count    int;
  v_match_count    int := 0;
  v_round          int;
  v_i              int;
  v_a_idx          int;
  v_b_idx          int;
  v_a_pid          uuid;
  v_b_pid          uuid;
  v_name           text;
  v_created_by     uuid;   -- PER-TOURNAMENT
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, format, pool_phase_config, display_name, created_by
    INTO v_status, v_format, v_pool_config, v_name, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the organizer_team_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  -- NEW MODEL: registration is always open once published; starting
  -- implicitly closes it. Accept both open and closed states.
  IF v_status NOT IN ('registration_open','registration_closed') THEN
    RAISE EXCEPTION 'tournament must be in status registration_open or registration_closed'
      USING ERRCODE = '22023';
  END IF;
  IF v_format NOT IN (
       'round_robin','swiss','schoch',
       'round_robin_then_ko','schoch_then_ko','swiss_then_ko') THEN
    RAISE EXCEPTION 'format not yet supported' USING ERRCODE = '0A000';
  END IF;

  -- ---- Hybrid (*_then_ko): delegate the pool phase ------------------
  IF v_format IN ('round_robin_then_ko','schoch_then_ko','swiss_then_ko') THEN
    IF v_pool_config IS NULL OR jsonb_typeof(v_pool_config) <> 'object' THEN
      RAISE EXCEPTION 'pool_phase_config required for hybrid format'
        USING ERRCODE = '22023';
    END IF;

    PERFORM public.tournament_start_pool_phase(p_tournament_id, v_pool_config);

    INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'started',
        v_caller,
        jsonb_build_object('format', v_format, 'phase', 'pool'));
    RETURN;
  END IF;

  -- ---- Non-hybrid formats: confirmed-participant precondition -------
  SELECT count(*) INTO v_confirmed
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status = 'confirmed';

  IF v_confirmed < 2 THEN
    RAISE EXCEPTION 'at least 2 confirmed participants required'
      USING ERRCODE = '22023';
  END IF;

  CREATE TEMP TABLE _tstart_slots (
    slot_idx int PRIMARY KEY,
    participant_id uuid NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _tstart_slots(slot_idx, participant_id)
  SELECT row_number() OVER (ORDER BY p.registered_at, p.id), p.id
    FROM public.tournament_participants p
    WHERE p.tournament_id = p_tournament_id
      AND p.registration_status = 'confirmed';

  UPDATE public.tournament_participants p
    SET seed = s.slot_idx
    FROM _tstart_slots s
    WHERE p.id = s.participant_id;

  -- ---- swiss / schoch: materialise ROUND 1 only ---------------------
  IF v_format IN ('swiss','schoch') THEN
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        participant_a, participant_b, pitch_number, status)
    SELECT
      p_tournament_id,
      1::smallint,
      (((s.slot_idx - 1) / 2) + 1)::smallint,
      s.participant_id,
      part.participant_id,
      1,
      'scheduled'
    FROM _tstart_slots s
    LEFT JOIN _tstart_slots part
      ON part.slot_idx = s.slot_idx + 1
    WHERE (s.slot_idx % 2) = 1;

    GET DIAGNOSTICS v_match_count = ROW_COUNT;

    DROP TABLE _tstart_slots;

    PERFORM public._tournament_assign_pitches(p_tournament_id, 1::smallint);

    UPDATE public.tournaments
      SET status = 'live', started_at = now()
      WHERE id = p_tournament_id;

    -- ADR-0031 A1: materialise the active round 1 schedule (phase 'group').
    PERFORM public._tournament_upsert_round_schedule(
      p_tournament_id, NULL, 1, 'group',
      (public._tournament_schedule_prelim_seconds(p_tournament_id)).match_seconds,
      (public._tournament_schedule_prelim_seconds(p_tournament_id)).break_seconds,
      NULL, now());

    -- ADR-0031 C1 (E1): per-pitch publish-notify of round 1 (phase 'group').
    -- After pitches + schedule exist; starts_at resolved inside the helper.
    PERFORM public._tournament_notify_round_per_pitch(
      p_tournament_id, 1, 'group', 'round_published',
      'Runde 1 veröffentlicht',
      'Turnier "' || coalesce(v_name, '') || '": Runde 1 ist da.');

    INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'started',
        v_caller,
        jsonb_build_object(
          'format',      v_format,
          'round_count', 1,
          'match_count', v_match_count));

    PERFORM public._tournament_notify_participants(
      p_tournament_id,
      'tournament_started',
      'Turnier gestartet',
      'Turnier "' || coalesce(v_name, '') || '" ist gestartet — dein Platz ist da, leg los!',
      jsonb_build_object('tournament_id', p_tournament_id, 'format', v_format));
    RETURN;
  END IF;

  -- ---- round_robin: original circle-rotation materialisation --------
  IF (v_confirmed % 2) = 1 THEN
    v_slot_count := v_confirmed + 1;
    INSERT INTO _tstart_slots(slot_idx, participant_id) VALUES (v_slot_count, NULL);
  ELSE
    v_slot_count := v_confirmed;
  END IF;

  v_round_count := v_slot_count - 1;

  CREATE TEMP TABLE _tstart_ring (
    pos int PRIMARY KEY,
    participant_id uuid NULL
  ) ON COMMIT DROP;

  INSERT INTO _tstart_ring(pos, participant_id)
    SELECT slot_idx, participant_id FROM _tstart_slots;

  FOR v_round IN 1..v_round_count LOOP
    FOR v_i IN 0..((v_slot_count / 2) - 1) LOOP
      v_a_idx := v_i + 1;
      v_b_idx := v_slot_count - v_i;

      SELECT participant_id INTO v_a_pid FROM _tstart_ring WHERE pos = v_a_idx;
      SELECT participant_id INTO v_b_pid FROM _tstart_ring WHERE pos = v_b_idx;

      IF v_a_pid IS NULL AND v_b_pid IS NULL THEN
        CONTINUE;
      END IF;
      IF v_a_pid IS NULL THEN
        v_a_pid := v_b_pid;
        v_b_pid := NULL;
      END IF;

      INSERT INTO public.tournament_matches(
          tournament_id, round_number, match_number_in_round,
          participant_a, participant_b, pitch_number, status)
        VALUES (
          p_tournament_id, v_round::smallint, (v_i + 1)::smallint,
          v_a_pid, v_b_pid, 1, 'scheduled');

      v_match_count := v_match_count + 1;
    END LOOP;

    PERFORM public._tournament_assign_pitches(p_tournament_id, v_round::smallint);

    -- ADR-0031 A1 (OE-2): only the active round 1 gets a schedule row.
    IF v_round = 1 THEN
      PERFORM public._tournament_upsert_round_schedule(
        p_tournament_id, NULL, 1, 'group',
        (public._tournament_schedule_prelim_seconds(p_tournament_id)).match_seconds,
        (public._tournament_schedule_prelim_seconds(p_tournament_id)).break_seconds,
        NULL, now());

      -- ADR-0031 C1 (E1): per-pitch publish-notify of the active round 1
      -- (phase 'group'). After pitches + schedule exist for round 1.
      PERFORM public._tournament_notify_round_per_pitch(
        p_tournament_id, 1, 'group', 'round_published',
        'Runde 1 veröffentlicht',
        'Turnier "' || coalesce(v_name, '') || '": Runde 1 ist da.');
    END IF;

    UPDATE _tstart_ring
      SET pos = CASE
                  WHEN pos = 1 THEN 1
                  WHEN pos = v_slot_count THEN 2
                  ELSE pos + 1
                END;
  END LOOP;

  DROP TABLE _tstart_ring;
  DROP TABLE _tstart_slots;

  UPDATE public.tournaments
    SET status = 'live', started_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'started',
      v_caller,
      jsonb_build_object(
        'format',      v_format,
        'round_count', v_round_count,
        'match_count', v_match_count));

  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_started',
    'Turnier gestartet',
    'Turnier "' || coalesce(v_name, '') || '" ist gestartet — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'format', v_format));
END;
$function$

;

-- ---- body update (basis: last applied body of tournament_start_pool_phase) ----
CREATE OR REPLACE FUNCTION public.tournament_start_pool_phase(p_tournament_id uuid, p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller        uuid;
  v_creator       uuid;
  v_pools         jsonb;
  v_participants  jsonb;
  v_assignments   int := 0;
  v_match_count   int := 0;
  v_existing      int;
  v_labels        text[];
  v_name          text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, display_name INTO v_creator, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the organizer_team_id.
  IF v_creator IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_existing
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase = 'group';
  IF v_existing > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: pool phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(id::text)
                            ORDER BY registered_at ASC, id ASC),
                  '[]'::jsonb)
    INTO v_participants
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status = 'confirmed';

  IF jsonb_array_length(v_participants) < 2 THEN
    RAISE EXCEPTION 'INVALID_POOL_CONFIG: at least 2 confirmed participants required'
      USING ERRCODE = '22023';
  END IF;

  v_pools := public._tournament_compute_pools(v_participants, p_config);

  WITH assignments AS (
    SELECT (elem ->> 'participant_id')::uuid AS pid,
           (elem ->> 'group_label')          AS lbl
      FROM jsonb_array_elements(v_pools) AS elem
  )
  UPDATE public.tournament_participants tp
     SET group_label = a.lbl
    FROM assignments a
   WHERE tp.id = a.pid
     AND tp.tournament_id = p_tournament_id;
  GET DIAGNOSTICS v_assignments = ROW_COUNT;

  SELECT array_agg(DISTINCT (elem ->> 'group_label') ORDER BY (elem ->> 'group_label'))
    INTO v_labels
    FROM jsonb_array_elements(v_pools) AS elem;

  WITH members AS (
    SELECT (elem ->> 'participant_id')::uuid AS pid,
           (elem ->> 'group_label')          AS lbl,
           (elem ->> 'group_position')::int  AS pos
      FROM jsonb_array_elements(v_pools) AS elem
  ),
  pairs AS (
    SELECT m1.lbl, m1.pid AS pid_a, m2.pid AS pid_b,
           m1.pos AS pos_a, m2.pos AS pos_b,
           row_number() OVER (
             PARTITION BY m1.lbl
             ORDER BY m1.pos, m2.pos
           ) AS pair_no
      FROM members m1
      JOIN members m2 ON m1.lbl = m2.lbl AND m1.pos < m2.pos
  )
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b,
      phase, group_label, status, pitch_number)
  SELECT p_tournament_id,
         1::smallint,
         pair_no::smallint,
         pid_a, pid_b,
         'group',
         lbl,
         'scheduled',
         1
    FROM pairs;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  PERFORM public._tournament_assign_pitches(p_tournament_id, 1::smallint);

  UPDATE public.tournaments
     SET status     = 'live',
         started_at = coalesce(started_at, now())
   WHERE id = p_tournament_id;

  -- ADR-0031 A1: materialise the group phase round 1 schedule.
  PERFORM public._tournament_upsert_round_schedule(
    p_tournament_id, NULL, 1, 'group',
    (public._tournament_schedule_prelim_seconds(p_tournament_id)).match_seconds,
    (public._tournament_schedule_prelim_seconds(p_tournament_id)).break_seconds,
    NULL, now());

  -- ADR-0031 C1 (E1): per-pitch publish-notify of round 1 (phase 'group').
  -- After pitches + schedule exist; starts_at resolved inside the helper.
  PERFORM public._tournament_notify_round_per_pitch(
    p_tournament_id, 1, 'group', 'round_published',
    'Runde 1 veröffentlicht',
    'Turnier "' || coalesce(v_name, '') || '": Runde 1 ist da.');

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'pool_phase_started',
      v_caller,
      jsonb_build_object(
        'group_count',           coalesce(array_length(v_labels, 1), 0),
        'assignments',           v_assignments,
        'match_count',           v_match_count,
        'config',                p_config));

  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_started',
    'Turnier gestartet',
    'Turnier "' || coalesce(v_name, '') || '" ist gestartet — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'phase', 'pool'));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'group_count',   coalesce(array_length(v_labels, 1), 0),
    'assignments',   v_assignments,
    'match_count',   v_match_count);
END;
$function$

;

