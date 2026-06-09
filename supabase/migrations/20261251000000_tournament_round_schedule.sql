-- Phase A (ADR-0031) Block A1 — tournament_round_schedule (CDC) + upsert helper.
--
-- The timed tournament runner needs server-authoritative per-round timestamps.
-- This migration is PURELY ADDITIVE: it creates ONE new table
-- public.tournament_round_schedule plus the central SECURITY-DEFINER helper
-- _tournament_upsert_round_schedule. No existing table, column, policy or
-- function is altered or dropped here. The materialisation RPCs that derive a
-- schedule row are re-based (with their genuine latest on-disk bodies) in the
-- companion migration 20261252000000_round_schedule_materialize.sql.
--
-- ============================ MODEL (ADR-0031) ============================
-- One row per (tournament, round, stage). stage_node_id is NULL for the
-- classic (non-stage-graph) path and equals tournament_stages.node_id for a
-- stage-graph round. Status automaton per round:
--   published -> call -> running -> awaiting_results -> completed
-- Restzeit formula (server == client):
--   effective_elapsed = (now - starts_at) - paused_accum_seconds
--                       - (paused_at IS NOT NULL ? (now - paused_at) : 0)
--   remaining         = match_seconds - effective_elapsed   -- <0 => expired
-- starts_at = published_at + break_seconds   (call/pause window before play)
-- ends_at   = starts_at    + match_seconds   (nominal match duration)
--
-- K5: the "tournament-wide pause" lives ON the schedule row (paused_at /
-- paused_accum_seconds). tournaments.paused_at does NOT exist; the uhr formula
-- reads exactly ONE source (the schedule row). Writes to those two columns
-- land later via the B2 pause/resume RPCs and the E cron tick; A only
-- reads/renders them and seeds them to their identity defaults (NULL / 0).
--
-- ============================ CDC (ADR-0029) =============================
-- The live runner subscribes to one per-tournament CDC channel
-- tournament_round_schedule:tournament_id=<id>. The table is added to the
-- (NOT "FOR ALL TABLES") supabase_realtime publication so Postgres emits
-- row-level change events. REPLICA IDENTITY stays DEFAULT ('d'): the consumer
-- only needs the NEW row to trigger a refresh and never inspects the OLD row,
-- so REPLICA IDENTITY FULL is deliberately NOT set. The SELECT policy gates on
-- the CDC filter column tournament_id and mirrors tournament_matches_read
-- (non-draft OR own draft); an optional anon policy mirrors
-- tournament_matches_anon_public_read (OE-3, public live view). There is NO
-- client write policy: every write goes through SECURITY-DEFINER RPCs.
--
-- ============================ DEPENDENCIES ===============================
-- Requires (all earlier on disk):
--   * public.tournaments(id, status, created_by, public) — 20260525000001 +
--       20260701000002 (public flag).
--   * tournament_matches_read predicate — 20260525000001 (l.206-214); the
--       anon predicate — 20260701000002 (l.51-69). Mirrored verbatim below.
--   * tournament_matches.stage_node_id is text (20261224000000) and
--       tournament_stages.node_id is text (20261223000000) — so stage_node_id
--       here is text for type parity.

-- ====================================================================
-- 1. Table.
-- ====================================================================

CREATE TABLE IF NOT EXISTS public.tournament_round_schedule (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id           uuid NOT NULL
    REFERENCES public.tournaments(id) ON DELETE CASCADE,
  -- NULL = classic (non-stage-graph) path; otherwise tournament_stages.node_id.
  stage_node_id           text NULL,
  round_number            smallint NOT NULL,
  -- Derived phase label of the round: 'group' (prelim/pool/swiss group round),
  -- 'ko' (knockout round), 'final' (the final). Free text on purpose — the
  -- materialiser sets it; no CHECK so future phases stay additive.
  phase                   text NOT NULL,
  status                  text NOT NULL DEFAULT 'published'
    CHECK (status IN (
      'published',
      'call',
      'running',
      'awaiting_results',
      'completed'
    )),
  published_at            timestamptz NOT NULL DEFAULT now(),
  -- starts_at = published_at + break_seconds; ends_at = starts_at + match_seconds.
  starts_at               timestamptz NOT NULL,
  ends_at                 timestamptz NOT NULL,
  break_seconds           int NOT NULL DEFAULT 0
    CHECK (break_seconds >= 0),
  match_seconds           int NOT NULL DEFAULT 0
    CHECK (match_seconds >= 0),
  -- NULL when the phase has no tiebreak window configured.
  tiebreak_after_seconds  int NULL
    CHECK (tiebreak_after_seconds IS NULL OR tiebreak_after_seconds >= 0),
  -- K5: tournament-wide pause anchor + accumulated frozen seconds. Written by
  -- B2/E; A seeds them to NULL / 0 and only reads them for the uhr formula.
  paused_at               timestamptz NULL,
  paused_accum_seconds    int NOT NULL DEFAULT 0
    CHECK (paused_accum_seconds >= 0),
  created_at              timestamptz NOT NULL DEFAULT now(),
  -- One schedule row per (tournament, round, stage). For the classic path
  -- (stage_node_id IS NULL) NULLs do not collide in a UNIQUE constraint, so a
  -- partial unique index below covers that path explicitly.
  CONSTRAINT tournament_round_schedule_uq
    UNIQUE (tournament_id, round_number, stage_node_id)
);

-- Classic-path uniqueness: a plain UNIQUE over (.., stage_node_id) does NOT
-- dedupe rows where stage_node_id IS NULL (NULLs are distinct), so guard the
-- classic path with a partial unique index.
CREATE UNIQUE INDEX IF NOT EXISTS tournament_round_schedule_classic_uq
  ON public.tournament_round_schedule (tournament_id, round_number)
  WHERE stage_node_id IS NULL;

-- CDC filter-column index (subscriptions filter on tournament_id).
CREATE INDEX IF NOT EXISTS tournament_round_schedule_tournament_idx
  ON public.tournament_round_schedule (tournament_id);


-- ====================================================================
-- 2. RLS — SELECT only; all writes go through SECURITY-DEFINER RPCs.
-- ====================================================================

ALTER TABLE public.tournament_round_schedule ENABLE ROW LEVEL SECURITY;

-- Mirrors tournament_matches_read (20260525000001 l.206-214): gate on the CDC
-- filter column tournament_id — visible when the tournament is non-draft, or
-- it is the caller's own draft.
CREATE POLICY tournament_round_schedule_read
  ON public.tournament_round_schedule FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tournaments t
      WHERE t.id = tournament_round_schedule.tournament_id
        AND (t.status <> 'draft' OR t.created_by = auth.uid())
    )
  );

-- OE-3: public anon live view. Mirrors tournament_matches_anon_public_read
-- (20260701000002 l.51-69) — same public + visible-status gate on
-- tournament_id, so the anon CDC stream is authorised identically.
CREATE POLICY tournament_round_schedule_anon_public_read
  ON public.tournament_round_schedule
  FOR SELECT
  TO anon
  USING (
    EXISTS (
      SELECT 1
        FROM public.tournaments t
       WHERE t.id = tournament_round_schedule.tournament_id
         AND t.public = true
         AND t.status IN (
           'published',
           'registration_open',
           'registration_closed',
           'live',
           'finalized'
         )
    )
  );


-- ====================================================================
-- 3. CDC publication membership (REPLICA IDENTITY stays DEFAULT).
-- ====================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_round_schedule;


-- ====================================================================
-- 4. Central upsert helper.
--
-- Idempotent materialisation of ONE round's schedule row. starts_at/ends_at
-- are derived from published_at via make_interval. For the non-NULL
-- stage_node_id path the table UNIQUE constraint backs ON CONFLICT DO NOTHING.
-- For the NULL (classic) path ON CONFLICT cannot target the partial unique
-- index by column list, so an explicit existence guard provides idempotency
-- there. No new config fields are introduced (E2 locked) — callers pass the
-- already-derived seconds.
-- ====================================================================

CREATE OR REPLACE FUNCTION public._tournament_upsert_round_schedule(
  p_tournament_id   uuid,
  p_stage_node_id   text,
  p_round_number    int,
  p_phase           text,
  p_match_seconds   int,
  p_break_seconds   int,
  p_tiebreak_after  int,
  p_published_at    timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match  int := greatest(0, coalesce(p_match_seconds, 0));
  v_break  int := greatest(0, coalesce(p_break_seconds, 0));
  v_pub    timestamptz := coalesce(p_published_at, now());
  v_starts timestamptz := coalesce(p_published_at, now())
                          + make_interval(secs => greatest(0, coalesce(p_break_seconds, 0)));
BEGIN
  IF p_stage_node_id IS NULL THEN
    -- Classic path: the partial unique index does not back ON CONFLICT, so
    -- guard explicitly. Another concurrent insert is serialised by the index
    -- (a duplicate would raise unique_violation, caught as a no-op).
    IF EXISTS (
      SELECT 1 FROM public.tournament_round_schedule s
       WHERE s.tournament_id = p_tournament_id
         AND s.round_number  = p_round_number::smallint
         AND s.stage_node_id IS NULL
    ) THEN
      RETURN;
    END IF;

    BEGIN
      INSERT INTO public.tournament_round_schedule(
          tournament_id, stage_node_id, round_number, phase, status,
          published_at, starts_at, ends_at,
          break_seconds, match_seconds, tiebreak_after_seconds)
        VALUES (
          p_tournament_id, NULL, p_round_number::smallint, p_phase, 'published',
          v_pub,
          v_starts,
          v_starts + make_interval(secs => v_match),
          v_break, v_match, p_tiebreak_after);
    EXCEPTION WHEN unique_violation THEN
      -- Concurrent insert won the race; the row exists — idempotent no-op.
      NULL;
    END;
  ELSE
    -- Stage path: the UNIQUE (tournament_id, round_number, stage_node_id)
    -- constraint backs ON CONFLICT DO NOTHING.
    INSERT INTO public.tournament_round_schedule(
        tournament_id, stage_node_id, round_number, phase, status,
        published_at, starts_at, ends_at,
        break_seconds, match_seconds, tiebreak_after_seconds)
      VALUES (
        p_tournament_id, p_stage_node_id, p_round_number::smallint, p_phase, 'published',
        v_pub,
        v_starts,
        v_starts + make_interval(secs => v_match),
        v_break, v_match, p_tiebreak_after)
      ON CONFLICT (tournament_id, round_number, stage_node_id) DO NOTHING;
  END IF;
END;
$$;

COMMENT ON FUNCTION public._tournament_upsert_round_schedule(
  uuid, text, int, text, int, int, int, timestamptz) IS
  'ADR-0031 Block A1: idempotent per-round schedule materialiser. Derives '
  'starts_at = published_at + break_seconds and ends_at = starts_at + '
  'match_seconds via make_interval. ON CONFLICT DO NOTHING for the non-NULL '
  'stage_node_id path; explicit existence guard (+ unique_violation no-op) for '
  'the classic stage_node_id IS NULL path (partial index). SECURITY DEFINER; '
  'all schedule writes flow through this helper, never the client.';


-- ====================================================================
-- 5. Config-derivation helpers (keep no new config fields — E2 locked).
--
-- These wrap the per-phase JSON reads so each materialisation RPC body needs
-- exactly ONE new line (the PERFORM _tournament_upsert_round_schedule call)
-- with the seconds derived inline — no new DECLARE/SELECT in the RPC bodies
-- (K3 stale-body discipline: the only change vs the on-disk source is that
-- single PERFORM line). Both helpers read tournaments and are STABLE.
-- ====================================================================

-- Prelim / classic / stage round: match (round) time + break, mirroring the
-- client precedence in tournament_stammdaten_card.dart and
-- _tournament_round_time_suffix (20261242000000): round_time_seconds, then
-- the time_limit_seconds alias. break_between_matches_seconds is the call/
-- pause window. OE-6: stage rounds share this prelim match_format time source
-- (tournament_stages.config carries NO timing keys — verified before build).
CREATE OR REPLACE FUNCTION public._tournament_schedule_prelim_seconds(
  p_tournament_id uuid,
  OUT match_seconds int,
  OUT break_seconds int
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fmt jsonb;
BEGIN
  SELECT match_format INTO v_fmt
    FROM public.tournaments WHERE id = p_tournament_id;

  IF v_fmt IS NULL OR jsonb_typeof(v_fmt) <> 'object' THEN
    match_seconds := 0;
    break_seconds := 0;
    RETURN;
  END IF;

  match_seconds := greatest(0, coalesce(
    (v_fmt ->> 'round_time_seconds')::int,
    (v_fmt ->> 'time_limit_seconds')::int,
    0));
  break_seconds := greatest(0, coalesce(
    (v_fmt ->> 'break_between_matches_seconds')::int, 0));
END;
$$;

COMMENT ON FUNCTION public._tournament_schedule_prelim_seconds(uuid) IS
  'ADR-0031 Block A1: prelim/classic/stage round time source. match_seconds '
  'from match_format.round_time_seconds (alias time_limit_seconds); '
  'break_seconds from match_format.break_between_matches_seconds. No new '
  'config fields.';

-- KO / final round N (1-based): per-round formats from ko_round_formats[N-1]
-- with fallback to ko_match_format, then match_format. final_no_tiebreak
-- suppresses the tiebreak window on the final round. round_time_seconds /
-- time_limit_seconds alias precedence as above.
CREATE OR REPLACE FUNCTION public._tournament_schedule_ko_seconds(
  p_tournament_id  uuid,
  p_round_number   int,
  p_is_final       boolean,
  OUT match_seconds   int,
  OUT break_seconds   int,
  OUT tiebreak_after  int
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ko_formats jsonb;
  v_ko_fmt     jsonb;
  v_match_fmt  jsonb;
  v_fmt        jsonb;
  v_round_fmt  jsonb;
BEGIN
  SELECT ko_round_formats, ko_match_format, match_format
    INTO v_ko_formats, v_ko_fmt, v_match_fmt
    FROM public.tournaments WHERE id = p_tournament_id;

  -- Per-round element (index N-1) wins; else ko_match_format; else match_format.
  v_round_fmt := NULL;
  IF v_ko_formats IS NOT NULL
     AND jsonb_typeof(v_ko_formats) = 'array'
     AND jsonb_array_length(v_ko_formats) >= p_round_number THEN
    v_round_fmt := v_ko_formats -> (p_round_number - 1);
  END IF;

  IF v_round_fmt IS NOT NULL AND jsonb_typeof(v_round_fmt) = 'object' THEN
    v_fmt := v_round_fmt;
  ELSIF v_ko_fmt IS NOT NULL AND jsonb_typeof(v_ko_fmt) = 'object' THEN
    v_fmt := v_ko_fmt;
  ELSE
    v_fmt := v_match_fmt;
  END IF;

  IF v_fmt IS NULL OR jsonb_typeof(v_fmt) <> 'object' THEN
    match_seconds  := 0;
    break_seconds  := 0;
    tiebreak_after := NULL;
    RETURN;
  END IF;

  match_seconds := greatest(0, coalesce(
    (v_fmt ->> 'round_time_seconds')::int,
    (v_fmt ->> 'time_limit_seconds')::int,
    0));
  break_seconds := greatest(0, coalesce(
    (v_fmt ->> 'break_between_matches_seconds')::int, 0));

  -- final_no_tiebreak suppresses the tiebreak window on the final round.
  IF p_is_final AND coalesce((v_fmt ->> 'final_no_tiebreak')::boolean, false) THEN
    tiebreak_after := NULL;
  ELSE
    tiebreak_after := (v_fmt ->> 'tiebreak_after_seconds')::int;
  END IF;
END;
$$;

COMMENT ON FUNCTION public._tournament_schedule_ko_seconds(uuid, int, boolean) IS
  'ADR-0031 Block A1: KO/final round time source. Reads ko_round_formats[N-1] '
  '(fallback ko_match_format, then match_format) for match/break/tiebreak '
  'seconds; final_no_tiebreak drops the tiebreak window on the final. No new '
  'config fields.';
