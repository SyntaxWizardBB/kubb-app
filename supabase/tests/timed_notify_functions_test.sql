-- ADR-0031 Phase C / Block C3 — _tournament_notify_match_running /
-- _tournament_notify_awaiting pgTAP suite.
--
-- Covers (C3-DoD-11) for BOTH functions:
--   match_running:
--     * per-recipient fan-out (1 row / recipient), correct pitch_number;
--     * team-roster resolution + guest/replaced exclusion;
--     * wire-kind = 'tournament_round', action_payload.kind = 'match_running';
--     * PII-free 6-key whitelist;
--     * idempotency (2nd call -> 0 rows).
--   awaiting / tiebreak:
--     * fan-out ONLY to recipients with an OPEN (non-terminal) match;
--     * recipients of a finished match get NO row;
--     * p_tiebreak=true -> action_payload.kind = 'tiebreak_hold';
--     * pitch_number of the open match in payload;
--     * idempotency (2nd call -> 0 rows); awaiting vs tiebreak don't block.
--
-- NO end-to-end tick test in C3 (per plan). pgTAP is installed transiently
-- inside BEGIN..ROLLBACK; everything rolls back, nothing is mutated.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(27);

-- --------------------------------------------------------------------
-- Fixture (as postgres):
--   * TEAM participation (2 open roster members + 1 replaced slot) playing a
--     round-1 match on pitch 5;
--   * SOLO participant playing a round-1 match on pitch 9;
--   * a schedule row giving round 1 a starts_at.
-- Match statuses are flipped per-subtest to exercise open vs terminal.
-- --------------------------------------------------------------------
SET LOCAL ROLE postgres;

CREATE OR REPLACE FUNCTION _tn_mk_user(p_uid uuid) RETURNS uuid
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
  v_creator  uuid := '66666666-6666-6666-6666-666666666601';
  v_tm_a     uuid := '66666666-6666-6666-6666-666666666602'; -- team member A
  v_tm_b     uuid := '66666666-6666-6666-6666-666666666603'; -- team member B
  v_solo     uuid := '66666666-6666-6666-6666-666666666604'; -- solo player
  v_repl     uuid := '66666666-6666-6666-6666-666666666605'; -- replaced team slot
  v_team     uuid := '55555555-5555-5555-5555-555555555501';
  v_team_opp uuid := '55555555-5555-5555-5555-555555555502';
  v_tour     uuid := '44444444-4444-4444-4444-444444444401';
  v_part_team uuid := 'bbbbbbbb-0000-0000-0000-000000000001';
  v_part_solo uuid := 'bbbbbbbb-0000-0000-0000-000000000002';
  v_opp_team  uuid := 'bbbbbbbb-0000-0000-0000-000000000003';
  v_opp_solo  uuid := 'bbbbbbbb-0000-0000-0000-000000000004';
BEGIN
  PERFORM _tn_mk_user(v_creator);
  PERFORM _tn_mk_user(v_tm_a);
  PERFORM _tn_mk_user(v_tm_b);
  PERFORM _tn_mk_user(v_solo);
  PERFORM _tn_mk_user(v_repl);

  INSERT INTO public.teams(id, display_name, created_by)
    VALUES (v_team, 'TN-Team', v_creator),
           (v_team_opp, 'TN-Team-Opp', v_creator);

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tour, v_creator, 'TN-Tour', 1, 2, 16, 'swiss', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);

  INSERT INTO public.tournament_round_schedule(
      tournament_id, stage_node_id, round_number, phase, status,
      published_at, starts_at, ends_at, break_seconds, match_seconds)
    VALUES (v_tour, NULL, 1, 'group', 'running',
            now() - interval '400 seconds',
            timestamptz '2026-06-09 14:30:00+00',
            timestamptz '2026-06-09 15:00:00+00',
            300, 1800);

  INSERT INTO public.tournament_participants(id, tournament_id, team_id, user_id, registration_status)
    VALUES (v_part_team, v_tour, v_team, NULL, 'confirmed');
  INSERT INTO public.tournament_participants(id, tournament_id, user_id, registration_status)
    VALUES (v_part_solo, v_tour, v_solo, 'confirmed'),
           (v_opp_solo,  v_tour, v_creator, 'withdrawn');
  INSERT INTO public.tournament_participants(id, tournament_id, team_id, user_id, registration_status)
    VALUES (v_opp_team, v_tour, v_team_opp, NULL, 'rejected');

  INSERT INTO public.tournament_roster_slots(participant_id, slot_index, member_user_id, guest_player_id)
    VALUES (v_part_team, 1, v_tm_a, NULL),
           (v_part_team, 2, v_tm_b, NULL);
  INSERT INTO public.tournament_roster_slots(participant_id, slot_index, member_user_id, guest_player_id, replaced_at)
    VALUES (v_part_team, 3, v_repl, NULL, now()); -- replaced -> drops out

  -- Round-1 matches: team on pitch 5, solo on pitch 9. Both 'scheduled' (open).
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round, participant_a, participant_b, pitch_number, status)
    VALUES
      (v_tour, 1, 1, v_part_team, v_opp_team, 5, 'scheduled'),
      (v_tour, 1, 2, v_part_solo, v_opp_solo, 9, 'scheduled');
END;
$fixture$;


-- ====================================================================
-- A) _tournament_notify_match_running (E2) — per-recipient pitch fan-out.
-- ====================================================================
SELECT is(
  public._tournament_notify_match_running(
    '44444444-4444-4444-4444-444444444401', 1, 'group',
    'Match läuft', 'Dein Match läuft jetzt.'),
  3,
  'match_running returns 3 inserted rows (2 team members + 1 solo)');

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND (action_payload ->> 'tournament_id') = '44444444-4444-4444-4444-444444444401'
       AND (action_payload ->> 'kind') = 'match_running'),
  3, 'match_running: exactly 3 inbox rows (one per recipient)');

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '66666666-6666-6666-6666-666666666605' -- replaced slot member
       AND (action_payload ->> 'kind') = 'match_running'),
  0, 'match_running: replaced roster slot member gets NO row (guest/replaced drop out)');

SELECT is(
  (SELECT (action_payload ->> 'pitch_number')::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '66666666-6666-6666-6666-666666666602' -- team member A
       AND (action_payload ->> 'kind') = 'match_running'),
  5, 'match_running: team member A gets the TEAM match pitch (5)');
SELECT is(
  (SELECT (action_payload ->> 'pitch_number')::int FROM public.user_inbox_messages
     WHERE kind = 'tournament_round'
       AND user_id = '66666666-6666-6666-6666-666666666604' -- solo
       AND (action_payload ->> 'kind') = 'match_running'),
  9, 'match_running: solo player gets the SOLO match pitch (9) — per-recipient pitch');

-- wire-kind durable, sub-event in payload only.
SELECT is(
  (SELECT kind FROM public.user_inbox_messages
     WHERE user_id = '66666666-6666-6666-6666-666666666604'
       AND (action_payload ->> 'kind') = 'match_running'),
  'tournament_round',
  'match_running: durable wire-kind is tournament_round (no new wire-kind)');

-- Body carries German Pitch + Start hint.
SELECT matches(
  (SELECT body FROM public.user_inbox_messages
     WHERE user_id = '66666666-6666-6666-6666-666666666604'
       AND (action_payload ->> 'kind') = 'match_running'),
  '— Pitch 9, Start 14:30'::text,
  'match_running: German "— Pitch 9, Start 14:30" body hint');

-- PII-free whitelist: exactly the 6 keys, nothing else.
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT jsonb_object_keys(action_payload) k FROM public.user_inbox_messages
       WHERE user_id = '66666666-6666-6666-6666-666666666604'
         AND (action_payload ->> 'kind') = 'match_running') t
     WHERE k NOT IN ('tournament_id','round_number','phase','starts_at','pitch_number','kind')),
  0, 'match_running: payload has NO key outside the 6-key whitelist');
SELECT is(
  (SELECT count(DISTINCT k)::int FROM (
     SELECT jsonb_object_keys(action_payload) k FROM public.user_inbox_messages
       WHERE user_id = '66666666-6666-6666-6666-666666666604'
         AND (action_payload ->> 'kind') = 'match_running') t),
  6, 'match_running: payload has exactly the 6 whitelist keys');

-- Idempotency: second identical call inserts 0 rows.
SELECT is(
  public._tournament_notify_match_running(
    '44444444-4444-4444-4444-444444444401', 1, 'group',
    'Match läuft', 'Dein Match läuft jetzt.'),
  0,
  'match_running: second identical call inserts 0 rows (NOT EXISTS guard)');
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE (action_payload ->> 'tournament_id') = '44444444-4444-4444-4444-444444444401'
       AND (action_payload ->> 'kind') = 'match_running'),
  3, 'match_running: total row count stays 3 after the second call');


-- ====================================================================
-- B) _tournament_notify_awaiting (E7) — only recipients with an OPEN match.
--    Flip the SOLO match terminal (finalized) so only the TEAM match is open.
-- ====================================================================
DO $awaiting_setup$
BEGIN
  SET LOCAL ROLE postgres;
  -- Solo match finalized (terminal) -> solo player must NOT get an awaiting row.
  UPDATE public.tournament_matches
     SET status = 'finalized'
   WHERE tournament_id = '44444444-4444-4444-4444-444444444401'
     AND round_number = 1
     AND match_number_in_round = 2;
  -- Team match stays 'scheduled' (open) -> its 2 members are the only awaiting
  -- recipients.
END;
$awaiting_setup$;

SELECT is(
  public._tournament_notify_awaiting(
    '44444444-4444-4444-4444-444444444401', 1, 'group', false,
    'Resultat fehlt', 'Bitte das Resultat eintragen.'),
  2,
  'awaiting: only the 2 team members (open match) get a row; solo (finalized) excluded');

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE user_id = '66666666-6666-6666-6666-666666666604' -- solo (finalized)
       AND (action_payload ->> 'kind') = 'awaiting_results'),
  0, 'awaiting: solo player with a finalized match gets NO row');
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE user_id = '66666666-6666-6666-6666-666666666602' -- team member A (open)
       AND (action_payload ->> 'kind') = 'awaiting_results'),
  1, 'awaiting: team member A (open match) gets exactly 1 row');
SELECT is(
  (SELECT (action_payload ->> 'pitch_number')::int FROM public.user_inbox_messages
     WHERE user_id = '66666666-6666-6666-6666-666666666603' -- team member B (open)
       AND (action_payload ->> 'kind') = 'awaiting_results'),
  5, 'awaiting: open-match pitch (5) in payload');

SELECT is(
  (SELECT kind FROM public.user_inbox_messages
     WHERE user_id = '66666666-6666-6666-6666-666666666602'
       AND (action_payload ->> 'kind') = 'awaiting_results'),
  'tournament_round',
  'awaiting: durable wire-kind is tournament_round');

-- PII-free whitelist for awaiting too.
SELECT is(
  (SELECT count(*)::int FROM (
     SELECT jsonb_object_keys(action_payload) k FROM public.user_inbox_messages
       WHERE user_id = '66666666-6666-6666-6666-666666666602'
         AND (action_payload ->> 'kind') = 'awaiting_results') t
     WHERE k NOT IN ('tournament_id','round_number','phase','starts_at','pitch_number','kind')),
  0, 'awaiting: payload has NO key outside the 6-key whitelist');

-- Idempotency: second identical awaiting call -> 0 rows.
SELECT is(
  public._tournament_notify_awaiting(
    '44444444-4444-4444-4444-444444444401', 1, 'group', false,
    'Resultat fehlt', 'Bitte das Resultat eintragen.'),
  0,
  'awaiting: second identical call inserts 0 rows (idempotent)');
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE (action_payload ->> 'tournament_id') = '44444444-4444-4444-4444-444444444401'
       AND (action_payload ->> 'kind') = 'awaiting_results'),
  2, 'awaiting: total awaiting row count stays 2');


-- ====================================================================
-- C) _tournament_notify_awaiting tiebreak (E8) — action_payload.kind.
--    'awaiting_results' rows already exist for the same round; tiebreak must
--    still fan out (different sub-event kind), addressing the open-match pair.
-- ====================================================================
SELECT is(
  public._tournament_notify_awaiting(
    '44444444-4444-4444-4444-444444444401', 1, 'group', true,
    'Tiebreak', 'Tiebreak — bitte spielen und eintragen.'),
  2,
  'tiebreak: fans out to the 2 open-match members (not blocked by awaiting_results)');
SELECT is(
  (SELECT (action_payload ->> 'kind') FROM public.user_inbox_messages
     WHERE user_id = '66666666-6666-6666-6666-666666666602'
       AND subject = 'Tiebreak'),
  'tiebreak_hold',
  'tiebreak: action_payload.kind = ''tiebreak_hold'' (E8)');
SELECT is(
  (SELECT kind FROM public.user_inbox_messages
     WHERE user_id = '66666666-6666-6666-6666-666666666602'
       AND (action_payload ->> 'kind') = 'tiebreak_hold'),
  'tournament_round',
  'tiebreak: durable wire-kind is still tournament_round');
SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
     WHERE user_id = '66666666-6666-6666-6666-666666666604' -- solo (finalized)
       AND (action_payload ->> 'kind') = 'tiebreak_hold'),
  0, 'tiebreak: solo player with a finalized match gets NO tiebreak row');

-- tiebreak idempotency.
SELECT is(
  public._tournament_notify_awaiting(
    '44444444-4444-4444-4444-444444444401', 1, 'group', true,
    'Tiebreak', 'Tiebreak — bitte spielen und eintragen.'),
  0,
  'tiebreak: second identical call inserts 0 rows (idempotent)');


-- ====================================================================
-- D) awaiting excludes 'voided' (no result expected) just like terminal.
--    Flip the team match to 'voided' -> no recipient has an open match now.
-- ====================================================================
DO $voided_setup$
BEGIN
  SET LOCAL ROLE postgres;
  UPDATE public.tournament_matches
     SET status = 'voided'
   WHERE tournament_id = '44444444-4444-4444-4444-444444444401'
     AND round_number = 1
     AND match_number_in_round = 1;
END;
$voided_setup$;

SELECT is(
  public._tournament_notify_awaiting(
    '44444444-4444-4444-4444-444444444401', 2, 'group', false,
    'Resultat fehlt', 'Bitte das Resultat eintragen.'),
  0,
  'awaiting (round 2, no open matches): voided/terminal -> 0 rows fanned out');

-- And awaiting with a 'disputed' (open, result-pending) match DOES fan out.
DO $disputed_setup$
BEGIN
  SET LOCAL ROLE postgres;
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, pitch_number, status)
    VALUES ('44444444-4444-4444-4444-444444444401', 3, 1,
            'bbbbbbbb-0000-0000-0000-000000000002',  -- solo participant
            'bbbbbbbb-0000-0000-0000-000000000004',
            4, 'disputed');
END;
$disputed_setup$;

SELECT is(
  public._tournament_notify_awaiting(
    '44444444-4444-4444-4444-444444444401', 3, 'group', false,
    'Resultat fehlt', 'Bitte das Resultat eintragen.'),
  1,
  'awaiting (round 3): a disputed (open) match counts -> solo player gets a row');
SELECT is(
  (SELECT (action_payload ->> 'pitch_number')::int FROM public.user_inbox_messages
     WHERE user_id = '66666666-6666-6666-6666-666666666604'
       AND (action_payload ->> 'round_number') = '3'
       AND (action_payload ->> 'kind') = 'awaiting_results'),
  4, 'awaiting (round 3): disputed match pitch (4) in payload');

SELECT * FROM finish();
ROLLBACK;
