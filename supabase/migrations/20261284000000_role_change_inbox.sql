-- P7: notify a member when their organizer-team role is changed.
-- ADR-0032 / docs/plans/permissions-organizer-teams PLAN P7.
--
-- (a) Extend the user_inbox_messages kind CHECK ADDITIVELY with the new
--     'club_role_changed' kind (the existing club_* inbox kinds stay — they
--     are an internal vocabulary, deliberately NOT renamed by the P6 rename,
--     so legacy inbox rows keep validating). Rebuilt verbatim from the live
--     constraint def + the one new kind.
-- (b) organizer_team_set_member_roles emits one inbox row to the affected
--     member (kind 'club_role_changed', PII-free payload) whenever a manager
--     changes their roles — except when a caller changes their own roles.
--     CREATE OR REPLACE on the current on-disk body (post-rename: references
--     team_members / organizer_team_id); only the inbox INSERT is new.

-- ---- (a) additive kind CHECK ------------------------------------------------
ALTER TABLE public.user_inbox_messages
  DROP CONSTRAINT user_inbox_messages_kind_check;

ALTER TABLE public.user_inbox_messages
  ADD CONSTRAINT user_inbox_messages_kind_check CHECK (
    kind = ANY (ARRAY[
      'notice', 'verification_request', 'system',
      'team_invitation', 'team_member_removed', 'team_dissolved',
      'club_invitation', 'club_member_removed', 'club_join_request',
      'club_role_changed',
      'tournament_started', 'tournament_round', 'tournament_team_registered',
      'tournament_registration_confirmed', 'tournament_waitlisted',
      'tournament_promoted', 'tournament_finished', 'tournament_invitation'
    ]::text[])
  );

-- ---- (b) emit inbox event on role change ------------------------------------
CREATE OR REPLACE FUNCTION public.organizer_team_set_member_roles(
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

  -- P7: notify the affected member (not a self-change). PII-free payload —
  -- the localized label is resolved client-side from the kind + payload.
  IF p_member_user_id <> v_caller THEN
    INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
      VALUES (
        p_member_user_id,
        'club_role_changed',
        'Rolle geändert',
        'Deine Rolle im Veranstalterteam wurde aktualisiert.',
        jsonb_build_object('organizer_team_id', p_club_id,
                           'roles', to_jsonb(p_roles))
      );
  END IF;
END;
$$;
