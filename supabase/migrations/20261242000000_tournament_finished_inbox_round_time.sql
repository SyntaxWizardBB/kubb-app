-- Tournament feature — N1: tournament-FINISHED inbox notification +
-- the CONFIGURED round time named in EVERY tournament notification
-- (started / round / finished).
--
-- Source: humanPlan/MilestoneTournamentHub_V1_Plan.md, Block N1. Decision:
-- the CONFIGURED round time (match_format.{round_time_seconds|
-- time_limit_seconds|round_time_minutes}) — NOT the actually elapsed time.
--
-- ====================== DESIGN / STALE-BODY NOTE ======================
-- Rather than re-stating the four large go-live RPCs (tournament_start,
-- tournament_start_pool_phase, tournament_pair_round,
-- tournament_start_ko_phase) — each a long CREATE-OR-REPLACE chain with a
-- real stale-body risk — this migration adds the round-time text at the
-- SINGLE fan-out point every tournament notification already flows through:
-- public._tournament_notify_participants(uuid,text,text,text,jsonb). That
-- helper was defined EXACTLY ONCE (20261201000010_tournament_golive_inbox
-- §1) and its on-disk body equals the live body (verified by diff), so there
-- is no stale-body risk. Re-stating it here:
--   * keeps the recipient resolution byte-for-byte identical (solo user_id
--     UNION open team roster member_user_id, guests/NULL drop out) — S2;
--   * widens the kind guard to also accept 'tournament_finished';
--   * appends the configured round-time suffix to the body, derived from the
--     tournament's match_format (prelim/group/swiss/round) or ko_match_format
--     (KO phase, falling back to match_format), using the SAME
--     seconds->minutes rounding as the client _roundTimeMinutes.
-- Because started/round/finished all fan out through this one helper, the
-- suffix appears in every tournament notification with no change to the four
-- RPCs (S4). When no round time is configured the suffix is omitted entirely
-- (no 'null min', no '0 min', no empty 'Spielzeit  min') — S5.
--
-- The tournament_finished fan-out hooks the tournaments.status -> 'finalized'
-- transition via an AFTER-UPDATE trigger, mirroring
-- 20261217000000_tournament_finalize_awards_trigger.sql (same WHEN gate, same
-- SECURITY DEFINER trust path). tournament_finalize itself stays untouched.
-- The trigger is idempotent: a NOT EXISTS guard skips the fan-out if a
-- tournament_finished row already exists for the tournament — S2.
--
-- Code comments English; UI/inbox strings German (project convention).
-- Additive only: no db reset, no destructive DDL.
-- =====================================================================


-- ---- 0. Extend the inbox kind CHECK ----------------------------------
-- Drop + re-add with the FULL current vocabulary (latest =
-- 20261201000040_tournament_open_registration_model.sql §0) plus the new
-- 'tournament_finished'. Every existing kind is preserved so no inbox row
-- is invalidated.
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


-- ---- 1. _tournament_round_time_suffix --------------------------------
-- Returns a ' — Spielzeit N min' suffix for a tournament notification body,
-- or '' when the relevant phase has no configured round time. The phase is
-- chosen by p_phase: 'ko' reads ko_match_format (falling back to
-- match_format when ko_match_format is NULL/empty); every other value
-- (NULL, 'pool', 'finished', a swiss round, …) reads match_format (the
-- prelim/group format). Round time is read in the SAME precedence and unit
-- handling as the Flutter client (_roundTimeMinutes in
-- tournament_stammdaten_card.dart): round_time_seconds, then
-- time_limit_seconds (both seconds, rounded to whole minutes), then
-- round_time_minutes. A non-positive or absent value yields '' (S5).
CREATE OR REPLACE FUNCTION public._tournament_round_time_suffix(
  p_tournament_id uuid,
  p_phase         text
)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_match_format jsonb;
  v_ko_format    jsonb;
  v_fmt          jsonb;
  v_secs         numeric;
  v_mins         numeric;
BEGIN
  SELECT match_format, ko_match_format
    INTO v_match_format, v_ko_format
    FROM public.tournaments
    WHERE id = p_tournament_id;

  IF p_phase = 'ko'
     AND v_ko_format IS NOT NULL
     AND jsonb_typeof(v_ko_format) = 'object' THEN
    v_fmt := v_ko_format;
  ELSE
    v_fmt := v_match_format;
  END IF;

  IF v_fmt IS NULL OR jsonb_typeof(v_fmt) <> 'object' THEN
    RETURN '';
  END IF;

  -- Canonical seconds key first, then the legacy alias; both in seconds.
  v_secs := coalesce(
    (v_fmt ->> 'round_time_seconds')::numeric,
    (v_fmt ->> 'time_limit_seconds')::numeric);

  IF v_secs IS NOT NULL AND v_secs > 0 THEN
    v_mins := round(v_secs / 60.0);
  ELSE
    -- Fallback: an explicit minutes value (no seconds configured).
    v_mins := (v_fmt ->> 'round_time_minutes')::numeric;
  END IF;

  IF v_mins IS NULL OR v_mins <= 0 THEN
    RETURN '';
  END IF;

  RETURN ' — Spielzeit ' || v_mins::int || ' min';
END;
$$;

REVOKE ALL ON FUNCTION public._tournament_round_time_suffix(uuid, text) FROM public;

COMMENT ON FUNCTION public._tournament_round_time_suffix(uuid, text) IS
  'N1: returns a German '' — Spielzeit N min'' suffix for a tournament '
  'notification body from the CONFIGURED round time (match_format, or '
  'ko_match_format for p_phase=''ko'' with match_format fallback). Empty '
  'string when no round time is configured (no null/0 min). seconds->minutes '
  'rounding matches the client _roundTimeMinutes. See '
  '20261242000000_tournament_finished_inbox_round_time.sql.';


-- ---- 2. _tournament_notify_participants (re-stated) -------------------
-- Verbatim re-statement of the 20261201000010 §1 body (the ONLY prior
-- definition; live body diff-verified), with two surgical additions:
--   (a) the kind guard also accepts 'tournament_finished';
--   (b) the configured round-time suffix (§1) is appended to the body,
--       choosing the phase format via p_payload->>'phase'.
-- Recipient resolution is UNCHANGED (S2). SECURITY DEFINER so the direct
-- INSERT bypasses the (intentionally absent) INSERT policy.
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
  'appends the configured round-time suffix to the body. See '
  '20261242000000_tournament_finished_inbox_round_time.sql.';


-- ---- 3. tournament_finished fan-out on finalize ----------------------
-- AFTER-UPDATE trigger on the tournaments.status -> 'finalized' transition
-- (same hook shape as 20261217000000_tournament_finalize_awards_trigger.sql).
-- Writes ONE 'tournament_finished' inbox row per distinct participant user
-- via the shared helper (§2), so the recipient set + PII-free body match the
-- started/round notifications exactly. PII-free: body carries only the
-- tournament display_name + round-time suffix, action_payload only
-- tournament_id + phase. Idempotent: a NOT EXISTS guard skips the fan-out
-- when a tournament_finished row already exists for the tournament.
CREATE OR REPLACE FUNCTION public.tournament_notify_finished()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- Idempotency: never fan out twice for the same tournament (guards a
  -- live->finalized re-entry on top of the WHEN-clause's once-per-transition
  -- firing).
  IF EXISTS (
    SELECT 1
      FROM public.user_inbox_messages m
     WHERE m.kind = 'tournament_finished'
       AND (m.action_payload ->> 'tournament_id') = NEW.id::text
  ) THEN
    RETURN NEW;
  END IF;

  PERFORM public._tournament_notify_participants(
    NEW.id,
    'tournament_finished',
    'Turnier beendet',
    'Turnier "' || coalesce(NEW.display_name, '')
      || '" ist beendet. Danke fürs Mitspielen!',
    jsonb_build_object('tournament_id', NEW.id, 'phase', 'finished'));

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.tournament_notify_finished() IS
  'AFTER-UPDATE trigger fn (SECURITY DEFINER): on a tournament''s transition '
  'to status=finalized, fans out one tournament_finished inbox row per '
  'distinct participant user via _tournament_notify_participants (PII-free '
  'body = display_name + configured round time). Idempotent (no-op if a '
  'tournament_finished row already exists for the tournament). '
  'tournament_finalize stays unchanged. N1.';

DROP TRIGGER IF EXISTS tournament_notify_finished ON public.tournaments;
CREATE TRIGGER tournament_notify_finished
  AFTER UPDATE ON public.tournaments
  FOR EACH ROW
  WHEN (
    old.status IS DISTINCT FROM 'finalized'
    AND new.status = 'finalized'
  )
  EXECUTE FUNCTION public.tournament_notify_finished();
