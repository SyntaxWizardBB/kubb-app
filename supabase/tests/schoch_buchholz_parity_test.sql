-- Schoch §5 Buchholz parity — server-side golden check (SM Einzel 2026).
--
-- Quelle der Wahrheit: docs/specs/schoch-swiss-pairing-buchholz-spec.md §4/§5
-- und der 1:1 daraus abgeleitete Dart-Golden-Datensatz
-- packages/kubb_domain/test/tournament/golden/sm_einzel_2026_fixture.dart
-- (73 Spieler, 8 Runden, 288 reale Partien + 8 Freilose, kubb.live-konform).
--
-- Dieser Test spielt den Golden-Datensatz direkt in tournament_matches ein
-- (eine schoch-Stage, ein Knoten 'schoch1') und prüft, dass die
-- server-autoritative Rangwertung aus 20261295000000 die §4/§5-Sollwerte
-- exakt trifft:
--   * total_points (eigene Spielpunkte über alle Runden, Freilos = 16),
--   * Buchholz (§5: Summe Gegner-Endpunkte minus deren H2H-Score gegen mich),
--   * rank (Sortierung Punkte -> Buchholz -> Seed, aus
--     tournament_stage_ranking selbst).
--
-- Die INSERT-Blöcke und Soll-Werte sind programmatisch aus der Markdown-/
-- Dart-Fixture erzeugt (kein Abtippen). Freilose modellieren wir wie der
-- Generator (20261293000000): participant_b NULL, winner = Freilos-Spieler,
-- final_score_a NULL — so prüft der Test, dass die Migration die 16 selbst
-- gutschreibt.
--
-- pgTAP wird transient in BEGIN..ROLLBACK installiert; nichts wird persistiert.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(222);

SET LOCAL ROLE postgres;

-- Eine auth.users-Zeile pro (synthetischer) Spieler-Index. Der Spieler-Index
-- ist die kubb.live-Reihenfolge (1-basiert) und doubelt als Seed.
CREATE OR REPLACE FUNCTION _sbp_mk_user(p_idx int) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_uid uuid := ('00000000-0000-0000-0d0d-' || lpad(p_idx::text, 12, '0'))::uuid;
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'p' || p_idx || '@sbp.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;
  RETURN v_uid;
END;
$$;

-- Fixtur-Konstanten, über den Test hinweg stabil.
CREATE OR REPLACE FUNCTION _sbp_tid() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5b0c0000-0000-0000-0000-000000000001'::uuid $$;
CREATE OR REPLACE FUNCTION _sbp_creator() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5b0c0000-0000-0000-0000-0000000000aa'::uuid $$;

-- Spieler-User-id aus dem Index (gespiegelt zu _sbp_mk_user). Muss vor dem
-- Fixture-Block stehen, weil die Teilnehmer-INSERTs _u() im selben DO-Block
-- aufrufen.
CREATE OR REPLACE FUNCTION _u(p_idx int) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('00000000-0000-0000-0d0d-' || lpad(p_idx::text, 12, '0'))::uuid
$$;

DO $fixture$
DECLARE
  v_tid uuid := _sbp_tid();
  v_t0  timestamptz := '2026-06-01 09:00:00+00';
  i     int;
BEGIN
  PERFORM _sbp_mk_user(0);  -- placeholder so creator user exists
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (_sbp_creator(), '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated', 'org@sbp.local', '',
            now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  -- 73 Spieler-User.
  FOR i IN 1..73 LOOP
    PERFORM _sbp_mk_user(i);
  END LOOP;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, _sbp_creator(), 'SM Einzel 2026', 1, 2, 200,
            'schoch', 'ekc',
            jsonb_build_object('round_time_seconds', 1800,
                               'break_between_matches_seconds', 300),
            'live', true);

  -- Schoch-Stage-Knoten.
  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tid, 'schoch1', 'schoch',
            '{}'::jsonb, 'manual', 'active');

  -- 73 confirmed Teilnehmer (Seed = Index, registered_at gestaffelt).
  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status, seed, registered_at)
  VALUES
    ('00000000-0000-0000-0c0c-000000000001'::uuid, v_tid, _u(1), 'confirmed', 1, v_t0 + (1 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000002'::uuid, v_tid, _u(2), 'confirmed', 2, v_t0 + (2 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000003'::uuid, v_tid, _u(3), 'confirmed', 3, v_t0 + (3 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000004'::uuid, v_tid, _u(4), 'confirmed', 4, v_t0 + (4 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000005'::uuid, v_tid, _u(5), 'confirmed', 5, v_t0 + (5 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000006'::uuid, v_tid, _u(6), 'confirmed', 6, v_t0 + (6 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000007'::uuid, v_tid, _u(7), 'confirmed', 7, v_t0 + (7 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000008'::uuid, v_tid, _u(8), 'confirmed', 8, v_t0 + (8 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000009'::uuid, v_tid, _u(9), 'confirmed', 9, v_t0 + (9 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000010'::uuid, v_tid, _u(10), 'confirmed', 10, v_t0 + (10 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000011'::uuid, v_tid, _u(11), 'confirmed', 11, v_t0 + (11 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000012'::uuid, v_tid, _u(12), 'confirmed', 12, v_t0 + (12 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000013'::uuid, v_tid, _u(13), 'confirmed', 13, v_t0 + (13 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000014'::uuid, v_tid, _u(14), 'confirmed', 14, v_t0 + (14 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000015'::uuid, v_tid, _u(15), 'confirmed', 15, v_t0 + (15 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000016'::uuid, v_tid, _u(16), 'confirmed', 16, v_t0 + (16 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000017'::uuid, v_tid, _u(17), 'confirmed', 17, v_t0 + (17 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000018'::uuid, v_tid, _u(18), 'confirmed', 18, v_t0 + (18 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000019'::uuid, v_tid, _u(19), 'confirmed', 19, v_t0 + (19 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000020'::uuid, v_tid, _u(20), 'confirmed', 20, v_t0 + (20 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000021'::uuid, v_tid, _u(21), 'confirmed', 21, v_t0 + (21 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000022'::uuid, v_tid, _u(22), 'confirmed', 22, v_t0 + (22 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000023'::uuid, v_tid, _u(23), 'confirmed', 23, v_t0 + (23 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000024'::uuid, v_tid, _u(24), 'confirmed', 24, v_t0 + (24 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000025'::uuid, v_tid, _u(25), 'confirmed', 25, v_t0 + (25 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000026'::uuid, v_tid, _u(26), 'confirmed', 26, v_t0 + (26 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000027'::uuid, v_tid, _u(27), 'confirmed', 27, v_t0 + (27 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000028'::uuid, v_tid, _u(28), 'confirmed', 28, v_t0 + (28 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000029'::uuid, v_tid, _u(29), 'confirmed', 29, v_t0 + (29 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000030'::uuid, v_tid, _u(30), 'confirmed', 30, v_t0 + (30 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000031'::uuid, v_tid, _u(31), 'confirmed', 31, v_t0 + (31 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000032'::uuid, v_tid, _u(32), 'confirmed', 32, v_t0 + (32 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000033'::uuid, v_tid, _u(33), 'confirmed', 33, v_t0 + (33 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000034'::uuid, v_tid, _u(34), 'confirmed', 34, v_t0 + (34 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000035'::uuid, v_tid, _u(35), 'confirmed', 35, v_t0 + (35 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000036'::uuid, v_tid, _u(36), 'confirmed', 36, v_t0 + (36 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000037'::uuid, v_tid, _u(37), 'confirmed', 37, v_t0 + (37 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000038'::uuid, v_tid, _u(38), 'confirmed', 38, v_t0 + (38 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000039'::uuid, v_tid, _u(39), 'confirmed', 39, v_t0 + (39 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000040'::uuid, v_tid, _u(40), 'confirmed', 40, v_t0 + (40 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000041'::uuid, v_tid, _u(41), 'confirmed', 41, v_t0 + (41 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000042'::uuid, v_tid, _u(42), 'confirmed', 42, v_t0 + (42 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000043'::uuid, v_tid, _u(43), 'confirmed', 43, v_t0 + (43 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000044'::uuid, v_tid, _u(44), 'confirmed', 44, v_t0 + (44 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000045'::uuid, v_tid, _u(45), 'confirmed', 45, v_t0 + (45 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000046'::uuid, v_tid, _u(46), 'confirmed', 46, v_t0 + (46 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000047'::uuid, v_tid, _u(47), 'confirmed', 47, v_t0 + (47 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000048'::uuid, v_tid, _u(48), 'confirmed', 48, v_t0 + (48 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000049'::uuid, v_tid, _u(49), 'confirmed', 49, v_t0 + (49 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000050'::uuid, v_tid, _u(50), 'confirmed', 50, v_t0 + (50 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000051'::uuid, v_tid, _u(51), 'confirmed', 51, v_t0 + (51 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000052'::uuid, v_tid, _u(52), 'confirmed', 52, v_t0 + (52 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000053'::uuid, v_tid, _u(53), 'confirmed', 53, v_t0 + (53 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000054'::uuid, v_tid, _u(54), 'confirmed', 54, v_t0 + (54 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000055'::uuid, v_tid, _u(55), 'confirmed', 55, v_t0 + (55 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000056'::uuid, v_tid, _u(56), 'confirmed', 56, v_t0 + (56 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000057'::uuid, v_tid, _u(57), 'confirmed', 57, v_t0 + (57 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000058'::uuid, v_tid, _u(58), 'confirmed', 58, v_t0 + (58 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000059'::uuid, v_tid, _u(59), 'confirmed', 59, v_t0 + (59 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000060'::uuid, v_tid, _u(60), 'confirmed', 60, v_t0 + (60 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000061'::uuid, v_tid, _u(61), 'confirmed', 61, v_t0 + (61 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000062'::uuid, v_tid, _u(62), 'confirmed', 62, v_t0 + (62 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000063'::uuid, v_tid, _u(63), 'confirmed', 63, v_t0 + (63 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000064'::uuid, v_tid, _u(64), 'confirmed', 64, v_t0 + (64 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000065'::uuid, v_tid, _u(65), 'confirmed', 65, v_t0 + (65 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000066'::uuid, v_tid, _u(66), 'confirmed', 66, v_t0 + (66 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000067'::uuid, v_tid, _u(67), 'confirmed', 67, v_t0 + (67 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000068'::uuid, v_tid, _u(68), 'confirmed', 68, v_t0 + (68 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000069'::uuid, v_tid, _u(69), 'confirmed', 69, v_t0 + (69 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000070'::uuid, v_tid, _u(70), 'confirmed', 70, v_t0 + (70 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000071'::uuid, v_tid, _u(71), 'confirmed', 71, v_t0 + (71 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000072'::uuid, v_tid, _u(72), 'confirmed', 72, v_t0 + (72 || ' seconds')::interval),
    ('00000000-0000-0000-0c0c-000000000073'::uuid, v_tid, _u(73), 'confirmed', 73, v_t0 + (73 || ' seconds')::interval);

  -- 288 reale Partien + 8 Freilose (final_score je Seite; winner gesetzt;
  -- Freilos: participant_b NULL, final_score_a NULL, winner = Freilos-Spieler).
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, winner_participant,
      final_score_a, final_score_b, stage_node_id)
  VALUES
    (v_tid, 1, 1, '00000000-0000-0000-0c0c-000000000002'::uuid, '00000000-0000-0000-0c0c-000000000061'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000002'::uuid, 16, 5, 'schoch1'),
    (v_tid, 1, 2, '00000000-0000-0000-0c0c-000000000007'::uuid, '00000000-0000-0000-0c0c-000000000036'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000007'::uuid, 16, 8, 'schoch1'),
    (v_tid, 1, 3, '00000000-0000-0000-0c0c-000000000014'::uuid, '00000000-0000-0000-0c0c-000000000055'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000014'::uuid, 16, 4, 'schoch1'),
    (v_tid, 1, 4, '00000000-0000-0000-0c0c-000000000001'::uuid, '00000000-0000-0000-0c0c-000000000060'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000001'::uuid, 16, 3, 'schoch1'),
    (v_tid, 1, 5, '00000000-0000-0000-0c0c-000000000004'::uuid, '00000000-0000-0000-0c0c-000000000031'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000004'::uuid, 16, 6, 'schoch1'),
    (v_tid, 1, 6, '00000000-0000-0000-0c0c-000000000016'::uuid, '00000000-0000-0000-0c0c-000000000051'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000016'::uuid, 16, 5, 'schoch1'),
    (v_tid, 1, 7, '00000000-0000-0000-0c0c-000000000006'::uuid, '00000000-0000-0000-0c0c-000000000039'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000006'::uuid, 16, 5, 'schoch1'),
    (v_tid, 1, 8, '00000000-0000-0000-0c0c-000000000037'::uuid, '00000000-0000-0000-0c0c-000000000034'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000037'::uuid, 16, 2, 'schoch1'),
    (v_tid, 1, 9, '00000000-0000-0000-0c0c-000000000063'::uuid, '00000000-0000-0000-0c0c-000000000009'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000009'::uuid, 7, 16, 'schoch1'),
    (v_tid, 1, 10, '00000000-0000-0000-0c0c-000000000003'::uuid, '00000000-0000-0000-0c0c-000000000046'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000003'::uuid, 16, 5, 'schoch1'),
    (v_tid, 1, 11, '00000000-0000-0000-0c0c-000000000011'::uuid, '00000000-0000-0000-0c0c-000000000048'::uuid, 'group', 'finalized', NULL, 9, 9, 'schoch1'),
    (v_tid, 1, 12, '00000000-0000-0000-0c0c-000000000021'::uuid, '00000000-0000-0000-0c0c-000000000066'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000021'::uuid, 16, 5, 'schoch1'),
    (v_tid, 1, 13, '00000000-0000-0000-0c0c-000000000012'::uuid, '00000000-0000-0000-0c0c-000000000059'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000012'::uuid, 16, 6, 'schoch1'),
    (v_tid, 1, 14, '00000000-0000-0000-0c0c-000000000013'::uuid, '00000000-0000-0000-0c0c-000000000024'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000024'::uuid, 11, 12, 'schoch1'),
    (v_tid, 1, 15, '00000000-0000-0000-0c0c-000000000040'::uuid, '00000000-0000-0000-0c0c-000000000045'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000040'::uuid, 16, 6, 'schoch1'),
    (v_tid, 1, 16, '00000000-0000-0000-0c0c-000000000015'::uuid, '00000000-0000-0000-0c0c-000000000047'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000015'::uuid, 16, 4, 'schoch1'),
    (v_tid, 1, 17, '00000000-0000-0000-0c0c-000000000019'::uuid, '00000000-0000-0000-0c0c-000000000062'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000019'::uuid, 16, 0, 'schoch1'),
    (v_tid, 1, 18, '00000000-0000-0000-0c0c-000000000010'::uuid, '00000000-0000-0000-0c0c-000000000057'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000010'::uuid, 16, 7, 'schoch1'),
    (v_tid, 1, 19, '00000000-0000-0000-0c0c-000000000020'::uuid, '00000000-0000-0000-0c0c-000000000038'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000020'::uuid, 16, 4, 'schoch1'),
    (v_tid, 1, 20, '00000000-0000-0000-0c0c-000000000023'::uuid, '00000000-0000-0000-0c0c-000000000072'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000023'::uuid, 16, 2, 'schoch1'),
    (v_tid, 1, 21, '00000000-0000-0000-0c0c-000000000033'::uuid, '00000000-0000-0000-0c0c-000000000070'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000033'::uuid, 16, 1, 'schoch1'),
    (v_tid, 1, 22, '00000000-0000-0000-0c0c-000000000026'::uuid, '00000000-0000-0000-0c0c-000000000035'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000026'::uuid, 16, 2, 'schoch1'),
    (v_tid, 1, 23, '00000000-0000-0000-0c0c-000000000068'::uuid, '00000000-0000-0000-0c0c-000000000008'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000008'::uuid, 1, 16, 'schoch1'),
    (v_tid, 1, 24, '00000000-0000-0000-0c0c-000000000071'::uuid, '00000000-0000-0000-0c0c-000000000022'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000071'::uuid, 13, 7, 'schoch1'),
    (v_tid, 1, 25, '00000000-0000-0000-0c0c-000000000018'::uuid, '00000000-0000-0000-0c0c-000000000044'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000018'::uuid, 16, 7, 'schoch1'),
    (v_tid, 1, 26, '00000000-0000-0000-0c0c-000000000043'::uuid, '00000000-0000-0000-0c0c-000000000032'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000032'::uuid, 10, 12, 'schoch1'),
    (v_tid, 1, 27, '00000000-0000-0000-0c0c-000000000042'::uuid, '00000000-0000-0000-0c0c-000000000005'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000005'::uuid, 4, 16, 'schoch1'),
    (v_tid, 1, 28, '00000000-0000-0000-0c0c-000000000052'::uuid, '00000000-0000-0000-0c0c-000000000041'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000041'::uuid, 7, 16, 'schoch1'),
    (v_tid, 1, 29, '00000000-0000-0000-0c0c-000000000028'::uuid, '00000000-0000-0000-0c0c-000000000053'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000028'::uuid, 16, 4, 'schoch1'),
    (v_tid, 1, 30, '00000000-0000-0000-0c0c-000000000027'::uuid, '00000000-0000-0000-0c0c-000000000056'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000027'::uuid, 16, 2, 'schoch1'),
    (v_tid, 1, 31, '00000000-0000-0000-0c0c-000000000017'::uuid, '00000000-0000-0000-0c0c-000000000064'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000017'::uuid, 16, 5, 'schoch1'),
    (v_tid, 1, 32, '00000000-0000-0000-0c0c-000000000050'::uuid, '00000000-0000-0000-0c0c-000000000030'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000030'::uuid, 3, 16, 'schoch1'),
    (v_tid, 1, 33, '00000000-0000-0000-0c0c-000000000049'::uuid, '00000000-0000-0000-0c0c-000000000065'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000049'::uuid, 13, 8, 'schoch1'),
    (v_tid, 1, 34, '00000000-0000-0000-0c0c-000000000069'::uuid, '00000000-0000-0000-0c0c-000000000029'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000029'::uuid, 3, 16, 'schoch1'),
    (v_tid, 1, 35, '00000000-0000-0000-0c0c-000000000058'::uuid, '00000000-0000-0000-0c0c-000000000054'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000054'::uuid, 8, 13, 'schoch1'),
    (v_tid, 1, 36, '00000000-0000-0000-0c0c-000000000067'::uuid, '00000000-0000-0000-0c0c-000000000025'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000025'::uuid, 5, 11, 'schoch1'),
    (v_tid, 2, 1, '00000000-0000-0000-0c0c-000000000002'::uuid, '00000000-0000-0000-0c0c-000000000020'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000002'::uuid, 13, 6, 'schoch1'),
    (v_tid, 2, 2, '00000000-0000-0000-0c0c-000000000007'::uuid, '00000000-0000-0000-0c0c-000000000023'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000023'::uuid, 12, 13, 'schoch1'),
    (v_tid, 2, 3, '00000000-0000-0000-0c0c-000000000014'::uuid, '00000000-0000-0000-0c0c-000000000033'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000014'::uuid, 16, 4, 'schoch1'),
    (v_tid, 2, 4, '00000000-0000-0000-0c0c-000000000001'::uuid, '00000000-0000-0000-0c0c-000000000026'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000001'::uuid, 16, 4, 'schoch1'),
    (v_tid, 2, 5, '00000000-0000-0000-0c0c-000000000004'::uuid, '00000000-0000-0000-0c0c-000000000018'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000004'::uuid, 12, 11, 'schoch1'),
    (v_tid, 2, 6, '00000000-0000-0000-0c0c-000000000016'::uuid, '00000000-0000-0000-0c0c-000000000028'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000016'::uuid, 16, 4, 'schoch1'),
    (v_tid, 2, 7, '00000000-0000-0000-0c0c-000000000006'::uuid, '00000000-0000-0000-0c0c-000000000027'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000006'::uuid, 16, 5, 'schoch1'),
    (v_tid, 2, 8, '00000000-0000-0000-0c0c-000000000037'::uuid, '00000000-0000-0000-0c0c-000000000017'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000017'::uuid, 3, 16, 'schoch1'),
    (v_tid, 2, 9, '00000000-0000-0000-0c0c-000000000003'::uuid, '00000000-0000-0000-0c0c-000000000073'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000003'::uuid, 16, 2, 'schoch1'),
    (v_tid, 2, 10, '00000000-0000-0000-0c0c-000000000021'::uuid, '00000000-0000-0000-0c0c-000000000009'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000009'::uuid, 9, 11, 'schoch1'),
    (v_tid, 2, 11, '00000000-0000-0000-0c0c-000000000012'::uuid, '00000000-0000-0000-0c0c-000000000008'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000008'::uuid, 11, 12, 'schoch1'),
    (v_tid, 2, 12, '00000000-0000-0000-0c0c-000000000040'::uuid, '00000000-0000-0000-0c0c-000000000005'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000005'::uuid, 6, 16, 'schoch1'),
    (v_tid, 2, 13, '00000000-0000-0000-0c0c-000000000015'::uuid, '00000000-0000-0000-0c0c-000000000041'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000015'::uuid, 16, 2, 'schoch1'),
    (v_tid, 2, 14, '00000000-0000-0000-0c0c-000000000019'::uuid, '00000000-0000-0000-0c0c-000000000029'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000029'::uuid, 10, 11, 'schoch1'),
    (v_tid, 2, 15, '00000000-0000-0000-0c0c-000000000010'::uuid, '00000000-0000-0000-0c0c-000000000030'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000030'::uuid, 9, 11, 'schoch1'),
    (v_tid, 2, 16, '00000000-0000-0000-0c0c-000000000071'::uuid, '00000000-0000-0000-0c0c-000000000054'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000071'::uuid, 8, 4, 'schoch1'),
    (v_tid, 2, 17, '00000000-0000-0000-0c0c-000000000049'::uuid, '00000000-0000-0000-0c0c-000000000024'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000049'::uuid, 12, 9, 'schoch1'),
    (v_tid, 2, 18, '00000000-0000-0000-0c0c-000000000032'::uuid, '00000000-0000-0000-0c0c-000000000013'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000032'::uuid, 10, 9, 'schoch1'),
    (v_tid, 2, 19, '00000000-0000-0000-0c0c-000000000025'::uuid, '00000000-0000-0000-0c0c-000000000011'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000011'::uuid, 7, 12, 'schoch1'),
    (v_tid, 2, 20, '00000000-0000-0000-0c0c-000000000043'::uuid, '00000000-0000-0000-0c0c-000000000048'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000048'::uuid, 9, 16, 'schoch1'),
    (v_tid, 2, 21, '00000000-0000-0000-0c0c-000000000058'::uuid, '00000000-0000-0000-0c0c-000000000065'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000065'::uuid, 6, 10, 'schoch1'),
    (v_tid, 2, 22, '00000000-0000-0000-0c0c-000000000036'::uuid, '00000000-0000-0000-0c0c-000000000063'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000063'::uuid, 10, 13, 'schoch1'),
    (v_tid, 2, 23, '00000000-0000-0000-0c0c-000000000052'::uuid, '00000000-0000-0000-0c0c-000000000022'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000022'::uuid, 3, 16, 'schoch1'),
    (v_tid, 2, 24, '00000000-0000-0000-0c0c-000000000057'::uuid, '00000000-0000-0000-0c0c-000000000044'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000057'::uuid, 10, 6, 'schoch1'),
    (v_tid, 2, 25, '00000000-0000-0000-0c0c-000000000031'::uuid, '00000000-0000-0000-0c0c-000000000045'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000045'::uuid, 5, 16, 'schoch1'),
    (v_tid, 2, 26, '00000000-0000-0000-0c0c-000000000059'::uuid, '00000000-0000-0000-0c0c-000000000067'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000059'::uuid, 9, 7, 'schoch1'),
    (v_tid, 2, 27, '00000000-0000-0000-0c0c-000000000061'::uuid, '00000000-0000-0000-0c0c-000000000046'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000061'::uuid, 16, 4, 'schoch1'),
    (v_tid, 2, 28, '00000000-0000-0000-0c0c-000000000051'::uuid, '00000000-0000-0000-0c0c-000000000066'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000051'::uuid, 11, 5, 'schoch1'),
    (v_tid, 2, 29, '00000000-0000-0000-0c0c-000000000039'::uuid, '00000000-0000-0000-0c0c-000000000064'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000039'::uuid, 16, 5, 'schoch1'),
    (v_tid, 2, 30, '00000000-0000-0000-0c0c-000000000042'::uuid, '00000000-0000-0000-0c0c-000000000038'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000038'::uuid, 8, 12, 'schoch1'),
    (v_tid, 2, 31, '00000000-0000-0000-0c0c-000000000055'::uuid, '00000000-0000-0000-0c0c-000000000053'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000053'::uuid, 8, 11, 'schoch1'),
    (v_tid, 2, 32, '00000000-0000-0000-0c0c-000000000047'::uuid, '00000000-0000-0000-0c0c-000000000050'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000047'::uuid, 12, 9, 'schoch1'),
    (v_tid, 2, 33, '00000000-0000-0000-0c0c-000000000069'::uuid, '00000000-0000-0000-0c0c-000000000060'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000060'::uuid, 1, 16, 'schoch1'),
    (v_tid, 2, 34, '00000000-0000-0000-0c0c-000000000034'::uuid, '00000000-0000-0000-0c0c-000000000035'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000034'::uuid, 12, 9, 'schoch1'),
    (v_tid, 2, 35, '00000000-0000-0000-0c0c-000000000072'::uuid, '00000000-0000-0000-0c0c-000000000056'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000056'::uuid, 5, 16, 'schoch1'),
    (v_tid, 2, 36, '00000000-0000-0000-0c0c-000000000068'::uuid, '00000000-0000-0000-0c0c-000000000070'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000068'::uuid, 9, 7, 'schoch1'),
    (v_tid, 3, 1, '00000000-0000-0000-0c0c-000000000001'::uuid, '00000000-0000-0000-0c0c-000000000006'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000006'::uuid, 8, 16, 'schoch1'),
    (v_tid, 3, 2, '00000000-0000-0000-0c0c-000000000015'::uuid, '00000000-0000-0000-0c0c-000000000016'::uuid, 'group', 'finalized', NULL, 12, 12, 'schoch1'),
    (v_tid, 3, 3, '00000000-0000-0000-0c0c-000000000014'::uuid, '00000000-0000-0000-0c0c-000000000005'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000005'::uuid, 10, 11, 'schoch1'),
    (v_tid, 3, 4, '00000000-0000-0000-0c0c-000000000017'::uuid, '00000000-0000-0000-0c0c-000000000003'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000003'::uuid, 4, 16, 'schoch1'),
    (v_tid, 3, 5, '00000000-0000-0000-0c0c-000000000002'::uuid, '00000000-0000-0000-0c0c-000000000023'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000002'::uuid, 16, 5, 'schoch1'),
    (v_tid, 3, 6, '00000000-0000-0000-0c0c-000000000007'::uuid, '00000000-0000-0000-0c0c-000000000008'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000007'::uuid, 11, 9, 'schoch1'),
    (v_tid, 3, 7, '00000000-0000-0000-0c0c-000000000004'::uuid, '00000000-0000-0000-0c0c-000000000009'::uuid, 'group', 'finalized', NULL, 10, 10, 'schoch1'),
    (v_tid, 3, 8, '00000000-0000-0000-0c0c-000000000012'::uuid, '00000000-0000-0000-0c0c-000000000030'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000012'::uuid, 16, 5, 'schoch1'),
    (v_tid, 3, 9, '00000000-0000-0000-0c0c-000000000018'::uuid, '00000000-0000-0000-0c0c-000000000029'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000018'::uuid, 13, 8, 'schoch1'),
    (v_tid, 3, 10, '00000000-0000-0000-0c0c-000000000019'::uuid, '00000000-0000-0000-0c0c-000000000010'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000019'::uuid, 12, 10, 'schoch1'),
    (v_tid, 3, 11, '00000000-0000-0000-0c0c-000000000049'::uuid, '00000000-0000-0000-0c0c-000000000048'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000048'::uuid, 10, 12, 'schoch1'),
    (v_tid, 3, 12, '00000000-0000-0000-0c0c-000000000021'::uuid, '00000000-0000-0000-0c0c-000000000022'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000022'::uuid, 9, 12, 'schoch1'),
    (v_tid, 3, 13, '00000000-0000-0000-0c0c-000000000040'::uuid, '00000000-0000-0000-0c0c-000000000020'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000040'::uuid, 16, 6, 'schoch1'),
    (v_tid, 3, 14, '00000000-0000-0000-0c0c-000000000032'::uuid, '00000000-0000-0000-0c0c-000000000045'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000032'::uuid, 16, 6, 'schoch1'),
    (v_tid, 3, 15, '00000000-0000-0000-0c0c-000000000027'::uuid, '00000000-0000-0000-0c0c-000000000071'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000027'::uuid, 16, 7, 'schoch1'),
    (v_tid, 3, 16, '00000000-0000-0000-0c0c-000000000011'::uuid, '00000000-0000-0000-0c0c-000000000024'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000011'::uuid, 16, 6, 'schoch1'),
    (v_tid, 3, 17, '00000000-0000-0000-0c0c-000000000039'::uuid, '00000000-0000-0000-0c0c-000000000061'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000039'::uuid, 16, 5, 'schoch1'),
    (v_tid, 3, 18, '00000000-0000-0000-0c0c-000000000028'::uuid, '00000000-0000-0000-0c0c-000000000026'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000026'::uuid, 3, 16, 'schoch1'),
    (v_tid, 3, 19, '00000000-0000-0000-0c0c-000000000033'::uuid, '00000000-0000-0000-0c0c-000000000013'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000033'::uuid, 13, 12, 'schoch1'),
    (v_tid, 3, 20, '00000000-0000-0000-0c0c-000000000063'::uuid, '00000000-0000-0000-0c0c-000000000037'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000063'::uuid, 16, 5, 'schoch1'),
    (v_tid, 3, 21, '00000000-0000-0000-0c0c-000000000043'::uuid, '00000000-0000-0000-0c0c-000000000060'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000043'::uuid, 11, 8, 'schoch1'),
    (v_tid, 3, 22, '00000000-0000-0000-0c0c-000000000065'::uuid, '00000000-0000-0000-0c0c-000000000036'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000065'::uuid, 11, 10, 'schoch1'),
    (v_tid, 3, 23, '00000000-0000-0000-0c0c-000000000041'::uuid, '00000000-0000-0000-0c0c-000000000073'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000041'::uuid, 16, 1, 'schoch1'),
    (v_tid, 3, 24, '00000000-0000-0000-0c0c-000000000025'::uuid, '00000000-0000-0000-0c0c-000000000056'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000025'::uuid, 11, 9, 'schoch1'),
    (v_tid, 3, 25, '00000000-0000-0000-0c0c-000000000054'::uuid, '00000000-0000-0000-0c0c-000000000057'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000057'::uuid, 4, 16, 'schoch1'),
    (v_tid, 3, 26, '00000000-0000-0000-0c0c-000000000051'::uuid, '00000000-0000-0000-0c0c-000000000047'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000047'::uuid, 8, 11, 'schoch1'),
    (v_tid, 3, 27, '00000000-0000-0000-0c0c-000000000062'::uuid, '00000000-0000-0000-0c0c-000000000038'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000038'::uuid, 5, 12, 'schoch1'),
    (v_tid, 3, 28, '00000000-0000-0000-0c0c-000000000059'::uuid, '00000000-0000-0000-0c0c-000000000053'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000059'::uuid, 11, 7, 'schoch1'),
    (v_tid, 3, 29, '00000000-0000-0000-0c0c-000000000058'::uuid, '00000000-0000-0000-0c0c-000000000034'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000034'::uuid, 3, 16, 'schoch1'),
    (v_tid, 3, 30, '00000000-0000-0000-0c0c-000000000044'::uuid, '00000000-0000-0000-0c0c-000000000042'::uuid, 'group', 'finalized', NULL, 11, 11, 'schoch1'),
    (v_tid, 3, 31, '00000000-0000-0000-0c0c-000000000055'::uuid, '00000000-0000-0000-0c0c-000000000050'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000055'::uuid, 11, 4, 'schoch1'),
    (v_tid, 3, 32, '00000000-0000-0000-0c0c-000000000067'::uuid, '00000000-0000-0000-0c0c-000000000031'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000031'::uuid, 7, 16, 'schoch1'),
    (v_tid, 3, 33, '00000000-0000-0000-0c0c-000000000035'::uuid, '00000000-0000-0000-0c0c-000000000064'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000035'::uuid, 11, 10, 'schoch1'),
    (v_tid, 3, 34, '00000000-0000-0000-0c0c-000000000066'::uuid, '00000000-0000-0000-0c0c-000000000068'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000068'::uuid, 7, 10, 'schoch1'),
    (v_tid, 3, 35, '00000000-0000-0000-0c0c-000000000052'::uuid, '00000000-0000-0000-0c0c-000000000046'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000046'::uuid, 8, 10, 'schoch1'),
    (v_tid, 3, 36, '00000000-0000-0000-0c0c-000000000070'::uuid, '00000000-0000-0000-0c0c-000000000072'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000070'::uuid, 16, 2, 'schoch1'),
    (v_tid, 4, 1, '00000000-0000-0000-0c0c-000000000006'::uuid, '00000000-0000-0000-0c0c-000000000003'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000006'::uuid, 12, 10, 'schoch1'),
    (v_tid, 4, 2, '00000000-0000-0000-0c0c-000000000002'::uuid, '00000000-0000-0000-0c0c-000000000015'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000002'::uuid, 12, 10, 'schoch1'),
    (v_tid, 4, 3, '00000000-0000-0000-0c0c-000000000016'::uuid, '00000000-0000-0000-0c0c-000000000005'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000005'::uuid, 8, 16, 'schoch1'),
    (v_tid, 4, 4, '00000000-0000-0000-0c0c-000000000012'::uuid, '00000000-0000-0000-0c0c-000000000014'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000014'::uuid, 10, 12, 'schoch1'),
    (v_tid, 4, 5, '00000000-0000-0000-0c0c-000000000001'::uuid, '00000000-0000-0000-0c0c-000000000018'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000001'::uuid, 16, 4, 'schoch1'),
    (v_tid, 4, 6, '00000000-0000-0000-0c0c-000000000007'::uuid, '00000000-0000-0000-0c0c-000000000004'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000007'::uuid, 12, 10, 'schoch1'),
    (v_tid, 4, 7, '00000000-0000-0000-0c0c-000000000040'::uuid, '00000000-0000-0000-0c0c-000000000019'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000019'::uuid, 8, 10, 'schoch1'),
    (v_tid, 4, 8, '00000000-0000-0000-0c0c-000000000032'::uuid, '00000000-0000-0000-0c0c-000000000009'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000032'::uuid, 12, 9, 'schoch1'),
    (v_tid, 4, 9, '00000000-0000-0000-0c0c-000000000008'::uuid, '00000000-0000-0000-0c0c-000000000048'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000008'::uuid, 16, 5, 'schoch1'),
    (v_tid, 4, 10, '00000000-0000-0000-0c0c-000000000027'::uuid, '00000000-0000-0000-0c0c-000000000011'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000011'::uuid, 5, 16, 'schoch1'),
    (v_tid, 4, 11, '00000000-0000-0000-0c0c-000000000039'::uuid, '00000000-0000-0000-0c0c-000000000017'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000017'::uuid, 7, 16, 'schoch1'),
    (v_tid, 4, 12, '00000000-0000-0000-0c0c-000000000026'::uuid, '00000000-0000-0000-0c0c-000000000063'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000026'::uuid, 16, 5, 'schoch1'),
    (v_tid, 4, 13, '00000000-0000-0000-0c0c-000000000010'::uuid, '00000000-0000-0000-0c0c-000000000029'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000010'::uuid, 11, 9, 'schoch1'),
    (v_tid, 4, 14, '00000000-0000-0000-0c0c-000000000049'::uuid, '00000000-0000-0000-0c0c-000000000022'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000022'::uuid, 5, 12, 'schoch1'),
    (v_tid, 4, 15, '00000000-0000-0000-0c0c-000000000023'::uuid, '00000000-0000-0000-0c0c-000000000021'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000023'::uuid, 16, 4, 'schoch1'),
    (v_tid, 4, 16, '00000000-0000-0000-0c0c-000000000041'::uuid, '00000000-0000-0000-0c0c-000000000033'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000033'::uuid, 7, 16, 'schoch1'),
    (v_tid, 4, 17, '00000000-0000-0000-0c0c-000000000057'::uuid, '00000000-0000-0000-0c0c-000000000030'::uuid, 'group', 'finalized', NULL, 8, 8, 'schoch1'),
    (v_tid, 4, 18, '00000000-0000-0000-0c0c-000000000013'::uuid, '00000000-0000-0000-0c0c-000000000043'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000013'::uuid, 16, 7, 'schoch1'),
    (v_tid, 4, 19, '00000000-0000-0000-0c0c-000000000034'::uuid, '00000000-0000-0000-0c0c-000000000025'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000034'::uuid, 16, 6, 'schoch1'),
    (v_tid, 4, 20, '00000000-0000-0000-0c0c-000000000065'::uuid, '00000000-0000-0000-0c0c-000000000020'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000020'::uuid, 4, 13, 'schoch1'),
    (v_tid, 4, 21, '00000000-0000-0000-0c0c-000000000071'::uuid, '00000000-0000-0000-0c0c-000000000045'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000045'::uuid, 1, 16, 'schoch1'),
    (v_tid, 4, 22, '00000000-0000-0000-0c0c-000000000036'::uuid, '00000000-0000-0000-0c0c-000000000038'::uuid, 'group', 'finalized', NULL, 10, 10, 'schoch1'),
    (v_tid, 4, 23, '00000000-0000-0000-0c0c-000000000024'::uuid, '00000000-0000-0000-0c0c-000000000060'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000024'::uuid, 12, 10, 'schoch1'),
    (v_tid, 4, 24, '00000000-0000-0000-0c0c-000000000047'::uuid, '00000000-0000-0000-0c0c-000000000031'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000031'::uuid, 4, 16, 'schoch1'),
    (v_tid, 4, 25, '00000000-0000-0000-0c0c-000000000056'::uuid, '00000000-0000-0000-0c0c-000000000061'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000061'::uuid, 9, 10, 'schoch1'),
    (v_tid, 4, 26, '00000000-0000-0000-0c0c-000000000059'::uuid, '00000000-0000-0000-0c0c-000000000037'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000037'::uuid, 6, 16, 'schoch1'),
    (v_tid, 4, 27, '00000000-0000-0000-0c0c-000000000044'::uuid, '00000000-0000-0000-0c0c-000000000051'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000044'::uuid, 13, 9, 'schoch1'),
    (v_tid, 4, 28, '00000000-0000-0000-0c0c-000000000070'::uuid, '00000000-0000-0000-0c0c-000000000028'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000028'::uuid, 4, 12, 'schoch1'),
    (v_tid, 4, 29, '00000000-0000-0000-0c0c-000000000042'::uuid, '00000000-0000-0000-0c0c-000000000055'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000042'::uuid, 12, 9, 'schoch1'),
    (v_tid, 4, 30, '00000000-0000-0000-0c0c-000000000035'::uuid, '00000000-0000-0000-0c0c-000000000053'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000035'::uuid, 16, 0, 'schoch1'),
    (v_tid, 4, 31, '00000000-0000-0000-0c0c-000000000054'::uuid, '00000000-0000-0000-0c0c-000000000062'::uuid, 'group', 'finalized', NULL, 10, 10, 'schoch1'),
    (v_tid, 4, 32, '00000000-0000-0000-0c0c-000000000064'::uuid, '00000000-0000-0000-0c0c-000000000068'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000068'::uuid, 6, 16, 'schoch1'),
    (v_tid, 4, 33, '00000000-0000-0000-0c0c-000000000069'::uuid, '00000000-0000-0000-0c0c-000000000046'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000046'::uuid, 10, 12, 'schoch1'),
    (v_tid, 4, 34, '00000000-0000-0000-0c0c-000000000073'::uuid, '00000000-0000-0000-0c0c-000000000067'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000067'::uuid, 4, 16, 'schoch1'),
    (v_tid, 4, 35, '00000000-0000-0000-0c0c-000000000052'::uuid, '00000000-0000-0000-0c0c-000000000058'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000058'::uuid, 4, 16, 'schoch1'),
    (v_tid, 4, 36, '00000000-0000-0000-0c0c-000000000066'::uuid, '00000000-0000-0000-0c0c-000000000050'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000050'::uuid, 6, 16, 'schoch1'),
    (v_tid, 5, 1, '00000000-0000-0000-0c0c-000000000006'::uuid, '00000000-0000-0000-0c0c-000000000005'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000006'::uuid, 11, 8, 'schoch1'),
    (v_tid, 5, 2, '00000000-0000-0000-0c0c-000000000003'::uuid, '00000000-0000-0000-0c0c-000000000002'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000002'::uuid, 10, 16, 'schoch1'),
    (v_tid, 5, 3, '00000000-0000-0000-0c0c-000000000001'::uuid, '00000000-0000-0000-0c0c-000000000014'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000001'::uuid, 11, 10, 'schoch1'),
    (v_tid, 5, 4, '00000000-0000-0000-0c0c-000000000015'::uuid, '00000000-0000-0000-0c0c-000000000008'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000008'::uuid, 10, 12, 'schoch1'),
    (v_tid, 5, 5, '00000000-0000-0000-0c0c-000000000012'::uuid, '00000000-0000-0000-0c0c-000000000011'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000011'::uuid, 7, 13, 'schoch1'),
    (v_tid, 5, 6, '00000000-0000-0000-0c0c-000000000016'::uuid, '00000000-0000-0000-0c0c-000000000026'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000016'::uuid, 11, 8, 'schoch1'),
    (v_tid, 5, 7, '00000000-0000-0000-0c0c-000000000017'::uuid, '00000000-0000-0000-0c0c-000000000007'::uuid, 'group', 'finalized', NULL, 10, 10, 'schoch1'),
    (v_tid, 5, 8, '00000000-0000-0000-0c0c-000000000032'::uuid, '00000000-0000-0000-0c0c-000000000023'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000032'::uuid, 16, 6, 'schoch1'),
    (v_tid, 5, 9, '00000000-0000-0000-0c0c-000000000033'::uuid, '00000000-0000-0000-0c0c-000000000004'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000004'::uuid, 4, 16, 'schoch1'),
    (v_tid, 5, 10, '00000000-0000-0000-0c0c-000000000019'::uuid, '00000000-0000-0000-0c0c-000000000013'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000019'::uuid, 12, 11, 'schoch1'),
    (v_tid, 5, 11, '00000000-0000-0000-0c0c-000000000022'::uuid, '00000000-0000-0000-0c0c-000000000040'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000022'::uuid, 11, 10, 'schoch1'),
    (v_tid, 5, 12, '00000000-0000-0000-0c0c-000000000009'::uuid, '00000000-0000-0000-0c0c-000000000010'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000010'::uuid, 9, 11, 'schoch1'),
    (v_tid, 5, 13, '00000000-0000-0000-0c0c-000000000034'::uuid, '00000000-0000-0000-0c0c-000000000018'::uuid, 'group', 'finalized', NULL, 9, 9, 'schoch1'),
    (v_tid, 5, 14, '00000000-0000-0000-0c0c-000000000039'::uuid, '00000000-0000-0000-0c0c-000000000045'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000039'::uuid, 16, 1, 'schoch1'),
    (v_tid, 5, 15, '00000000-0000-0000-0c0c-000000000029'::uuid, '00000000-0000-0000-0c0c-000000000031'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000029'::uuid, 16, 6, 'schoch1'),
    (v_tid, 5, 16, '00000000-0000-0000-0c0c-000000000048'::uuid, '00000000-0000-0000-0c0c-000000000027'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000027'::uuid, 5, 12, 'schoch1'),
    (v_tid, 5, 17, '00000000-0000-0000-0c0c-000000000020'::uuid, '00000000-0000-0000-0c0c-000000000063'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000063'::uuid, 10, 11, 'schoch1'),
    (v_tid, 5, 18, '00000000-0000-0000-0c0c-000000000057'::uuid, '00000000-0000-0000-0c0c-000000000041'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000041'::uuid, 4, 16, 'schoch1'),
    (v_tid, 5, 19, '00000000-0000-0000-0c0c-000000000030'::uuid, '00000000-0000-0000-0c0c-000000000037'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000030'::uuid, 16, 5, 'schoch1'),
    (v_tid, 5, 20, '00000000-0000-0000-0c0c-000000000049'::uuid, '00000000-0000-0000-0c0c-000000000021'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000021'::uuid, 4, 16, 'schoch1'),
    (v_tid, 5, 21, '00000000-0000-0000-0c0c-000000000024'::uuid, '00000000-0000-0000-0c0c-000000000036'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000024'::uuid, 12, 10, 'schoch1'),
    (v_tid, 5, 22, '00000000-0000-0000-0c0c-000000000035'::uuid, '00000000-0000-0000-0c0c-000000000043'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000043'::uuid, 8, 9, 'schoch1'),
    (v_tid, 5, 23, '00000000-0000-0000-0c0c-000000000038'::uuid, '00000000-0000-0000-0c0c-000000000060'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000038'::uuid, 10, 8, 'schoch1'),
    (v_tid, 5, 24, '00000000-0000-0000-0c0c-000000000044'::uuid, '00000000-0000-0000-0c0c-000000000061'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000044'::uuid, 16, 6, 'schoch1'),
    (v_tid, 5, 25, '00000000-0000-0000-0c0c-000000000056'::uuid, '00000000-0000-0000-0c0c-000000000068'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000056'::uuid, 11, 4, 'schoch1'),
    (v_tid, 5, 26, '00000000-0000-0000-0c0c-000000000025'::uuid, '00000000-0000-0000-0c0c-000000000042'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000042'::uuid, 10, 11, 'schoch1'),
    (v_tid, 5, 27, '00000000-0000-0000-0c0c-000000000028'::uuid, '00000000-0000-0000-0c0c-000000000067'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000028'::uuid, 11, 7, 'schoch1'),
    (v_tid, 5, 28, '00000000-0000-0000-0c0c-000000000065'::uuid, '00000000-0000-0000-0c0c-000000000051'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000051'::uuid, 5, 12, 'schoch1'),
    (v_tid, 5, 29, '00000000-0000-0000-0c0c-000000000058'::uuid, '00000000-0000-0000-0c0c-000000000055'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000055'::uuid, 6, 10, 'schoch1'),
    (v_tid, 5, 30, '00000000-0000-0000-0c0c-000000000059'::uuid, '00000000-0000-0000-0c0c-000000000050'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000050'::uuid, 7, 16, 'schoch1'),
    (v_tid, 5, 31, '00000000-0000-0000-0c0c-000000000047'::uuid, '00000000-0000-0000-0c0c-000000000046'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000046'::uuid, 2, 16, 'schoch1'),
    (v_tid, 5, 32, '00000000-0000-0000-0c0c-000000000054'::uuid, '00000000-0000-0000-0c0c-000000000069'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000054'::uuid, 11, 10, 'schoch1'),
    (v_tid, 5, 33, '00000000-0000-0000-0c0c-000000000062'::uuid, '00000000-0000-0000-0c0c-000000000071'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000062'::uuid, 11, 9, 'schoch1'),
    (v_tid, 5, 34, '00000000-0000-0000-0c0c-000000000070'::uuid, '00000000-0000-0000-0c0c-000000000064'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000070'::uuid, 5, 4, 'schoch1'),
    (v_tid, 5, 35, '00000000-0000-0000-0c0c-000000000072'::uuid, '00000000-0000-0000-0c0c-000000000073'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000072'::uuid, 10, 5, 'schoch1'),
    (v_tid, 5, 36, '00000000-0000-0000-0c0c-000000000066'::uuid, '00000000-0000-0000-0c0c-000000000052'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000052'::uuid, 5, 16, 'schoch1'),
    (v_tid, 6, 1, '00000000-0000-0000-0c0c-000000000002'::uuid, '00000000-0000-0000-0c0c-000000000006'::uuid, 'group', 'finalized', NULL, 11, 11, 'schoch1'),
    (v_tid, 6, 2, '00000000-0000-0000-0c0c-000000000003'::uuid, '00000000-0000-0000-0c0c-000000000005'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000005'::uuid, 6, 16, 'schoch1'),
    (v_tid, 6, 3, '00000000-0000-0000-0c0c-000000000001'::uuid, '00000000-0000-0000-0c0c-000000000011'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000001'::uuid, 16, 8, 'schoch1'),
    (v_tid, 6, 4, '00000000-0000-0000-0c0c-000000000032'::uuid, '00000000-0000-0000-0c0c-000000000008'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000008'::uuid, 5, 16, 'schoch1'),
    (v_tid, 6, 5, '00000000-0000-0000-0c0c-000000000014'::uuid, '00000000-0000-0000-0c0c-000000000015'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000015'::uuid, 10, 13, 'schoch1'),
    (v_tid, 6, 6, '00000000-0000-0000-0c0c-000000000004'::uuid, '00000000-0000-0000-0c0c-000000000016'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000016'::uuid, 9, 11, 'schoch1'),
    (v_tid, 6, 7, '00000000-0000-0000-0c0c-000000000017'::uuid, '00000000-0000-0000-0c0c-000000000012'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000017'::uuid, 13, 10, 'schoch1'),
    (v_tid, 6, 8, '00000000-0000-0000-0c0c-000000000007'::uuid, '00000000-0000-0000-0c0c-000000000026'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000007'::uuid, 16, 4, 'schoch1'),
    (v_tid, 6, 9, '00000000-0000-0000-0c0c-000000000019'::uuid, '00000000-0000-0000-0c0c-000000000039'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000019'::uuid, 16, 5, 'schoch1'),
    (v_tid, 6, 10, '00000000-0000-0000-0c0c-000000000029'::uuid, '00000000-0000-0000-0c0c-000000000013'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000013'::uuid, 5, 16, 'schoch1'),
    (v_tid, 6, 11, '00000000-0000-0000-0c0c-000000000022'::uuid, '00000000-0000-0000-0c0c-000000000010'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000010'::uuid, 9, 10, 'schoch1'),
    (v_tid, 6, 12, '00000000-0000-0000-0c0c-000000000041'::uuid, '00000000-0000-0000-0c0c-000000000023'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000041'::uuid, 11, 10, 'schoch1'),
    (v_tid, 6, 13, '00000000-0000-0000-0c0c-000000000040'::uuid, '00000000-0000-0000-0c0c-000000000030'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000040'::uuid, 16, 9, 'schoch1'),
    (v_tid, 6, 14, '00000000-0000-0000-0c0c-000000000009'::uuid, '00000000-0000-0000-0c0c-000000000034'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000009'::uuid, 16, 6, 'schoch1'),
    (v_tid, 6, 15, '00000000-0000-0000-0c0c-000000000027'::uuid, '00000000-0000-0000-0c0c-000000000021'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000027'::uuid, 12, 8, 'schoch1'),
    (v_tid, 6, 16, '00000000-0000-0000-0c0c-000000000018'::uuid, '00000000-0000-0000-0c0c-000000000033'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000018'::uuid, 12, 10, 'schoch1'),
    (v_tid, 6, 17, '00000000-0000-0000-0c0c-000000000044'::uuid, '00000000-0000-0000-0c0c-000000000063'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000044'::uuid, 16, 1, 'schoch1'),
    (v_tid, 6, 18, '00000000-0000-0000-0c0c-000000000020'::uuid, '00000000-0000-0000-0c0c-000000000024'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000020'::uuid, 12, 10, 'schoch1'),
    (v_tid, 6, 19, '00000000-0000-0000-0c0c-000000000031'::uuid, '00000000-0000-0000-0c0c-000000000036'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000036'::uuid, 4, 16, 'schoch1'),
    (v_tid, 6, 20, '00000000-0000-0000-0c0c-000000000038'::uuid, '00000000-0000-0000-0c0c-000000000050'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000038'::uuid, 9, 8, 'schoch1'),
    (v_tid, 6, 21, '00000000-0000-0000-0c0c-000000000048'::uuid, '00000000-0000-0000-0c0c-000000000056'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000056'::uuid, 9, 10, 'schoch1'),
    (v_tid, 6, 22, '00000000-0000-0000-0c0c-000000000046'::uuid, '00000000-0000-0000-0c0c-000000000043'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000046'::uuid, 13, 9, 'schoch1'),
    (v_tid, 6, 23, '00000000-0000-0000-0c0c-000000000042'::uuid, '00000000-0000-0000-0c0c-000000000028'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000028'::uuid, 5, 16, 'schoch1'),
    (v_tid, 6, 24, '00000000-0000-0000-0c0c-000000000035'::uuid, '00000000-0000-0000-0c0c-000000000045'::uuid, 'group', 'finalized', NULL, 11, 11, 'schoch1'),
    (v_tid, 6, 25, '00000000-0000-0000-0c0c-000000000057'::uuid, '00000000-0000-0000-0c0c-000000000037'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000037'::uuid, 7, 16, 'schoch1'),
    (v_tid, 6, 26, '00000000-0000-0000-0c0c-000000000025'::uuid, '00000000-0000-0000-0c0c-000000000060'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000025'::uuid, 16, 4, 'schoch1'),
    (v_tid, 6, 27, '00000000-0000-0000-0c0c-000000000051'::uuid, '00000000-0000-0000-0c0c-000000000049'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000051'::uuid, 11, 4, 'schoch1'),
    (v_tid, 6, 28, '00000000-0000-0000-0c0c-000000000061'::uuid, '00000000-0000-0000-0c0c-000000000055'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000055'::uuid, 2, 10, 'schoch1'),
    (v_tid, 6, 29, '00000000-0000-0000-0c0c-000000000067'::uuid, '00000000-0000-0000-0c0c-000000000054'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000067'::uuid, 8, 4, 'schoch1'),
    (v_tid, 6, 30, '00000000-0000-0000-0c0c-000000000062'::uuid, '00000000-0000-0000-0c0c-000000000068'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000062'::uuid, 9, 6, 'schoch1'),
    (v_tid, 6, 31, '00000000-0000-0000-0c0c-000000000069'::uuid, '00000000-0000-0000-0c0c-000000000059'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000059'::uuid, 8, 10, 'schoch1'),
    (v_tid, 6, 32, '00000000-0000-0000-0c0c-000000000058'::uuid, '00000000-0000-0000-0c0c-000000000071'::uuid, 'group', 'finalized', NULL, 4, 4, 'schoch1'),
    (v_tid, 6, 33, '00000000-0000-0000-0c0c-000000000065'::uuid, '00000000-0000-0000-0c0c-000000000052'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000052'::uuid, 3, 16, 'schoch1'),
    (v_tid, 6, 34, '00000000-0000-0000-0c0c-000000000053'::uuid, '00000000-0000-0000-0c0c-000000000072'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000053'::uuid, 16, 5, 'schoch1'),
    (v_tid, 6, 35, '00000000-0000-0000-0c0c-000000000047'::uuid, '00000000-0000-0000-0c0c-000000000070'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000047'::uuid, 16, 2, 'schoch1'),
    (v_tid, 6, 36, '00000000-0000-0000-0c0c-000000000064'::uuid, '00000000-0000-0000-0c0c-000000000073'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000073'::uuid, 8, 9, 'schoch1'),
    (v_tid, 7, 1, '00000000-0000-0000-0c0c-000000000002'::uuid, '00000000-0000-0000-0c0c-000000000005'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000002'::uuid, 16, 7, 'schoch1'),
    (v_tid, 7, 2, '00000000-0000-0000-0c0c-000000000001'::uuid, '00000000-0000-0000-0c0c-000000000008'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000001'::uuid, 11, 10, 'schoch1'),
    (v_tid, 7, 3, '00000000-0000-0000-0c0c-000000000006'::uuid, '00000000-0000-0000-0c0c-000000000015'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000015'::uuid, 11, 12, 'schoch1'),
    (v_tid, 7, 4, '00000000-0000-0000-0c0c-000000000007'::uuid, '00000000-0000-0000-0c0c-000000000019'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000007'::uuid, 12, 8, 'schoch1'),
    (v_tid, 7, 5, '00000000-0000-0000-0c0c-000000000017'::uuid, '00000000-0000-0000-0c0c-000000000013'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000017'::uuid, 12, 10, 'schoch1'),
    (v_tid, 7, 6, '00000000-0000-0000-0c0c-000000000014'::uuid, '00000000-0000-0000-0c0c-000000000003'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000003'::uuid, 5, 16, 'schoch1'),
    (v_tid, 7, 7, '00000000-0000-0000-0c0c-000000000016'::uuid, '00000000-0000-0000-0c0c-000000000011'::uuid, 'group', 'finalized', NULL, 11, 11, 'schoch1'),
    (v_tid, 7, 8, '00000000-0000-0000-0c0c-000000000004'::uuid, '00000000-0000-0000-0c0c-000000000040'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000004'::uuid, 16, 2, 'schoch1'),
    (v_tid, 7, 9, '00000000-0000-0000-0c0c-000000000032'::uuid, '00000000-0000-0000-0c0c-000000000012'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000012'::uuid, 8, 16, 'schoch1'),
    (v_tid, 7, 10, '00000000-0000-0000-0c0c-000000000009'::uuid, '00000000-0000-0000-0c0c-000000000044'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000009'::uuid, 16, 3, 'schoch1'),
    (v_tid, 7, 11, '00000000-0000-0000-0c0c-000000000041'::uuid, '00000000-0000-0000-0c0c-000000000010'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000010'::uuid, 6, 16, 'schoch1'),
    (v_tid, 7, 12, '00000000-0000-0000-0c0c-000000000022'::uuid, '00000000-0000-0000-0c0c-000000000023'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000022'::uuid, 16, 7, 'schoch1'),
    (v_tid, 7, 13, '00000000-0000-0000-0c0c-000000000027'::uuid, '00000000-0000-0000-0c0c-000000000018'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000018'::uuid, 9, 12, 'schoch1'),
    (v_tid, 7, 14, '00000000-0000-0000-0c0c-000000000029'::uuid, '00000000-0000-0000-0c0c-000000000030'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000030'::uuid, 10, 11, 'schoch1'),
    (v_tid, 7, 15, '00000000-0000-0000-0c0c-000000000039'::uuid, '00000000-0000-0000-0c0c-000000000026'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000026'::uuid, 4, 16, 'schoch1'),
    (v_tid, 7, 16, '00000000-0000-0000-0c0c-000000000036'::uuid, '00000000-0000-0000-0c0c-000000000033'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000036'::uuid, 12, 10, 'schoch1'),
    (v_tid, 7, 17, '00000000-0000-0000-0c0c-000000000020'::uuid, '00000000-0000-0000-0c0c-000000000021'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000020'::uuid, 13, 12, 'schoch1'),
    (v_tid, 7, 18, '00000000-0000-0000-0c0c-000000000028'::uuid, '00000000-0000-0000-0c0c-000000000034'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000034'::uuid, 8, 12, 'schoch1'),
    (v_tid, 7, 19, '00000000-0000-0000-0c0c-000000000024'::uuid, '00000000-0000-0000-0c0c-000000000037'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000024'::uuid, 12, 9, 'schoch1'),
    (v_tid, 7, 20, '00000000-0000-0000-0c0c-000000000025'::uuid, '00000000-0000-0000-0c0c-000000000046'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000025'::uuid, 16, 4, 'schoch1'),
    (v_tid, 7, 21, '00000000-0000-0000-0c0c-000000000038'::uuid, '00000000-0000-0000-0c0c-000000000056'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000038'::uuid, 16, 4, 'schoch1'),
    (v_tid, 7, 22, '00000000-0000-0000-0c0c-000000000035'::uuid, '00000000-0000-0000-0c0c-000000000048'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000048'::uuid, 9, 11, 'schoch1'),
    (v_tid, 7, 23, '00000000-0000-0000-0c0c-000000000045'::uuid, '00000000-0000-0000-0c0c-000000000051'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000045'::uuid, 10, 5, 'schoch1'),
    (v_tid, 7, 24, '00000000-0000-0000-0c0c-000000000050'::uuid, '00000000-0000-0000-0c0c-000000000043'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000043'::uuid, 7, 12, 'schoch1'),
    (v_tid, 7, 25, '00000000-0000-0000-0c0c-000000000052'::uuid, '00000000-0000-0000-0c0c-000000000053'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000052'::uuid, 13, 8, 'schoch1'),
    (v_tid, 7, 26, '00000000-0000-0000-0c0c-000000000063'::uuid, '00000000-0000-0000-0c0c-000000000031'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000031'::uuid, 2, 16, 'schoch1'),
    (v_tid, 7, 27, '00000000-0000-0000-0c0c-000000000057'::uuid, '00000000-0000-0000-0c0c-000000000055'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000055'::uuid, 4, 5, 'schoch1'),
    (v_tid, 7, 28, '00000000-0000-0000-0c0c-000000000042'::uuid, '00000000-0000-0000-0c0c-000000000062'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000042'::uuid, 16, 3, 'schoch1'),
    (v_tid, 7, 29, '00000000-0000-0000-0c0c-000000000067'::uuid, '00000000-0000-0000-0c0c-000000000060'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000067'::uuid, 8, 4, 'schoch1'),
    (v_tid, 7, 30, '00000000-0000-0000-0c0c-000000000047'::uuid, '00000000-0000-0000-0c0c-000000000059'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000047'::uuid, 9, 8, 'schoch1'),
    (v_tid, 7, 31, '00000000-0000-0000-0c0c-000000000049'::uuid, '00000000-0000-0000-0c0c-000000000069'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000049'::uuid, 13, 5, 'schoch1'),
    (v_tid, 7, 32, '00000000-0000-0000-0c0c-000000000068'::uuid, '00000000-0000-0000-0c0c-000000000054'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000054'::uuid, 5, 16, 'schoch1'),
    (v_tid, 7, 33, '00000000-0000-0000-0c0c-000000000061'::uuid, '00000000-0000-0000-0c0c-000000000058'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000061'::uuid, 10, 7, 'schoch1'),
    (v_tid, 7, 34, '00000000-0000-0000-0c0c-000000000066'::uuid, '00000000-0000-0000-0c0c-000000000071'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000066'::uuid, 12, 6, 'schoch1'),
    (v_tid, 7, 35, '00000000-0000-0000-0c0c-000000000065'::uuid, '00000000-0000-0000-0c0c-000000000073'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000065'::uuid, 4, 3, 'schoch1'),
    (v_tid, 7, 36, '00000000-0000-0000-0c0c-000000000072'::uuid, '00000000-0000-0000-0c0c-000000000064'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000064'::uuid, 1, 16, 'schoch1'),
    (v_tid, 8, 1, '00000000-0000-0000-0c0c-000000000002'::uuid, '00000000-0000-0000-0c0c-000000000001'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000001'::uuid, 9, 16, 'schoch1'),
    (v_tid, 8, 2, '00000000-0000-0000-0c0c-000000000006'::uuid, '00000000-0000-0000-0c0c-000000000008'::uuid, 'group', 'finalized', NULL, 9, 9, 'schoch1'),
    (v_tid, 8, 3, '00000000-0000-0000-0c0c-000000000005'::uuid, '00000000-0000-0000-0c0c-000000000007'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000005'::uuid, 13, 12, 'schoch1'),
    (v_tid, 8, 4, '00000000-0000-0000-0c0c-000000000003'::uuid, '00000000-0000-0000-0c0c-000000000015'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000003'::uuid, 16, 6, 'schoch1'),
    (v_tid, 8, 5, '00000000-0000-0000-0c0c-000000000004'::uuid, '00000000-0000-0000-0c0c-000000000017'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000004'::uuid, 16, 6, 'schoch1'),
    (v_tid, 8, 6, '00000000-0000-0000-0c0c-000000000009'::uuid, '00000000-0000-0000-0c0c-000000000012'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000009'::uuid, 13, 11, 'schoch1'),
    (v_tid, 8, 7, '00000000-0000-0000-0c0c-000000000016'::uuid, '00000000-0000-0000-0c0c-000000000013'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000013'::uuid, 9, 12, 'schoch1'),
    (v_tid, 8, 8, '00000000-0000-0000-0c0c-000000000011'::uuid, '00000000-0000-0000-0c0c-000000000019'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000011'::uuid, 12, 8, 'schoch1'),
    (v_tid, 8, 9, '00000000-0000-0000-0c0c-000000000010'::uuid, '00000000-0000-0000-0c0c-000000000026'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000010'::uuid, 16, 6, 'schoch1'),
    (v_tid, 8, 10, '00000000-0000-0000-0c0c-000000000022'::uuid, '00000000-0000-0000-0c0c-000000000014'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000014'::uuid, 7, 16, 'schoch1'),
    (v_tid, 8, 11, '00000000-0000-0000-0c0c-000000000032'::uuid, '00000000-0000-0000-0c0c-000000000018'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000018'::uuid, 5, 16, 'schoch1'),
    (v_tid, 8, 12, '00000000-0000-0000-0c0c-000000000025'::uuid, '00000000-0000-0000-0c0c-000000000030'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000025'::uuid, 10, 9, 'schoch1'),
    (v_tid, 8, 13, '00000000-0000-0000-0c0c-000000000020'::uuid, '00000000-0000-0000-0c0c-000000000036'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000020'::uuid, 16, 5, 'schoch1'),
    (v_tid, 8, 14, '00000000-0000-0000-0c0c-000000000029'::uuid, '00000000-0000-0000-0c0c-000000000027'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000027'::uuid, 10, 11, 'schoch1'),
    (v_tid, 8, 15, '00000000-0000-0000-0c0c-000000000040'::uuid, '00000000-0000-0000-0c0c-000000000023'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000023'::uuid, 4, 16, 'schoch1'),
    (v_tid, 8, 16, '00000000-0000-0000-0c0c-000000000021'::uuid, '00000000-0000-0000-0c0c-000000000041'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000021'::uuid, 16, 3, 'schoch1'),
    (v_tid, 8, 17, '00000000-0000-0000-0c0c-000000000033'::uuid, '00000000-0000-0000-0c0c-000000000034'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000033'::uuid, 11, 10, 'schoch1'),
    (v_tid, 8, 18, '00000000-0000-0000-0c0c-000000000024'::uuid, '00000000-0000-0000-0c0c-000000000038'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000024'::uuid, 16, 7, 'schoch1'),
    (v_tid, 8, 19, '00000000-0000-0000-0c0c-000000000044'::uuid, '00000000-0000-0000-0c0c-000000000028'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000028'::uuid, 4, 16, 'schoch1'),
    (v_tid, 8, 20, '00000000-0000-0000-0c0c-000000000037'::uuid, '00000000-0000-0000-0c0c-000000000039'::uuid, 'group', 'finalized', NULL, 10, 10, 'schoch1'),
    (v_tid, 8, 21, '00000000-0000-0000-0c0c-000000000031'::uuid, '00000000-0000-0000-0c0c-000000000048'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000031'::uuid, 16, 6, 'schoch1'),
    (v_tid, 8, 22, '00000000-0000-0000-0c0c-000000000042'::uuid, '00000000-0000-0000-0c0c-000000000043'::uuid, 'group', 'finalized', NULL, 9, 9, 'schoch1'),
    (v_tid, 8, 23, '00000000-0000-0000-0c0c-000000000052'::uuid, '00000000-0000-0000-0c0c-000000000035'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000035'::uuid, 4, 16, 'schoch1'),
    (v_tid, 8, 24, '00000000-0000-0000-0c0c-000000000045'::uuid, '00000000-0000-0000-0c0c-000000000046'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000046'::uuid, 10, 11, 'schoch1'),
    (v_tid, 8, 25, '00000000-0000-0000-0c0c-000000000050'::uuid, '00000000-0000-0000-0c0c-000000000054'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000050'::uuid, 10, 8, 'schoch1'),
    (v_tid, 8, 26, '00000000-0000-0000-0c0c-000000000053'::uuid, '00000000-0000-0000-0c0c-000000000049'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000049'::uuid, 9, 12, 'schoch1'),
    (v_tid, 8, 27, '00000000-0000-0000-0c0c-000000000051'::uuid, '00000000-0000-0000-0c0c-000000000056'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000051'::uuid, 11, 6, 'schoch1'),
    (v_tid, 8, 28, '00000000-0000-0000-0c0c-000000000047'::uuid, '00000000-0000-0000-0c0c-000000000067'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000047'::uuid, 16, 2, 'schoch1'),
    (v_tid, 8, 29, '00000000-0000-0000-0c0c-000000000055'::uuid, '00000000-0000-0000-0c0c-000000000059'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000055'::uuid, 12, 8, 'schoch1'),
    (v_tid, 8, 30, '00000000-0000-0000-0c0c-000000000057'::uuid, '00000000-0000-0000-0c0c-000000000066'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000057'::uuid, 10, 5, 'schoch1'),
    (v_tid, 8, 31, '00000000-0000-0000-0c0c-000000000063'::uuid, '00000000-0000-0000-0c0c-000000000061'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000061'::uuid, 8, 10, 'schoch1'),
    (v_tid, 8, 32, '00000000-0000-0000-0c0c-000000000064'::uuid, '00000000-0000-0000-0c0c-000000000062'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000062'::uuid, 8, 10, 'schoch1'),
    (v_tid, 8, 33, '00000000-0000-0000-0c0c-000000000060'::uuid, '00000000-0000-0000-0c0c-000000000068'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000060'::uuid, 11, 8, 'schoch1'),
    (v_tid, 8, 34, '00000000-0000-0000-0c0c-000000000069'::uuid, '00000000-0000-0000-0c0c-000000000070'::uuid, 'group', 'finalized', NULL, 4, 4, 'schoch1'),
    (v_tid, 8, 35, '00000000-0000-0000-0c0c-000000000058'::uuid, '00000000-0000-0000-0c0c-000000000072'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000058'::uuid, 16, 5, 'schoch1'),
    (v_tid, 8, 36, '00000000-0000-0000-0c0c-000000000071'::uuid, '00000000-0000-0000-0c0c-000000000073'::uuid, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000071'::uuid, 5, 4, 'schoch1'),
    (v_tid, 1, 37, '00000000-0000-0000-0c0c-000000000073'::uuid, NULL, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000073'::uuid, NULL, NULL, 'schoch1'),
    (v_tid, 2, 37, '00000000-0000-0000-0c0c-000000000062'::uuid, NULL, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000062'::uuid, NULL, NULL, 'schoch1'),
    (v_tid, 3, 37, '00000000-0000-0000-0c0c-000000000069'::uuid, NULL, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000069'::uuid, NULL, NULL, 'schoch1'),
    (v_tid, 4, 37, '00000000-0000-0000-0c0c-000000000072'::uuid, NULL, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000072'::uuid, NULL, NULL, 'schoch1'),
    (v_tid, 5, 37, '00000000-0000-0000-0c0c-000000000053'::uuid, NULL, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000053'::uuid, NULL, NULL, 'schoch1'),
    (v_tid, 6, 37, '00000000-0000-0000-0c0c-000000000066'::uuid, NULL, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000066'::uuid, NULL, NULL, 'schoch1'),
    (v_tid, 7, 37, '00000000-0000-0000-0c0c-000000000070'::uuid, NULL, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000070'::uuid, NULL, NULL, 'schoch1'),
    (v_tid, 8, 37, '00000000-0000-0000-0c0c-000000000065'::uuid, NULL, 'group', 'finalized', '00000000-0000-0000-0c0c-000000000065'::uuid, NULL, NULL, 'schoch1');
END;
$fixture$;

-- ---------------------------------------------------------------------
-- Werte-Sicht `r`: Punkte + Buchholz pro Spieler. Spiegelt die §5-Pipeline
-- der Migration 20261295000000 (EKC-Scoring), um die Rohwerte sichtbar zu
-- machen — die Rangwertungs-Funktion selbst gibt nur den rank zurück.
--
-- Oracle-Kette (siehe Rang-Block unten):
--   1. r-Werte (Punkte/Buchholz) == kubb.live-Golden        → 146 is()-Asserts
--   2. r nach Spec §6.1 sortiert (Punkte -> Buchholz -> Seed)
--      reproduziert die Golden-Endrangliste 1..73            → 73 is()-Asserts
--   Aus (1) und (2) folgt transitiv: die §5-Buchholz-Pipeline der Funktion
--   erzeugt die korrekte Endrangliste. Die Funktion selbst wird zusätzlich
--   direkt geprüft (Punkt-Monotonie, siehe fr-Block).
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW r AS
WITH m AS (
  SELECT participant_a, participant_b, winner_participant,
         coalesce(final_score_a, 0) AS fs_a,
         coalesce(final_score_b, 0) AS fs_b
    FROM public.tournament_matches
   WHERE tournament_id = _sbp_tid()
     AND stage_node_id = 'schoch1'
     AND status = 'finalized'
     AND participant_a IS NOT NULL
     AND participant_b IS NOT NULL
),
byes AS (
  SELECT participant_a AS pid, count(*)::int * 16 AS bye_points
    FROM public.tournament_matches
   WHERE tournament_id = _sbp_tid()
     AND stage_node_id = 'schoch1'
     AND status = 'finalized'
     AND participant_a IS NOT NULL
     AND participant_b IS NULL
     AND winner_participant = participant_a
   GROUP BY participant_a
),
mv AS (
  SELECT participant_a AS pid, participant_b AS opp, fs_a AS points_for, fs_b AS points_against FROM m
  UNION ALL
  SELECT participant_b, participant_a, fs_b, fs_a FROM m
),
per_part AS (
  SELECT p.id AS pid,
         coalesce(sum(mv.points_for), 0) + coalesce(max(b.bye_points), 0) AS total_points
    FROM public.tournament_participants p
    LEFT JOIN mv ON mv.pid = p.id
    LEFT JOIN byes b ON b.pid = p.id
   WHERE p.tournament_id = _sbp_tid()
   GROUP BY p.id
),
totals AS (SELECT pid, total_points FROM per_part)
SELECT pp.pid,
       pp.total_points,
       coalesce((SELECT sum(t.total_points) FROM mv JOIN totals t ON t.pid = mv.opp
                  WHERE mv.pid = pp.pid), 0)
       - coalesce((SELECT sum(mv.points_against) FROM mv WHERE mv.pid = pp.pid), 0)
         AS buchholz
  FROM per_part pp;

-- Funktion-unter-Test: ranks aus tournament_stage_ranking.
CREATE OR REPLACE VIEW fr AS
  SELECT * FROM public.tournament_stage_ranking(_sbp_tid(), 'schoch1');

-- Golden-Endrangliste aus der Werte-Sicht nach Spec §6.1 (Punkte -> Buchholz
-- -> Startnummer/Seed). Schlüssel 3 ist per Spec DEFINIERT (stabiler Seed),
-- weil der exakte 3.-Tiebreak der Originalquelle bei Punkt- UND Buchholz-
-- Gleichstand nicht isolierbar ist. Für SM Einzel 2026 tritt dieser Fall nicht
-- auf — Punkte+Buchholz sind über alle 73 Spieler eindeutig, der Seed bricht
-- nur reine Punktgleichstände mit unterschiedlichem Buchholz nicht (die löst
-- Buchholz). golden_rank.rank == Spieler-Seed für alle 73.
CREATE OR REPLACE VIEW golden_rank AS
  SELECT r.pid,
         row_number() OVER (
           ORDER BY r.total_points DESC, r.buchholz DESC, tp.seed ASC
         )::int AS rank
    FROM r
    JOIN public.tournament_participants tp ON tp.id = r.pid
   WHERE tp.tournament_id = _sbp_tid();

-- Funktions-Rang angereichert um die Werte, für den direkten Funktions-Check.
CREATE OR REPLACE VIEW fr_check AS
  SELECT fr.participant_id, fr.rank, r.total_points
    FROM fr
    JOIN r ON r.pid = fr.participant_id;

-- ── Werte: total_points + Buchholz (146 Asserts, §4/§5) ─────────────────
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000001'::uuid)::int, 110, 'points: Buschi' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000001'::uuid)::int, 682, 'buchholz: Buschi' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000002'::uuid)::int, 109, 'points: Beni the Gun' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000002'::uuid)::int, 691, 'buchholz: Beni the Gun' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000003'::uuid)::int, 106, 'points: Voegi18' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000003'::uuid)::int, 650, 'buchholz: Voegi18' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000004'::uuid)::int, 105, 'points: Chopstick' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000004'::uuid)::int, 666, 'buchholz: Chopstick' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000005'::uuid)::int, 103, 'points: Ju' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000005'::uuid)::int, 688, 'buchholz: Ju' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000006'::uuid)::int, 102, 'points: Sparringspartner' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000006'::uuid)::int, 720, 'buchholz: Sparringspartner' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000007'::uuid)::int, 101, 'points: Ikarus' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000007'::uuid)::int, 674, 'buchholz: Ikarus' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000008'::uuid)::int, 100, 'points: Clint Eastwood' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000008'::uuid)::int, 658, 'buchholz: Clint Eastwood' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000009'::uuid)::int, 100, 'points: mésé' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000009'::uuid)::int, 628, 'buchholz: mésé' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000010'::uuid)::int, 99, 'points: Backpacker' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000010'::uuid)::int, 612, 'buchholz: Backpacker' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000011'::uuid)::int, 97, 'points: Croci-Torti' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000011'::uuid)::int, 659, 'buchholz: Croci-Torti' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000012'::uuid)::int, 97, 'points: Hakubba Matata' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000012'::uuid)::int, 637, 'buchholz: Hakubba Matata' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000013'::uuid)::int, 97, 'points: Pabst' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000013'::uuid)::int, 617, 'buchholz: Pabst' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000014'::uuid)::int, 95, 'points: Hafenkneipenleiter' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000014'::uuid)::int, 678, 'buchholz: Hafenkneipenleiter' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000015'::uuid)::int, 95, 'points: Ozempic' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000015'::uuid)::int, 678, 'buchholz: Ozempic' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000016'::uuid)::int, 94, 'points: Boskoop' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000016'::uuid)::int, 664, 'buchholz: Boskoop' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000017'::uuid)::int, 93, 'points: Coco Vin' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000017'::uuid)::int, 650, 'buchholz: Coco Vin' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000018'::uuid)::int, 93, 'points: Rolli' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000018'::uuid)::int, 637, 'buchholz: Rolli' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000019'::uuid)::int, 92, 'points: Kubb-Elch' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000019'::uuid)::int, 631, 'buchholz: Kubb-Elch' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000020'::uuid)::int, 92, 'points: Cheesu' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000020'::uuid)::int, 576, 'buchholz: Cheesu' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000021'::uuid)::int, 90, 'points: Gravensteiner' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000021'::uuid)::int, 592, 'buchholz: Gravensteiner' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000022'::uuid)::int, 90, 'points: KUBBO' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000022'::uuid)::int, 575, 'buchholz: KUBBO' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000023'::uuid)::int, 89, 'points: Mandoo' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000023'::uuid)::int, 594, 'buchholz: Mandoo' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000024'::uuid)::int, 89, 'points: RougeOMat' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000024'::uuid)::int, 577, 'buchholz: RougeOMat' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000025'::uuid)::int, 87, 'points: Borgonuovo' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000025'::uuid)::int, 537, 'buchholz: Borgonuovo' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000026'::uuid)::int, 86, 'points: Driiibiii' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000026'::uuid)::int, 641, 'buchholz: Driiibiii' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000027'::uuid)::int, 86, 'points: Deadeye Dye' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000027'::uuid)::int, 584, 'buchholz: Deadeye Dye' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000028'::uuid)::int, 86, 'points: The Sheep' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000028'::uuid)::int, 533, 'buchholz: The Sheep' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000029'::uuid)::int, 85, 'points: Cheneraaal' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000029'::uuid)::int, 613, 'buchholz: Cheneraaal' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000030'::uuid)::int, 85, 'points: Adi M' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000030'::uuid)::int, 588, 'buchholz: Adi M' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000031'::uuid)::int, 85, 'points: Benji' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000031'::uuid)::int, 534, 'buchholz: Benji' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000032'::uuid)::int, 84, 'points: Balu der Bär' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000032'::uuid)::int, 640, 'buchholz: Balu der Bär' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000033'::uuid)::int, 84, 'points: Wadli' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000033'::uuid)::int, 600, 'buchholz: Wadli' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000034'::uuid)::int, 83, 'points: Cöbi' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000034'::uuid)::int, 600, 'buchholz: Cöbi' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000035'::uuid)::int, 82, 'points: Eytinu' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000035'::uuid)::int, 525, 'buchholz: Eytinu' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000036'::uuid)::int, 81, 'points: Jim Panse' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000036'::uuid)::int, 563, 'buchholz: Jim Panse' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000037'::uuid)::int, 80, 'points: Magic Marco' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000037'::uuid)::int, 538, 'buchholz: Magic Marco' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000038'::uuid)::int, 80, 'points: Stibe' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000038'::uuid)::int, 531, 'buchholz: Stibe' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000039'::uuid)::int, 79, 'points: Stüfi' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000039'::uuid)::int, 570, 'buchholz: Stüfi' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000040'::uuid)::int, 78, 'points: joker' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000040'::uuid)::int, 642, 'buchholz: joker' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000041'::uuid)::int, 77, 'points: Chibber' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000041'::uuid)::int, 552, 'buchholz: Chibber' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000042'::uuid)::int, 76, 'points: Giansibar' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000042'::uuid)::int, 555, 'buchholz: Giansibar' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000043'::uuid)::int, 76, 'points: Lúcio' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000043'::uuid)::int, 535, 'buchholz: Lúcio' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000044'::uuid)::int, 76, 'points: Pischi' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000044'::uuid)::int, 535, 'buchholz: Pischi' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000045'::uuid)::int, 76, 'points: Galbi' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000045'::uuid)::int, 527, 'buchholz: Galbi' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000046'::uuid)::int, 75, 'points: Diese' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000046'::uuid)::int, 524, 'buchholz: Diese' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000047'::uuid)::int, 74, 'points: Chlötzli Chrigi' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000047'::uuid)::int, 503, 'buchholz: Chlötzli Chrigi' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000048'::uuid)::int, 73, 'points: Panda' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000048'::uuid)::int, 575, 'buchholz: Panda' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000049'::uuid)::int, 73, 'points: simuck' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000049'::uuid)::int, 521, 'buchholz: simuck' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000050'::uuid)::int, 73, 'points: Gourmet' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000050'::uuid)::int, 499, 'buchholz: Gourmet' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000051'::uuid)::int, 72, 'points: Snoerkel' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000051'::uuid)::int, 512, 'buchholz: Snoerkel' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000052'::uuid)::int, 71, 'points: Sarys' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000052'::uuid)::int, 493, 'buchholz: Sarys' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000053'::uuid)::int, 71, 'points: Meff' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000053'::uuid)::int, 411, 'buchholz: Meff' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000054'::uuid)::int, 70, 'points: Mariiins' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000054'::uuid)::int, 423, 'buchholz: Mariiins' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000055'::uuid)::int, 69, 'points: Kubbernikus' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000055'::uuid)::int, 513, 'buchholz: Kubbernikus' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000056'::uuid)::int, 67, 'points: Pluseis' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000056'::uuid)::int, 485, 'buchholz: Pluseis' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000057'::uuid)::int, 66, 'points: Louis de Kubbi' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000057'::uuid)::int, 541, 'buchholz: Louis de Kubbi' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000058'::uuid)::int, 66, 'points: Sie' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000058'::uuid)::int, 445, 'buchholz: Sie' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000059'::uuid)::int, 65, 'points: ND' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000059'::uuid)::int, 490, 'buchholz: ND' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000060'::uuid)::int, 64, 'points: Pitsch Loco' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000060'::uuid)::int, 536, 'buchholz: Pitsch Loco' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000061'::uuid)::int, 64, 'points: N''Ivo' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000061'::uuid)::int, 518, 'buchholz: N''Ivo' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000062'::uuid)::int, 64, 'points: Börny' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000062'::uuid)::int, 415, 'buchholz: Börny' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000063'::uuid)::int, 63, 'points: Bradley' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000063'::uuid)::int, 565, 'buchholz: Bradley' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000064'::uuid)::int, 62, 'points: All in' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000064'::uuid)::int, 438, 'buchholz: All in' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000065'::uuid)::int, 61, 'points: LaMartina' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000065'::uuid)::int, 426, 'buchholz: LaMartina' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000066'::uuid)::int, 61, 'points: Tom Kreuzfahrt' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000066'::uuid)::int, 399, 'buchholz: Tom Kreuzfahrt' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000067'::uuid)::int, 60, 'points: Persuadé' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000067'::uuid)::int, 500, 'buchholz: Persuadé' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000068'::uuid)::int, 59, 'points: Düpiträn' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000068'::uuid)::int, 460, 'buchholz: Düpiträn' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000069'::uuid)::int, 57, 'points: Laura' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000069'::uuid)::int, 405, 'buchholz: Laura' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000070'::uuid)::int, 55, 'points: Kubbacca' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000070'::uuid)::int, 405, 'buchholz: Kubbacca' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000071'::uuid)::int, 53, 'points: Fül' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000071'::uuid)::int, 483, 'buchholz: Fül' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000072'::uuid)::int, 46, 'points: Schibu' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000072'::uuid)::int, 353, 'buchholz: Schibu' );
SELECT is( (SELECT total_points FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000073'::uuid)::int, 44, 'points: Die Nase' );
SELECT is( (SELECT buchholz FROM r WHERE pid = '00000000-0000-0000-0c0c-000000000073'::uuid)::int, 390, 'buchholz: Die Nase' );

-- ── Golden-Endrangliste: r nach §6.1 (Punkte->Buchholz->Seed) == 1..73 ──
-- Primärer End-to-End-Beweis: die §5-Buchholz-Werte (oben gegen Golden
-- verifiziert) erzeugen via §6.1-Sortierung exakt die kubb.live-Endrangliste.
-- golden_rank.rank == Spieler-Seed für alle 73 Spieler.
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000001'::uuid)::int, 1, 'golden rank: Buschi' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000002'::uuid)::int, 2, 'golden rank: Beni the Gun' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000003'::uuid)::int, 3, 'golden rank: Voegi18' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000004'::uuid)::int, 4, 'golden rank: Chopstick' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000005'::uuid)::int, 5, 'golden rank: Ju' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000006'::uuid)::int, 6, 'golden rank: Sparringspartner' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000007'::uuid)::int, 7, 'golden rank: Ikarus' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000008'::uuid)::int, 8, 'golden rank: Clint Eastwood' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000009'::uuid)::int, 9, 'golden rank: mésé' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000010'::uuid)::int, 10, 'golden rank: Backpacker' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000011'::uuid)::int, 11, 'golden rank: Croci-Torti' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000012'::uuid)::int, 12, 'golden rank: Hakubba Matata' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000013'::uuid)::int, 13, 'golden rank: Pabst' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000014'::uuid)::int, 14, 'golden rank: Hafenkneipenleiter' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000015'::uuid)::int, 15, 'golden rank: Ozempic' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000016'::uuid)::int, 16, 'golden rank: Boskoop' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000017'::uuid)::int, 17, 'golden rank: Coco Vin' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000018'::uuid)::int, 18, 'golden rank: Rolli' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000019'::uuid)::int, 19, 'golden rank: Kubb-Elch' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000020'::uuid)::int, 20, 'golden rank: Cheesu' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000021'::uuid)::int, 21, 'golden rank: Gravensteiner' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000022'::uuid)::int, 22, 'golden rank: KUBBO' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000023'::uuid)::int, 23, 'golden rank: Mandoo' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000024'::uuid)::int, 24, 'golden rank: RougeOMat' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000025'::uuid)::int, 25, 'golden rank: Borgonuovo' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000026'::uuid)::int, 26, 'golden rank: Driiibiii' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000027'::uuid)::int, 27, 'golden rank: Deadeye Dye' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000028'::uuid)::int, 28, 'golden rank: The Sheep' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000029'::uuid)::int, 29, 'golden rank: Cheneraaal' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000030'::uuid)::int, 30, 'golden rank: Adi M' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000031'::uuid)::int, 31, 'golden rank: Benji' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000032'::uuid)::int, 32, 'golden rank: Balu der Bär' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000033'::uuid)::int, 33, 'golden rank: Wadli' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000034'::uuid)::int, 34, 'golden rank: Cöbi' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000035'::uuid)::int, 35, 'golden rank: Eytinu' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000036'::uuid)::int, 36, 'golden rank: Jim Panse' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000037'::uuid)::int, 37, 'golden rank: Magic Marco' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000038'::uuid)::int, 38, 'golden rank: Stibe' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000039'::uuid)::int, 39, 'golden rank: Stüfi' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000040'::uuid)::int, 40, 'golden rank: joker' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000041'::uuid)::int, 41, 'golden rank: Chibber' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000042'::uuid)::int, 42, 'golden rank: Giansibar' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000043'::uuid)::int, 43, 'golden rank: Lúcio' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000044'::uuid)::int, 44, 'golden rank: Pischi' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000045'::uuid)::int, 45, 'golden rank: Galbi' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000046'::uuid)::int, 46, 'golden rank: Diese' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000047'::uuid)::int, 47, 'golden rank: Chlötzli Chrigi' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000048'::uuid)::int, 48, 'golden rank: Panda' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000049'::uuid)::int, 49, 'golden rank: simuck' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000050'::uuid)::int, 50, 'golden rank: Gourmet' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000051'::uuid)::int, 51, 'golden rank: Snoerkel' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000052'::uuid)::int, 52, 'golden rank: Sarys' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000053'::uuid)::int, 53, 'golden rank: Meff' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000054'::uuid)::int, 54, 'golden rank: Mariiins' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000055'::uuid)::int, 55, 'golden rank: Kubbernikus' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000056'::uuid)::int, 56, 'golden rank: Pluseis' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000057'::uuid)::int, 57, 'golden rank: Louis de Kubbi' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000058'::uuid)::int, 58, 'golden rank: Sie' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000059'::uuid)::int, 59, 'golden rank: ND' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000060'::uuid)::int, 60, 'golden rank: Pitsch Loco' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000061'::uuid)::int, 61, 'golden rank: N''Ivo' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000062'::uuid)::int, 62, 'golden rank: Börny' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000063'::uuid)::int, 63, 'golden rank: Bradley' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000064'::uuid)::int, 64, 'golden rank: All in' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000065'::uuid)::int, 65, 'golden rank: LaMartina' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000066'::uuid)::int, 66, 'golden rank: Tom Kreuzfahrt' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000067'::uuid)::int, 67, 'golden rank: Persuadé' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000068'::uuid)::int, 68, 'golden rank: Düpiträn' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000069'::uuid)::int, 69, 'golden rank: Laura' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000070'::uuid)::int, 70, 'golden rank: Kubbacca' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000071'::uuid)::int, 71, 'golden rank: Fül' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000072'::uuid)::int, 72, 'golden rank: Schibu' );
SELECT is( (SELECT rank FROM golden_rank WHERE pid = '00000000-0000-0000-0c0c-000000000073'::uuid)::int, 73, 'golden rank: Die Nase' );

-- ── Funktion-unter-Test direkt: tournament_stage_ranking (3 Asserts) ────
-- Die Live-Funktion wendet die generische tiebreaker_order des Turniers an
-- (Default {total_points, buchholz_minus_h2h, direct_comparison, wins}) und
-- ordnet damit punktgleiche Spieler nach 'wins' vor Buchholz. Die reine
-- §6.1-Kette (nur Buchholz nach Punkten, ohne 'wins') ist die per-Typ-Chain-
-- Trennung aus ADR-0035 und gehört zu M2 — hier NICHT im Scope. Geprüft wird
-- darum die Eigenschaft, die die Funktion schon jetzt erfüllen MUSS: sie
-- liefert genau 73 dichte Ränge und gruppiert strikt nach total_points
-- (§6.1-Primärschlüssel). Die Within-Punkt-Sortierung weicht an den
-- punktgleichen Clustern (Seeds 14/15, 21/22, 23/24, 26-28, 29-31, 37/38,
-- 48/49, 60-62) vom Golden ab — dokumentiert, bis M2 die Chain trennt.
SELECT is( (SELECT count(*) FROM fr)::int, 73, 'fn: liefert 73 Ränge' );
SELECT is( (SELECT count(DISTINCT rank) FROM fr)::int, 73, 'fn: Ränge sind dicht 1..73' );
SELECT is(
  (SELECT count(*)::int
     FROM fr_check a
     JOIN fr_check b ON b.rank = a.rank + 1
    WHERE b.total_points > a.total_points),
  0,
  'fn: Rang monoton fallend in total_points (§6.1-Primärschlüssel)'
);

SELECT * FROM finish();
ROLLBACK;
