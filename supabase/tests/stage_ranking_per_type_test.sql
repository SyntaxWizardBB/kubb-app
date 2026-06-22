-- Per-type stage ranking — group-phase audit + Dart parity (M2-T06).
--
-- Covers the M2-T05 chain split (migration 20261296000000_stage_ranking_per_type):
--
--   1. AUDIT. No group-phase ranking branch may carry Buchholz in its sort
--      (ADR-0035 / vorrunde-ranking-spec §6.2 / §7.5). Repo grep that backs
--      this assertion (run at authoring time, kept here as the documented
--      evidence the test is built on):
--
--        $ grep -n "v_type in ('swiss', 'schoch') then -e.buchholz" \
--              supabase/migrations/20261296000000_stage_ranking_per_type.sql
--        -> the ONLY -e.buchholz in the file sits behind the schoch/swiss
--           guard; the else-branch uses -e.kubb_diff.
--        $ grep -n "buchholz" <pool_standings ORDER BY> -> none in the
--           tournament_pool_standings `ordered` window.
--
--      The functional half of the audit introspects the LIVE function bodies
--      from pg_proc and asserts the group-phase sort path mentions kubb_diff
--      and never reaches Buchholz outside the schoch/swiss guard.
--
--   2. SMOKE PARITY. A 3-player group_phase stage where two participants are
--      point-equal but differ on kubb difference. The SQL rank from
--      tournament_stage_ranking must match the Dart computeStageStandings(
--      groupPhase) order — which is chainForStageType(groupPhase) =
--      totalPoints -> kubbDifference -> shoot-out, then the deterministic
--      participantId tail (tiebreaker.dart L108/L171-178). Soll order is
--      HARD-CODED below (computed by hand from the fixture, NOT read back from
--      the function under test).
--
-- pgTAP runs transiently in BEGIN..ROLLBACK; nothing is persisted.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(17);

SET LOCAL ROLE postgres;

-- ---------------------------------------------------------------------
-- Fixture identifiers.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _spt_tid() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5b0c0000-0000-0000-0000-0000000000b1'::uuid $$;
CREATE OR REPLACE FUNCTION _spt_creator() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5b0c0000-0000-0000-0000-0000000000c1'::uuid $$;

-- Participant ids are chosen so a naive id-sort would put P2 BEFORE P1
-- (P2's id is lexically smaller). kubb_difference must override that and
-- rank P1 first — proving the criterion is load-bearing, not the id tail.
CREATE OR REPLACE FUNCTION _spt_p1() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-0000-0b0b-0000000000a2'::uuid $$;  -- P1, higher kubb_diff
CREATE OR REPLACE FUNCTION _spt_p2() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-0000-0b0b-0000000000a1'::uuid $$;  -- P2, lower kubb_diff
CREATE OR REPLACE FUNCTION _spt_p3() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-0000-0b0b-0000000000a9'::uuid $$;  -- P3, lowest points

DO $fixture$
DECLARE
  v_tid uuid := _spt_tid();
  v_t0  timestamptz := '2026-06-01 09:00:00+00';
  v_m12 uuid := '00000000-0000-0000-0e0e-000000000012'::uuid;  -- P1 vs P2
  v_m13 uuid := '00000000-0000-0000-0e0e-000000000013'::uuid;  -- P1 vs P3
  v_m23 uuid := '00000000-0000-0000-0e0e-000000000023'::uuid;  -- P2 vs P3
  v_sub uuid := '00000000-0000-0000-0e0e-0000000000ff'::uuid;  -- proposal submitter
  v_u1  uuid := '00000000-0000-0000-0a0a-000000000001'::uuid;  -- P1 user
  v_u2  uuid := '00000000-0000-0000-0a0a-000000000002'::uuid;  -- P2 user
  v_u3  uuid := '00000000-0000-0000-0a0a-000000000003'::uuid;  -- P3 user
BEGIN
  -- Auth users: organizer, proposal submitter, and one per participant.
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (_spt_creator(), '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'org@spt.local', '', now(), now(), now()),
    (v_sub, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'sub@spt.local', '', now(), now(), now()),
    (v_u1, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'p1@spt.local', '', now(), now(), now()),
    (v_u2, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'p2@spt.local', '', now(), now(), now()),
    (v_u3, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'p3@spt.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, _spt_creator(), 'PerType Group Phase', 1, 2, 32,
            'round_robin', 'ekc',
            jsonb_build_object('round_time_seconds', 1800), 'live', true);

  -- group_phase stage node.
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tid, 'gp1', 'group_phase',
            '{}'::jsonb, 'manual', 'active');

  -- 3 confirmed participants, all in group 'A'. registered_at is staggered so
  -- it does NOT coincide with the correct order either (P2 registered first).
  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status, seed, group_label,
      registered_at)
  VALUES
    (_spt_p1(), v_tid, v_u1, 'confirmed', 1, 'A', v_t0 + interval '3 seconds'),
    (_spt_p2(), v_tid, v_u2, 'confirmed', 2, 'A', v_t0 + interval '1 seconds'),
    (_spt_p3(), v_tid, v_u3, 'confirmed', 3, 'A', v_t0 + interval '2 seconds');

  -- Full round-robin, one set each, all finalized. final_score feeds EKC
  -- total_points; basekubbs (in the set proposals below) feed kubb_diff.
  --   M12: P1 10 : 10 P2   (point tie)         basekubbs 6 : 2
  --   M13: P1 16 :  5 P3                        basekubbs 6 : 0
  --   M23: P2 16 :  5 P3                        basekubbs 6 : 0
  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, winner_participant,
      final_score_a, final_score_b, group_label, stage_node_id, consensus_round)
  VALUES
    (v_m12, v_tid, 1, 1, _spt_p1(), _spt_p2(), 'group', 'finalized', NULL,           10, 10, 'A', 'gp1', 1),
    (v_m13, v_tid, 1, 2, _spt_p1(), _spt_p3(), 'group', 'finalized', _spt_p1(),      16,  5, 'A', 'gp1', 1),
    (v_m23, v_tid, 1, 3, _spt_p2(), _spt_p3(), 'group', 'finalized', _spt_p2(),      16,  5, 'A', 'gp1', 1);

  -- Consensus set proposals (one set per match, consensus_round = 1). The
  -- basekubbs drive kubbs_scored/kubbs_conceded -> kubb_diff.
  INSERT INTO public.tournament_set_score_proposals(
      id, match_id, consensus_round, set_number, submitter_user_id,
      basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner,
      proposed_at, set_king_outcome)
  VALUES
    (gen_random_uuid(), v_m12, 1, 1, v_sub, 6, 2, 'none', now(), 'missed'),
    (gen_random_uuid(), v_m13, 1, 1, v_sub, 6, 0, 'A',    now(), 'hit_by'),
    (gen_random_uuid(), v_m23, 1, 1, v_sub, 6, 0, 'A',    now(), 'hit_by');
END;
$fixture$;

-- Function under test.
CREATE OR REPLACE VIEW spt_fr AS
  SELECT * FROM public.tournament_stage_ranking(_spt_tid(), 'gp1');

-- ── Sanity: 3 dense ranks, no KO elimination round. ──────────────────
SELECT is( (SELECT count(*) FROM spt_fr)::int, 3, 'gp: liefert 3 Ränge' );
SELECT is( (SELECT count(DISTINCT rank) FROM spt_fr)::int, 3, 'gp: Ränge dicht 1..3' );
SELECT is(
  (SELECT count(*) FROM spt_fr WHERE ko_elimination_round IS NOT NULL)::int,
  0,
  'gp: ko_elimination_round ist NULL in der Gruppenphase'
);

-- ── Smoke parity: HARD-CODED Soll-Reihenfolge (Dart-Oracle) ──────────
-- computeStageStandings(groupPhase) order, computed by hand from the fixture:
--   total_points: P1=26, P2=26, P3=10
--   kubb_diff:    P1=+10, P2=+2, P3=-12
--   chain points -> kubb_diff -> shoot-out (neutral) -> id-tail:
--   P1 and P2 tie on points; kubb_diff (+10 > +2) puts P1 first; P3 last.
-- Soll: rank 1 = P1, rank 2 = P2, rank 3 = P3.
SELECT is(
  (SELECT participant_id FROM spt_fr WHERE rank = 1),
  _spt_p1(),
  'gp parity: Rang 1 = P1 (gleiche Punkte, höhere Kubb-Differenz)'
);
SELECT is(
  (SELECT participant_id FROM spt_fr WHERE rank = 2),
  _spt_p2(),
  'gp parity: Rang 2 = P2 (gleiche Punkte, tiefere Kubb-Differenz)'
);
SELECT is(
  (SELECT participant_id FROM spt_fr WHERE rank = 3),
  _spt_p3(),
  'gp parity: Rang 3 = P3 (tiefste Punkte)'
);

-- The point-equal pair is separated by kubb_diff, NOT by id/registered_at:
-- a naive id-sort would rank P2 before P1 (P2 id is lexically smaller) and a
-- registered_at-sort likewise (P2 registered first). The function still puts
-- P1 first -> kubb_difference is the deciding criterion.
SELECT cmp_ok(
  (SELECT rank FROM spt_fr WHERE participant_id = _spt_p1())::int,
  '<',
  (SELECT rank FROM spt_fr WHERE participant_id = _spt_p2())::int,
  'gp parity: P1 vor P2 trotz kleinerer P2-id und früherer P2-Anmeldung'
);

-- ── Audit: no Buchholz in any group-phase ranking sort path ──────────
-- tournament_stage_ranking: the only -e.buchholz in the live body sits behind
-- the schoch/swiss guard; the group-phase branch uses -e.kubb_diff.
SELECT ok(
  pg_get_functiondef('public.tournament_stage_ranking(uuid,text)'::regprocedure)
    LIKE '%when v_type in (''swiss'', ''schoch'') then -e.buchholz%',
  'audit: stage_ranking gated Buchholz nur für schoch/swiss'
);
SELECT ok(
  pg_get_functiondef('public.tournament_stage_ranking(uuid,text)'::regprocedure)
    LIKE '%else -e.kubb_diff end%',
  'audit: stage_ranking group_phase-Zweig nutzt kubb_diff'
);

-- tournament_pool_standings is a pure group-phase RPC; its `ordered` window
-- must not sort on Buchholz at all. The body still mentions buchholz nowhere
-- in an ORDER BY: assert the live body contains no "-e.buchholz" (the old
-- fallback) and does contain the kubb_diff sort key.
SELECT ok(
  pg_get_functiondef('public.tournament_pool_standings(uuid)'::regprocedure)
    NOT LIKE '%-e.buchholz%',
  'audit: pool_standings sortiert nicht mehr auf Buchholz'
);
SELECT ok(
  pg_get_functiondef('public.tournament_pool_standings(uuid)'::regprocedure)
    LIKE '%-e.kubb_diff%',
  'audit: pool_standings sortiert auf kubb_diff'
);

-- ── Audit: the three cut/seed sites found in the second sweep ─────────
-- _tournament_compute_pool_cut, _tournament_detect_shootout_groups and
-- tournament_start_ko_phase ranked group-phase participants
-- total_points -> wins -> kubb_diff gated by tiebreaker_order. ADR-0035 forbids
-- both the wins-before-kubb_diff order and the tiebreaker_order gating for the
-- preliminary round. The audit normalises whitespace (pg_get_functiondef pretty-
-- prints), then asserts: (a) no "= any(v_chain)" gating survives, and (b) the
-- group-phase sort puts kubb_diff DIRECTLY after total_points (no wins between).
CREATE OR REPLACE FUNCTION _spt_norm(p_oid regprocedure) RETURNS text
LANGUAGE sql STABLE AS $$
  SELECT regexp_replace(lower(pg_get_functiondef(p_oid)), '\s+', ' ', 'g')
$$;

-- _tournament_compute_pool_cut: the `ranked` row_number and the `grouped`
-- tie-detection GROUP BY both run the hard-coded points -> kubb_diff chain.
SELECT ok(
  _spt_norm('public._tournament_compute_pool_cut(uuid,text,integer)'::regprocedure)
    NOT LIKE '%= any(v_chain)%',
  'audit: pool_cut hat kein tiebreaker_order-Gating mehr'
);
SELECT ok(
  _spt_norm('public._tournament_compute_pool_cut(uuid,text,integer)'::regprocedure)
    LIKE '%-s.total_points, -s.kubb_diff,%',
  'audit: pool_cut rankt kubb_diff direkt nach total_points (kein wins)'
);
SELECT ok(
  _spt_norm('public._tournament_compute_pool_cut(uuid,text,integer)'::regprocedure)
    LIKE '%group by total_points, kubb_diff %',
  'audit: pool_cut Tie-Detection gruppiert auf total_points/kubb_diff (kein wins)'
);

-- _tournament_detect_shootout_groups: sort and fingerprint share the chain.
SELECT ok(
  _spt_norm('public._tournament_detect_shootout_groups(uuid,integer)'::regprocedure)
    NOT LIKE '%= any(v_chain)%',
  'audit: detect_shootout_groups hat kein tiebreaker_order-Gating mehr'
);
SELECT ok(
  _spt_norm('public._tournament_detect_shootout_groups(uuid,integer)'::regprocedure)
    LIKE '%-s.total_points, -s.kubb_diff,%',
  'audit: detect_shootout_groups rankt kubb_diff direkt nach total_points'
);

-- tournament_start_ko_phase: all three flat-preliminary seed CTEs lost the
-- gating; none of the three may carry a wins sort key any more.
SELECT ok(
  _spt_norm('public.tournament_start_ko_phase(uuid,jsonb)'::regprocedure)
    NOT LIKE '%= any(v_chain)%',
  'audit: start_ko_phase Seed-Ranking ohne tiebreaker_order-Gating'
);

SELECT * FROM finish();
ROLLBACK;
