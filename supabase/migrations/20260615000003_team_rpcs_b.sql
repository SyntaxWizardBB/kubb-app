-- Team feature — M3 RPCs part B (guest add, removals, leave, dissolve).
--
-- Five SECURITY DEFINER RPCs that close the membership lifecycle started
-- in part A. All mutations resolve the caller via auth.uid(); pool
-- membership is verified inline (no captain role per ADR-0018).
--
-- OD-M3-01 (recommendation B): critical mutations (member removal, team
-- dissolution) emit a team_audit_events row AND fan out inbox messages
-- of kind `team_member_removed` / `team_dissolved` to every OTHER active
-- pool member. The acting member is excluded — they triggered the action
-- and do not need a self-notification (FR-NOT consistent).
--
-- Inbox kinds `team_member_removed` and `team_dissolved` are enabled by
-- migration 20260615000002 (TASK-M3.1-T6); this file assumes the CHECK
-- constraint on user_inbox_messages.kind has been widened accordingly.
--
-- Consent model for team_dissolve (pragmatic, no extra schema):
--   * Each pool member must independently emit a `dissolve_consent`
--     audit event (any time before the dissolve call).
--   * team_dissolve passes only when, for every currently active
--     membership, there exists at least one matching dissolve_consent
--     audit event whose actor_user_id equals that member. Otherwise the
--     call raises DISSOLVE_NEEDS_CONSENT (errcode 22023).
--   * Consent expression is intentionally append-only and idempotent.
--     Reset semantics ("re-ask after a join/leave") are out of scope for
--     M3 — the bar is low enough to keep the schema clean.
--
-- Errcodes (token in MESSAGE, SQLSTATE in ERRCODE):
--   NOT_AUTHENTICATED          — 42501
--   NOT_POOL_MEMBER            — 42501
--   TEAM_DISSOLVED             — 22023
--   TARGET_NOT_MEMBER          — 22023
--   TARGET_NOT_GUEST           — 22023
--   DISSOLVE_NEEDS_CONSENT     — 22023


-- ---- Helper: guard active pool membership ----------------------------

CREATE OR REPLACE FUNCTION public._team_assert_active_member(
  p_team_id uuid,
  p_user_id uuid
)
RETURNS void
LANGUAGE plpgsql
SET search_path = public, auth
AS $$
DECLARE
  v_dissolved timestamptz;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT dissolved_at INTO v_dissolved
    FROM public.teams WHERE id = p_team_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT_POOL_MEMBER' USING ERRCODE = '42501';
  END IF;
  IF v_dissolved IS NOT NULL THEN
    RAISE EXCEPTION 'TEAM_DISSOLVED' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.team_memberships
    WHERE team_id = p_team_id
      AND user_id = p_user_id
      AND removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'NOT_POOL_MEMBER' USING ERRCODE = '42501';
  END IF;
END;
$$;


-- ---- 1. team_add_guest -----------------------------------------------

CREATE OR REPLACE FUNCTION public.team_add_guest(
  p_team_id      uuid,
  p_display_name text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_guest_id uuid;
BEGIN
  PERFORM public._team_assert_active_member(p_team_id, v_caller);

  INSERT INTO public.team_guest_players(team_id, display_name, added_by)
    VALUES (p_team_id, p_display_name, v_caller)
    RETURNING id INTO v_guest_id;

  INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
    VALUES (
      p_team_id,
      'guest_added',
      v_caller,
      jsonb_build_object('guest_player_id', v_guest_id, 'display_name', p_display_name)
    );

  RETURN v_guest_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_add_guest(uuid, text) TO authenticated;


-- ---- 2. team_remove_member -------------------------------------------

CREATE OR REPLACE FUNCTION public.team_remove_member(
  p_team_id         uuid,
  p_member_user_id  uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_rows int;
BEGIN
  PERFORM public._team_assert_active_member(p_team_id, v_caller);

  UPDATE public.team_memberships
     SET removed_at = now(),
         removed_by = v_caller
   WHERE team_id = p_team_id
     AND user_id = p_member_user_id
     AND removed_at IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'TARGET_NOT_MEMBER' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
    VALUES (
      p_team_id,
      'member_removed',
      v_caller,
      jsonb_build_object('removed_user_id', p_member_user_id)
    );

  -- OD-M3-01: notify every OTHER active pool member.
  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    SELECT
      m.user_id,
      'team_member_removed',
      'Team-Mitglied entfernt',
      'Ein Mitglied wurde aus dem Pool entfernt.',
      jsonb_build_object(
        'team_id', p_team_id,
        'removed_user_id', p_member_user_id,
        'actor_user_id', v_caller
      )
    FROM public.team_memberships m
    WHERE m.team_id = p_team_id
      AND m.removed_at IS NULL
      AND m.user_id <> v_caller;
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_remove_member(uuid, uuid) TO authenticated;


-- ---- 3. team_remove_guest --------------------------------------------

CREATE OR REPLACE FUNCTION public.team_remove_guest(
  p_team_id         uuid,
  p_guest_player_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_rows int;
BEGIN
  PERFORM public._team_assert_active_member(p_team_id, v_caller);

  UPDATE public.team_guest_players
     SET removed_at = now()
   WHERE id = p_guest_player_id
     AND team_id = p_team_id
     AND removed_at IS NULL;
  GET DIAGNOSTICS v_rows = ROW_COUNT;
  IF v_rows = 0 THEN
    RAISE EXCEPTION 'TARGET_NOT_GUEST' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
    VALUES (
      p_team_id,
      'guest_removed',
      v_caller,
      jsonb_build_object('guest_player_id', p_guest_player_id)
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_remove_guest(uuid, uuid) TO authenticated;


-- ---- 4. team_leave ---------------------------------------------------
--
-- The caller drops their own active membership. If they were the last
-- registered (non-guest) member, the team is auto-dissolved per
-- FR-TEAM-19 and a `team_dissolved` audit event is appended. Inbox fan
-- out is skipped on auto-dissolve because no other members remain.

CREATE OR REPLACE FUNCTION public.team_leave(p_team_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_remaining int;
BEGIN
  PERFORM public._team_assert_active_member(p_team_id, v_caller);

  UPDATE public.team_memberships
     SET removed_at = now(),
         removed_by = v_caller
   WHERE team_id = p_team_id
     AND user_id = v_caller
     AND removed_at IS NULL;

  INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
    VALUES (p_team_id, 'member_left', v_caller, '{}'::jsonb);

  SELECT count(*) INTO v_remaining
    FROM public.team_memberships
    WHERE team_id = p_team_id AND removed_at IS NULL;

  IF v_remaining = 0 THEN
    UPDATE public.teams SET dissolved_at = now() WHERE id = p_team_id;
    INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
      VALUES (
        p_team_id, 'team_dissolved', v_caller,
        jsonb_build_object('cause', 'auto_last_member_left')
      );
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_leave(uuid) TO authenticated;


-- ---- 5. team_dissolve ------------------------------------------------
--
-- Explicit dissolve. Requires that every currently active pool member
-- has previously emitted a `dissolve_consent` audit event for this team.
-- The caller's own consent is implied by the call itself but must still
-- be recorded — clients should invoke a consent RPC (out of scope for
-- T5) or directly insert a consent event before this call. We register
-- the caller's consent here to keep the happy path ergonomic on solo
-- teams and to make the consent set self-consistent at commit time.

CREATE OR REPLACE FUNCTION public.team_dissolve(p_team_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_missing int;
BEGIN
  PERFORM public._team_assert_active_member(p_team_id, v_caller);

  -- Caller's consent is recorded by the act of calling team_dissolve.
  INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
    VALUES (p_team_id, 'dissolve_consent', v_caller, '{}'::jsonb);

  -- Count active members lacking any dissolve_consent event.
  SELECT count(*) INTO v_missing
    FROM public.team_memberships m
    WHERE m.team_id = p_team_id
      AND m.removed_at IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.team_audit_events e
        WHERE e.team_id = p_team_id
          AND e.kind = 'dissolve_consent'
          AND e.actor_user_id = m.user_id
      );

  IF v_missing > 0 THEN
    RAISE EXCEPTION 'DISSOLVE_NEEDS_CONSENT: % member(s) have not consented', v_missing
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.teams SET dissolved_at = now() WHERE id = p_team_id;

  INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
    VALUES (p_team_id, 'team_dissolved', v_caller,
            jsonb_build_object('cause', 'explicit_dissolve'));

  -- OD-M3-01: notify every OTHER active pool member.
  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    SELECT
      m.user_id,
      'team_dissolved',
      'Team aufgeloest',
      'Der Team-Pool wurde aufgeloest.',
      jsonb_build_object('team_id', p_team_id, 'actor_user_id', v_caller)
    FROM public.team_memberships m
    WHERE m.team_id = p_team_id
      AND m.removed_at IS NULL
      AND m.user_id <> v_caller;
END;
$$;

GRANT EXECUTE ON FUNCTION public.team_dissolve(uuid) TO authenticated;
