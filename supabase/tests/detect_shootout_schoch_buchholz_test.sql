-- Shoot-out detector — Schoch/Swiss tied-key includes §5 Buchholz (M2-T08).
--
-- Backs migration 20261297000000_detect_shootout_schoch_buchholz: the flat
-- shoot-out detector _tournament_detect_shootout_groups must use the
-- preliminary-type chain. For format schoch_then_ko / swiss_then_ko the tied-key
-- is total_points -> §5 Buchholz (vorrunde-ranking-spec §2.2); for every other
-- flat format it stays total_points -> kubb_difference (§2.1/§4).
--
-- Three flat tournaments, all cut at q = 2, all 5 confirmed participants
-- (so q < N — the cut line exists). Match results are chosen so that a
-- point-equal pair P1/P2 straddles the cut at ranks 1 and 2.
--
--   CASE A (schoch_then_ko): P1 and P2 are equal on BOTH points (24) AND
--     final-score kubb_diff (8) but DIFFER on §5 Buchholz (15 vs 44). The OLD
--     kubb_diff-only detector flags them tied and fires a spurious shoot-out;
--     the new Buchholz-aware detector separates them -> NO group. (RED before
--     the migration, GREEN after.)
--
--   CASE B (schoch_then_ko): P1 and P2 are equal on points (22) AND Buchholz
--     (48) -> a genuine qualification-relevant tie -> exactly one group
--     {P1, P2} at start_rank 1. (No false-negative: the detector still fires
--     when truly tied.)
--
--   CASE C (round_robin_then_ko): same numbers as CASE A. The group-phase
--     branch is unchanged, so the point/kubb_diff-equal pair P1/P2 DOES fire
--     here -> one group {P1, P2}. Proves the branch is load-bearing and the
--     group-phase path is untouched.
--
-- pgTAP runs transiently in BEGIN..ROLLBACK; nothing is persisted.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

SET LOCAL ROLE postgres;

-- ---------------------------------------------------------------------
-- Helpers: deterministic ids per (case, role).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _dsb_tid(p_case text) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5b0c0000-0000-0000-0000-0000000000' ||
          CASE p_case WHEN 'A' THEN 'a1' WHEN 'B' THEN 'b1' ELSE 'c1' END)::uuid
$$;

-- Participant id from (case, idx). idx 0..4 -> P0..P4. The id tail is chosen so
-- a naive id/registered_at sort would NOT coincide with the correct order — the
-- criterion (Buchholz / kubb_diff) has to be load-bearing.
CREATE OR REPLACE FUNCTION _dsb_pid(p_case text, p_idx int) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('00000000-0000-0000-0b0b-' ||
          CASE p_case WHEN 'A' THEN 'a' WHEN 'B' THEN 'b' ELSE 'c' END ||
          lpad(p_idx::text, 11, '0'))::uuid
$$;

-- One match builder: a flat 'group' match, finalized, with a winner.
CREATE OR REPLACE FUNCTION _dsb_match(
  p_case text, p_a int, p_b int, p_sa int, p_sb int) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_tid uuid := _dsb_tid(p_case);
  v_a   uuid := _dsb_pid(p_case, p_a);
  v_b   uuid := _dsb_pid(p_case, p_b);
BEGIN
  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, winner_participant,
      final_score_a, final_score_b, stage_node_id, consensus_round)
    VALUES (gen_random_uuid(), v_tid, 1, 1, v_a, v_b, 'group', 'finalized',
            CASE WHEN p_sa >= p_sb THEN v_a ELSE v_b END,
            p_sa, p_sb, NULL, 1);
END;
$$;

-- Builds a 5-participant flat tournament of the given format and seeds the
-- common scaffolding (creator, users, participants). Matches are added by the
-- caller via _dsb_match.
CREATE OR REPLACE FUNCTION _dsb_setup(p_case text, p_format text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_tid uuid := _dsb_tid(p_case);
  v_t0  timestamptz := '2026-06-01 09:00:00+00';
  v_org uuid := ('5b0c0000-0000-0000-00aa-0000000000' ||
                 CASE p_case WHEN 'A' THEN 'a1' WHEN 'B' THEN 'b1' ELSE 'c1' END)::uuid;
  v_uid uuid;
  i     int;
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (v_org, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'org' || p_case || '@dsb.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, v_org, 'DSB ' || p_case, 1, 2, 32,
            p_format, 'ekc',
            jsonb_build_object('round_time_seconds', 1800), 'live', true);

  FOR i IN 0..4 LOOP
    v_uid := ('00000000-0000-0000-0a0a-' || p_case ||
              lpad(i::text, 11, '0'))::uuid;
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated',
              'p' || p_case || i || '@dsb.local', '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
    -- registered_at descending in idx so it does NOT coincide with rank order.
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, seed, registered_at)
      VALUES (_dsb_pid(p_case, i), v_tid, v_uid, 'confirmed', i + 1,
              v_t0 + ((9 - i) || ' seconds')::interval);
  END LOOP;
END;
$$;

-- ---------------------------------------------------------------------
-- CASE A — schoch_then_ko, points+kubb_diff equal, Buchholz differs.
--   P0 16:4 P3 | P0 16:5 P4 | P1 12:8 P3 | P1 12:8 P4 | P2 12:10 P0 | P2 12:6 P3
--   totals  P0=42 P1=24 P2=24 P3=18 P4=13
--   buchholz P0=34 P1=15 P2=44 P3=50 P4=38
--   kubb_diff P0=21 P1=8  P2=8  P3=-22 P4=-15
-- ---------------------------------------------------------------------
DO $caseA$
BEGIN
  PERFORM _dsb_setup('A', 'schoch_then_ko');
  PERFORM _dsb_match('A', 0, 3, 16, 4);
  PERFORM _dsb_match('A', 0, 4, 16, 5);
  PERFORM _dsb_match('A', 1, 3, 12, 8);
  PERFORM _dsb_match('A', 1, 4, 12, 8);
  PERFORM _dsb_match('A', 2, 0, 12, 10);
  PERFORM _dsb_match('A', 2, 3, 12, 6);
END;
$caseA$;

-- ---------------------------------------------------------------------
-- CASE B — schoch_then_ko, points AND Buchholz equal -> genuine tie.
--   P0 16:4 P3 | P0 16:4 P4 | P1 12:8 P3 | P1 10:12 P0 | P2 12:8 P4 | P2 10:12 P0
--   totals  P0=56 P1=22 P2=22 P3=12 P4=12
--   buchholz P0=40 P1=48 P2=48 P3=50 P4=50
-- ---------------------------------------------------------------------
DO $caseB$
BEGIN
  PERFORM _dsb_setup('B', 'schoch_then_ko');
  PERFORM _dsb_match('B', 0, 3, 16, 4);
  PERFORM _dsb_match('B', 0, 4, 16, 4);
  PERFORM _dsb_match('B', 1, 3, 12, 8);
  PERFORM _dsb_match('B', 1, 0, 10, 12);
  PERFORM _dsb_match('B', 2, 4, 12, 8);
  PERFORM _dsb_match('B', 2, 0, 10, 12);
END;
$caseB$;

-- ---------------------------------------------------------------------
-- CASE C — round_robin_then_ko, same numbers as CASE A. Group-phase branch
-- unchanged: P1/P2 are point+kubb_diff-equal -> fires.
-- ---------------------------------------------------------------------
DO $caseC$
BEGIN
  PERFORM _dsb_setup('C', 'round_robin_then_ko');
  PERFORM _dsb_match('C', 0, 3, 16, 4);
  PERFORM _dsb_match('C', 0, 4, 16, 5);
  PERFORM _dsb_match('C', 1, 3, 12, 8);
  PERFORM _dsb_match('C', 1, 4, 12, 8);
  PERFORM _dsb_match('C', 2, 0, 12, 10);
  PERFORM _dsb_match('C', 2, 3, 12, 6);
END;
$caseC$;

-- ── CASE A: Buchholz separates the pair -> no qualification-relevant group ──
SELECT is(
  (SELECT count(*)::int
     FROM public._tournament_detect_shootout_groups(_dsb_tid('A'), 2)),
  0,
  'schoch A: punktgleich + kubb-diff-gleich, aber Buchholz trennt -> kein Shoot-out'
);

-- ── CASE B: points and Buchholz equal -> exactly one group {P1, P2} ──
SELECT is(
  (SELECT count(*)::int
     FROM public._tournament_detect_shootout_groups(_dsb_tid('B'), 2)),
  1,
  'schoch B: punkt- UND buchholz-gleich an der Cut-Linie -> ein Shoot-out'
);
SELECT is(
  (SELECT start_rank
     FROM public._tournament_detect_shootout_groups(_dsb_tid('B'), 2)),
  1,
  'schoch B: Gruppe beginnt auf Rang 1 (straddle q=2)'
);
SELECT ok(
  (SELECT participant_ids @> ARRAY[_dsb_pid('B',1), _dsb_pid('B',2)]
      AND participant_ids <@ ARRAY[_dsb_pid('B',1), _dsb_pid('B',2)]
     FROM public._tournament_detect_shootout_groups(_dsb_tid('B'), 2)),
  'schoch B: getied sind genau P1 und P2'
);

-- ── CASE C: group_phase branch unchanged -> the same pair DOES fire ──
SELECT is(
  (SELECT count(*)::int
     FROM public._tournament_detect_shootout_groups(_dsb_tid('C'), 2)),
  1,
  'round_robin C: punkt+kubb-diff-gleicher Run feuert (Gruppenphase unverändert)'
);
SELECT ok(
  (SELECT participant_ids @> ARRAY[_dsb_pid('C',1), _dsb_pid('C',2)]
      AND participant_ids <@ ARRAY[_dsb_pid('C',1), _dsb_pid('C',2)]
     FROM public._tournament_detect_shootout_groups(_dsb_tid('C'), 2)),
  'round_robin C: getied sind genau P1 und P2 (kein Buchholz im Schlüssel)'
);

-- ── Audit: the live body branches on the schoch/swiss format and the §5
-- Buchholz tied-key sits behind that branch (group-phase stays kubb_diff). ──
SELECT ok(
  regexp_replace(lower(pg_get_functiondef(
      'public._tournament_detect_shootout_groups(uuid,integer)'::regprocedure)),
      '\s+', ' ', 'g')
    LIKE '%schoch_then_ko%' ESCAPE '!',
  'audit: detector verzweigt nach Vorrunden-Typ (schoch_then_ko)'
);

SELECT * FROM finish();
ROLLBACK;
