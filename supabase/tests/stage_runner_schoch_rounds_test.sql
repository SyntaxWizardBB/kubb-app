-- Schoch-Runden-Brücke im Stufen-Graph-Runner — ADR-0039 §2 (HIGH-1).
--
-- Migration 20261300000000_stage_runner_schoch_rounds.sql verzweigt den Runner
-- (tournament_run_stage_graph) für Schoch-Stufen runden-scoped: solange die
-- höchste Runde r < R fertig ist, bleibt die Stufe 'active' und es feuert nur
-- ein 'swiss_round_complete'-Audit-Signal; erst bei r >= R läuft der bestehende
-- Schliess-/Route-/Cascade-Pfad. Jeder andere Stufen-Typ schliesst weiterhin
-- stufenweit, sobald ALLE seine Matches terminal sind.
--
-- Geprüft wird NUR die Runner-Verzweigung. Die Paarung der Folgerunden ist eine
-- Organizer-Aktion (B4/B5, spätere Unit) — der Test materialisiert Runde 2/3 von
-- Hand und finalisiert sie per UPDATE, was den AFTER-UPDATE-Trigger feuert.
--
-- Soll-Werte sind hartkodiert (echtes Oracle). Alles läuft transient in
-- BEGIN..ROLLBACK; nichts wird persistiert.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(15);

SET LOCAL ROLE postgres;

-- ---------------------------------------------------------------------
-- Fixture identifiers.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _srs_tid() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5c0d0000-0000-0000-0000-0000000000d1'::uuid $$;
CREATE OR REPLACE FUNCTION _srs_creator() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5c0d0000-0000-0000-0000-0000000000e1'::uuid $$;

-- Four schoch participants. Ids chosen distinct; seed drives the routing order.
CREATE OR REPLACE FUNCTION _srs_p(p_idx int) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('00000000-0000-0000-0c0d-' || lpad(p_idx::text, 12, '0'))::uuid
$$;

DO $fixture$
DECLARE
  v_tid uuid := _srs_tid();
  v_u   uuid;
  i     int;
BEGIN
  -- Organizer + one auth user per participant.
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (_srs_creator(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated', 'org@srs.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  FOR i IN 1..4 LOOP
    v_u := ('00000000-0000-0000-0a0d-' || lpad(i::text, 12, '0'))::uuid;
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_u, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated', 'p' || i || '@srs.local',
              '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
  END LOOP;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, _srs_creator(), 'Schoch Runner Bridge', 1, 2, 32,
            'schoch_then_ko', 'ekc',
            jsonb_build_object('round_time_seconds', 1800), 'live', true);

  -- Schoch stage sw1 with R=3 rounds, active. Outgoing top_k(2) edge into the
  -- KO stage ko1 (pending). A second sink stage proves the regression types.
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES
      (gen_random_uuid(), v_tid, 'sw1', 'schoch',
         jsonb_build_object('rounds', 3), 'as_routed', 'active'),
      (gen_random_uuid(), v_tid, 'ko1', 'single_elim',
         '{}'::jsonb, 'as_routed', 'pending');

  INSERT INTO public.tournament_stage_edges(
      id, tournament_id, from_node_id, to_node_id, selector, seeding_in)
    VALUES (gen_random_uuid(), v_tid, 'sw1', 'ko1',
            jsonb_build_object('kind', 'top_k', 'k', 2), 'order_preserving');

  -- Four confirmed participants seeded 1..4.
  FOR i IN 1..4 LOOP
    v_u := ('00000000-0000-0000-0a0d-' || lpad(i::text, 12, '0'))::uuid;
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, seed, registered_at)
      VALUES (_srs_p(i), v_tid, v_u, 'confirmed', i,
              '2026-06-01 09:00:00+00'::timestamptz + (i || ' seconds')::interval);
  END LOOP;

  -- Round 1 matches (scheduled — finalized later via UPDATE to fire the trigger).
  -- P1 beats P3, P2 beats P4. EKC final scores feed total_points / Buchholz.
  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, winner_participant,
      final_score_a, final_score_b, stage_node_id, consensus_round)
    VALUES
      ('00000000-0000-0000-0eed-000000000101'::uuid, v_tid, 1, 1,
         _srs_p(1), _srs_p(3), 'group', 'scheduled', NULL, NULL, NULL, 'sw1', 1),
      ('00000000-0000-0000-0eed-000000000102'::uuid, v_tid, 1, 2,
         _srs_p(2), _srs_p(4), 'group', 'scheduled', NULL, NULL, NULL, 'sw1', 1);
END;
$fixture$;

-- =====================================================================
-- Round 1: finalize all matches -> the highest round (1) is terminal, but
-- 1 < R=3, so the stage MUST stay 'active' and emit 'swiss_round_complete'
-- with completed_round=1, awaiting=2. No routing, no KO activation.
-- =====================================================================
UPDATE public.tournament_matches
   SET status = 'finalized', winner_participant = _srs_p(1),
       final_score_a = 16, final_score_b = 5
 WHERE id = '00000000-0000-0000-0eed-000000000101'::uuid;
UPDATE public.tournament_matches
   SET status = 'finalized', winner_participant = _srs_p(2),
       final_score_a = 16, final_score_b = 5
 WHERE id = '00000000-0000-0000-0eed-000000000102'::uuid;

SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = _srs_tid() AND node_id = 'sw1'),
  'active',
  'r1<R: Schoch-Stufe bleibt active (keine vorzeitige Schliessung)'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_audit_events
    WHERE tournament_id = _srs_tid() AND kind = 'swiss_round_complete'),
  1,
  'r1<R: genau ein swiss_round_complete-Signal'
);
SELECT is(
  (SELECT (payload->>'completed_round')::int FROM public.tournament_audit_events
    WHERE tournament_id = _srs_tid() AND kind = 'swiss_round_complete'),
  1,
  'r1<R: completed_round = 1'
);
SELECT is(
  (SELECT (payload->>'awaiting')::int FROM public.tournament_audit_events
    WHERE tournament_id = _srs_tid() AND kind = 'swiss_round_complete'),
  2,
  'r1<R: awaiting = 2'
);
SELECT is(
  (SELECT (payload->>'rounds_total')::int FROM public.tournament_audit_events
    WHERE tournament_id = _srs_tid() AND kind = 'swiss_round_complete'),
  3,
  'r1<R: rounds_total = R = 3'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_stage_inputs
    WHERE tournament_id = _srs_tid() AND target_node_id = 'ko1'),
  0,
  'r1<R: keine KO-Inputs geroutet'
);
SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = _srs_tid() AND node_id = 'ko1'),
  'pending',
  'r1<R: KO-Stufe bleibt pending'
);

-- =====================================================================
-- Round 2: materialize + finalize. Highest round becomes 2, still 2 < R=3:
-- the stage stays active and a SECOND swiss_round_complete fires (awaiting=3).
-- =====================================================================
INSERT INTO public.tournament_matches(
    id, tournament_id, round_number, match_number_in_round,
    participant_a, participant_b, phase, status, winner_participant,
    final_score_a, final_score_b, stage_node_id, consensus_round)
  VALUES
    ('00000000-0000-0000-0eed-000000000201'::uuid, _srs_tid(), 2, 1,
       _srs_p(1), _srs_p(2), 'group', 'scheduled', NULL, NULL, NULL, 'sw1', 1),
    ('00000000-0000-0000-0eed-000000000202'::uuid, _srs_tid(), 2, 2,
       _srs_p(3), _srs_p(4), 'group', 'scheduled', NULL, NULL, NULL, 'sw1', 1);

UPDATE public.tournament_matches
   SET status = 'finalized', winner_participant = _srs_p(1),
       final_score_a = 16, final_score_b = 8
 WHERE id = '00000000-0000-0000-0eed-000000000201'::uuid;
UPDATE public.tournament_matches
   SET status = 'finalized', winner_participant = _srs_p(3),
       final_score_a = 16, final_score_b = 8
 WHERE id = '00000000-0000-0000-0eed-000000000202'::uuid;

SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = _srs_tid() AND node_id = 'sw1'),
  'active',
  'r2<R: Schoch-Stufe bleibt active'
);
SELECT is(
  (SELECT (payload->>'awaiting')::int FROM public.tournament_audit_events
    WHERE tournament_id = _srs_tid() AND kind = 'swiss_round_complete'
    ORDER BY created_at DESC, payload->>'completed_round' DESC LIMIT 1),
  3,
  'r2<R: jüngstes Signal awaiting = 3'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_audit_events
    WHERE tournament_id = _srs_tid() AND kind = 'swiss_round_complete'),
  2,
  'r2<R: zwei swiss_round_complete-Signale insgesamt'
);

-- =====================================================================
-- Round 3 (= R): materialize + finalize. Highest round = 3 >= R=3 -> the
-- stage MUST close (completed) and route into the KO stage (top_k(2) -> 2
-- inputs), activating ko1. No NEW swiss_round_complete for the terminal round.
-- =====================================================================
INSERT INTO public.tournament_matches(
    id, tournament_id, round_number, match_number_in_round,
    participant_a, participant_b, phase, status, winner_participant,
    final_score_a, final_score_b, stage_node_id, consensus_round)
  VALUES
    ('00000000-0000-0000-0eed-000000000301'::uuid, _srs_tid(), 3, 1,
       _srs_p(1), _srs_p(4), 'group', 'scheduled', NULL, NULL, NULL, 'sw1', 1),
    ('00000000-0000-0000-0eed-000000000302'::uuid, _srs_tid(), 3, 2,
       _srs_p(2), _srs_p(3), 'group', 'scheduled', NULL, NULL, NULL, 'sw1', 1);

UPDATE public.tournament_matches
   SET status = 'finalized', winner_participant = _srs_p(1),
       final_score_a = 16, final_score_b = 9
 WHERE id = '00000000-0000-0000-0eed-000000000301'::uuid;
UPDATE public.tournament_matches
   SET status = 'finalized', winner_participant = _srs_p(2),
       final_score_a = 16, final_score_b = 9
 WHERE id = '00000000-0000-0000-0eed-000000000302'::uuid;

SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = _srs_tid() AND node_id = 'sw1'),
  'completed',
  'r3=R: Schoch-Stufe wird geschlossen (completed)'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_stage_inputs
    WHERE tournament_id = _srs_tid() AND target_node_id = 'ko1'),
  2,
  'r3=R: top_k(2) routet 2 Teilnehmer in die KO-Stufe'
);
SELECT is(
  (SELECT count(*)::int FROM public.tournament_audit_events
    WHERE tournament_id = _srs_tid() AND kind = 'swiss_round_complete'),
  2,
  'r3=R: kein zusätzliches swiss_round_complete für die letzte Runde'
);

-- =====================================================================
-- Regression: a single_elim and a round_robin stage close stage-WIDE as before
-- the moment all their matches are terminal. Proves the schoch branch is a
-- pre-guard that leaves the default close path byte-identical for other types.
-- Both are sink stages here (no outgoing edge) — Guard D closes without routing.
-- =====================================================================
DO $reg$
DECLARE
  v_tid uuid := _srs_tid();
BEGIN
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES
      (gen_random_uuid(), v_tid, 'se1', 'single_elim', '{}'::jsonb, 'as_routed', 'active'),
      (gen_random_uuid(), v_tid, 'rr1', 'round_robin', '{}'::jsonb, 'as_routed', 'active');

  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, winner_participant,
      final_score_a, final_score_b, stage_node_id, consensus_round)
    VALUES
      ('00000000-0000-0000-0eed-0000000005e1'::uuid, v_tid, 1, 1,
         _srs_p(1), _srs_p(2), 'group', 'scheduled', NULL, NULL, NULL, 'se1', 1),
      ('00000000-0000-0000-0eed-000000000711'::uuid, v_tid, 1, 1,
         _srs_p(3), _srs_p(4), 'group', 'scheduled', NULL, NULL, NULL, 'rr1', 1);
END;
$reg$;

UPDATE public.tournament_matches
   SET status = 'finalized', winner_participant = _srs_p(1),
       final_score_a = 16, final_score_b = 0
 WHERE id = '00000000-0000-0000-0eed-0000000005e1'::uuid;

SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = _srs_tid() AND node_id = 'se1'),
  'completed',
  'Regression single_elim: schliesst stufenweit wie bisher (completed)'
);

UPDATE public.tournament_matches
   SET status = 'finalized', winner_participant = _srs_p(3),
       final_score_a = 16, final_score_b = 0
 WHERE id = '00000000-0000-0000-0eed-000000000711'::uuid;

SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = _srs_tid() AND node_id = 'rr1'),
  'completed',
  'Regression round_robin: schliesst stufenweit wie bisher (completed)'
);

SELECT * FROM finish();
ROLLBACK;
