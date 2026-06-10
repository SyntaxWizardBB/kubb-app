-- Phase C / Block C2 — pause / resume durable inbox notify.
--
-- Source: docs/plans/tournament-scheduler-dashboard/phase-c-plan.md (C2) +
-- docs/adr/0031-timed-tournament-runner-and-organizer-dashboard.md (§8 Notify,
-- Notify-Matrix E5/E6) + README.md (K2 spine, OD-2 seam).
--
-- ====================== DESIGN / STALE-BODY NOTE ======================
-- PURELY ADDITIVE. Three CREATE OR REPLACE FUNCTION statements only:
--   §1  public._tournament_notify_paused(uuid, boolean)  — NEW. This signature
--       did NOT exist on disk before this block (verified:
--       `grep -rl 'FUNCTION public._tournament_notify_paused(' supabase/
--       migrations/` lists only this file) -> no stale-body risk for it.
--   §2  public.tournament_pause(uuid)   — RE-BASED on its TRUE latest on-disk
--       body, 20261256000000_tournament_schedule_control_rpcs.sql (Block B2s;
--       verified highest timestamp for `FUNCTION public.tournament_pause(`).
--       The ENTIRE B2 body (gate tournament_caller_can_manage / 42501, advisory
--       xact-lock, the UPDATE on tournament_round_schedule guarded on status IN
--       ('call','running','awaiting_results') AND paused_at IS NULL,
--       SECURITY DEFINER, SET search_path = public, auth, REVOKE/GRANT, COMMENT)
--       is preserved byte-for-byte. The ONLY intended change is ONE added
--       PERFORM public._tournament_notify_paused(p_tournament_id, false) line,
--       fired only when the UPDATE actually changed a row (E5).
--   §3  public.tournament_resume(uuid)  — RE-BASED analogously on the same
--       20261256000000 body. The ONLY intended change is ONE added
--       PERFORM public._tournament_notify_paused(p_tournament_id, true) line,
--       fired only when the resume actually changed a row (E6).
--
-- tournament_skip_forward / tournament_skip_back are NOT touched here (skip
-- fires no paused/resumed notify). No other foreign function/table/policy is
-- redefined. The kind CHECK is NOT re-stated (C0 set it last; no new wire-kind:
-- the schedule sub-event rides on the existing 'tournament_round' wire-kind and
-- is disambiguated client-side via action_payload.kind, here 'paused' /
-- 'resumed' — E5/E6).
--
-- Recipient spine (broadcast): solo confirmed participants (user_id) UNION open
-- team roster members (member_user_id, replaced_at IS NULL, confirmed) — exactly
-- the spine of _tournament_notify_participants / _tournament_notify_round_per_
-- pitch (20261260000000). Guest / NULL slots drop out. Exactly one inbox row per
-- distinct recipient.
--
-- PII-free (privacy whitelist): action_payload holds ONLY tournament_id and
-- kind — no names, no opponent / user-ids (user_id only as the inbox target
-- column). A broadcast event has no per-recipient pitch / round / phase, so the
-- payload is the broadcast-sensible subset of the whitelist (tournament_id,
-- kind) — no dead NULL keys.
--
-- Idempotency / double-notify avoidance is structural: the PERFORM in the RPCs
-- fires ONLY when the underlying UPDATE actually transitioned a row
-- (GET DIAGNOSTICS row count > 0), so a no-op pause (nothing active / already
-- paused) or a no-op resume (not paused) writes NO inbox row.
--
-- Code comments English; UI / inbox strings German (project convention).
-- Additive only: no db reset, no DROP/TRUNCATE/DELETE, no schema / column /
-- policy change, no ALTER PUBLICATION, no tournaments.paused_at.
-- =====================================================================


-- ---- 1. _tournament_notify_paused (NEW broadcast helper, E5/E6) -------------
-- Writes EXACTLY ONE user_inbox_messages row per distinct confirmed recipient
-- (broadcast). p_resumed=false -> 'paused' sub-event (E5); p_resumed=true ->
-- 'resumed' (E6). Durable wire-kind is always 'tournament_round'; the schedule
-- sub-event tag lives in action_payload.kind. German subject/body. PII-free
-- payload (tournament_id, kind). SECURITY DEFINER. Returns the number of
-- inbox rows written (for tests / diagnostics).
CREATE OR REPLACE FUNCTION public._tournament_notify_paused(
  p_tournament_id uuid,
  p_resumed       boolean
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_kind     text := 'tournament_round';       -- durable wire-kind (no new kind)
  v_event    text := CASE WHEN p_resumed THEN 'resumed' ELSE 'paused' END;
  v_subject  text := CASE WHEN p_resumed
                          THEN 'Turnier fortgesetzt'
                          ELSE 'Turnier pausiert' END;
  v_body     text := CASE WHEN p_resumed
                          THEN 'Das Turnier wurde fortgesetzt.'
                          ELSE 'Das Turnier wurde pausiert.' END;
  v_count    int  := 0;
BEGIN
  WITH recipients AS (
    -- Solo participants: the participant row itself carries the user.
    SELECT p.user_id AS user_id
      FROM public.tournament_participants p
     WHERE p.tournament_id = p_tournament_id
       AND p.registration_status = 'confirmed'
       AND p.user_id IS NOT NULL
    UNION
    -- Team participants: every open roster slot's member. Guest slots
    -- (member_user_id NULL) carry no app user and drop out naturally.
    SELECT s.member_user_id AS user_id
      FROM public.tournament_participants p
      JOIN public.tournament_roster_slots s
        ON s.participant_id = p.id
     WHERE p.tournament_id = p_tournament_id
       AND p.registration_status = 'confirmed'
       AND p.team_id IS NOT NULL
       AND s.replaced_at IS NULL
       AND s.member_user_id IS NOT NULL
  ),
  ins AS (
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
    SELECT DISTINCT
        r.user_id,
        v_kind,
        v_subject,
        v_body,
        -- PII-free broadcast whitelist subset (C2-04): a broadcast pause/resume
        -- has no per-recipient round/phase/pitch, so only the two keys that
        -- carry information are written (tournament_id, kind). No dead NULL keys
        -- the client (C4 _kindLabel/_kindBg) could misread as set-but-null.
        jsonb_build_object(
          'tournament_id', p_tournament_id,
          'kind',          v_event)
      FROM recipients r
      WHERE r.user_id IS NOT NULL
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM ins;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public._tournament_notify_paused(uuid, boolean) FROM public;

COMMENT ON FUNCTION public._tournament_notify_paused(uuid, boolean) IS
  'ADR-0031 Phase C / Block C2 (Notify-Matrix E5/E6): broadcast durable inbox '
  'notify on tournament pause (p_resumed=false -> action_payload.kind=''paused'') '
  'and resume (p_resumed=true -> ''resumed''). One user_inbox_messages row per '
  'distinct confirmed recipient (solo user_id + open team roster member_user_id; '
  'guests skipped) — same spine as _tournament_notify_participants. Durable '
  'wire-kind is always tournament_round. PII-free payload (tournament_id, '
  'kind). German subject/body. SECURITY DEFINER. Called via PERFORM from the B2 '
  'RPCs tournament_pause / tournament_resume (OD-2). Added by '
  '20261262000000_pause_resume_notify.sql.';


-- ---- 2. tournament_pause(uuid) — RE-BASED on 20261256000000 + PERFORM (E5) --
-- The whole body below is byte-for-byte the 20261256000000_tournament_schedule_
-- control_rpcs.sql tournament_pause body. The ONLY intended addition is the
-- GET DIAGNOSTICS row-count capture + the conditional PERFORM
-- _tournament_notify_paused(..., false): the notify fires ONLY when the UPDATE
-- actually transitioned an active (non-terminal) row from unpaused -> paused.
-- An idempotent double-pause (paused_at already set -> 0 rows updated) or a
-- pause of a non-active tournament writes NO second 'paused' notify (C2-09).
CREATE OR REPLACE FUNCTION public.tournament_pause(
  p_tournament_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_changed int := 0;  -- C2: rows actually transitioned unpaused -> paused
BEGIN
  IF NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  -- Serialise against the E cron tick and concurrent control calls.
  PERFORM pg_advisory_xact_lock(hashtext(p_tournament_id::text));

  -- Freeze the active round's clock: set paused_at only when not already paused
  -- (idempotent — a 2nd consecutive pause does not advance/overwrite paused_at
  -- and does not corrupt paused_accum_seconds). Active = non-terminal row.
  UPDATE public.tournament_round_schedule s
     SET paused_at = now()
   WHERE s.tournament_id = p_tournament_id
     AND s.status IN ('call','running','awaiting_results')
     AND s.paused_at IS NULL;

  -- C2 (E5): durable broadcast notify only on a REAL transition. A no-op pause
  -- (nothing active / already paused -> 0 rows) sends no second 'paused' notify.
  GET DIAGNOSTICS v_changed = ROW_COUNT;
  IF v_changed > 0 THEN
    PERFORM public._tournament_notify_paused(p_tournament_id, false);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_pause(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_pause(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_pause(uuid) IS
  'ADR-0031 Block B2s: tournament-wide pause (K5). Sets paused_at = now() on '
  'the active (non-terminal) tournament_round_schedule row when paused_at IS '
  'NULL (idempotent). Gate tournament_caller_can_manage (42501). Advisory '
  'xact-lock on the tournament. Writes ONLY tournament_round_schedule. '
  'Targets ALL active (non-terminal) rows of the tournament; the classic '
  'single-active-round case touches exactly one row. A future parallel-stage '
  'feature may add a p_stage_node_id / p_round_number scope. '
  'C2 (E5): fires _tournament_notify_paused(..., false) only on a real '
  'unpaused -> paused transition (broadcast durable inbox notify).';


-- ---- 3. tournament_resume(uuid) — RE-BASED on 20261256000000 + PERFORM (E6) -
-- The whole body below is byte-for-byte the 20261256000000 tournament_resume
-- body. The ONLY intended addition is the GET DIAGNOSTICS row-count capture +
-- the conditional PERFORM _tournament_notify_paused(..., true): the notify fires
-- ONLY when the UPDATE actually resumed a paused row. A resume of a non-paused
-- tournament (0 rows updated) writes NO 'resumed' notify (C2-09).
CREATE OR REPLACE FUNCTION public.tournament_resume(
  p_tournament_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_changed int := 0;  -- C2: rows actually resumed (paused -> unpaused)
BEGIN
  IF NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_tournament_id::text));

  -- Add the frozen interval to paused_accum_seconds and clear paused_at.
  -- Guarded on paused_at IS NOT NULL so a resume while not paused is a no-op
  -- (no negative / garbage accumulation, idempotent).
  UPDATE public.tournament_round_schedule s
     SET paused_accum_seconds =
           s.paused_accum_seconds
           + EXTRACT(EPOCH FROM (now() - s.paused_at))::int,
         paused_at = NULL
   WHERE s.tournament_id = p_tournament_id
     AND s.status IN ('call','running','awaiting_results')
     AND s.paused_at IS NOT NULL;

  -- C2 (E6): durable broadcast notify only on a REAL resume. A no-op resume
  -- (not paused -> 0 rows) sends no 'resumed' notify.
  GET DIAGNOSTICS v_changed = ROW_COUNT;
  IF v_changed > 0 THEN
    PERFORM public._tournament_notify_paused(p_tournament_id, true);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_resume(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_resume(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_resume(uuid) IS
  'ADR-0031 Block B2s: resume a paused tournament. Adds EXTRACT(EPOCH FROM '
  'now()-paused_at)::int to paused_accum_seconds and clears paused_at on the '
  'active tournament_round_schedule row (no-op when paused_at IS NULL, '
  'idempotent). Gate (42501). Advisory xact-lock. Writes ONLY the schedule. '
  'C2 (E6): fires _tournament_notify_paused(..., true) only on a real resume '
  '(broadcast durable inbox notify).';
