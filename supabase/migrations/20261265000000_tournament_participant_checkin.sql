-- ADR-0031 Phase D Block D1 — on-site participant check-in.
--
-- Adds the `checked_in_at` presence timestamp to tournament_participants
-- (physical attendance, distinct from registration_status='confirmed' which
-- is pool membership) plus two SECURITY DEFINER RPCs that manage authority
-- gated, status gated and idempotent toggle that timestamp and write an
-- audit event — mirroring the existing tournament_match_forfeit RPC pattern
-- (20260601000001) for audit + grant shape and tournament_caller_can_manage
-- (20261201000031) for the authority gate (K4: creator + active
-- owner/admin/organizer of the tournament's club; referee arrives via Phase B).
--
-- ============================ DEPENDENCIES ============================
-- Requires (all earlier on disk):
--   * public.tournament_participants (20260525000001_tournament_schema.sql)
--     — target of the new column; columns id/tournament_id/registration_status.
--   * public.tournaments (20260525000001) — status enum incl.
--     registration_open|registration_closed|live.
--   * public.tournament_audit_events (20260525000001) — kind is free-text
--     (no CHECK), so the new audit kinds need no constraint change.
--   * public.tournament_caller_can_manage(uuid) (20261201000031) — authority gate.
--   * tournament_participants is already in supabase_realtime
--     (20261236000000_cdc_tournament_participants.sql); the new NULLable column
--     is emitted over the existing publication with no further ALTER PUBLICATION
--     and REPLICA IDENTITY stays DEFAULT. No new RLS policy is added here.
-- =====================================================================


-- ---- 1. tournament_participants.checked_in_at ------------------------
-- Purely additive: NULLable, no DEFAULT, no NOT NULL, no backfill of existing
-- rows. NULL = not checked in; non-NULL = on-site presence confirmed at that
-- server timestamp.

ALTER TABLE public.tournament_participants
  ADD COLUMN IF NOT EXISTS checked_in_at timestamptz NULL;

COMMENT ON COLUMN public.tournament_participants.checked_in_at IS
  'On-site presence timestamp (physical attendance). NULL = not checked in. '
  'Distinct from registration_status=confirmed (pool membership). Toggled by '
  'tournament_checkin_participant / tournament_undo_checkin — see '
  '20261265000000_tournament_participant_checkin.sql.';


-- ---- 2. tournament_checkin_participant -------------------------------
-- Marks a confirmed participant as physically present. Manage-authority
-- gated, tournament-status gated (OE-D1: registration_open|registration_closed|
-- live), participant must be registration_status='confirmed'. Idempotent: a
-- re-check-in on an already checked-in row is a no-op (the existing timestamp
-- is preserved, no audit event is written). NEW function — no prior on-disk
-- definition, so no stale-body risk.

CREATE FUNCTION public.tournament_checkin_participant(
  p_participant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_tournament_id uuid;
  v_reg_status    text;
  v_checked_in_at timestamptz;
  v_t_status      text;
  v_now           timestamptz;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Lock the participant row so a concurrent toggle cannot race us.
  SELECT p.tournament_id, p.registration_status, p.checked_in_at
    INTO v_tournament_id, v_reg_status, v_checked_in_at
    FROM public.tournament_participants p
    WHERE p.id = p_participant_id
    FOR UPDATE;

  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'participant not found' USING ERRCODE = 'P0002';
  END IF;

  -- Authority gate (K4): creator OR active owner/admin/organizer of the
  -- tournament's club. No bespoke role set here.
  IF NOT public.tournament_caller_can_manage(v_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  -- Tournament status gate (OE-D1): check-in only inside the registration /
  -- live window. draft/published/finalized/aborted are rejected.
  SELECT t.status INTO v_t_status
    FROM public.tournaments t
    WHERE t.id = v_tournament_id;
  IF v_t_status NOT IN ('registration_open','registration_closed','live') THEN
    RAISE EXCEPTION 'check-in not allowed in tournament status %', v_t_status
      USING ERRCODE = '22023';
  END IF;

  -- Participant status gate: only confirmed participants can be checked in.
  IF v_reg_status <> 'confirmed' THEN
    RAISE EXCEPTION 'check-in only allowed for confirmed participants (is %)',
      v_reg_status USING ERRCODE = '22023';
  END IF;

  -- Idempotent: already checked in => no-op, preserve the existing timestamp,
  -- write no audit event.
  IF v_checked_in_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'participant_id', p_participant_id,
      'checked_in_at',  v_checked_in_at,
      'changed',        false
    );
  END IF;

  v_now := now();
  UPDATE public.tournament_participants
    SET checked_in_at = v_now
    WHERE id = p_participant_id;

  -- Audit (mirrors the forfeit RPC pattern): one event per real state change.
  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id, 'participant_checked_in', v_caller,
      jsonb_build_object(
        'participant_id', p_participant_id,
        'checked_in_at',  v_now
      ));

  RETURN jsonb_build_object(
    'participant_id', p_participant_id,
    'checked_in_at',  v_now,
    'changed',        true
  );
END;
$$;

-- REVOKE from public AND anon explicitly: the local Supabase stack grants
-- EXECUTE to {anon,authenticated,service_role} via ALTER DEFAULT PRIVILEGES on
-- CREATE FUNCTION, so REVOKE FROM public alone leaves anon able to execute.
-- Lock anon out so only authenticated callers reach the manage-gate.
REVOKE ALL ON FUNCTION public.tournament_checkin_participant(uuid)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tournament_checkin_participant(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_checkin_participant(uuid) IS
  'Mark a confirmed participant as on-site present (sets checked_in_at). '
  'Manage-authority gated via tournament_caller_can_manage; tournament status '
  'must be registration_open|registration_closed|live; participant must be '
  'confirmed. Idempotent (re-check-in no-op, no duplicate audit). Writes a '
  'participant_checked_in audit event. See '
  '20261265000000_tournament_participant_checkin.sql.';


-- ---- 3. tournament_undo_checkin --------------------------------------
-- Clears a participant's presence timestamp. Same authority / status /
-- participant gates as check-in. Idempotent: undo on an already-NULL row is a
-- no-op (no audit event). NEW function — no stale-body risk.

CREATE FUNCTION public.tournament_undo_checkin(
  p_participant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_tournament_id uuid;
  v_reg_status    text;
  v_checked_in_at timestamptz;
  v_t_status      text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Lock the participant row so a concurrent toggle cannot race us.
  SELECT p.tournament_id, p.registration_status, p.checked_in_at
    INTO v_tournament_id, v_reg_status, v_checked_in_at
    FROM public.tournament_participants p
    WHERE p.id = p_participant_id
    FOR UPDATE;

  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'participant not found' USING ERRCODE = 'P0002';
  END IF;

  -- Authority gate (K4): same gate as check-in.
  IF NOT public.tournament_caller_can_manage(v_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  -- Tournament status gate (OE-D1): same window as check-in.
  SELECT t.status INTO v_t_status
    FROM public.tournaments t
    WHERE t.id = v_tournament_id;
  IF v_t_status NOT IN ('registration_open','registration_closed','live') THEN
    RAISE EXCEPTION 'undo check-in not allowed in tournament status %', v_t_status
      USING ERRCODE = '22023';
  END IF;

  -- Participant status gate: only confirmed participants are check-in subjects.
  IF v_reg_status <> 'confirmed' THEN
    RAISE EXCEPTION 'undo check-in only allowed for confirmed participants (is %)',
      v_reg_status USING ERRCODE = '22023';
  END IF;

  -- Idempotent: already not checked in => no-op, write no audit event.
  IF v_checked_in_at IS NULL THEN
    RETURN jsonb_build_object(
      'participant_id', p_participant_id,
      'checked_in_at',  NULL,
      'changed',        false
    );
  END IF;

  UPDATE public.tournament_participants
    SET checked_in_at = NULL
    WHERE id = p_participant_id;

  -- Audit: one event per real state change.
  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id, 'participant_checkin_undone', v_caller,
      jsonb_build_object(
        'participant_id',         p_participant_id,
        'previous_checked_in_at', v_checked_in_at
      ));

  RETURN jsonb_build_object(
    'participant_id', p_participant_id,
    'checked_in_at',  NULL,
    'changed',        true
  );
END;
$$;

-- See the check-in RPC: also REVOKE FROM anon so the default-privilege grant
-- does not leave anon with EXECUTE.
REVOKE ALL ON FUNCTION public.tournament_undo_checkin(uuid)
  FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tournament_undo_checkin(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_undo_checkin(uuid) IS
  'Clear a participant''s on-site presence (sets checked_in_at = NULL). Same '
  'manage-authority / tournament-status / confirmed-participant gates as '
  'tournament_checkin_participant. Idempotent (undo on already-NULL no-op, no '
  'duplicate audit). Writes a participant_checkin_undone audit event. See '
  '20261265000000_tournament_participant_checkin.sql.';
