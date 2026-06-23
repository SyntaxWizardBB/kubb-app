-- Organizer override writes per-set proposal rows (Maengel #5).
--
-- Migration 20261314000000_override_writes_proposal_rows makes
-- tournament_organizer_override persist the same per-set consensus rows the
-- player path writes, so kubb_diff + wins flow into the standings/ranking RPCs
-- for overridden matches too. Before the fix an overridden match had no
-- proposal rows: the DISTINCT ON (match_id, set_number) aggregate in
-- tournament_pool_standings / tournament_stage_ranking / _tournament_schoch_buchholz
-- found nothing and collapsed kubb_diff/wins to 0.
--
-- Cases:
--   1. Override on an awaiting_results match writes exactly one proposal row
--      with the organizer as submitter; final_score stays consistent with
--      _tournament_compute_ekc.
--   2. Ranking: A wins by override with base margin +5, B wins by consensus
--      with base margin +1, both tied on total_points -> stage_ranking and
--      pool_standings rank A before B on kubb_diff.
--   3. classic scoring: a match decided by override gives the winner
--      total_points > 0 (set wins), not 0.
--   4. Double override by the same organizer (different score) -> no duplicate
--      row (ON CONFLICT) and stale rows past the new set count are gone.
--   5. Override out of 'disputed' (player consensus rows exist) -> after the
--      override only organizer rows remain, no mixing.
--
-- pgTAP runs transiently in BEGIN..ROLLBACK; nothing is persisted.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(16);

-- ---------------------------------------------------------------------
-- Auth-switch helpers (analog score_rpc_idempotency_test).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _ovk_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _ovk_as_postgres() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

CREATE OR REPLACE FUNCTION _ovk_count(p_match uuid) RETURNS int
LANGUAGE sql AS $$
  SELECT count(*)::int FROM public.tournament_set_score_proposals
    WHERE match_id = p_match;
$$;

-- =====================================================================
-- Fixture: one ekc round_robin tournament, 3 confirmed participants, full
-- round-robin in a group_phase stage. P1 (override) and P2 (consensus) tie
-- on total_points; P1 has the higher kubb_diff.
--
--   M13  P1 vs P3   override   6:1 (A wins)   base margin +5
--   M23  P2 vs P3   consensus  6:5 (A wins)   base margin +1
--   M12  P1 vs P2   consensus  5:5 (none)     base margin  0
--
--   EKC final_score (basekubbs + 3 per set win):
--     P1: M13 9, M12 5  -> total 14   kubb_diff: (6-1)+(5-5) = +5
--     P2: M23 9, M12 5  -> total 14   kubb_diff: (6-5)+(5-5) = +1
--     P3: M13 1, M23 5  -> total 6    kubb_diff: -6
-- =====================================================================
CREATE OR REPLACE FUNCTION _ovk_tid()  RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT 'a0c0a0c0-0000-0000-0000-0000000000e1'::uuid $$;
CREATE OR REPLACE FUNCTION _ovk_org()  RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT 'a0c0a0c0-0000-0000-0000-0000000000c1'::uuid $$;

-- Participant ids chosen so a naive id-sort would put P2 BEFORE P1 (P2 id is
-- lexically smaller). kubb_diff must override that and rank P1 first.
CREATE OR REPLACE FUNCTION _ovk_p1() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-0000-0c0c-0000000000a2'::uuid $$;
CREATE OR REPLACE FUNCTION _ovk_p2() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-0000-0c0c-0000000000a1'::uuid $$;
CREATE OR REPLACE FUNCTION _ovk_p3() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-0000-0c0c-0000000000a9'::uuid $$;

CREATE OR REPLACE FUNCTION _ovk_m13() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-0000-0d0d-000000000013'::uuid $$;
CREATE OR REPLACE FUNCTION _ovk_m23() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-0000-0d0d-000000000023'::uuid $$;
CREATE OR REPLACE FUNCTION _ovk_m12() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-0000-0d0d-000000000012'::uuid $$;

DO $fixture$
DECLARE
  v_tid uuid := _ovk_tid();
  v_t0  timestamptz := '2026-06-01 09:00:00+00';
  v_u1  uuid := '00000000-0000-0000-0b0b-000000000001'::uuid;
  v_u2  uuid := '00000000-0000-0000-0b0b-000000000002'::uuid;
  v_u3  uuid := '00000000-0000-0000-0b0b-000000000003'::uuid;
  v_sub uuid := '00000000-0000-0000-0b0b-0000000000ff'::uuid;  -- consensus submitter
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (_ovk_org(), '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'org@ovk.local', '', now(), now(), now()),
    (v_sub, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'sub@ovk.local', '', now(), now(), now()),
    (v_u1, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'p1@ovk.local', '', now(), now(), now()),
    (v_u2, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'p2@ovk.local', '', now(), now(), now()),
    (v_u3, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'p3@ovk.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, _ovk_org(), 'Override Kubb-Diff', 1, 2, 32,
            'round_robin', 'ekc',
            jsonb_build_object('round_time_seconds', 1800), 'live', true);

  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tid, 'gp1', 'group_phase',
            '{}'::jsonb, 'manual', 'active');

  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status, seed, group_label,
      registered_at)
  VALUES
    (_ovk_p1(), v_tid, v_u1, 'confirmed', 1, 'A', v_t0 + interval '3 seconds'),
    (_ovk_p2(), v_tid, v_u2, 'confirmed', 2, 'A', v_t0 + interval '1 seconds'),
    (_ovk_p3(), v_tid, v_u3, 'confirmed', 3, 'A', v_t0 + interval '2 seconds');

  -- M13 stays awaiting_results: the override under test stamps it. M23 + M12
  -- are pre-finalized by the consensus path (final_score + proposal rows
  -- inserted directly, the consensus RPC is not under test here).
  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, winner_participant,
      final_score_a, final_score_b, group_label, stage_node_id, consensus_round)
  VALUES
    (_ovk_m13(), v_tid, 1, 1, _ovk_p1(), _ovk_p3(), 'group', 'awaiting_results',
       NULL, NULL, NULL, 'A', 'gp1', 1),
    (_ovk_m23(), v_tid, 1, 2, _ovk_p2(), _ovk_p3(), 'group', 'finalized',
       _ovk_p2(), 9, 5, 'A', 'gp1', 1),
    (_ovk_m12(), v_tid, 1, 3, _ovk_p1(), _ovk_p2(), 'group', 'finalized',
       NULL, 5, 5, 'A', 'gp1', 1);

  -- Consensus proposal rows for the two finalized matches only.
  INSERT INTO public.tournament_set_score_proposals(
      id, match_id, consensus_round, set_number, submitter_user_id,
      basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner,
      proposed_at, set_king_outcome)
  VALUES
    (gen_random_uuid(), _ovk_m23(), 1, 1, v_sub, 6, 5, 'A',    now(), 'missed'),
    (gen_random_uuid(), _ovk_m12(), 1, 1, v_sub, 5, 5, 'none', now(), 'missed');
END;
$fixture$;

-- ---------------------------------------------------------------------
-- Run the override on M13 as the organizer: P1 6 : 1 P3, A wins.
-- ---------------------------------------------------------------------
DO $$
BEGIN
  PERFORM _ovk_as(_ovk_org());
  PERFORM public.tournament_organizer_override(
    _ovk_m13(),
    '[{"basekubbs_a":6,"basekubbs_b":1,"winner":"A"}]'::jsonb,
    'on-site result');
  PERFORM _ovk_as_postgres();
END $$;

-- ── Case 1: exactly one proposal row, organizer is submitter ─────────
SELECT is( _ovk_count(_ovk_m13()), 1,
  'Case 1: Override schreibt genau eine Proposal-Zeile' );

SELECT row_eq(
  $$ SELECT consensus_round, set_number, submitter_user_id,
            basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner
       FROM public.tournament_set_score_proposals
      WHERE match_id = _ovk_m13() $$,
  ROW(1::smallint, 1::smallint, _ovk_org(), 6::smallint, 1::smallint, 'A'::text),
  'Case 1: Proposal-Zeile traegt round=1, set=1, Organizer, 6:1, set_winner A' );

-- final_score on the match row stays consistent with _tournament_compute_ekc:
-- A 6 + 3 (set win) = 9, B 1.
SELECT row_eq(
  $$ SELECT status, winner_participant, final_score_a, final_score_b
       FROM public.tournament_matches WHERE id = _ovk_m13() $$,
  ROW('overridden'::text, _ovk_p1(), 9, 1),
  'Case 1: Match-Stamp unveraendert konsistent zu _tournament_compute_ekc' );

SELECT is(
  (SELECT final_score_a FROM public.tournament_matches WHERE id = _ovk_m13()),
  (SELECT (public._tournament_compute_ekc(
      '[{"basekubbs_a":6,"basekubbs_b":1,"winner":"A"}]'::jsonb) ->> 'final_score_a')::int),
  'Case 1: final_score_a stimmt mit _tournament_compute_ekc ueberein' );

-- ── Case 2: stage_ranking ranks A (override) before B (consensus) ────
-- Both tie on total_points (14); P1 kubb_diff +5 > P2 +1. Without proposal
-- rows for M13 P1 would have kubb_diff +0 and lose the tiebreak (the bug).
CREATE OR REPLACE VIEW _ovk_sr AS
  SELECT * FROM public.tournament_stage_ranking(_ovk_tid(), 'gp1');

SELECT is( (SELECT count(*) FROM _ovk_sr)::int, 3,
  'Case 2: stage_ranking liefert 3 Raenge' );

SELECT is(
  (SELECT participant_id FROM _ovk_sr WHERE rank = 1), _ovk_p1(),
  'Case 2: Rang 1 = P1 (Override-Match, hoehere Kubb-Differenz)' );

SELECT cmp_ok(
  (SELECT rank FROM _ovk_sr WHERE participant_id = _ovk_p1())::int, '<',
  (SELECT rank FROM _ovk_sr WHERE participant_id = _ovk_p2())::int,
  'Case 2: P1 vor P2 trotz Punktegleichstand und kleinerer P1-id' );

-- pool_standings is SECURITY DEFINER with an auth + visibility gate, so the
-- snapshot is taken as the organizer and stashed in a temp table to assert on.
-- The stats array is already ordered by rank (total_points -> kubb_diff).
DO $$
DECLARE v_json jsonb;
BEGIN
  PERFORM _ovk_as(_ovk_org());
  v_json := public.tournament_pool_standings(_ovk_tid());
  PERFORM _ovk_as_postgres();
  CREATE TEMP TABLE _ovk_ps ON COMMIT DROP AS SELECT v_json AS j;
END $$;

SELECT is(
  ( SELECT (entry ->> 'participant_id')
      FROM jsonb_array_elements(
             (SELECT j FROM _ovk_ps) -> 'groups' -> 0 -> 'stats'
           ) WITH ORDINALITY AS t(entry, ord)
     WHERE ord = 1 ),
  _ovk_p1()::text,
  'Case 2: pool_standings rankt P1 zuoberst (kubb_diff aus Override-Zeile)' );

-- The override participant now carries a non-zero kubb difference
-- (kubbs_scored - kubbs_conceded) in the standings; it was 0 before the fix.
SELECT cmp_ok(
  ( SELECT (entry ->> 'kubbs_scored')::int - (entry ->> 'kubbs_conceded')::int
      FROM jsonb_array_elements(
             (SELECT j FROM _ovk_ps) -> 'groups' -> 0 -> 'stats'
           ) AS entry
     WHERE (entry ->> 'participant_id') = _ovk_p1()::text ),
  '>', 0,
  'Case 2: P1 Kubb-Differenz > 0 in pool_standings (war 0 vor dem Fix)' );

-- =====================================================================
-- Case 3: classic scoring. A separate tournament, a single group match
-- decided by override. The winner must score total_points > 0 (set wins),
-- not 0 — the classic standings derive set wins from the proposal rows.
-- =====================================================================
DO $classic$
DECLARE
  v_tid uuid := 'c1a55c1a-0000-0000-0000-0000000000e1'::uuid;
  v_org uuid := 'c1a55c1a-0000-0000-0000-0000000000c1'::uuid;
  v_pa  uuid := '00000000-0000-0000-0e0e-0000000000a1'::uuid;
  v_pb  uuid := '00000000-0000-0000-0e0e-0000000000b1'::uuid;
  v_ua  uuid := '00000000-0000-0000-0f0f-000000000001'::uuid;
  v_ub  uuid := '00000000-0000-0000-0f0f-000000000002'::uuid;
  v_m   uuid := '00000000-0000-0000-0f0f-0000000000ab'::uuid;
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_org, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'org@cls.local', '', now(), now(), now()),
    (v_ua, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'a@cls.local', '', now(), now(), now()),
    (v_ub, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'b@cls.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, v_org, 'Override Classic', 1, 2, 32,
            'round_robin', 'classic',
            jsonb_build_object('round_time_seconds', 1800), 'live', true);

  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status, seed, group_label)
  VALUES
    (v_pa, v_tid, v_ua, 'confirmed', 1, 'A'),
    (v_pb, v_tid, v_ub, 'confirmed', 2, 'A');

  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, group_label, consensus_round)
    VALUES (v_m, v_tid, 1, 1, v_pa, v_pb, 'group', 'awaiting_results', 'A', 1);

  PERFORM _ovk_as(v_org);
  PERFORM public.tournament_organizer_override(
    v_m,
    '[{"basekubbs_a":6,"basekubbs_b":2,"winner":"A"}]'::jsonb,
    'classic on-site');
  -- Snapshot standings while still authenticated as the organizer.
  CREATE TEMP TABLE _ovk_cls ON COMMIT DROP AS
    SELECT v_tid AS tid, v_pa AS pa, v_pb AS pb, v_m AS m,
           public.tournament_pool_standings(v_tid) AS j;
  PERFORM _ovk_as_postgres();
END $classic$;

SELECT is( _ovk_count((SELECT m FROM _ovk_cls)), 1,
  'Case 3: classic-Override schreibt eine Proposal-Zeile' );

-- classic total_points = sets won. Winner A has 1 set -> > 0.
SELECT cmp_ok(
  ( SELECT (entry ->> 'total_points')::int
      FROM jsonb_array_elements(
             (SELECT j FROM _ovk_cls) -> 'groups' -> 0 -> 'stats'
           ) AS entry
     WHERE (entry ->> 'participant_id') = (SELECT pa::text FROM _ovk_cls) ),
  '>', 0,
  'Case 3: classic-Gewinner hat total_points > 0 (Set-Wins aus Override-Zeile)' );

-- =====================================================================
-- Case 4: double override by the same organizer (different score, fewer
-- sets) -> no duplicate row, stale rows past the new set count are gone.
-- First override writes 3 sets, second writes 1 set.
-- =====================================================================
DO $dbl$
DECLARE
  v_tid uuid := 'd0b1e000-0000-0000-0000-0000000000e1'::uuid;
  v_org uuid := 'd0b1e000-0000-0000-0000-0000000000c1'::uuid;
  v_pa  uuid := '00000000-0000-0000-1a1a-0000000000a1'::uuid;
  v_pb  uuid := '00000000-0000-0000-1a1a-0000000000b1'::uuid;
  v_ua  uuid := '00000000-0000-0000-1b1b-000000000001'::uuid;
  v_ub  uuid := '00000000-0000-0000-1b1b-000000000002'::uuid;
  v_m   uuid := '00000000-0000-0000-1b1b-0000000000ab'::uuid;
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_org, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'org@dbl.local', '', now(), now(), now()),
    (v_ua, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'a@dbl.local', '', now(), now(), now()),
    (v_ub, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'b@dbl.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, v_org, 'Override Double', 1, 2, 32,
            'round_robin', 'ekc',
            jsonb_build_object('round_time_seconds', 1800), 'live', true);

  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status, seed, group_label)
  VALUES
    (v_pa, v_tid, v_ua, 'confirmed', 1, 'A'),
    (v_pb, v_tid, v_ub, 'confirmed', 2, 'A');

  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, group_label, consensus_round)
    VALUES (v_m, v_tid, 1, 1, v_pa, v_pb, 'group', 'awaiting_results', 'A', 1);

  PERFORM _ovk_as(v_org);
  -- First override: 3 sets, A wins 2:1.
  PERFORM public.tournament_organizer_override(
    v_m,
    '[{"basekubbs_a":6,"basekubbs_b":2,"winner":"A"},
      {"basekubbs_a":3,"basekubbs_b":6,"winner":"B"},
      {"basekubbs_a":6,"basekubbs_b":4,"winner":"A"}]'::jsonb,
    'first');
  -- Re-open the match so a corrected override can run again. The override
  -- gate rejects an already-overridden match; resetting to awaiting_results
  -- mirrors a re-opened result and exercises the ON CONFLICT / stale-cleanup
  -- path for the same organizer submitting a different (shorter) score.
  PERFORM _ovk_as_postgres();
  UPDATE public.tournament_matches SET status = 'awaiting_results' WHERE id = v_m;
  PERFORM _ovk_as(v_org);
  -- Second override (corrected): single set, A wins.
  PERFORM public.tournament_organizer_override(
    v_m,
    '[{"basekubbs_a":6,"basekubbs_b":0,"winner":"A"}]'::jsonb,
    'corrected');
  PERFORM _ovk_as_postgres();

  CREATE TEMP TABLE _ovk_dbl ON COMMIT DROP AS SELECT v_m AS m;
END $dbl$;

SELECT is( _ovk_count((SELECT m FROM _ovk_dbl)), 1,
  'Case 4: Doppel-Override hinterlaesst genau eine Zeile (kein Stale-Rest)' );

SELECT row_eq(
  $$ SELECT set_number, basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner
       FROM public.tournament_set_score_proposals
      WHERE match_id = (SELECT m FROM _ovk_dbl) $$,
  ROW(1::smallint, 6::smallint, 0::smallint, 'A'::text),
  'Case 4: verbleibende Zeile traegt den korrigierten Score (6:0)' );

-- =====================================================================
-- Case 5: override out of 'disputed'. Two players submitted conflicting
-- consensus rows on the same slot; after the override only organizer rows
-- remain (stale-cleanup), no player/organizer mix.
-- =====================================================================
DO $disp$
DECLARE
  v_tid uuid := 'd15b0000-0000-0000-0000-0000000000e1'::uuid;
  v_org uuid := 'd15b0000-0000-0000-0000-0000000000c1'::uuid;
  v_pa  uuid := '00000000-0000-0000-2a2a-0000000000a1'::uuid;
  v_pb  uuid := '00000000-0000-0000-2a2a-0000000000b1'::uuid;
  v_ua  uuid := '00000000-0000-0000-2b2b-000000000001'::uuid;
  v_ub  uuid := '00000000-0000-0000-2b2b-000000000002'::uuid;
  v_m   uuid := '00000000-0000-0000-2b2b-0000000000ab'::uuid;
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
  VALUES
    (v_org, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'org@dsp.local', '', now(), now(), now()),
    (v_ua, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'a@dsp.local', '', now(), now(), now()),
    (v_ub, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', 'b@dsp.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, v_org, 'Override Disputed', 1, 2, 32,
            'round_robin', 'ekc',
            jsonb_build_object('round_time_seconds', 1800), 'live', true);

  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status, seed, group_label)
  VALUES
    (v_pa, v_tid, v_ua, 'confirmed', 1, 'A'),
    (v_pb, v_tid, v_ub, 'confirmed', 2, 'A');

  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, group_label, consensus_round)
    VALUES (v_m, v_tid, 1, 1, v_pa, v_pb, 'group', 'disputed', 'A', 1);

  -- Two conflicting player consensus rows on the same slot.
  INSERT INTO public.tournament_set_score_proposals(
      id, match_id, consensus_round, set_number, submitter_user_id,
      basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner,
      proposed_at, set_king_outcome)
  VALUES
    (gen_random_uuid(), v_m, 1, 1, v_ua, 6, 2, 'A', now(), 'missed'),
    (gen_random_uuid(), v_m, 1, 1, v_ub, 2, 6, 'B', now(), 'missed');

  PERFORM _ovk_as(v_org);
  PERFORM public.tournament_organizer_override(
    v_m,
    '[{"basekubbs_a":6,"basekubbs_b":3,"winner":"A"}]'::jsonb,
    'resolve dispute');
  PERFORM _ovk_as_postgres();

  CREATE TEMP TABLE _ovk_disp ON COMMIT DROP AS
    SELECT v_m AS m, v_org AS org;
END $disp$;

SELECT is( _ovk_count((SELECT m FROM _ovk_disp)), 1,
  'Case 5: nach Override aus disputed bleibt genau eine Zeile' );

SELECT is(
  (SELECT count(DISTINCT submitter_user_id)::int
     FROM public.tournament_set_score_proposals
    WHERE match_id = (SELECT m FROM _ovk_disp)),
  1,
  'Case 5: nur ein Submitter uebrig (keine Spieler/Organizer-Mischung)' );

SELECT is(
  (SELECT submitter_user_id FROM public.tournament_set_score_proposals
    WHERE match_id = (SELECT m FROM _ovk_disp)),
  (SELECT org FROM _ovk_disp),
  'Case 5: verbleibende Zeile gehoert dem Organizer' );

SELECT * FROM finish();
ROLLBACK;
