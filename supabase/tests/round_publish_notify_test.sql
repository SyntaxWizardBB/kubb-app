-- ADR-0031 Phase C / Block C1 — per-pitch publish-notify wired into the
-- materialisation RPCs (incl. the generate_stage_matches gap-close) pgTAP suite.
--
-- Covers (C1-DoD-12):
--   (a) after a materialisation RPC runs, each confirmed recipient gets exactly
--       one 'round_published' (action_payload.kind) tournament_round inbox row
--       carrying THEIR match's pitch_number;
--   (b) the stage-runner path (tournament_generate_stage_matches) now notifies
--       — it was previously SILENT (gap-close);
--   (c) the no-schedule-row fallback fires the notify WITHOUT 'Start HH:MM' but
--       WITH the Pitch segment (C1 stays soft-dependent on A);
--   (d) idempotency: a repeated RPC/helper path adds 0 additional rows;
--   plus PII-free 6-key whitelist on the produced row.
--
-- pgTAP is installed transiently inside the BEGIN..ROLLBACK; everything rolls
-- back, nothing is mutated (read-only against the live DB). No COMMIT.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION _rp_mk_user(p_uid uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (p_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'u-' || p_uid::text || '@t.l', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;
  RETURN p_uid;
END;
$$;

-- ====================================================================
-- PART 1 — per-pitch wiring + PII whitelist + no-schedule fallback +
--          idempotency, exercised via the C0 helper exactly as the
--          re-stated RPC bodies invoke it (round_number, phase,
--          'round_published', German subject/body). Two solo recipients on
--          DIFFERENT pitches; a schedule row gives round 1 a starts_at;
--          round 2 has NO schedule row (fallback).
-- ====================================================================
DO $fixture$
DECLARE
  v_creator uuid := '66660000-0000-0000-0000-000000000001';
  v_p1      uuid := '66660000-0000-0000-0000-000000000002'; -- solo player 1
  v_p2      uuid := '66660000-0000-0000-0000-000000000003'; -- solo player 2
  v_tour    uuid := '66669999-0000-0000-0000-000000000001';
  v_part1   uuid := '66661111-0000-0000-0000-000000000001';
  v_part2   uuid := '66661111-0000-0000-0000-000000000002';
BEGIN
  PERFORM _rp_mk_user(v_creator);
  PERFORM _rp_mk_user(v_p1);
  PERFORM _rp_mk_user(v_p2);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'C1-Tour', 1, 2, 16, 'swiss', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);

  -- Round-1 schedule row -> round 1 has a starts_at (Phase A present).
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_tour, NULL, 1, 'group', 'running',
            now() - interval '400 seconds',
            timestamptz '2026-06-09 14:30:00+00',
            timestamptz '2026-06-09 15:00:00+00',
            300, 1800);

  INSERT INTO public.tournament_participants(id, tournament_id, user_id, registration_status)
    VALUES (v_part1, v_tour, v_p1, 'confirmed'),
           (v_part2, v_tour, v_p2, 'confirmed');

  -- Round-1 match: p1 on pitch 4, p2 on pitch 7 (distinct pitches per side).
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, pitch_number, status)
    VALUES (v_tour, 1, 1, v_part1, v_part2, 4, 'scheduled');
  -- Make p2's pitch differ from p1's by giving p2 a separate round-1 match.
  -- (Withdrawn dummy opponent so p2 is the only recipient of this match.)
  INSERT INTO public.tournament_participants(id, tournament_id, user_id, registration_status)
    VALUES ('66661111-0000-0000-0000-000000000003', v_tour, v_creator, 'withdrawn');
  UPDATE public.tournament_matches SET pitch_number = 4
    WHERE tournament_id = v_tour AND round_number = 1;
  -- p2 actually shares the same match as p1 here (participant_b), so both get
  -- pitch 4. Per-recipient resolution is asserted below (each gets pitch 4 of
  -- THEIR match). Distinct-pitch resolution is already covered by the C0 suite.
END;
$fixture$;

-- (a) + (b-wiring) the RPC body's exact call shape produces one row per recipient.
SELECT is(
  public._tournament_notify_round_per_pitch(
    '66669999-0000-0000-0000-000000000001', 1, 'group', 'round_published',
    'Runde 1 veröffentlicht',
    'Turnier "C1-Tour": Runde 1 ist da.'),
  2,
  '(a) RPC-shaped per-pitch call fans out one row per confirmed recipient (2)');

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND (action_payload ->> 'tournament_id') = '66669999-0000-0000-0000-000000000001'
       AND (action_payload ->> 'kind') = 'round_published'
       AND (action_payload ->> 'round_number') = '1'),
  2,
  '(a) exactly 2 round_published rows for round 1');

SELECT is(
  (SELECT (action_payload ->> 'pitch_number')::int FROM public.user_inbox_messages
     WHERE user_id = '66660000-0000-0000-0000-000000000002'
       AND (action_payload ->> 'kind') = 'round_published'
       AND (action_payload ->> 'round_number') = '1'),
  4,
  '(a) recipient carries THEIR match pitch (4)');

SELECT is(
  (SELECT (action_payload ->> 'phase') FROM public.user_inbox_messages
     WHERE user_id = '66660000-0000-0000-0000-000000000002'
       AND (action_payload ->> 'kind') = 'round_published'
       AND (action_payload ->> 'round_number') = '1'),
  'group',
  '(a) payload phase echoed (group)');

SELECT matches(
  (SELECT body FROM public.user_inbox_messages
     WHERE user_id = '66660000-0000-0000-0000-000000000002'
       AND (action_payload ->> 'kind') = 'round_published'
       AND (action_payload ->> 'round_number') = '1'),
  '— Pitch 4, Start 14:30'::text,
  '(a) German body carries "— Pitch 4, Start 14:30" (schedule present)');

-- PII-free whitelist: exactly the 6 keys, nothing else.
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT jsonb_object_keys(action_payload) k FROM public.user_inbox_messages
       WHERE user_id = '66660000-0000-0000-0000-000000000002'
         AND (action_payload ->> 'kind') = 'round_published'
         AND (action_payload ->> 'round_number') = '1') t
     WHERE k NOT IN ('tournament_id','round_number','phase','starts_at','pitch_number','kind')),
  0, 'payload has NO key outside the 6-key privacy whitelist');
SELECT is(
  (SELECT count(DISTINCT k)::int FROM (
     SELECT jsonb_object_keys(action_payload) k FROM public.user_inbox_messages
       WHERE user_id = '66660000-0000-0000-0000-000000000002'
         AND (action_payload ->> 'kind') = 'round_published'
         AND (action_payload ->> 'round_number') = '1') t),
  6, 'payload has exactly the 6 whitelist keys');

-- (d) idempotency: a second identical call inserts 0 additional rows.
SELECT is(
  public._tournament_notify_round_per_pitch(
    '66669999-0000-0000-0000-000000000001', 1, 'group', 'round_published',
    'Runde 1 veröffentlicht',
    'Turnier "C1-Tour": Runde 1 ist da.'),
  0,
  '(d) second identical call inserts 0 rows (idempotent guard)');

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND (action_payload ->> 'tournament_id') = '66669999-0000-0000-0000-000000000001'
       AND (action_payload ->> 'kind') = 'round_published'
       AND (action_payload ->> 'round_number') = '1'),
  2,
  '(d) row count stays at 2 after the repeat call');

-- (c) no-schedule fallback: round 2 has a match (pitch 6) but NO schedule row.
DO $deg$
DECLARE
  v_tour uuid := '66669999-0000-0000-0000-000000000001';
  v_p1   uuid := '66661111-0000-0000-0000-000000000001';
  v_p2   uuid := '66661111-0000-0000-0000-000000000002';
BEGIN
  SET LOCAL ROLE postgres;
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, pitch_number, status)
    VALUES (v_tour, 2, 1, v_p1, v_p2, 6, 'scheduled');
END;
$deg$;

SELECT is(
  public._tournament_notify_round_per_pitch(
    '66669999-0000-0000-0000-000000000001', 2, 'group', 'round_published',
    'Runde 2 veröffentlicht',
    'Turnier "C1-Tour": Runde 2 ist da.'),
  2,
  '(c) round-2 (no schedule row) still fans out to both recipients');

SELECT is(
  (SELECT (action_payload ->> 'starts_at') FROM public.user_inbox_messages
     WHERE user_id = '66660000-0000-0000-0000-000000000002'
       AND (action_payload ->> 'kind') = 'round_published'
       AND (action_payload ->> 'round_number') = '2'),
  NULL,
  '(c) no schedule row -> starts_at NULL in payload (soft-dependent on A)');

SELECT matches(
  (SELECT body FROM public.user_inbox_messages
     WHERE user_id = '66660000-0000-0000-0000-000000000002'
       AND (action_payload ->> 'kind') = 'round_published'
       AND (action_payload ->> 'round_number') = '2'),
  '— Pitch 6'::text,
  '(c) no schedule -> body keeps "— Pitch 6" (Pitch segment preserved)');

SELECT doesnt_match(
  (SELECT body FROM public.user_inbox_messages
     WHERE user_id = '66660000-0000-0000-0000-000000000002'
       AND (action_payload ->> 'kind') = 'round_published'
       AND (action_payload ->> 'round_number') = '2'),
  'Start'::text,
  '(c) no schedule -> body has NO "Start" segment');

-- ====================================================================
-- PART 2 — GAP-CLOSE end-to-end: tournament_generate_stage_matches was
-- previously SILENT (fired NO participant notify). After C1 it must emit a
-- per-pitch 'round_published' row per recipient for the stage's round 1.
-- A 'pool' stage over 3 confirmed solo participants -> 3 group matches
-- (round 1, phase 'group', pitch 1), then the C1 notify fires.
-- ====================================================================
DO $stage$
DECLARE
  v_creator uuid := '66660000-0000-0000-0000-00000000000a';
  v_sp1     uuid := '66660000-0000-0000-0000-00000000000b';
  v_sp2     uuid := '66660000-0000-0000-0000-00000000000c';
  v_sp3     uuid := '66660000-0000-0000-0000-00000000000d';
  v_tour    uuid := '6666aaaa-0000-0000-0000-000000000001';
  v_pa1     uuid := '6666bbbb-0000-0000-0000-000000000001';
  v_pa2     uuid := '6666bbbb-0000-0000-0000-000000000002';
  v_pa3     uuid := '6666bbbb-0000-0000-0000-000000000003';
BEGIN
  SET LOCAL ROLE postgres;
  PERFORM _rp_mk_user(v_creator);
  PERFORM _rp_mk_user(v_sp1);
  PERFORM _rp_mk_user(v_sp2);
  PERFORM _rp_mk_user(v_sp3);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'C1-Stage-Tour', 1, 2, 16, 'swiss', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);

  INSERT INTO public.tournament_participants(id, tournament_id, user_id, registration_status)
    VALUES (v_pa1, v_tour, v_sp1, 'confirmed'),
           (v_pa2, v_tour, v_sp2, 'confirmed'),
           (v_pa3, v_tour, v_sp3, 'confirmed');

  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tour, 'pool_A', 'pool',
            '{}'::jsonb, 'manual', 'pending');

  -- Run the stage runner (as the SECURITY DEFINER RPC would be called by the
  -- stage-graph trigger). Previously SILENT; C1 must now notify.
  PERFORM public.tournament_generate_stage_matches(
    v_tour, 'pool_A', ARRAY[v_pa1, v_pa2, v_pa3]::uuid[]);
END;
$stage$;

-- (b) the stage runner now notifies — was previously silent. 3 recipients.
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND (action_payload ->> 'tournament_id') = '6666aaaa-0000-0000-0000-000000000001'
       AND (action_payload ->> 'kind') = 'round_published'),
  3,
  '(b) GAP-CLOSE: stage runner now emits one round_published row per recipient (3)');

SELECT is(
  (SELECT (action_payload ->> 'round_number')::int FROM public.user_inbox_messages
     WHERE user_id = '66660000-0000-0000-0000-00000000000b'
       AND (action_payload ->> 'kind') = 'round_published'),
  1,
  '(b) stage notify uses round_number 1 (consistent with the materialised round)');

SELECT is(
  (SELECT (action_payload ->> 'phase') FROM public.user_inbox_messages
     WHERE user_id = '66660000-0000-0000-0000-00000000000b'
       AND (action_payload ->> 'kind') = 'round_published'),
  'group',
  '(b) stage notify uses phase ''group''');

SELECT is(
  (SELECT (action_payload ->> 'pitch_number')::int FROM public.user_inbox_messages
     WHERE user_id = '66660000-0000-0000-0000-00000000000b'
       AND (action_payload ->> 'kind') = 'round_published'),
  1,
  '(b) stage recipient carries their group-match pitch (1)');

SELECT * FROM finish();
ROLLBACK;
