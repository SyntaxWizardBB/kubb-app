-- Phase C / Block C3 — timed schedule-event notify helpers (E2 / E7 / E8).
--
-- Source: docs/plans/tournament-scheduler-dashboard/phase-c-plan.md (C3) +
-- docs/adr/0031-timed-tournament-runner-and-organizer-dashboard.md (§8 Notify,
-- Notify-Matrix E2/E7/E8) + README.md (K2 spine; PII-free whitelist).
--
-- ====================== DESIGN / STALE-BODY NOTE ======================
-- PURELY ADDITIVE. This migration defines exactly TWO NEW functions via
-- CREATE FUNCTION / CREATE OR REPLACE:
--   §1  public._tournament_notify_match_running(uuid, int, text, text, text)
--       — NEW. The "match läuft jetzt" notify (E2), fired per recipient with
--       the pitch of THEIR OWN match in the round (per-pitch fan-out, analogous
--       to _tournament_notify_round_per_pitch). action_payload.kind =
--       'match_running'.
--   §2  public._tournament_notify_awaiting(uuid, int, text, boolean, text, text)
--       — NEW. The "überfällig" / "tiebreak-hold" notify (E7 / E8), fired ONLY
--       to recipients who still have an OPEN (non-terminal) match in the round
--       (result missing). Recipients with no open match get NO row.
--       action_payload.kind = 'awaiting_results' (E7) or 'tiebreak_hold' (E8,
--       p_tiebreak = true).
--
-- STALE-BODY: NEITHER function existed on disk before this block (verified:
--   grep -rl 'FUNCTION public._tournament_notify_match_running(' supabase/migrations/
--   grep -rl 'FUNCTION public._tournament_notify_awaiting('       supabase/migrations/
-- both list ONLY this file) — so there is no prior body to diff against and no
-- stale-body risk. No foreign layered function (e.g.
-- _tournament_notify_participants, _tournament_notify_round_per_pitch,
-- _tournament_notify_paused, tournament_pause / tournament_resume, the
-- materialisation RPCs, RPCs, triggers) is re-defined here.
--
-- NO CALL IS WIRED IN C3: neither function is PERFORM/SELECT-invoked from
-- tournament_schedule_tick or any other RPC/trigger here; tournament_schedule_
-- tick is NOT defined or altered in this file. The actual invocation lives in
-- the Phase E cron tick (E2/E7/E8). This migration only DEFINES the helpers.
--
-- Recipient spine (per-recipient): solo confirmed participants (p.user_id)
-- UNION open team roster slots (s.member_user_id, s.replaced_at IS NULL,
-- s.member_user_id IS NOT NULL, on a confirmed team participant) — the SAME
-- spine as _tournament_notify_participants / _tournament_notify_round_per_pitch
-- (20261260000000) and _tournament_notify_paused (20261262000000). Guest / NULL
-- slots drop out; at most one row per distinct user per sub-event. The
-- recipient -> match-side resolution (participant_a / participant_b) mirrors
-- _tournament_notify_round_per_pitch.
--
-- Wire-kind: BOTH functions write user_inbox_messages.kind = 'tournament_round'
-- ALWAYS (the existing durable wire-kind — NO new wire-kind). The schedule
-- sub-event lives ONLY in action_payload.kind ('match_running' / 'awaiting_
-- results' / 'tiebreak_hold'). The kind CHECK constraint is NOT touched (C0
-- last set it; no new kind is needed).
--
-- PII-free (privacy whitelist): action_payload holds ONLY keys from
-- {tournament_id, round_number, phase, starts_at, pitch_number, kind} — no
-- names, no opponent / user-ids (user_id only as the inbox target column).
-- Broadcast-sense-less keys are omitted, not written as NULL, where the C2
-- convention prescribes it.
--
-- Idempotency: BOTH functions are idempotent over the key set
-- (tournament_id, round_number, action_payload.kind, user_id) via a
-- per-recipient NOT EXISTS guard scoped to THIS sub-event's rows (keyed on the
-- action_payload.kind tag and, for match_running, on the per-pitch
-- action_payload ? 'pitch_number' shape). A second identical call
-- (double / late cron tick) inserts 0 additional rows; a DIFFERENT
-- action_payload.kind for the same round is NOT blocked (it fans out anew).
--
-- "Open / non-terminal" match (awaiting): status NOT IN
-- ('finalized','overridden','voided'). The first two are the terminal
-- with-result states (see 20261201000010 §standings, m.status IN
-- ('finalized','overridden')); 'voided' is a cancelled match for which no
-- result is expected. The remaining states ('scheduled','awaiting_results',
-- 'disputed') still need a result -> their participants are the awaiting /
-- tiebreak recipients.
--
-- Code comments English; UI / inbox strings German (project convention).
-- Additive only: no db reset, no DROP/TRUNCATE/DELETE, no schema / column /
-- policy change, no ALTER PUBLICATION, no kind-CHECK change.
-- =====================================================================


-- ---- 1. _tournament_notify_match_running (NEW, E2, per-recipient pitch) -----
-- Writes EXACTLY ONE user_inbox_messages row per recipient when the round's
-- matches transition call -> running ("Dein Match läuft jetzt"). Each row
-- carries the pitch_number of THAT recipient's OWN match in the round
-- (per-pitch, NOT broadcast), resolved via the recipient's participant_id on
-- match side a or b — exactly the resolution of
-- _tournament_notify_round_per_pitch. The German body gets the same
-- "— Pitch X, Start HH:MM" hint (both segments degrade cleanly: no pitch / no
-- schedule starts_at).
--
-- PII-free whitelist payload (tournament_id, round_number, phase, starts_at,
-- pitch_number, kind='match_running'). Idempotent over
-- (tournament_id, round_number, kind, user_id) via a per-recipient NOT EXISTS
-- guard scoped to per-pitch rows of THIS sub-event (action_payload ?
-- 'pitch_number' AND action_payload.kind = 'match_running'), so a re-tick
-- inserts nothing and a broadcast-shaped tournament_round row cannot suppress
-- it.
CREATE OR REPLACE FUNCTION public._tournament_notify_match_running(
  p_tournament_id uuid,
  p_round_number  int,
  p_phase         text,
  p_subject       text,
  p_body          text
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_kind     text := 'tournament_round';   -- durable wire-kind (no new kind)
  v_event    text := 'match_running';       -- schedule sub-event (E2)
  v_count    int  := 0;
  v_starts   timestamptz;
BEGIN
  -- Schedule start time for this round (Phase A). Absent when A has not
  -- materialised a schedule row yet -> the body's 'Start HH:MM' segment is
  -- omitted (C is not hard-dependent on A). The classic path (stage_node_id
  -- NULL) and the stage path share (tournament_id, round_number); take the
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
    -- team-mate gets the pitch of THEIR team's match. Guest / NULL / replaced
    -- slots drop out.
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
  -- -> 'Pitch X' segment omitted). DISTINCT ON collapses any (unsupported)
  -- multi-match-per-round case deterministically to the LOWEST assigned pitch.
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
        v_kind,
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
          'kind',          v_event)
      FROM per_recipient pr
      -- Idempotency guard: skip a recipient who already has a match_running
      -- per-pitch row for this (tournament, round). Keyed on action_payload so
      -- a second identical tick inserts nothing. The action_payload ?
      -- 'pitch_number' clause scopes the guard to per-pitch rows of THIS
      -- fan-out, so a broadcast-shaped tournament_round row (no pitch_number
      -- key) cannot spuriously suppress it.
      WHERE NOT EXISTS (
        SELECT 1
          FROM public.user_inbox_messages x
         WHERE x.user_id = pr.user_id
           AND x.kind = v_kind
           AND x.action_payload ? 'pitch_number'
           AND (x.action_payload ->> 'tournament_id') = p_tournament_id::text
           AND (x.action_payload ->> 'round_number')  = p_round_number::text
           AND (x.action_payload ->> 'kind')          = v_event
      )
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM ins;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public._tournament_notify_match_running(uuid, int, text, text, text) FROM public;

COMMENT ON FUNCTION public._tournament_notify_match_running(uuid, int, text, text, text) IS
  'ADR-0031 Phase C / Block C3 (Notify-Matrix E2): per-recipient "match läuft '
  'jetzt" fan-out on the call -> running transition. One user_inbox_messages '
  'row per confirmed-participant user (solo + open team roster member; guests '
  'skipped), each carrying the pitch_number of THAT recipient''s match in the '
  'round (same resolution as _tournament_notify_round_per_pitch). Durable '
  'wire-kind is always tournament_round; the schedule sub-event lives in '
  'action_payload.kind = ''match_running''. PII-free payload (tournament_id, '
  'round_number, phase, starts_at, pitch_number, kind). Idempotent over '
  '(tournament_id, round_number, kind, user_id) via a NOT EXISTS guard scoped '
  'to per-pitch rows. SECURITY DEFINER. NOT called here — wired by the Phase E '
  'cron tick. Added by 20261263000000_timed_notify_functions.sql (C3).';


-- ---- 2. _tournament_notify_awaiting (NEW, E7 / E8, only open matches) -------
-- Writes ONE user_inbox_messages row ONLY to recipients who still have an OPEN
-- (non-terminal) match in the round — i.e. a match whose result is still
-- missing (status NOT IN ('finalized','overridden','voided')). Recipients
-- whose match is already terminal get NO row. This is the "Zeit um, Resultat
-- fehlt" notify (E7); when p_tiebreak = true it is the tiebreak-hold notify
-- (E8) and the sub-event tag becomes 'tiebreak_hold' (addressing the
-- recipients of the hanging match).
--
-- A recipient is a recipient of an OPEN match iff their participation
-- (participant_id) is participant_a or participant_b of a non-terminal
-- round-p_round_number match. The recipient spine (solo + open team roster
-- member) is the same as _tournament_notify_round_per_pitch; the open-match
-- INNER JOIN (not LEFT) is what restricts the fan-out to players with a result
-- still pending. Each row carries that open match's pitch_number.
--
-- PII-free whitelist payload (tournament_id, round_number, phase, starts_at,
-- pitch_number, kind). Idempotent over (tournament_id, round_number, kind,
-- user_id): a per-recipient NOT EXISTS guard scoped to THIS sub-event's
-- action_payload.kind makes a second identical call a no-op. Because the guard
-- is keyed on the kind tag, an 'awaiting_results' and a later 'tiebreak_hold'
-- for the same round do not block each other.
CREATE OR REPLACE FUNCTION public._tournament_notify_awaiting(
  p_tournament_id uuid,
  p_round_number  int,
  p_phase         text,
  p_tiebreak      boolean,
  p_subject       text,
  p_body          text
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_kind     text := 'tournament_round';   -- durable wire-kind (no new kind)
  -- Schedule sub-event tag: E8 tiebreak-hold vs E7 awaiting-results.
  v_event    text := CASE WHEN p_tiebreak THEN 'tiebreak_hold'
                          ELSE 'awaiting_results' END;
  v_count    int  := 0;
  v_starts   timestamptz;
BEGIN
  SELECT min(s.starts_at)
    INTO v_starts
    FROM public.tournament_round_schedule s
   WHERE s.tournament_id = p_tournament_id
     AND s.round_number  = p_round_number;

  WITH recipients AS (
    -- Solo participants.
    SELECT p.user_id AS user_id,
           p.id      AS participant_id
      FROM public.tournament_participants p
     WHERE p.tournament_id = p_tournament_id
       AND p.registration_status = 'confirmed'
       AND p.user_id IS NOT NULL
    UNION
    -- Team participants: open roster members. Guest / NULL / replaced drop out.
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
  -- INNER JOIN to OPEN (non-terminal) round matches only: a recipient appears
  -- here iff their participation has a match whose result is still missing.
  -- Recipients of a finished match drop out entirely (no row). DISTINCT ON
  -- collapses to a single row carrying the LOWEST open pitch deterministically.
  per_recipient AS (
    SELECT DISTINCT ON (r.user_id)
           r.user_id           AS user_id,
           m.pitch_number      AS pitch_number
      FROM recipients r
      JOIN public.tournament_matches m
        ON m.tournament_id = p_tournament_id
       AND m.round_number  = p_round_number
       AND m.status NOT IN ('finalized','overridden','voided')  -- open only
       AND (m.participant_a = r.participant_id
            OR m.participant_b = r.participant_id)
     ORDER BY r.user_id, m.pitch_number NULLS LAST
  ),
  ins AS (
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
    SELECT
        pr.user_id,
        v_kind,
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
          'kind',          v_event)
      FROM per_recipient pr
      -- Idempotency guard scoped to THIS sub-event (kind = v_event). A second
      -- identical call inserts nothing; an 'awaiting_results' row does not
      -- block a later 'tiebreak_hold' row (different v_event) for the same
      -- round, and vice versa.
      WHERE NOT EXISTS (
        SELECT 1
          FROM public.user_inbox_messages x
         WHERE x.user_id = pr.user_id
           AND x.kind = v_kind
           AND (x.action_payload ->> 'tournament_id') = p_tournament_id::text
           AND (x.action_payload ->> 'round_number')  = p_round_number::text
           AND (x.action_payload ->> 'kind')          = v_event
      )
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM ins;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public._tournament_notify_awaiting(uuid, int, text, boolean, text, text) FROM public;

COMMENT ON FUNCTION public._tournament_notify_awaiting(uuid, int, text, boolean, text, text) IS
  'ADR-0031 Phase C / Block C3 (Notify-Matrix E7 / E8): per-recipient '
  '"überfällig" / tiebreak-hold fan-out. Writes ONE user_inbox_messages row '
  'ONLY to recipients who still have an OPEN (non-terminal: status NOT IN '
  'finalized/overridden/voided) match in the round (result missing); '
  'recipients of a finished match get NO row. p_tiebreak=false -> '
  'action_payload.kind=''awaiting_results'' (E7); p_tiebreak=true -> '
  '''tiebreak_hold'' (E8, addressing the hanging match''s players). Durable '
  'wire-kind is always tournament_round. PII-free payload (tournament_id, '
  'round_number, phase, starts_at, pitch_number, kind). Idempotent over '
  '(tournament_id, round_number, kind, user_id) via a NOT EXISTS guard scoped '
  'to the sub-event kind. SECURITY DEFINER. NOT called here — wired by the '
  'Phase E cron tick. Added by 20261263000000_timed_notify_functions.sql (C3).';
