-- ADR-0031 Block A1 — tournament_round_schedule pgTAP suite.
--
-- Covers (A1-DoD-12):
--   * has_table + required columns/types
--   * status CHECK = exactly {published, call, running, awaiting_results, completed}
--   * paused_at / paused_accum_seconds present (K5)
--   * CDC publication membership (pg_publication_tables), REPLICA IDENTITY DEFAULT
--   * RLS SELECT-policy filter-column parity on tournament_id
--   * derivation fixture: match_format 1800/300 -> one row, starts_at/ends_at
--     match published_at + break and starts_at + match
--   * idempotency: a second helper call inserts no duplicate (NULL + non-NULL paths)
--   * KO with 2 rounds via the ko helper + upsert -> 2 rows
--
-- pgTAP is installed transiently inside the BEGIN..ROLLBACK (see
-- realtime_cdc_rls_test.sql note); everything rolls back, nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(34);

-- ---- 1. table + columns ----
SELECT has_table('public', 'tournament_round_schedule', 'table exists');
SELECT has_column('public', 'tournament_round_schedule', 'tournament_id', 'tournament_id col');
SELECT has_column('public', 'tournament_round_schedule', 'stage_node_id', 'stage_node_id col');
SELECT has_column('public', 'tournament_round_schedule', 'round_number', 'round_number col');
SELECT has_column('public', 'tournament_round_schedule', 'phase', 'phase col');
SELECT has_column('public', 'tournament_round_schedule', 'status', 'status col');
SELECT has_column('public', 'tournament_round_schedule', 'published_at', 'published_at col');
SELECT has_column('public', 'tournament_round_schedule', 'starts_at', 'starts_at col');
SELECT has_column('public', 'tournament_round_schedule', 'ends_at', 'ends_at col');
SELECT has_column('public', 'tournament_round_schedule', 'break_seconds', 'break_seconds col');
SELECT has_column('public', 'tournament_round_schedule', 'match_seconds', 'match_seconds col');
SELECT has_column('public', 'tournament_round_schedule', 'tiebreak_after_seconds', 'tiebreak_after_seconds col');
SELECT has_column('public', 'tournament_round_schedule', 'paused_at', 'paused_at col (K5)');
SELECT has_column('public', 'tournament_round_schedule', 'paused_accum_seconds', 'paused_accum_seconds col (K5)');
SELECT col_type_is('public', 'tournament_round_schedule', 'stage_node_id', 'text',
  'stage_node_id is text (type parity with tournament_matches.stage_node_id)');

-- ---- 2. status CHECK = exactly the 5 round states ----
SELECT is(
  (SELECT pg_get_constraintdef(oid)
     FROM pg_constraint
    WHERE conrelid = 'public.tournament_round_schedule'::regclass
      AND contype = 'c'
      AND conname = 'tournament_round_schedule_status_check'),
  $$CHECK ((status = ANY (ARRAY['published'::text, 'call'::text, 'running'::text, 'awaiting_results'::text, 'completed'::text])))$$,
  'status CHECK lists exactly published/call/running/awaiting_results/completed'
);

-- ---- 3. CDC: publication membership + REPLICA IDENTITY DEFAULT ----
SELECT ok(
  EXISTS (SELECT 1 FROM pg_publication_tables
           WHERE pubname='supabase_realtime'
             AND schemaname='public'
             AND tablename='tournament_round_schedule'),
  'tournament_round_schedule is a member of supabase_realtime (CDC)'
);
SELECT is(
  (SELECT relreplident FROM pg_class WHERE oid='public.tournament_round_schedule'::regclass),
  'd'::"char",
  'REPLICA IDENTITY is DEFAULT (NEW-only consumer, never FULL)'
);

-- ---- 4. RLS SELECT policy gates on the CDC filter column tournament_id ----
SELECT ok(
  (SELECT relrowsecurity FROM pg_class WHERE oid='public.tournament_round_schedule'::regclass),
  'RLS is enabled'
);
SELECT policy_cmd_is(
  'public', 'tournament_round_schedule', 'tournament_round_schedule_read', 'SELECT',
  'tournament_round_schedule_read is a SELECT policy'
);
SELECT ok(
  (SELECT qual FROM pg_policies
    WHERE schemaname='public' AND tablename='tournament_round_schedule'
      AND policyname='tournament_round_schedule_read') LIKE '%tournament_id%',
  'tournament_round_schedule_read USING references tournament_id (CDC filter parity)'
);
-- No client write policy (all writes via SECURITY DEFINER RPC).
SELECT is(
  (SELECT count(*)::int FROM pg_policies
    WHERE schemaname='public' AND tablename='tournament_round_schedule'
      AND cmd IN ('INSERT','UPDATE','DELETE','ALL')),
  0,
  'no INSERT/UPDATE/DELETE/ALL policy exists (writes only via RPC)'
);

-- ====================================================================
-- Fixture: an organiser + a tournament with match_format 1800/300 and a
-- two-round KO format. Drives the upsert + derivation helpers directly.
-- ====================================================================
SET LOCAL ROLE postgres;

DO $fixture$
DECLARE
  v_org uuid := gen_random_uuid();
  v_tid uuid := '11111111-1111-1111-1111-111111111111';
  v_kid uuid := '22222222-2222-2222-2222-222222222222';
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (v_org, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'org-' || v_org::text || '@t.l', '', now(), now(), now());

  -- Prelim/derivation tournament: match_format 1800/300.
  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (
      v_tid, v_org, 'Sched-Fixture', 1, 2, 16, 'swiss', 'ekc',
      jsonb_build_object('round_time_seconds', 1800,
                         'break_between_matches_seconds', 300),
      'live', true);

  -- Separate KO tournament with a two-round ko_round_formats array so the
  -- KO rounds do not collide with the classic group round 1 above.
  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public,
      ko_round_formats)
    VALUES (
      v_kid, v_org, 'Sched-KO-Fixture', 1, 2, 16, 'swiss', 'ekc',
      jsonb_build_object('round_time_seconds', 1800,
                         'break_between_matches_seconds', 300),
      'live', true,
      jsonb_build_array(
        jsonb_build_object('time_limit_seconds', 900,
                           'break_between_matches_seconds', 120,
                           'tiebreak_after_seconds', 60),
        jsonb_build_object('time_limit_seconds', 1200,
                           'break_between_matches_seconds', 180,
                           'tiebreak_after_seconds', 90,
                           'final_no_tiebreak', true)));
END;
$fixture$;

-- ---- 5. prelim derivation: match 1800, break 300 ----
SELECT is(
  (public._tournament_schedule_prelim_seconds(
     '11111111-1111-1111-1111-111111111111')).match_seconds,
  1800, 'prelim match_seconds derived from round_time_seconds');
SELECT is(
  (public._tournament_schedule_prelim_seconds(
     '11111111-1111-1111-1111-111111111111')).break_seconds,
  300, 'prelim break_seconds derived from break_between_matches_seconds');

-- ---- 6. classic upsert: one row, starts/ends derived ----
SELECT public._tournament_upsert_round_schedule(
  '11111111-1111-1111-1111-111111111111', NULL, 1, 'group',
  1800, 300, NULL, '2026-06-09 10:00:00+00'::timestamptz);

SELECT is(
  (SELECT count(*)::int FROM public.tournament_round_schedule
     WHERE tournament_id='11111111-1111-1111-1111-111111111111'
       AND stage_node_id IS NULL),
  1, 'classic upsert created exactly one row');
SELECT is(
  (SELECT starts_at FROM public.tournament_round_schedule
     WHERE tournament_id='11111111-1111-1111-1111-111111111111'
       AND stage_node_id IS NULL AND round_number=1),
  '2026-06-09 10:05:00+00'::timestamptz,
  'starts_at = published_at + break_seconds (10:00 + 300s)');
SELECT is(
  (SELECT ends_at FROM public.tournament_round_schedule
     WHERE tournament_id='11111111-1111-1111-1111-111111111111'
       AND stage_node_id IS NULL AND round_number=1),
  '2026-06-09 10:35:00+00'::timestamptz,
  'ends_at = starts_at + match_seconds (10:05 + 1800s)');

-- ---- 7. idempotency, NULL path: second identical call -> no duplicate ----
SELECT public._tournament_upsert_round_schedule(
  '11111111-1111-1111-1111-111111111111', NULL, 1, 'group',
  1800, 300, NULL, '2026-06-09 12:00:00+00'::timestamptz);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_round_schedule
     WHERE tournament_id='11111111-1111-1111-1111-111111111111'
       AND stage_node_id IS NULL AND round_number=1),
  1, 'NULL-path upsert is idempotent (no duplicate, original kept)');

-- ---- 8. idempotency, non-NULL stage path ----
SELECT public._tournament_upsert_round_schedule(
  '11111111-1111-1111-1111-111111111111', 'nodeA', 1, 'group',
  1800, 300, NULL, '2026-06-09 10:00:00+00'::timestamptz);
SELECT public._tournament_upsert_round_schedule(
  '11111111-1111-1111-1111-111111111111', 'nodeA', 1, 'group',
  1800, 300, NULL, '2026-06-09 10:00:00+00'::timestamptz);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_round_schedule
     WHERE tournament_id='11111111-1111-1111-1111-111111111111'
       AND stage_node_id='nodeA'),
  1, 'stage-path upsert is idempotent (ON CONFLICT DO NOTHING)');

-- ---- 9. KO 2 rounds: round1 'ko' (tiebreak 60), round2 'final'
--         (final_no_tiebreak -> NULL) -> 2 rows ----
SELECT public._tournament_upsert_round_schedule(
  '22222222-2222-2222-2222-222222222222', NULL, 1, 'ko',
  (public._tournament_schedule_ko_seconds('22222222-2222-2222-2222-222222222222',1,false)).match_seconds,
  (public._tournament_schedule_ko_seconds('22222222-2222-2222-2222-222222222222',1,false)).break_seconds,
  (public._tournament_schedule_ko_seconds('22222222-2222-2222-2222-222222222222',1,false)).tiebreak_after,
  '2026-06-09 14:00:00+00'::timestamptz);
SELECT public._tournament_upsert_round_schedule(
  '22222222-2222-2222-2222-222222222222', NULL, 2, 'final',
  (public._tournament_schedule_ko_seconds('22222222-2222-2222-2222-222222222222',2,true)).match_seconds,
  (public._tournament_schedule_ko_seconds('22222222-2222-2222-2222-222222222222',2,true)).break_seconds,
  (public._tournament_schedule_ko_seconds('22222222-2222-2222-2222-222222222222',2,true)).tiebreak_after,
  '2026-06-09 15:00:00+00'::timestamptz);

SELECT is(
  (SELECT count(*)::int FROM public.tournament_round_schedule
     WHERE tournament_id='22222222-2222-2222-2222-222222222222'
       AND phase IN ('ko','final')),
  2, 'KO with 2 rounds materialised 2 schedule rows');
SELECT is(
  (SELECT match_seconds FROM public.tournament_round_schedule
     WHERE tournament_id='22222222-2222-2222-2222-222222222222'
       AND phase='ko' AND round_number=1),
  900, 'KO round 1 match_seconds from ko_round_formats[0].time_limit_seconds');
SELECT is(
  (SELECT tiebreak_after_seconds FROM public.tournament_round_schedule
     WHERE tournament_id='22222222-2222-2222-2222-222222222222'
       AND phase='ko' AND round_number=1),
  60, 'KO round 1 tiebreak_after from ko_round_formats[0]');
SELECT is(
  (SELECT match_seconds FROM public.tournament_round_schedule
     WHERE tournament_id='22222222-2222-2222-2222-222222222222'
       AND phase='final' AND round_number=2),
  1200, 'final round match_seconds from ko_round_formats[1].time_limit_seconds');
SELECT ok(
  (SELECT tiebreak_after_seconds FROM public.tournament_round_schedule
     WHERE tournament_id='22222222-2222-2222-2222-222222222222'
       AND phase='final' AND round_number=2) IS NULL,
  'final round tiebreak suppressed by final_no_tiebreak (NULL)');

SELECT * FROM finish();
ROLLBACK;
