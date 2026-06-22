-- Cut vs detector §5 Buchholz consistency — flat schoch_then_ko (M2-T09).
--
-- Backs migration 20261297000000: ranking, shoot-out detector and the KO cut
-- (tournament_start_ko_phase) share ONE §5 Buchholz source. The bug this guards
-- against: the detector separated a point-equal pair by Buchholz (so it fired no
-- shoot-out) while the KO cut ordered the SAME pair by kubb_difference — so the
-- kubb_diff-higher player qualified silently even though Buchholz puts the other
-- one ahead. Detector and cut disagreed; no test caught it. This is that test.
--
-- Two flat schoch_then_ko tournaments, qualifier_count = 2, no group_label
-- (flat preliminary), so the C6 default-seed CTE in tournament_start_ko_phase is
-- the cut. In both, a points-equal pair P1/P2 sits at ranks 2 and 3 straddling
-- the q = 2 line, with Buchholz(P1) > Buchholz(P2) but kubb_diff(P2) > kubb_diff
-- (P1). So:
--   (i)  the detector reports NO shoot-out group (Buchholz separates the pair),
--   (ii) the cut qualifies EXACTLY P1 (Buchholz-higher), NOT P2 (kubb_diff- /
--        final_score-higher).
--
--   CASE EKC (scoring = ekc): total_points / Buchholz are final-score based. The
--     old cut (points -> kubb_difference) would have seeded P2; the helper-fed
--     cut seeds P1.
--   CASE CLASSIC (scoring = classic): total_points / Buchholz are set-win based.
--     P2 is given a massively higher final_score, so the old final-score-shaped
--     cut would have seeded P2; the scoring-aware helper ranks by set wins ->
--     set-win Buchholz and seeds P1. This proves the scoring-aware convergence:
--     the detector and the cut both read the helper, so classic Schoch agrees.
--
-- pgTAP runs transiently in BEGIN..ROLLBACK; nothing is persisted.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(8);

SET LOCAL ROLE postgres;

-- ---------------------------------------------------------------------
-- Deterministic ids per (case, role). The participant id tail is chosen so a
-- naive id-sort does NOT coincide with the correct order — Buchholz has to be
-- the load-bearing criterion, not the id/registered_at tail.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _cbc_tid(p_case text) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5b0c0000-0000-0000-0000-00000000cb' ||
          CASE p_case WHEN 'EKC' THEN 'e1' ELSE 'c1' END)::uuid
$$;
CREATE OR REPLACE FUNCTION _cbc_org(p_case text) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('5b0c0000-0000-0000-00aa-00000000cb' ||
          CASE p_case WHEN 'EKC' THEN 'e1' ELSE 'c1' END)::uuid
$$;
-- idx 0..5 -> seed 1..6, registered_at descending in idx (so a registered_at
-- sort does not match rank order either). pid tail = (5 - idx).
CREATE OR REPLACE FUNCTION _cbc_pid(p_case text, p_idx int) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('00000000-0000-0000-0b0b-' ||
          CASE p_case WHEN 'EKC' THEN 'e' ELSE 'c' END ||
          lpad((5 - p_idx)::text, 11, '0'))::uuid
$$;
CREATE OR REPLACE FUNCTION _cbc_uid(p_case text, p_idx int) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('00000000-0000-0000-0a0a-' ||
          CASE p_case WHEN 'EKC' THEN 'e' ELSE 'c' END ||
          lpad(p_idx::text, 11, '0'))::uuid
$$;

-- 6-participant flat schoch_then_ko, qualifier_count = 2, auto seeding.
CREATE OR REPLACE FUNCTION _cbc_setup(p_case text, p_scoring text) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_tid uuid := _cbc_tid(p_case);
  v_org uuid := _cbc_org(p_case);
  v_t0  timestamptz := '2026-06-01 09:00:00+00';
  v_uid uuid;
  i     int;
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (v_org, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'org' || p_case || '@cbc.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public,
      bracket_type, ko_config)
    VALUES (v_tid, v_org, 'CBC ' || p_case, 1, 2, 32,
            'schoch_then_ko', p_scoring,
            jsonb_build_object('round_time_seconds', 1800), 'live', true,
            'single_elimination',
            jsonb_build_object('qualifier_count', 2, 'seeding_mode', 'auto'));

  FOR i IN 0..5 LOOP
    v_uid := _cbc_uid(p_case, i);
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated',
              'p' || p_case || i || '@cbc.local', '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, seed, registered_at)
      VALUES (_cbc_pid(p_case, i), v_tid, v_uid, 'confirmed', i + 1,
              v_t0 + ((9 - i) || ' seconds')::interval);
  END LOOP;
END;
$$;

-- EKC match: final scores decide total_points / kubb_diff directly.
CREATE OR REPLACE FUNCTION _cbc_match_ekc(
  p_case text, p_a int, p_b int, p_sa int, p_sb int) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_a uuid := _cbc_pid(p_case, p_a);
  v_b uuid := _cbc_pid(p_case, p_b);
BEGIN
  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, winner_participant,
      final_score_a, final_score_b, stage_node_id, consensus_round)
    VALUES (gen_random_uuid(), _cbc_tid(p_case), 1, 1, v_a, v_b,
            'group', 'finalized',
            CASE WHEN p_sa >= p_sb THEN v_a ELSE v_b END,
            p_sa, p_sb, NULL, 1);
END;
$$;

-- Classic match: p_wa/p_wb set wins (modelled as consensus set rows). The
-- final_score is set deliberately misleading so the classic ranking must use
-- set wins, not final scores.
CREATE OR REPLACE FUNCTION _cbc_match_classic(
  p_case text, p_a int, p_b int, p_wa int, p_wb int,
  p_fsa int, p_fsb int) RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_a   uuid := _cbc_pid(p_case, p_a);
  v_b   uuid := _cbc_pid(p_case, p_b);
  v_mid uuid := gen_random_uuid();
  v_sub uuid := _cbc_uid(p_case, p_a);
  s     int;
BEGIN
  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, winner_participant,
      final_score_a, final_score_b, stage_node_id, consensus_round)
    VALUES (v_mid, _cbc_tid(p_case), 1, 1, v_a, v_b,
            'group', 'finalized',
            CASE WHEN p_wa >= p_wb THEN v_a ELSE v_b END,
            p_fsa, p_fsb, NULL, 1);
  FOR s IN 1 .. p_wa LOOP
    INSERT INTO public.tournament_set_score_proposals(
        match_id, consensus_round, set_number, submitter_user_id,
        basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner,
        proposed_at, set_king_outcome)
      VALUES (v_mid, 1, s, v_sub, 6, 0, 'A', now(), 'hit_by');
  END LOOP;
  FOR s IN 1 .. p_wb LOOP
    INSERT INTO public.tournament_set_score_proposals(
        match_id, consensus_round, set_number, submitter_user_id,
        basekubbs_knocked_by_a, basekubbs_knocked_by_b, set_winner,
        proposed_at, set_king_outcome)
      VALUES (v_mid, 1, p_wa + s, v_sub, 0, 6, 'B', now(), 'hit_by');
  END LOOP;
END;
$$;

-- Reads the qualifier seed list the cut wrote into the ko_phase_started audit
-- event (the same list that feeds the bracket builder).
CREATE OR REPLACE FUNCTION _cbc_seeds(p_case text) RETURNS uuid[]
LANGUAGE sql STABLE AS $$
  SELECT array_agg((e #>> '{}')::uuid ORDER BY ord)
    FROM public.tournament_audit_events a
    CROSS JOIN LATERAL jsonb_array_elements(a.payload -> 'seeds')
         WITH ORDINALITY AS t(e, ord)
   WHERE a.tournament_id = _cbc_tid(p_case)
     AND a.kind = 'ko_phase_started';
$$;

-- ---------------------------------------------------------------------
-- CASE EKC: P0 leader; P1/P2 tied at 26 points; Buchholz(P1)=63 >
-- Buchholz(P2)=50; kubb_diff(P1)=-8 < kubb_diff(P2)=+1. P3=25, P4=24, P5=3.
-- ---------------------------------------------------------------------
DO $ekc$
BEGIN
  PERFORM _cbc_setup('EKC', 'ekc');
  PERFORM _cbc_match_ekc('EKC', 0, 1, 16, 5);
  PERFORM _cbc_match_ekc('EKC', 0, 2, 16, 5);
  PERFORM _cbc_match_ekc('EKC', 0, 3, 16, 8);
  PERFORM _cbc_match_ekc('EKC', 1, 3, 12, 11);
  PERFORM _cbc_match_ekc('EKC', 1, 4, 9, 7);
  PERFORM _cbc_match_ekc('EKC', 2, 5, 16, 0);
  PERFORM _cbc_match_ekc('EKC', 2, 4, 5, 9);
  PERFORM _cbc_match_ekc('EKC', 3, 5, 6, 2);
  PERFORM _cbc_match_ekc('EKC', 4, 5, 8, 1);
END;
$ekc$;

-- ---------------------------------------------------------------------
-- CASE CLASSIC: set-win scoring. P0 leader (2-0 everywhere); P1/P2 tied at 4
-- set wins; Buchholz(P1)=8 > Buchholz(P2)=6. P2 is handed huge final scores so
-- the OLD final-score cut would have seeded P2 — the scoring-aware helper does
-- not. P3=3, P4=2, P5=0 set wins.
-- ---------------------------------------------------------------------
DO $classic$
BEGIN
  PERFORM _cbc_setup('CLA', 'classic');
  PERFORM _cbc_match_classic('CLA', 0, 1, 2, 0, 99, 0);
  PERFORM _cbc_match_classic('CLA', 0, 2, 2, 0, 99, 0);
  PERFORM _cbc_match_classic('CLA', 0, 3, 2, 0, 99, 0);
  PERFORM _cbc_match_classic('CLA', 1, 3, 2, 1, 5, 5);
  PERFORM _cbc_match_classic('CLA', 1, 4, 2, 0, 5, 5);
  PERFORM _cbc_match_classic('CLA', 2, 5, 2, 0, 99, 0);
  PERFORM _cbc_match_classic('CLA', 2, 4, 2, 0, 99, 0);
  PERFORM _cbc_match_classic('CLA', 3, 5, 2, 0, 5, 5);
  PERFORM _cbc_match_classic('CLA', 4, 5, 2, 0, 5, 5);
END;
$classic$;

-- Start the KO phase as the creator for both tournaments. The auto-seed gate,
-- the phase-complete guard and the SHOOTOUT-GATE (detector) all pass, so the
-- cut runs and writes the seed list.
SELECT set_config('request.jwt.claims',
  jsonb_build_object('sub', _cbc_org('EKC')::text, 'role', 'authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
SELECT public.tournament_start_ko_phase(_cbc_tid('EKC'),
  jsonb_build_object('qualifier_count', 2, 'seeding_mode', 'auto'));
SELECT set_config('request.jwt.claims',
  jsonb_build_object('sub', _cbc_org('CLA')::text, 'role', 'authenticated')::text, true);
SELECT public.tournament_start_ko_phase(_cbc_tid('CLA'),
  jsonb_build_object('qualifier_count', 2, 'seeding_mode', 'auto'));
SELECT set_config('role', 'postgres', true);

-- ── CASE EKC ──────────────────────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int
     FROM public._tournament_detect_shootout_groups(_cbc_tid('EKC'), 2)),
  0,
  'ekc: Detektor meldet keine Gruppe — Buchholz trennt das punktgleiche Paar'
);
SELECT ok(
  _cbc_seeds('EKC') @> ARRAY[_cbc_pid('EKC', 1)],
  'ekc: Cut qualifiziert den buchholz-höheren Spieler P1'
);
SELECT ok(
  NOT (_cbc_seeds('EKC') @> ARRAY[_cbc_pid('EKC', 2)]),
  'ekc: Cut qualifiziert NICHT den kubb-diff-höheren P2 (alter Pfad hätte P2)'
);
SELECT is(
  array_length(_cbc_seeds('EKC'), 1),
  2,
  'ekc: genau 2 Qualifikanten (P0 + P1)'
);

-- ── CASE CLASSIC ──────────────────────────────────────────────────────
SELECT is(
  (SELECT count(*)::int
     FROM public._tournament_detect_shootout_groups(_cbc_tid('CLA'), 2)),
  0,
  'classic: Detektor meldet keine Gruppe — Satzgewinn-Buchholz trennt das Paar'
);
SELECT ok(
  _cbc_seeds('CLA') @> ARRAY[_cbc_pid('CLA', 1)],
  'classic: Cut qualifiziert den buchholz-höheren P1 (scoring-aware Satzgewinne)'
);
SELECT ok(
  NOT (_cbc_seeds('CLA') @> ARRAY[_cbc_pid('CLA', 2)]),
  'classic: Cut qualifiziert NICHT P2 trotz weit höherer Endpunkte (alter Pfad)'
);
SELECT is(
  array_length(_cbc_seeds('CLA'), 1),
  2,
  'classic: genau 2 Qualifikanten (P0 + P1)'
);

SELECT * FROM finish();
ROLLBACK;
