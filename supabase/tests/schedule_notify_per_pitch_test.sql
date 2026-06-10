-- ADR-0031 Phase C / Block C0 — _tournament_notify_round_per_pitch pgTAP suite.
--
-- Covers (C0-DoD-11):
--   (a) helper writes exactly 1 row per recipient;
--   (b) pitch is resolved PER recipient (two recipients on different pitches
--       -> different stored pitch_number / Pitch text);
--   (c) team-roster resolution (both open team members get their team's pitch;
--       a guest / NULL slot produces no row; a solo player gets their pitch);
--   (d) idempotency (a second identical call inserts 0 additional rows);
--   (e) kind CHECK (all 16 kinds accepted, a fabricated kind rejected).
--
-- pgTAP is installed transiently inside the BEGIN..ROLLBACK; everything rolls
-- back, nothing is mutated (read-only against the live DB).

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(29);

-- --------------------------------------------------------------------
-- Fixture (as postgres): one tournament with
--   * a TEAM participant (2 open roster members + 1 guest/NULL slot) playing
--     a round-1 match on pitch 5;
--   * a SOLO participant playing a round-1 match on pitch 9;
-- plus a schedule row giving the round a starts_at.
-- --------------------------------------------------------------------
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION _np_mk_user(p_uid uuid) RETURNS uuid
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

DO $fixture$
DECLARE
  v_creator  uuid := '77777777-7777-7777-7777-777777777701';
  v_tm_a     uuid := '77777777-7777-7777-7777-777777777702'; -- team member A
  v_tm_b     uuid := '77777777-7777-7777-7777-777777777703'; -- team member B
  v_solo     uuid := '77777777-7777-7777-7777-777777777704'; -- solo player
  v_repl     uuid := '77777777-7777-7777-7777-777777777705'; -- replaced team slot
  v_team     uuid := '88888888-8888-8888-8888-888888888801';
  v_team_opp uuid := '88888888-8888-8888-8888-888888888802';
  v_tour     uuid := '99999999-9999-9999-9999-999999999901';
  v_part_team uuid := 'aaaaaaaa-0000-0000-0000-000000000001';
  v_part_solo uuid := 'aaaaaaaa-0000-0000-0000-000000000002';
  v_opp_team  uuid := 'aaaaaaaa-0000-0000-0000-000000000003'; -- team's opponent
  v_opp_solo  uuid := 'aaaaaaaa-0000-0000-0000-000000000004'; -- solo's opponent
BEGIN
  PERFORM _np_mk_user(v_creator);
  PERFORM _np_mk_user(v_tm_a);
  PERFORM _np_mk_user(v_tm_b);
  PERFORM _np_mk_user(v_solo);
  PERFORM _np_mk_user(v_repl);

  INSERT INTO public.teams(id, display_name, created_by)
    VALUES (v_team, 'NP-Team', v_creator),
           (v_team_opp, 'NP-Team-Opp', v_creator);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'NP-Tour', 1, 2, 16, 'swiss', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);

  -- Schedule row -> round 1 has a starts_at (Phase A present).
  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_tour, NULL, 1, 'group', 'running',
            now() - interval '400 seconds',
            timestamptz '2026-06-09 14:30:00+00',
            timestamptz '2026-06-09 15:00:00+00',
            300, 1800);

  -- Participants: one team participation (team_id set), one solo, plus two
  -- opponents so each side has a match.
  INSERT INTO public.tournament_participants(id, tournament_id, team_id, user_id, registration_status)
    VALUES (v_part_team, v_tour, v_team, NULL, 'confirmed');
  INSERT INTO public.tournament_participants(id, tournament_id, user_id, registration_status)
    VALUES (v_part_solo, v_tour, v_solo, 'confirmed'),
           -- Solo opponent: withdrawn -> exists for the match FK but is never a
           -- recipient (so the solo player is the only round-1 solo recipient).
           (v_opp_solo,  v_tour, v_creator, 'withdrawn');
  -- Team opponent: a second team participation (rejected -> never a recipient;
  -- its roster is intentionally empty, so even if it were confirmed it would
  -- add no recipients).
  INSERT INTO public.tournament_participants(id, tournament_id, team_id, user_id, registration_status)
    VALUES (v_opp_team, v_tour, v_team_opp, NULL, 'rejected');

  -- Roster of the TEAM participation: 2 open members + 1 guest (NULL member).
  INSERT INTO public.tournament_roster_slots(participant_id, slot_index, member_user_id, guest_player_id)
    VALUES (v_part_team, 1, v_tm_a, NULL),
           (v_part_team, 2, v_tm_b, NULL);
  -- Non-recipient slot: a REPLACED member slot (replaced_at set) must drop out,
  -- exercising the same `s.replaced_at IS NULL` filter that excludes guest /
  -- NULL-member slots. v_repl is used nowhere else, so it must end with 0 rows.
  INSERT INTO public.tournament_roster_slots(participant_id, slot_index, member_user_id, guest_player_id, replaced_at)
    VALUES (v_part_team, 3, v_repl, NULL, now()); -- replaced -> drops out

  -- Round-1 matches: team on pitch 5, solo on pitch 9.
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round, participant_a, participant_b, pitch_number, status)
    VALUES
      (v_tour, 1, 1, v_part_team, v_opp_team, 5, 'scheduled'),
      (v_tour, 1, 2, v_part_solo, v_opp_solo, 9, 'scheduled');
END;
$fixture$;

-- ====================================================================
-- (e) kind CHECK: all 16 kinds accepted, a fabricated kind rejected.
-- ====================================================================
-- Each existing kind must INSERT cleanly.
SELECT lives_ok(
  $$INSERT INTO public.user_inbox_messages(user_id, kind, subject, body)
      SELECT '77777777-7777-7777-7777-777777777704', k, 's', 'b'
        FROM unnest(ARRAY[
          'notice','verification_request','system','team_invitation',
          'team_member_removed','team_dissolved','club_invitation',
          'club_member_removed','club_join_request','tournament_started',
          'tournament_round','tournament_team_registered',
          'tournament_registration_confirmed','tournament_waitlisted',
          'tournament_promoted','tournament_finished']) k$$,
  'kind CHECK accepts all 16 existing kinds');

SELECT throws_ok(
  $$INSERT INTO public.user_inbox_messages(user_id, kind, subject, body)
      VALUES ('77777777-7777-7777-7777-777777777704','made_up_kind','s','b')$$,
  '23514',
  NULL,
  'kind CHECK rejects a fabricated kind');

-- Clean the kind-probe rows so they do not pollute the per-pitch counts.
DELETE FROM public.user_inbox_messages
  WHERE user_id = '77777777-7777-7777-7777-777777777704'
    AND action_payload IS NULL;

-- ====================================================================
-- First call of the per-pitch helper.
-- ====================================================================
SELECT is(
  public._tournament_notify_round_per_pitch(
    '99999999-9999-9999-9999-999999999901', 1, 'group',
    'round_published', 'Runde 1', 'Runde 1 wurde veröffentlicht.'),
  3,
  'helper returns 3 inserted rows (2 team members + 1 solo)');

-- ---- (a) exactly one row per recipient ----
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND (action_payload ->> 'tournament_id') = '99999999-9999-9999-9999-999999999901'
       AND (action_payload ->> 'kind') = 'round_published'),
  3,
  '(a) exactly 3 inbox rows total (one per recipient)');

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777702'
       AND (action_payload ->> 'kind') = 'round_published'),
  1, '(a) team member A has exactly 1 row');
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777703'
       AND (action_payload ->> 'kind') = 'round_published'),
  1, '(a) team member B has exactly 1 row');
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777704'
       AND (action_payload ->> 'kind') = 'round_published'),
  1, '(a) solo player has exactly 1 row');

-- ---- (c) replaced / non-recipient users get NO row ----
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777705' -- replaced team slot member
       AND (action_payload ->> 'kind') = 'round_published'),
  0, '(c) replaced roster slot member gets NO row (guest/NULL/replaced drop out)');

-- ---- (b) + (c) pitch resolved PER recipient ----
SELECT is(
  (SELECT (action_payload ->> 'pitch_number')::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777702'
       AND (action_payload ->> 'kind') = 'round_published'),
  5, '(b) team member A gets the TEAM match pitch (5)');
SELECT is(
  (SELECT (action_payload ->> 'pitch_number')::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777703'
       AND (action_payload ->> 'kind') = 'round_published'),
  5, '(b) team member B gets the TEAM match pitch (5)');
SELECT is(
  (SELECT (action_payload ->> 'pitch_number')::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777704'
       AND (action_payload ->> 'kind') = 'round_published'),
  9, '(b) solo player gets the SOLO match pitch (9) — different pitch per recipient');

-- ---- Body carries the German Pitch + Start hint ----
SELECT matches(
  (SELECT body FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777704'
       AND (action_payload ->> 'kind') = 'round_published'),
  '— Pitch 9, Start 14:30'::text,
  'body has the German "— Pitch 9, Start 14:30" hint'::text);
SELECT matches(
  (SELECT body FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777702'
       AND (action_payload ->> 'kind') = 'round_published'),
  '— Pitch 5, Start 14:30'::text,
  'team member body has the German "— Pitch 5, Start 14:30" hint'::text);

-- ---- (C0-8) PII-free whitelist: exactly the 6 keys, nothing else ----
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT jsonb_object_keys(action_payload) k FROM public.user_inbox_messages
       WHERE kind = 'tournament_round'
         AND user_id = '77777777-7777-7777-7777-777777777704'
         AND (action_payload ->> 'kind') = 'round_published') t
     WHERE k NOT IN ('tournament_id','round_number','phase','starts_at','pitch_number','kind')),
  0, 'payload has NO key outside the 6-key privacy whitelist');
SELECT is(
  (SELECT count(DISTINCT k)::int FROM (
     SELECT jsonb_object_keys(action_payload) k FROM public.user_inbox_messages
       WHERE kind = 'tournament_round'
         AND user_id = '77777777-7777-7777-7777-777777777704'
         AND (action_payload ->> 'kind') = 'round_published') t),
  6, 'payload has exactly the 6 whitelist keys');
SELECT is(
  (SELECT (action_payload ->> 'phase') FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777704'
       AND (action_payload ->> 'kind') = 'round_published'),
  'group', 'payload phase echoed');
SELECT is(
  (SELECT (action_payload ->> 'round_number')::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777704'
       AND (action_payload ->> 'kind') = 'round_published'),
  1, 'payload round_number echoed');

-- ---- (d) idempotency: a second identical call inserts 0 additional rows ----
SELECT is(
  public._tournament_notify_round_per_pitch(
    '99999999-9999-9999-9999-999999999901', 1, 'group',
    'round_published', 'Runde 1', 'Runde 1 wurde veröffentlicht.'),
  0,
  '(d) second identical call inserts 0 rows (NOT EXISTS guard)');

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND (action_payload ->> 'tournament_id') = '99999999-9999-9999-9999-999999999901'
       AND (action_payload ->> 'kind') = 'round_published'),
  3,
  '(d) total row count stays at 3 after the second call');

-- ---- A DIFFERENT event-kind for the same round is NOT blocked by the guard --
SELECT is(
  public._tournament_notify_round_per_pitch(
    '99999999-9999-9999-9999-999999999901', 1, 'group',
    'match_running', 'Runde 1 läuft', 'Dein Match läuft jetzt.'),
  3,
  'a different action_payload.kind for the same round fans out again (3 rows)');

-- ---- Degradation: a round WITHOUT a schedule row -> no Start segment, but
--      Pitch segment + per-recipient row still present (C not hard-dep on A).
DO $deg$
DECLARE
  v_tour uuid := '99999999-9999-9999-9999-999999999901';
  v_pt   uuid := 'aaaaaaaa-0000-0000-0000-000000000002'; -- solo participant
  v_op   uuid := 'aaaaaaaa-0000-0000-0000-000000000004';
BEGIN
  SET LOCAL ROLE postgres;
  -- Round 2 match for the solo player, NO schedule row for round 2.
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round, participant_a, participant_b, pitch_number, status)
    VALUES (v_tour, 2, 1, v_pt, v_op, 3, 'scheduled');
END;
$deg$;

-- The helper fans out to every confirmed recipient of the tournament (same
-- spine as _tournament_notify_participants): the 2 team members + the solo
-- player = 3. The solo player has a round-2 match (pitch 3); the team members
-- have none -> their row carries a NULL pitch (bye / no-match degradation,
-- "Pitch X" omitted), which is asserted just below.
SELECT is(
  public._tournament_notify_round_per_pitch(
    '99999999-9999-9999-9999-999999999901', 2, 'group',
    'round_published', 'Runde 2', 'Runde 2 wurde veröffentlicht.'),
  3,
  'round-2 (no schedule) fans out to all 3 confirmed recipients');

SELECT is(
  (SELECT (action_payload ->> 'pitch_number')::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777704'
       AND (action_payload ->> 'round_number') = '2'
       AND (action_payload ->> 'kind') = 'round_published'),
  3, 'solo player gets round-2 match pitch (3)');

SELECT is(
  (SELECT (action_payload ->> 'pitch_number') FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777702'
       AND (action_payload ->> 'round_number') = '2'
       AND (action_payload ->> 'kind') = 'round_published'),
  NULL, 'team member without a round-2 match gets NULL pitch (no-match degradation)');

SELECT is(
  (SELECT (action_payload ->> 'starts_at') FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777704'
       AND (action_payload ->> 'round_number') = '2'
       AND (action_payload ->> 'kind') = 'round_published'),
  NULL, 'no schedule row -> starts_at is NULL in payload (degrades cleanly)');

SELECT matches(
  (SELECT body FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777704'
       AND (action_payload ->> 'round_number') = '2'
       AND (action_payload ->> 'kind') = 'round_published'),
  '— Pitch 3'::text,
  'no schedule -> body keeps "— Pitch 3" (no Start segment)'::text);

SELECT doesnt_match(
  (SELECT body FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '77777777-7777-7777-7777-777777777704'
       AND (action_payload ->> 'round_number') = '2'
       AND (action_payload ->> 'kind') = 'round_published'),
  'Start'::text,
  'no schedule -> body has NO Start segment'::text);

-- ====================================================================
-- Guard scoping: a broadcast-shaped tournament_round row (no pitch_number
-- key, written e.g. by _tournament_notify_participants) must NOT suppress a
-- per-pitch fan-out for the same (tournament, round, kind, user). Round 3 is
-- fresh; we seed one broadcast-shaped row for the solo player, then fan out.
-- The per-pitch guard requires action_payload ? 'pitch_number', so the seeded
-- row is ignored and all 3 recipients still receive a per-pitch row.
-- ====================================================================
DO $guard$
DECLARE
  v_tour uuid := '99999999-9999-9999-9999-999999999901';
  v_pt   uuid := 'aaaaaaaa-0000-0000-0000-000000000002'; -- solo participant
  v_op   uuid := 'aaaaaaaa-0000-0000-0000-000000000004';
BEGIN
  SET LOCAL ROLE postgres;
  -- Round 3 match for the solo player (pitch 7).
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round, participant_a, participant_b, pitch_number, status)
    VALUES (v_tour, 3, 1, v_pt, v_op, 7, 'scheduled');
  -- Pre-existing BROADCAST-shaped row for the solo player: same tournament /
  -- round / kind, but NO pitch_number key (payload as _tournament_notify_
  -- participants would write it). The per-pitch guard must ignore this.
  INSERT INTO public.user_inbox_messages(user_id, kind, subject, body, action_payload)
    VALUES ('77777777-7777-7777-7777-777777777704', 'tournament_round',
            'broadcast', 'broadcast body',
            jsonb_build_object('tournament_id', v_tour::text,
                               'round_number', '3',
                               'phase', 'group',
                               'kind', 'round_published'));
END;
$guard$;

SELECT is(
  public._tournament_notify_round_per_pitch(
    '99999999-9999-9999-9999-999999999901', 3, 'group',
    'round_published', 'Runde 3', 'Runde 3 wurde veröffentlicht.'),
  3,
  'broadcast-shaped row (no pitch_number key) does NOT suppress per-pitch fan-out (3 rows)');

-- ====================================================================
-- Deterministic multi-match collapse: if a recipient ever appeared in >1
-- match of the same round (not in supported formats, but the DISTINCT ON
-- tie-break must be deterministic), the LOWEST assigned pitch wins. Round 4
-- gives the solo player two matches (pitch 8 and pitch 2) -> exactly one row
-- carrying pitch 2.
-- ====================================================================
DO $multi$
DECLARE
  v_tour uuid := '99999999-9999-9999-9999-999999999901';
  v_pt   uuid := 'aaaaaaaa-0000-0000-0000-000000000002'; -- solo participant
  v_op   uuid := 'aaaaaaaa-0000-0000-0000-000000000004';
BEGIN
  SET LOCAL ROLE postgres;
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round, participant_a, participant_b, pitch_number, status)
    VALUES (v_tour, 4, 1, v_pt, v_op, 8, 'scheduled'),
           (v_tour, 4, 2, v_pt, v_op, 2, 'scheduled');
  -- Fan out round 4; the solo player has two matches -> exactly one collapsed
  -- row must result (DISTINCT ON), carrying the LOWEST pitch (2).
  PERFORM public._tournament_notify_round_per_pitch(
    v_tour, 4, 'group', 'round_published', 'Runde 4',
    'Runde 4 wurde veröffentlicht.');
END;
$multi$;

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE user_id = '77777777-7777-7777-7777-777777777704'
       AND (action_payload ->> 'round_number') = '4'
       AND (action_payload ->> 'kind') = 'round_published'),
  1,
  'multi-match recipient collapses to a SINGLE row (DISTINCT ON)');

SELECT is(
  (SELECT (action_payload ->> 'pitch_number')::int FROM public.user_inbox_messages
     WHERE user_id = '77777777-7777-7777-7777-777777777704'
       AND (action_payload ->> 'round_number') = '4'
       AND (action_payload ->> 'kind') = 'round_published'),
  2,
  'multi-match collapse is deterministic: the LOWEST pitch wins (2 over 8)');

SELECT * FROM finish();
ROLLBACK;
