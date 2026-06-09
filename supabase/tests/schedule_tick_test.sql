-- ADR-0031 Block E2 — tournament_schedule_tick(p_now) pgTAP suite.
--
-- tournament_schedule_tick is the pg_cron pure-time driver of the round-clock
-- automaton. Every assertion injects a FIXED p_now (K7: pgTAP freezes now()
-- inside the transaction, so the tick MUST take p_now explicitly). The 11 cases:
--   (1)  published -> running                 (starts_at <= p_now)
--   (2)  call -> running                      (starts_at <= p_now)
--   (3)  all-terminal -> completed            (ends_at <= p_now, all matches terminal)
--   (4)  missing result -> awaiting_results   (ends_at <= p_now, NO auto-forfait)
--   (5)  awaiting_results -> completed        (last result entered, all terminal)
--   (6)  idempotency                          (re-tick with same p_now returns 0)
--   (7)  late tick                            (long-overdue boundaries still flip)
--   (8)  pause guard                          (paused_at set on the row => no flip)
--   (9)  fault tolerance                      (a broken tournament does not block others)
--   (10) NULL path                            (classic round, stage_node_id IS NULL)
--   (11) stage path                           (stage_node_id NOT NULL)
--
-- pgTAP is installed transiently inside BEGIN..ROLLBACK; everything rolls back,
-- nothing is mutated. Fixtures run as postgres (SECURITY DEFINER call path +
-- direct seeding of schedule/matches rows, which have no client-write policy).

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(14);

SELECT has_function('public', 'tournament_schedule_tick',
  ARRAY['timestamptz'],
  'tournament_schedule_tick(timestamptz) exists');

-- SECURITY DEFINER + empty search_path, straight from the catalog. proconfig
-- stores the empty search_path as the literal text search_path="".
SELECT is(
  (SELECT p.prosecdef::text || '/' || coalesce(
            (SELECT cfg FROM unnest(p.proconfig) cfg WHERE cfg LIKE 'search_path=%'),
            'search_path=<unset>')
     FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname = 'tournament_schedule_tick'),
  'true/search_path=""',
  'tournament_schedule_tick is SECURITY DEFINER with empty search_path');

SET LOCAL ROLE postgres;

-- ====================================================================
-- Fixture: one organiser + several live tournaments. Frozen test clock:
--   p_now := '2026-06-09 12:00:00+00'
-- Schedule rows are seeded directly with hand-picked starts_at/ends_at so each
-- case exercises exactly one boundary. Matches are INSERTed already-terminal /
-- already-open (the stage-runner trigger is AFTER UPDATE only, so a direct
-- INSERT of a terminal match never fires it — E2 stays isolated).
-- ====================================================================

DO $fixture$
DECLARE
  v_org uuid := gen_random_uuid();
  -- one tournament per scenario so advisory locks / subtransactions never blur
  v_t1  uuid := '10000000-0000-0000-0000-000000000001'; -- published -> running
  v_t2  uuid := '10000000-0000-0000-0000-000000000002'; -- call -> running
  v_t3  uuid := '10000000-0000-0000-0000-000000000003'; -- all-terminal -> completed (NULL path)
  v_t4  uuid := '10000000-0000-0000-0000-000000000004'; -- missing -> awaiting_results
  v_t5  uuid := '10000000-0000-0000-0000-000000000005'; -- awaiting -> completed
  v_t6  uuid := '10000000-0000-0000-0000-000000000006'; -- idempotency
  v_t7  uuid := '10000000-0000-0000-0000-000000000007'; -- late tick
  v_t8  uuid := '10000000-0000-0000-0000-000000000008'; -- pause guard
  v_t9  uuid := '10000000-0000-0000-0000-000000000009'; -- stage path
  v_tb  uuid := '10000000-0000-0000-0000-00000000000b'; -- broken tournament (fault tolerance)
  v_tc  uuid := '10000000-0000-0000-0000-00000000000c'; -- healthy sibling (fault tolerance)
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (v_org, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'org-' || v_org::text || '@t.l', '', now(), now(), now());

  -- display_name has a case-insensitive UNIQUE index, so suffix each with its id.
  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
  SELECT id, v_org, 'Tick-Fixture-' || id::text, 1, 2, 16, 'swiss', 'ekc',
         '{}'::jsonb, 'live', true
    FROM unnest(ARRAY[v_t1, v_t2, v_t3, v_t4, v_t5, v_t6, v_t7, v_t8, v_t9, v_tb, v_tc]) AS id;

  -- ---- helper seed: schedule row -------------------------------------------
  -- (inlined below per case to keep starts_at/ends_at explicit)

  -- (1) T1 classic published, started in the past, ends in the future -> running
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_t1, NULL, 1, 'group', 'published',
            '2026-06-09 11:00:00+00', '2026-06-09 11:55:00+00',
            '2026-06-09 12:30:00+00', 0, 2100);

  -- (2) T2 classic call, started in the past -> running
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_t2, NULL, 1, 'group', 'call',
            '2026-06-09 11:00:00+00', '2026-06-09 11:55:00+00',
            '2026-06-09 12:30:00+00', 0, 2100);

  -- (3)+(10) T3 classic running, ended in the past, ALL matches terminal -> completed
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_t3, NULL, 1, 'group', 'running',
            '2026-06-09 10:00:00+00', '2026-06-09 10:30:00+00',
            '2026-06-09 11:30:00+00', 0, 3600);
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round, status)
    VALUES (v_t3, 1, 1, 'finalized'),
           (v_t3, 1, 2, 'overridden');

  -- (4) T4 classic running, ended in the past, one match still open -> awaiting_results
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_t4, NULL, 1, 'group', 'running',
            '2026-06-09 10:00:00+00', '2026-06-09 10:30:00+00',
            '2026-06-09 11:30:00+00', 0, 3600);
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round, status)
    VALUES (v_t4, 1, 1, 'finalized'),
           (v_t4, 1, 2, 'scheduled');   -- open => no completion, NO forfait

  -- (5) T5 classic awaiting_results, ended in the past, now ALL terminal -> completed
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_t5, NULL, 1, 'group', 'awaiting_results',
            '2026-06-09 10:00:00+00', '2026-06-09 10:30:00+00',
            '2026-06-09 11:30:00+00', 0, 3600);
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round, status)
    VALUES (v_t5, 1, 1, 'finalized'),
           (v_t5, 1, 2, 'voided');

  -- (6) T6 classic published -> running, used SOLELY for the idempotency re-tick.
  -- Kept independent from the fault-tolerance sibling (Tc) so a future edit to
  -- case (9) cannot silently weaken the idempotency assertion.
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_t6, NULL, 1, 'group', 'published',
            '2026-06-09 11:00:00+00', '2026-06-09 11:55:00+00',
            '2026-06-09 12:30:00+00', 0, 2100);

  -- (7) T7 classic published, starts_at LONG overdue (hours in the past) but the
  -- round is still within its match window (ends_at in the future) -> running.
  -- Proves a late/delayed tick still performs the overdue start transition.
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_t7, NULL, 1, 'group', 'published',
            '2026-06-09 06:00:00+00', '2026-06-09 06:05:00+00',
            '2026-06-09 18:00:00+00', 0, 43200);

  -- (8) T8 classic published, started in the past, but PAUSED -> NO flip (K5)
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds,
      paused_at)
    VALUES (v_t8, NULL, 1, 'group', 'published',
            '2026-06-09 11:00:00+00', '2026-06-09 11:55:00+00',
            '2026-06-09 12:30:00+00', 0, 2100,
            '2026-06-09 11:58:00+00');

  -- (11) T9 STAGE path running, ended in the past, all stage matches terminal -> completed.
  -- A tournament_stages row backs the composite FK (tournament_id, stage_node_id)
  -- on the seeded stage match.
  INSERT INTO public.tournament_stages(tournament_id, node_id, type, status)
    VALUES (v_t9, 'nodeA', 'pool', 'active');
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_t9, 'nodeA', 1, 'group', 'running',
            '2026-06-09 10:00:00+00', '2026-06-09 10:30:00+00',
            '2026-06-09 11:30:00+00', 0, 3600);
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round, status, stage_node_id)
    VALUES (v_t9, 1, 1, 'finalized', 'nodeA');

  -- (9) Tb is the BROKEN tournament for the fault-tolerance case. It is seeded
  -- as a normal due 'published' row; the poison BEFORE-UPDATE trigger added
  -- after this fixture makes its status flip RAISE, so its per-tournament
  -- subtransaction rolls back while every other tournament still transitions.
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_tb, NULL, 1, 'group', 'published',
            '2026-06-09 11:00:00+00', '2026-06-09 11:55:00+00',
            '2026-06-09 12:30:00+00', 0, 2100);

  -- (9) Tc is the HEALTHY sibling for the fault-tolerance case: a normal due
  -- 'published' row that MUST still flip to 'running' in the same tick that
  -- rolls back the poisoned Tb. Dedicated (not the idempotency T6) so cases (6)
  -- and (9) are fully independent.
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_tc, NULL, 1, 'group', 'published',
            '2026-06-09 11:00:00+00', '2026-06-09 11:55:00+00',
            '2026-06-09 12:30:00+00', 0, 2100);
END;
$fixture$;

-- ====================================================================
-- Fault-tolerance fixture (case 9): a tournament whose per-tournament
-- subtransaction is GUARANTEED to raise, proving it does not block the others.
-- We attach a row-level BEFORE trigger to tournament_round_schedule that raises
-- whenever the poisoned tournament's row is UPDATEd (the tick's status flip).
-- A normal tournament (e.g. T1) MUST still flip in the same tick.
-- ====================================================================
CREATE OR REPLACE FUNCTION public._tick_test_poison()
RETURNS trigger LANGUAGE plpgsql AS $poison$
BEGIN
  IF NEW.tournament_id = '10000000-0000-0000-0000-00000000000b'::uuid THEN
    RAISE EXCEPTION 'poisoned tournament % (test)', NEW.tournament_id;
  END IF;
  RETURN NEW;
END;
$poison$;

CREATE TRIGGER _tick_test_poison_trg
  BEFORE UPDATE ON public.tournament_round_schedule
  FOR EACH ROW EXECUTE FUNCTION public._tick_test_poison();

-- ====================================================================
-- THE TICK. Single injected instant; one call drives all due rows.
-- ====================================================================
SELECT public.tournament_schedule_tick('2026-06-09 12:00:00+00'::timestamptz)
  AS first_tick \gset

-- ---- (1) published -> running ----
SELECT is(
  (SELECT status FROM public.tournament_round_schedule
    WHERE tournament_id='10000000-0000-0000-0000-000000000001' AND round_number=1),
  'running',
  '(1) published & starts_at<=p_now -> running');

-- ---- (2) call -> running ----
SELECT is(
  (SELECT status FROM public.tournament_round_schedule
    WHERE tournament_id='10000000-0000-0000-0000-000000000002' AND round_number=1),
  'running',
  '(2) call & starts_at<=p_now -> running');

-- ---- (3)+(10) all-terminal classic (NULL path) -> completed ----
SELECT is(
  (SELECT status FROM public.tournament_round_schedule
    WHERE tournament_id='10000000-0000-0000-0000-000000000003' AND round_number=1),
  'completed',
  '(3)/(10) running, all matches terminal, NULL stage path -> completed');

-- ---- (4) missing result -> awaiting_results (NO forfait) ----
SELECT is(
  (SELECT status FROM public.tournament_round_schedule
    WHERE tournament_id='10000000-0000-0000-0000-000000000004' AND round_number=1),
  'awaiting_results',
  '(4) running, a match still open at ends_at -> awaiting_results (no auto-forfait)');
-- the open match is untouched (no forfait write)
SELECT is(
  (SELECT status FROM public.tournament_matches
    WHERE tournament_id='10000000-0000-0000-0000-000000000004'
      AND match_number_in_round=2),
  'scheduled',
  '(4) the open match stays scheduled (E2 writes no result/forfait)');

-- ---- (5) awaiting_results, now all terminal -> completed ----
SELECT is(
  (SELECT status FROM public.tournament_round_schedule
    WHERE tournament_id='10000000-0000-0000-0000-000000000005' AND round_number=1),
  'completed',
  '(5) awaiting_results, all matches terminal -> completed');

-- ---- (7) late tick: long-overdue published still flips -> running ----
SELECT is(
  (SELECT status FROM public.tournament_round_schedule
    WHERE tournament_id='10000000-0000-0000-0000-000000000007' AND round_number=1),
  'running',
  '(7) long-overdue boundaries still transition (late tick)');

-- ---- (8) pause guard: paused row does NOT flip (K5: s.paused_at) ----
SELECT is(
  (SELECT status FROM public.tournament_round_schedule
    WHERE tournament_id='10000000-0000-0000-0000-000000000008' AND round_number=1),
  'published',
  '(8) paused_at set on the schedule row => no flip (K5 pause guard)');

-- ---- (11) stage path running, all stage matches terminal -> completed ----
SELECT is(
  (SELECT status FROM public.tournament_round_schedule
    WHERE tournament_id='10000000-0000-0000-0000-000000000009'
      AND stage_node_id='nodeA' AND round_number=1),
  'completed',
  '(11) stage_node_id NOT NULL path: all stage matches terminal -> completed');

-- ---- (9) fault tolerance: poisoned tournament raised, others still flipped ----
-- T1 flipped (asserted in case 1) DESPITE the poisoned Tb in the same tick.
SELECT is(
  (SELECT status FROM public.tournament_round_schedule
    WHERE tournament_id='10000000-0000-0000-0000-00000000000b' AND round_number=1),
  'published',
  '(9) poisoned tournament stayed unchanged (its subtx rolled back)');
-- and its dedicated healthy sibling Tc (published, due) DID flip in the same tick.
SELECT is(
  (SELECT status FROM public.tournament_round_schedule
    WHERE tournament_id='10000000-0000-0000-0000-00000000000c' AND round_number=1),
  'running',
  '(9) a healthy tournament still transitioned in the same tick (fault isolation)');

-- ---- (6) idempotency: re-tick with the SAME p_now applies nothing -> 0 ----
SELECT is(
  public.tournament_schedule_tick('2026-06-09 12:00:00+00'::timestamptz),
  0,
  '(6) re-tick with identical p_now performs 0 transitions (idempotent)');

SELECT * FROM finish();
ROLLBACK;
