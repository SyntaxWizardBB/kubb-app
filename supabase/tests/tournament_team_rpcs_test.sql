-- RPC-Integrationstests fuer Tournament-Team-RPCs (TASK-M3.2-T8).
--
-- Deckt die Pfade aus den parallelen Wave-6-Migrationen ab:
--   * tournament_register_team / tournament_roster_replace /
--     tournament_roster_list           (T6, 20260615000006-naehe)
--   * tournament_propose_set_scores    (T7-Patch: Team-Member-Validierung
--                                        zusaetzlich zum M1 user_id-Pfad)
--
-- Auth-Kontext wie in tournament_ko_rpcs.sql ueber
-- `SET LOCAL request.jwt.claims` umgeschaltet (Supabase-Standard,
-- pgtap-feasibility.md §Option A). Direkt-Inserts in auth.users +
-- public.teams legen die FK-Pflicht-Rows an; produktiv liefen die
-- Teams ueber team_create (M3.1-T4).
--
-- Errcodes-Konvention der Migration:
--   * 42501 — Auth / Pool-Mitgliedschaft
--   * 23P01 — BR-5 Trigger (Cross-Team innerhalb desselben Turniers)
--   * P0001 — Domain-Tokens: MIN_ONE_REGISTERED, ROSTER_LOCKED,
--             ROSTER_LOCKED_DURING_MATCH

BEGIN;

SELECT plan(15);

-- ---------------------------------------------------------------------
-- Helpers: Auth-Switch + Fixture-Builder.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _tt_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _tt_mk_user(p_uid uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
    VALUES (p_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'tt-' || p_uid::text || '@test.local',
            '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;
  RETURN p_uid;
END;
$$;

-- Team + Creator-Membership + ein Gast (FK-stabil fuer Roster-Slots).
CREATE OR REPLACE FUNCTION _tt_mk_team(p_creator uuid)
RETURNS TABLE(team_id uuid, guest_id uuid)
LANGUAGE plpgsql AS $$
DECLARE
  v_team uuid := gen_random_uuid();
  v_guest uuid := gen_random_uuid();
BEGIN
  PERFORM _tt_mk_user(p_creator);
  INSERT INTO public.teams(id, display_name, league_membership, created_by)
    VALUES (v_team, 'Crew-' || substr(v_team::text, 1, 8), 'B', p_creator);
  INSERT INTO public.team_memberships(team_id, user_id)
    VALUES (v_team, p_creator);
  INSERT INTO public.team_guest_players(id, team_id, display_name, added_by)
    VALUES (v_guest, v_team, 'Gast', p_creator);
  RETURN QUERY SELECT v_team, v_guest;
END;
$$;

-- Minimal Team-Turnier (team_size=3, status=registration_open).
CREATE OR REPLACE FUNCTION _tt_mk_tournament(p_creator uuid)
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_tid uuid := gen_random_uuid();
BEGIN
  PERFORM _tt_mk_user(p_creator);
  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status)
    VALUES (v_tid, p_creator, 'T8-Team-Cup', 3, 2, 32,
            'round_robin_then_ko', 'ekc',
            '{"format":"best_of_1","sets_to_win":1}'::jsonb,
            'registration_open');
  RETURN v_tid;
END;
$$;

-- Roster-JSON: 1 Member + 2 Guests (default Layout fuer Happy-Path).
CREATE OR REPLACE FUNCTION _tt_roster(
  p_member uuid, p_guest1 uuid, p_guest2 uuid)
RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_array(
    jsonb_build_object('slot_index', 1, 'member_user_id', p_member),
    jsonb_build_object('slot_index', 2, 'guest_player_id', p_guest1),
    jsonb_build_object('slot_index', 3, 'guest_player_id', p_guest2));
$$;


-- ---------------------------------------------------------------------
-- 1. tournament_register_team — Happy-Path: participant + 3 slots.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid uuid;
  v_team uuid;
  v_g1 uuid;
  v_g2 uuid;
  v_part uuid;
BEGIN
  v_tid := _tt_mk_tournament(v_creator);
  SELECT team_id, guest_id INTO v_team, v_g1 FROM _tt_mk_team(v_creator);
  -- Zweiter Gast im selben Team.
  v_g2 := gen_random_uuid();
  INSERT INTO public.team_guest_players(id, team_id, display_name, added_by)
    VALUES (v_g2, v_team, 'Gast-2', v_creator);

  PERFORM _tt_as(v_creator);
  v_part := public.tournament_register_team(
    v_tid, v_team, _tt_roster(v_creator, v_g1, v_g2));

  CREATE TEMP TABLE _tt_reg_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_tid AS tid, v_team AS team,
           v_g1 AS g1, v_g2 AS g2, v_part AS participant;
END $$;

SELECT is(
  (SELECT count(*)::int FROM public.tournament_roster_slots
    WHERE participant_id = (SELECT participant FROM _tt_reg_ctx)
      AND replaced_at IS NULL),
  3,
  'tournament_register_team: Happy-Path schreibt 3 offene Slot-Rows');

SELECT is(
  (SELECT team_id FROM public.tournament_participants
    WHERE id = (SELECT participant FROM _tt_reg_ctx)),
  (SELECT team FROM _tt_reg_ctx),
  'tournament_register_team: participant.team_id verlinkt mit team_id');

-- ---------------------------------------------------------------------
-- 2. tournament_register_team — Roster ohne registriertes Mitglied
--    → P0001 MIN_ONE_REGISTERED (FR-REG-12).
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_tid uuid;
  v_team uuid;
  v_g1 uuid;
  v_g2 uuid;
  v_g3 uuid;
BEGIN
  v_tid := _tt_mk_tournament(v_creator);
  SELECT team_id, guest_id INTO v_team, v_g1 FROM _tt_mk_team(v_creator);
  v_g2 := gen_random_uuid();
  v_g3 := gen_random_uuid();
  INSERT INTO public.team_guest_players(id, team_id, display_name, added_by)
    VALUES (v_g2, v_team, 'Gast-2', v_creator),
           (v_g3, v_team, 'Gast-3', v_creator);
  CREATE TEMP TABLE _tt_minreg_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_tid AS tid, v_team AS team,
           v_g1 AS g1, v_g2 AS g2, v_g3 AS g3;
END $$;

SELECT _tt_as((SELECT creator FROM _tt_minreg_ctx));
SELECT throws_ok(
  format($$
    SELECT public.tournament_register_team(
      %L::uuid, %L::uuid,
      jsonb_build_array(
        jsonb_build_object('slot_index', 1, 'guest_player_id', %L::uuid),
        jsonb_build_object('slot_index', 2, 'guest_player_id', %L::uuid),
        jsonb_build_object('slot_index', 3, 'guest_player_id', %L::uuid)))
  $$, (SELECT tid FROM _tt_minreg_ctx),
       (SELECT team FROM _tt_minreg_ctx),
       (SELECT g1 FROM _tt_minreg_ctx),
       (SELECT g2 FROM _tt_minreg_ctx),
       (SELECT g3 FROM _tt_minreg_ctx)),
  'P0001', 'MIN_ONE_REGISTERED',
  'tournament_register_team: nur Gaeste → P0001 MIN_ONE_REGISTERED');

-- ---------------------------------------------------------------------
-- 3. tournament_register_team — Caller nicht Pool-Mitglied → 42501.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_outsider uuid := gen_random_uuid();
  v_tid uuid;
  v_team uuid;
  v_g1 uuid;
  v_g2 uuid;
BEGIN
  v_tid := _tt_mk_tournament(v_creator);
  SELECT team_id, guest_id INTO v_team, v_g1 FROM _tt_mk_team(v_creator);
  v_g2 := gen_random_uuid();
  INSERT INTO public.team_guest_players(id, team_id, display_name, added_by)
    VALUES (v_g2, v_team, 'Gast-2', v_creator);
  PERFORM _tt_mk_user(v_outsider);
  CREATE TEMP TABLE _tt_outsider_ctx ON COMMIT DROP AS
    SELECT v_outsider AS outsider, v_tid AS tid, v_team AS team,
           v_g1 AS g1, v_g2 AS g2;
END $$;

SELECT _tt_as((SELECT outsider FROM _tt_outsider_ctx));
SELECT throws_ok(
  format($$
    SELECT public.tournament_register_team(
      %L::uuid, %L::uuid,
      jsonb_build_array(
        jsonb_build_object('slot_index', 1, 'member_user_id', %L::uuid),
        jsonb_build_object('slot_index', 2, 'guest_player_id', %L::uuid),
        jsonb_build_object('slot_index', 3, 'guest_player_id', %L::uuid)))
  $$, (SELECT tid FROM _tt_outsider_ctx),
       (SELECT team FROM _tt_outsider_ctx),
       (SELECT outsider FROM _tt_outsider_ctx),
       (SELECT g1 FROM _tt_outsider_ctx),
       (SELECT g2 FROM _tt_outsider_ctx)),
  '42501', NULL,
  'tournament_register_team: Caller kein Pool-Mitglied → 42501');

-- ---------------------------------------------------------------------
-- 4. tournament_roster_replace — Happy-Path:
--    alter Slot replaced_at, neuer Slot, Audit-Event.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_partner uuid := gen_random_uuid();
  v_tid uuid;
  v_team uuid;
  v_g1 uuid;
  v_g2 uuid;
  v_part uuid;
BEGIN
  v_tid := _tt_mk_tournament(v_creator);
  SELECT team_id, guest_id INTO v_team, v_g1 FROM _tt_mk_team(v_creator);
  v_g2 := gen_random_uuid();
  INSERT INTO public.team_guest_players(id, team_id, display_name, added_by)
    VALUES (v_g2, v_team, 'Gast-2', v_creator);
  -- Zweites Pool-Mitglied als Replacement-Kandidat.
  PERFORM _tt_mk_user(v_partner);
  INSERT INTO public.team_memberships(team_id, user_id)
    VALUES (v_team, v_partner);
  PERFORM _tt_as(v_creator);
  v_part := public.tournament_register_team(
    v_tid, v_team, _tt_roster(v_creator, v_g1, v_g2));
  -- Slot 2 (g1) wird durch v_partner ersetzt.
  PERFORM public.tournament_roster_replace(
    v_part, 2, v_partner, NULL, 'Verletzung');
  CREATE TEMP TABLE _tt_repl_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_partner AS partner, v_tid AS tid,
           v_team AS team, v_part AS participant;
END $$;

SELECT is(
  (SELECT count(*)::int FROM public.tournament_roster_slots
    WHERE participant_id = (SELECT participant FROM _tt_repl_ctx)
      AND slot_index = 2
      AND replaced_at IS NOT NULL),
  1,
  'tournament_roster_replace: alter Slot bekommt replaced_at');

SELECT is(
  (SELECT member_user_id FROM public.tournament_roster_slots
    WHERE participant_id = (SELECT participant FROM _tt_repl_ctx)
      AND slot_index = 2
      AND replaced_at IS NULL),
  (SELECT partner FROM _tt_repl_ctx),
  'tournament_roster_replace: neuer offener Slot referenziert Partner');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_audit_events
    WHERE tournament_id = (SELECT tid FROM _tt_repl_ctx)
      AND kind = 'roster_replaced'),
  1,
  'tournament_roster_replace: Audit-Event roster_replaced geschrieben');

-- ---------------------------------------------------------------------
-- 5. tournament_roster_replace bei awaiting_results Match
--    → P0001 ROSTER_LOCKED_DURING_MATCH (OD-M3-07).
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_opponent uuid := gen_random_uuid();
  v_partner uuid := gen_random_uuid();
  v_tid uuid;
  v_team uuid;
  v_g1 uuid;
  v_g2 uuid;
  v_part uuid;
  v_opp_part uuid;
BEGIN
  v_tid := _tt_mk_tournament(v_creator);
  SELECT team_id, guest_id INTO v_team, v_g1 FROM _tt_mk_team(v_creator);
  v_g2 := gen_random_uuid();
  INSERT INTO public.team_guest_players(id, team_id, display_name, added_by)
    VALUES (v_g2, v_team, 'Gast-2', v_creator);
  PERFORM _tt_mk_user(v_partner);
  INSERT INTO public.team_memberships(team_id, user_id)
    VALUES (v_team, v_partner);
  PERFORM _tt_as(v_creator);
  v_part := public.tournament_register_team(
    v_tid, v_team, _tt_roster(v_creator, v_g1, v_g2));
  -- Opponent-Participant (Single, fuer Match-Pairing).
  PERFORM _tt_mk_user(v_opponent);
  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status, registered_at)
    VALUES (gen_random_uuid(), v_tid, v_opponent, 'confirmed', now())
    RETURNING id INTO v_opp_part;
  -- Offenes Match in awaiting_results sperrt das Roster.
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, status)
    VALUES (v_tid, 1, 1, v_part, v_opp_part, 'awaiting_results');
  CREATE TEMP TABLE _tt_locked_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_partner AS partner, v_tid AS tid,
           v_part AS participant;
END $$;

SELECT _tt_as((SELECT creator FROM _tt_locked_ctx));
SELECT throws_ok(
  format($$
    SELECT public.tournament_roster_replace(
      %L::uuid, 2, %L::uuid, NULL, 'Versuch')
  $$, (SELECT participant FROM _tt_locked_ctx),
       (SELECT partner FROM _tt_locked_ctx)),
  'P0001', 'ROSTER_LOCKED_DURING_MATCH',
  'tournament_roster_replace: awaiting_results-Match → P0001 ROSTER_LOCKED_DURING_MATCH');

-- ---------------------------------------------------------------------
-- 6. tournament_roster_replace nach finalized → P0001 ROSTER_LOCKED.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_partner uuid := gen_random_uuid();
  v_tid uuid;
  v_team uuid;
  v_g1 uuid;
  v_g2 uuid;
  v_part uuid;
BEGIN
  v_tid := _tt_mk_tournament(v_creator);
  SELECT team_id, guest_id INTO v_team, v_g1 FROM _tt_mk_team(v_creator);
  v_g2 := gen_random_uuid();
  INSERT INTO public.team_guest_players(id, team_id, display_name, added_by)
    VALUES (v_g2, v_team, 'Gast-2', v_creator);
  PERFORM _tt_mk_user(v_partner);
  INSERT INTO public.team_memberships(team_id, user_id)
    VALUES (v_team, v_partner);
  PERFORM _tt_as(v_creator);
  v_part := public.tournament_register_team(
    v_tid, v_team, _tt_roster(v_creator, v_g1, v_g2));
  -- Turnier in finalized → Roster permanent gesperrt (FR-TEAM-15).
  UPDATE public.tournaments SET status = 'finalized' WHERE id = v_tid;
  CREATE TEMP TABLE _tt_fin_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_partner AS partner,
           v_part AS participant;
END $$;

SELECT _tt_as((SELECT creator FROM _tt_fin_ctx));
SELECT throws_ok(
  format($$
    SELECT public.tournament_roster_replace(
      %L::uuid, 2, %L::uuid, NULL, 'Versuch')
  $$, (SELECT participant FROM _tt_fin_ctx),
       (SELECT partner FROM _tt_fin_ctx)),
  'P0001', 'ROSTER_LOCKED',
  'tournament_roster_replace: nach finalized → P0001 ROSTER_LOCKED');

-- ---------------------------------------------------------------------
-- 7. BR-5: User bereits in anderem Team desselben Turniers → 23P01.
--    Replace setzt Slot auf einen User, der schon offenen Roster-Slot
--    in einem anderen participant hat → Trigger blockt.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creatorA uuid := gen_random_uuid();
  v_creatorB uuid := gen_random_uuid();
  v_shared   uuid := gen_random_uuid();
  v_tid uuid;
  v_teamA uuid;
  v_teamB uuid;
  v_gA1 uuid;
  v_gA2 uuid;
  v_gB1 uuid;
  v_gB2 uuid;
  v_partA uuid;
BEGIN
  v_tid := _tt_mk_tournament(v_creatorA);
  -- Team A (Captain v_creatorA, Member v_shared).
  SELECT team_id, guest_id INTO v_teamA, v_gA1 FROM _tt_mk_team(v_creatorA);
  v_gA2 := gen_random_uuid();
  INSERT INTO public.team_guest_players(id, team_id, display_name, added_by)
    VALUES (v_gA2, v_teamA, 'GA2', v_creatorA);
  PERFORM _tt_mk_user(v_shared);
  INSERT INTO public.team_memberships(team_id, user_id)
    VALUES (v_teamA, v_shared);
  -- Team B (Captain v_creatorB, v_shared spielt dort registriert).
  SELECT team_id, guest_id INTO v_teamB, v_gB1 FROM _tt_mk_team(v_creatorB);
  v_gB2 := gen_random_uuid();
  INSERT INTO public.team_guest_players(id, team_id, display_name, added_by)
    VALUES (v_gB2, v_teamB, 'GB2', v_creatorB);
  INSERT INTO public.team_memberships(team_id, user_id)
    VALUES (v_teamB, v_shared);
  -- Team B registriert sich mit v_shared auf Slot 1.
  PERFORM _tt_as(v_creatorB);
  PERFORM public.tournament_register_team(
    v_tid, v_teamB, _tt_roster(v_shared, v_gB1, v_gB2));
  -- Team A registriert: Captain v_creatorA + 2 Gaeste; OK.
  PERFORM _tt_as(v_creatorA);
  v_partA := public.tournament_register_team(
    v_tid, v_teamA, _tt_roster(v_creatorA, v_gA1, v_gA2));
  CREATE TEMP TABLE _tt_br5_ctx ON COMMIT DROP AS
    SELECT v_creatorA AS creatorA, v_shared AS shared, v_partA AS partA;
END $$;

-- Versuch: in Team A Slot 2 v_shared eintragen → BR-5 Violation.
SELECT _tt_as((SELECT creatorA FROM _tt_br5_ctx));
SELECT throws_ok(
  format($$
    SELECT public.tournament_roster_replace(
      %L::uuid, 2, %L::uuid, NULL, 'Cross-Team-Versuch')
  $$, (SELECT partA FROM _tt_br5_ctx),
       (SELECT shared FROM _tt_br5_ctx)),
  '23P01', NULL,
  'tournament_roster_replace: Spieler in anderem Team → 23P01 BR-5');

-- ---------------------------------------------------------------------
-- 8. tournament_roster_list — liefert nur offene (replaced_at IS NULL) Slots.
-- ---------------------------------------------------------------------

SELECT is(
  (SELECT count(*)::int FROM public.tournament_roster_list(
     (SELECT tid FROM _tt_repl_ctx), NULL)),
  3,
  'tournament_roster_list: liefert 3 offene Slots nach Replace (kein History-Row)');

-- ---------------------------------------------------------------------
-- 9. Score-RPC — Single-Match Regression: user_id-Caller funktioniert.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_tid uuid;
  v_pa uuid;
  v_pb uuid;
  v_mid uuid;
BEGIN
  v_tid := _tt_mk_tournament(v_a);
  PERFORM _tt_mk_user(v_b);
  v_pa := gen_random_uuid();
  v_pb := gen_random_uuid();
  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status, registered_at)
    VALUES (v_pa, v_tid, v_a, 'confirmed', now()),
           (v_pb, v_tid, v_b, 'confirmed', now());
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, status)
    VALUES (v_tid, 1, 1, v_pa, v_pb, 'scheduled')
    RETURNING id INTO v_mid;
  CREATE TEMP TABLE _tt_solo_ctx ON COMMIT DROP AS
    SELECT v_a AS a, v_mid AS mid;
END $$;

SELECT _tt_as((SELECT a FROM _tt_solo_ctx));
SELECT lives_ok(
  format($$
    SELECT public.tournament_propose_set_scores(
      %L::uuid, 1,
      jsonb_build_array(jsonb_build_object(
        'basekubbs_a', 6, 'basekubbs_b', 3, 'winner', 'A')))
  $$, (SELECT mid FROM _tt_solo_ctx)),
  'tournament_propose_set_scores: Single-Match user_id-Caller → OK (M1-Regression)');

-- ---------------------------------------------------------------------
-- 10. Score-RPC — Team-Match: Pool-Mitglied (nicht Captain) → OK.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_captainA uuid := gen_random_uuid();
  v_memberA  uuid := gen_random_uuid();
  v_captainB uuid := gen_random_uuid();
  v_tid uuid;
  v_teamA uuid;
  v_teamB uuid;
  v_gA1 uuid;
  v_gA2 uuid;
  v_gB1 uuid;
  v_gB2 uuid;
  v_partA uuid;
  v_partB uuid;
  v_mid uuid;
BEGIN
  v_tid := _tt_mk_tournament(v_captainA);
  SELECT team_id, guest_id INTO v_teamA, v_gA1 FROM _tt_mk_team(v_captainA);
  v_gA2 := gen_random_uuid();
  INSERT INTO public.team_guest_players(id, team_id, display_name, added_by)
    VALUES (v_gA2, v_teamA, 'GA2', v_captainA);
  PERFORM _tt_mk_user(v_memberA);
  INSERT INTO public.team_memberships(team_id, user_id)
    VALUES (v_teamA, v_memberA);
  SELECT team_id, guest_id INTO v_teamB, v_gB1 FROM _tt_mk_team(v_captainB);
  v_gB2 := gen_random_uuid();
  INSERT INTO public.team_guest_players(id, team_id, display_name, added_by)
    VALUES (v_gB2, v_teamB, 'GB2', v_captainB);
  PERFORM _tt_as(v_captainA);
  v_partA := public.tournament_register_team(
    v_tid, v_teamA, _tt_roster(v_captainA, v_gA1, v_gA2));
  PERFORM _tt_as(v_captainB);
  v_partB := public.tournament_register_team(
    v_tid, v_teamB, _tt_roster(v_captainB, v_gB1, v_gB2));
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, status)
    VALUES (v_tid, 1, 1, v_partA, v_partB, 'scheduled')
    RETURNING id INTO v_mid;
  CREATE TEMP TABLE _tt_team_score_ctx ON COMMIT DROP AS
    SELECT v_captainA AS captainA, v_memberA AS memberA,
           v_teamA AS teamA, v_mid AS mid;
END $$;

SELECT _tt_as((SELECT memberA FROM _tt_team_score_ctx));
SELECT lives_ok(
  format($$
    SELECT public.tournament_propose_set_scores(
      %L::uuid, 1,
      jsonb_build_array(jsonb_build_object(
        'basekubbs_a', 5, 'basekubbs_b', 4, 'winner', 'A')))
  $$, (SELECT mid FROM _tt_team_score_ctx)),
  'tournament_propose_set_scores: Team-Match Pool-Mitglied (non-Captain) → OK (BR-9)');

-- ---------------------------------------------------------------------
-- 11. Score-RPC — Team-Match: Non-Pool-Member → 42501.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_outsider uuid := gen_random_uuid();
BEGIN
  PERFORM _tt_mk_user(v_outsider);
  CREATE TEMP TABLE _tt_score_ns_ctx ON COMMIT DROP AS
    SELECT v_outsider AS outsider,
           (SELECT mid FROM _tt_team_score_ctx) AS mid;
END $$;

SELECT _tt_as((SELECT outsider FROM _tt_score_ns_ctx));
SELECT throws_ok(
  format($$
    SELECT public.tournament_propose_set_scores(
      %L::uuid, 1,
      jsonb_build_array(jsonb_build_object(
        'basekubbs_a', 1, 'basekubbs_b', 1, 'winner', 'A')))
  $$, (SELECT mid FROM _tt_score_ns_ctx)),
  '42501', NULL,
  'tournament_propose_set_scores: Non-Pool-Member ruft Team-Match → 42501');

-- ---------------------------------------------------------------------
-- 12. Score-RPC — Pool-Mitglied wurde entfernt (removed_at gesetzt) → 42501.
-- ---------------------------------------------------------------------

DO $$
BEGIN
  -- Pool-Membership von memberA entziehen (FR: BR-9 erwartet active membership).
  UPDATE public.team_memberships
    SET removed_at = now()
    WHERE team_id = (SELECT teamA FROM _tt_team_score_ctx)
      AND user_id = (SELECT memberA FROM _tt_team_score_ctx);
END $$;

SELECT _tt_as((SELECT memberA FROM _tt_team_score_ctx));
SELECT throws_ok(
  format($$
    SELECT public.tournament_propose_set_scores(
      %L::uuid, 1,
      jsonb_build_array(jsonb_build_object(
        'basekubbs_a', 2, 'basekubbs_b', 2, 'winner', 'none')))
  $$, (SELECT mid FROM _tt_team_score_ctx)),
  '42501', NULL,
  'tournament_propose_set_scores: removed_at Pool-Mitglied → 42501');

SELECT * FROM finish();

ROLLBACK;
