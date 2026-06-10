-- Phase C / Block C0 — schedule-event notify helpers.
--
-- Source: docs/plans/tournament-scheduler-dashboard/phase-c-plan.md (C0) +
-- docs/adr/0031-timed-tournament-runner-and-organizer-dashboard.md (§8 Notify).
--
-- ====================== DESIGN / STALE-BODY NOTE ======================
-- Per README.md K2, the inbox `kind` CHECK and
-- public._tournament_notify_participants(uuid,text,text,text,jsonb) were LAST
-- (re-)defined in 20261242000000_tournament_finished_inbox_round_time.sql
-- (verified: `grep -rl 'FUNCTION public._tournament_notify_participants('
-- supabase/migrations/` lists only 20261201000010 and 20261242000000, the
-- latter being the highest on-disk timestamp). This migration re-bases BOTH on
-- that 20261242000000 body — NOT on the stale 20261201000010 version — and the
-- only intended differences from §0 / §2 are documented inline.
--
-- §0  kind CHECK: re-stated VERBATIM from 20261242000000 §0 (all 16 kinds).
--     NO new wire-kind is added — every schedule sub-event rides on the
--     existing 'tournament_round' wire-kind and is disambiguated client-side
--     via action_payload.kind (same pattern as the shootout events). The CHECK
--     is re-stated only so this migration is self-contained against the latest
--     vocabulary; the kind set is byte-for-byte identical to 20261242000000.
--
-- §1  _tournament_notify_participants: CREATE OR REPLACE re-stating the
--     20261242000000 §2 body. Recipient resolution (solo p.user_id UNION open
--     team roster member_user_id), the kind guard, the round_time_suffix call,
--     SECURITY DEFINER and SET search_path = public, auth are byte-for-byte
--     identical. INTENDED C0 difference: NONE to the runtime body — it is
--     re-stated here purely to keep the C0 migration self-contained on the
--     verified-latest definition (K2). (No second, divergent body is frozen.)
--
-- §2  _tournament_notify_round_per_pitch: NEW per-recipient fan-out. Resolves
--     each recipient's OWN match in the round and writes exactly one inbox row
--     carrying THAT match's pitch_number (per-pitch, not broadcast). The body
--     gets the German '— Pitch X, Start HH:MM' hint; both segments degrade
--     cleanly (no pitch / no start). PII-free: action_payload holds only the
--     6 whitelist keys (tournament_id, round_number, phase, starts_at,
--     pitch_number, kind). Idempotent over (tournament_id, round_number, kind,
--     user_id) via a per-recipient NOT EXISTS guard scoped to per-pitch rows
--     (also requires a pitch_number payload key, so a broadcast-shaped
--     tournament_round row cannot suppress it) — double-notify / double-cron
--     safe.
--
-- Code comments English; UI/inbox strings German (project convention).
-- Additive only: no db reset, no destructive DDL beyond the unavoidable
-- DROP CONSTRAINT IF EXISTS / ADD CONSTRAINT pair for the kind CHECK.
-- =====================================================================


-- ---- 0. Re-state the inbox kind CHECK (K2 re-base on 20261242000000 §0) ----
-- The FULL current vocabulary (16 kinds), VERBATIM from
-- 20261242000000_tournament_finished_inbox_round_time.sql Z.52-69. No kind is
-- stripped, no new wire-kind is added (schedule events reuse 'tournament_round'
-- + action_payload.kind). Every existing kind is preserved so no inbox row is
-- invalidated.
ALTER TABLE public.user_inbox_messages
  DROP CONSTRAINT IF EXISTS user_inbox_messages_kind_check;
ALTER TABLE public.user_inbox_messages
  ADD CONSTRAINT user_inbox_messages_kind_check
    CHECK (kind IN (
      'notice',
      'verification_request',
      'system',
      'team_invitation',
      'team_member_removed',
      'team_dissolved',
      'club_invitation',
      'club_member_removed',
      'club_join_request',
      'tournament_started',
      'tournament_round',
      'tournament_team_registered',
      'tournament_registration_confirmed',
      'tournament_waitlisted',
      'tournament_promoted',
      'tournament_finished'
    ));


-- ---- 1. _tournament_notify_participants (re-stated, K2 re-base) -------------
-- CREATE OR REPLACE on the EXACT 20261242000000 §2 on-disk body (Z.156-217).
-- Signature (uuid,text,text,text,jsonb), the recipient CTE (solo user_id UNION
-- open team roster member_user_id with replaced_at IS NULL / member_user_id IS
-- NOT NULL / registration_status='confirmed'), the kind guard, the
-- round_time_suffix append, the RETURNING/count and SECURITY DEFINER /
-- SET search_path = public, auth are byte-for-byte identical to 20261242000000.
-- Intended C0 difference to the body: NONE (re-stated for self-containment).
CREATE OR REPLACE FUNCTION public._tournament_notify_participants(
  p_tournament_id uuid,
  p_kind          text,
  p_subject       text,
  p_body          text,
  p_payload       jsonb DEFAULT NULL
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_inserted int := 0;
  v_body     text;   -- N1: body + configured round-time suffix
BEGIN
  IF p_kind NOT IN ('tournament_started', 'tournament_round',
                    'tournament_finished') THEN
    RAISE EXCEPTION 'invalid tournament inbox kind: %', p_kind
      USING ERRCODE = '22023';
  END IF;

  -- N1: name the CONFIGURED round time of the relevant phase in EVERY
  -- tournament notification (started / round / finished). The phase comes
  -- from the payload; absent/non-'ko' phases use the prelim match_format.
  v_body := p_body
    || public._tournament_round_time_suffix(
         p_tournament_id, p_payload ->> 'phase');

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
    SELECT DISTINCT r.user_id, p_kind, p_subject, v_body, p_payload
      FROM recipients r
      WHERE r.user_id IS NOT NULL
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM ins;

  RETURN v_inserted;
END;
$$;

REVOKE ALL ON FUNCTION public._tournament_notify_participants(uuid, text, text, text, jsonb) FROM public;

COMMENT ON FUNCTION public._tournament_notify_participants(uuid, text, text, text, jsonb) IS
  'Fan-out one user_inbox_messages row per distinct confirmed-participant '
  'user (solo user_id + open team roster member_user_id; guests skipped). '
  'SECURITY DEFINER. Used by tournament go-live / round-publish RPCs and the '
  'tournament_finished trigger. N1: accepts kind tournament_finished and '
  'appends the configured round-time suffix to the body. Re-based verbatim on '
  '20261242000000 §2 by 20261260000000_schedule_notify_helpers.sql (K2).';


-- ---- 2. _tournament_notify_round_per_pitch (NEW, per-recipient fan-out) -----
-- Writes EXACTLY ONE user_inbox_messages row per recipient, carrying the
-- pitch_number of THAT recipient's match in round p_round_number (match->pitch
-- per recipient, NOT a broadcast). Receivers are the same spine as
-- _tournament_notify_participants: solo participants (user_id) UNION open team
-- roster slots (member_user_id, replaced_at IS NULL, member_user_id IS NOT
-- NULL, on a confirmed participant). Guest / NULL slots drop out.
--
-- Each recipient is mapped to a match via their participant_id (the solo
-- participant.id, or the team roster slot's participant_id) appearing as
-- participant_a OR participant_b of a round-p_round_number match. The pitch and
-- the schedule starts_at feed the German body hint '— Pitch X, Start HH:MM':
--   * 'Pitch X' only when pitch_number is present and > 0 (OD-3: "Pitch X" only
--     when a pitch is actually assigned);
--   * 'Start HH:MM' only when a schedule starts_at exists (C degrades cleanly
--     without Phase A — no start segment, the pitch segment stays).
--
-- PII-free (privacy whitelist): action_payload holds ONLY tournament_id,
-- round_number, phase, starts_at, pitch_number, kind — no names, no opponent
-- user-ids. The body likewise carries only round / pitch / start time.
--
-- Idempotent: a per-recipient NOT EXISTS guard on the key set
-- (tournament_id + round_number + action_payload.kind + user_id) makes a second
-- identical call a no-op (double-notify / double-cron safe).
--
-- p_event_kind is the SCHEDULE sub-event tag stored in action_payload.kind
-- (e.g. 'round_published'); the durable wire-kind written to
-- user_inbox_messages.kind is always 'tournament_round' (no new wire-kind).
CREATE OR REPLACE FUNCTION public._tournament_notify_round_per_pitch(
  p_tournament_id uuid,
  p_round_number  int,
  p_phase         text,
  p_event_kind    text,
  p_subject       text,
  p_body          text
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_inserted text := 'tournament_round';  -- durable wire-kind (no new kind)
  v_count    int  := 0;
  v_starts   timestamptz;
BEGIN
  -- Schedule start time for this round (Phase A). Absent when A has not
  -- materialised a schedule row yet -> the body's 'Start HH:MM' segment is
  -- omitted (C is not hard-dependent on A). The classic path (stage_node_id
  -- NULL) and the stage path share (tournament_id, round_number); we take the
  -- earliest start should several stage rows share the round number.
  SELECT min(s.starts_at)
    INTO v_starts
    FROM public.tournament_round_schedule s
   WHERE s.tournament_id = p_tournament_id
     AND s.round_number  = p_round_number;

  WITH recipients AS (
    -- Solo participants: participant.id is the match side; user_id is the
    -- recipient.
    SELECT p.user_id AS user_id,
           p.id      AS participant_id
      FROM public.tournament_participants p
     WHERE p.tournament_id = p_tournament_id
       AND p.registration_status = 'confirmed'
       AND p.user_id IS NOT NULL
    UNION
    -- Team participants: each open roster slot's member is a recipient; the
    -- participant_id (the team's participation) is the match side, so every
    -- team-mate gets the pitch of THEIR team's match. Guest / NULL slots drop.
    SELECT s.member_user_id AS user_id,
           p.id             AS participant_id
      FROM public.tournament_participants p
      JOIN public.tournament_roster_slots s
        ON s.participant_id = p.id
     WHERE p.tournament_id = p_tournament_id
       AND p.registration_status = 'confirmed'
       AND p.team_id IS NOT NULL
       AND s.replaced_at IS NULL
       AND s.member_user_id IS NOT NULL
  ),
  -- Resolve each recipient's pitch from THEIR match in the round (participant
  -- on side a or b). LEFT JOIN keeps a recipient with no match row (pitch NULL
  -- -> 'Pitch X' segment omitted for them).
  --
  -- One-match-per-recipient-per-round assumption: in every supported format
  -- (pool / swiss / single-game KO) a participation plays at most ONE match in
  -- a given round_number, so DISTINCT ON selects that unique row. Should a
  -- future multi-match-per-round format ever exist, DISTINCT ON deterministically
  -- collapses the recipient to the LOWEST assigned pitch (ORDER BY pitch_number
  -- NULLS LAST -> a real pitch is preferred over NULL, then the smallest pitch).
  -- This deterministic tie-break is exercised by the pgTAP suite.
  per_recipient AS (
    SELECT DISTINCT ON (r.user_id)
           r.user_id           AS user_id,
           m.pitch_number      AS pitch_number
      FROM recipients r
      LEFT JOIN public.tournament_matches m
        ON m.tournament_id = p_tournament_id
       AND m.round_number  = p_round_number
       AND (m.participant_a = r.participant_id
            OR m.participant_b = r.participant_id)
     ORDER BY r.user_id, m.pitch_number NULLS LAST
  ),
  ins AS (
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
    SELECT
        pr.user_id,
        v_inserted,
        p_subject,
        -- German body hint, segments degrade cleanly.
        p_body
          || CASE WHEN pr.pitch_number IS NOT NULL AND pr.pitch_number > 0
                  THEN ' — Pitch ' || pr.pitch_number::int
                  ELSE '' END
          || CASE WHEN v_starts IS NOT NULL
                  THEN CASE WHEN pr.pitch_number IS NOT NULL
                                 AND pr.pitch_number > 0
                            THEN ', Start '
                            ELSE ' — Start ' END
                       || to_char(v_starts, 'HH24:MI')
                  ELSE '' END,
        -- PII-free whitelist: exactly these 6 keys.
        jsonb_build_object(
          'tournament_id', p_tournament_id,
          'round_number',  p_round_number,
          'phase',         p_phase,
          'starts_at',     v_starts,
          'pitch_number',  pr.pitch_number,
          'kind',          p_event_kind)
      FROM per_recipient pr
      -- Idempotency guard: skip a recipient who already has a per-pitch row for
      -- this (tournament, round, event-kind). Keyed on action_payload so a
      -- second identical call (re-publish / double cron) inserts nothing.
      -- The `action_payload ? 'pitch_number'` clause scopes the guard to rows
      -- written by THIS per-pitch fan-out (the 6-key whitelist always carries a
      -- pitch_number key), so an unrelated tournament_round row produced by the
      -- broadcast _tournament_notify_participants path — whose payload never
      -- carries pitch_number — can never spuriously suppress a per-pitch row.
      WHERE NOT EXISTS (
        SELECT 1
          FROM public.user_inbox_messages x
         WHERE x.user_id = pr.user_id
           AND x.kind = v_inserted
           AND x.action_payload ? 'pitch_number'
           AND (x.action_payload ->> 'tournament_id') = p_tournament_id::text
           AND (x.action_payload ->> 'round_number')  = p_round_number::text
           AND (x.action_payload ->> 'kind')          = p_event_kind
      )
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM ins;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public._tournament_notify_round_per_pitch(uuid, int, text, text, text, text) FROM public;

COMMENT ON FUNCTION public._tournament_notify_round_per_pitch(uuid, int, text, text, text, text) IS
  'Per-recipient round notify fan-out: one user_inbox_messages row per '
  'confirmed-participant user (solo + open team roster member; guests skipped), '
  'each carrying the pitch_number of THAT recipient''s match in the round. '
  'Durable wire-kind is always tournament_round; the schedule sub-event is in '
  'action_payload.kind. PII-free payload (tournament_id, round_number, phase, '
  'starts_at, pitch_number, kind). Idempotent over '
  '(tournament_id, round_number, kind, user_id) via a NOT EXISTS guard scoped '
  'to per-pitch rows (action_payload ? pitch_number). '
  'SECURITY DEFINER. Added by 20261260000000_schedule_notify_helpers.sql (C0).';
