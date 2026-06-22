-- End-to-End-Integration des Schoch-Stufen-Graph-Pfads — ADR-0039 (M4 T19).
--
-- Die Per-Leg-Suiten decken je ein Bein ab:
--   * schoch_then_ko_start_path_test    -> der START (2-Stufen-Graph, Runde 1).
--   * pair_round_stage_scoped_test      -> eine stage-scoped Folge-Paarung.
--   * stage_runner_schoch_rounds_test   -> die Runner-Verzweigung r<R vs r>=R.
--   * stage_type_graph_advance_route    -> winner-advance im KO.
-- KEINE einzelne Suite fädelt aber den vollen Weg vom Start bis zum Champion.
-- Genau das macht dieser Test — und zwar ausschliesslich über die echten RPCs.
--
-- Der EINZIGE manuelle Insert ist das Seeding: ein Turnier + 8 bestätigte
-- Teilnehmer (wie schoch_then_ko_start_path_test, als postgres). ALLES weitere
-- — jede Runde, der KO-Route, jedes Match, jeder Fortschritt — entsteht aus den
-- Engine-Funktionen:
--   * tournament_start            -> bootet den Graph, materialisiert Runde 1.
--   * tournament_pair_round(...,   p_stage_node_id) -> paart Runde 2 und 3.
--   * tournament_organizer_override -> schliesst JEDES Match ab (status
--       'overridden'); der AFTER-UPDATE-Trigger feuert tournament_run_stage_graph
--       (Schoch-Runner) bzw. tournament_advance_ko_winner (KO-Bracket).
--   * Nach Runde R routet der Runner selbst top_k=4 in die KO-Stufe, aktiviert
--     sie und generiert das Bracket (tournament_route_completed_stage +
--     tournament_generate_stage_matches).
--   * tournament_advance_ko_winner schiebt die KO-Sieger weiter bis zum Final.
--
-- N=8, R=3: 8 ist eine Zweierpotenz — jede Schoch-Runde sind exakt 4 Matches
-- ohne BYE, sauber teilbar. top_k=4 routet in ein 4-Spieler-single_elim
-- (2 Halbfinals + 1 Final), das genau EINEN Champion liefert. Kein BYE irgendwo
-- hält die Orakel scharf.
--
-- Soll-Werte hartkodiert. Alles transient in BEGIN..ROLLBACK; nichts persistiert.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(22);

-- ---------------------------------------------------------------------
-- Auth-actor-switching wie schoch_then_ko_start_path_test: authentifiziert
-- als Creator via JWT-Claims, Fixtures als postgres geseedet.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _s2k_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _s2k_as_pg() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

CREATE OR REPLACE FUNCTION _s2k_tid() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5c0d0000-0000-0000-0000-0000000002e1'::uuid $$;
CREATE OR REPLACE FUNCTION _s2k_org() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5c0d0000-0000-0000-0000-0000000002f1'::uuid $$;

-- Eine valide EKC-Set-Wertung mit A als Set-Sieger (winner='A' -> match_winner A).
-- Wire-Form per _tournament_compute_ekc: basekubbs_a/_b + winner in {A,B,none}.
CREATE OR REPLACE FUNCTION _s2k_score_a() RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_array(
    jsonb_build_object('basekubbs_a', 5, 'basekubbs_b', 2, 'winner', 'A'))
$$;

-- Schliesst JEDES offene (scheduled/awaiting_results) Match einer Stufen-Runde
-- über den ECHTEN Organizer-Override-Pfad ab. participant_a gewinnt jeweils.
-- Der Override setzt status='overridden' und feuert den AFTER-UPDATE-Trigger,
-- der den Runner (bzw. KO-Advance) anstösst — kein Hand-UPDATE auf Matches.
CREATE OR REPLACE FUNCTION _s2k_finalize_round(p_stage text, p_round int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_ids uuid[];
  v_id  uuid;
BEGIN
  -- IDs als postgres lesen (RLS/Grants verbieten authenticated den Tabellen-
  -- Lesezugriff), den Override-RPC dann als Creator aufrufen. Der RPC ist
  -- SECURITY DEFINER und prüft selbst tournament_caller_can_administer.
  PERFORM _s2k_as_pg();
  SELECT array_agg(id ORDER BY match_number_in_round, bracket_position)
    INTO v_ids
    FROM public.tournament_matches
   WHERE tournament_id = _s2k_tid()
     AND stage_node_id = p_stage
     AND round_number = p_round
     AND status IN ('scheduled','awaiting_results','disputed')
     AND participant_a IS NOT NULL
     AND participant_b IS NOT NULL;

  PERFORM _s2k_as(_s2k_org());
  FOREACH v_id IN ARRAY coalesce(v_ids, ARRAY[]::uuid[]) LOOP
    PERFORM public.tournament_organizer_override(
      v_id, _s2k_score_a(), 'on-site result entry');
  END LOOP;
  PERFORM _s2k_as_pg();
END;
$$;

-- Baut eine vollständige, nicht-wiederholende Paarung aller 8 Teilnehmer für die
-- nächste Schoch-Runde: greedy über die Teilnehmer in seed-Reihenfolge, jeder
-- Gegner ist der erste noch freie Partner, mit dem in DIESER Stufe noch nicht
-- gespielt wurde. Bei N=8/R=3 existiert eine solche Paarung immer (1-Faktor).
-- Gibt das pairings-jsonb für tournament_pair_round zurück.
CREATE OR REPLACE FUNCTION _s2k_next_pairing(p_stage text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_players uuid[];
  v_used    boolean[];
  v_pairs   jsonb := '[]'::jsonb;
  i int;
  j int;
  n int;
BEGIN
  SELECT array_agg(id ORDER BY seed)
    INTO v_players
    FROM public.tournament_participants
    WHERE tournament_id = _s2k_tid()
      AND registration_status = 'confirmed';

  n := array_length(v_players, 1);
  v_used := array_fill(false, ARRAY[n]);

  FOR i IN 1 .. n LOOP
    IF v_used[i] THEN CONTINUE; END IF;
    FOR j IN i + 1 .. n LOOP
      IF v_used[j] THEN CONTINUE; END IF;
      -- Diese Paarung darf in dieser Stufe noch nicht gespielt worden sein.
      PERFORM 1 FROM public.tournament_matches m
        WHERE m.tournament_id = _s2k_tid()
          AND m.stage_node_id = p_stage
          AND m.participant_b IS NOT NULL
          AND ((m.participant_a = v_players[i] AND m.participant_b = v_players[j])
            OR (m.participant_a = v_players[j] AND m.participant_b = v_players[i]));
      IF NOT FOUND THEN
        v_used[i] := true;
        v_used[j] := true;
        v_pairs := v_pairs || jsonb_build_array(jsonb_build_object(
          'participant_a', v_players[i]::text,
          'participant_b', v_players[j]::text));
        EXIT;
      END IF;
    END LOOP;
  END LOOP;
  RETURN v_pairs;
END;
$$;

-- =====================================================================
-- Seeding (der EINZIGE manuelle Insert): schoch_then_ko, 8 confirmed,
-- pool_phase_config.schoch_rounds=3 (R), qualifier_count=4 (top_k),
-- Status registration_closed -> tournament_start akzeptiert.
-- =====================================================================
SELECT _s2k_as_pg();

DO $fixture$
DECLARE
  v_tid uuid := _s2k_tid();
  v_org uuid := _s2k_org();
  v_u   uuid;
  i     int;
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (v_org, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated', 'org@s2k.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public,
      pool_phase_config, ko_config, ko_matchup)
    VALUES (v_tid, v_org, 'Schoch nach KO — voller Pfad', 1, 2, 32,
            'schoch_then_ko', 'ekc',
            jsonb_build_object('round_time_seconds', 1800),
            'registration_closed', true,
            jsonb_build_object('group_count', 1, 'qualifiers_per_group', 4,
                               'strategy', 'snake', 'schoch_rounds', 3),
            jsonb_build_object('qualifier_count', 4,
                               'with_third_place_playoff', false,
                               'seeding_mode', 'auto'),
            'seed_high_vs_low');

  FOR i IN 1..8 LOOP
    v_u := ('00000000-0000-0000-02e0-' || lpad(i::text, 12, '0'))::uuid;
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_u, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated', 'p' || i || '@s2k.local',
              '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, seed, registered_at)
      VALUES (('00000000-0000-0000-02e1-' || lpad(i::text, 12, '0'))::uuid,
              v_tid, v_u, 'confirmed', i,
              '2026-06-01 09:00:00+00'::timestamptz + (i || ' seconds')::interval);
  END LOOP;
END;
$fixture$;

-- =====================================================================
-- (1) START: bootet den 2-Stufen-Graph + materialisiert Runde 1 (Seed-Slide).
-- =====================================================================
SELECT _s2k_as(_s2k_org());
SELECT lives_ok(
  format($$ SELECT public.tournament_start(%L::uuid) $$, _s2k_tid()),
  'tournament_start fädelt schoch_then_ko ohne Fehler');
SELECT _s2k_as_pg();

SELECT is(
  (SELECT type FROM public.tournament_stages
    WHERE tournament_id = _s2k_tid() AND node_id = 'vorrunde'),
  'schoch',
  'Start: Root-Stufe ist schoch');
SELECT is(
  (SELECT (config->>'rounds')::int FROM public.tournament_stages
    WHERE tournament_id = _s2k_tid() AND node_id = 'vorrunde'),
  3,
  'Start: config[rounds] = R = 3');
SELECT is(
  (SELECT (selector->>'k')::int FROM public.tournament_stage_edges
    WHERE tournament_id = _s2k_tid()
      AND from_node_id = 'vorrunde' AND to_node_id = 'ko'),
  4,
  'Start: top_k-Edge k = qualifier_count = 4');

-- Runde 1 = ceil(8/2) = 4 Matches mit stage_node_id NOT NULL, KEIN RR-Pool
-- (N*(N-1)/2 = 28). Bei gerader Zahl gibt es kein BYE.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s2k_tid()
      AND stage_node_id = 'vorrunde' AND round_number = 1),
  4,
  'Start: Runde 1 = ceil(N/2)=4 Seed-Slide-Matches (kein RR-Pool)');
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s2k_tid() AND stage_node_id IS NULL),
  0,
  'Start: kein Match ohne stage_node_id (kein flacher Pool)');
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s2k_tid()
      AND stage_node_id = 'vorrunde' AND round_number = 1
      AND participant_b IS NULL),
  0,
  'Start: gerades Feld -> kein BYE in Runde 1');

-- =====================================================================
-- (2) Runde 1 abschliessen (echter Override-Pfad). r=1 < R=3:
-- der Runner hält die Stufe active und feuert 'swiss_round_complete'.
-- =====================================================================
SELECT _s2k_finalize_round('vorrunde', 1);

SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = _s2k_tid() AND node_id = 'vorrunde'),
  'active',
  'r1<R: Schoch-Stufe bleibt active (Runner schliesst nicht vorzeitig)');
SELECT is(
  (SELECT count(*)::int FROM public.tournament_audit_events
    WHERE tournament_id = _s2k_tid() AND kind = 'swiss_round_complete'),
  1,
  'r1<R: genau ein swiss_round_complete-Signal');
SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = _s2k_tid() AND node_id = 'ko'),
  'pending',
  'r1<R: KO-Stufe bleibt pending');

-- Runde 2 über den echten stage-scoped Paarungs-RPC paaren, dann abschliessen.
SELECT _s2k_as(_s2k_org());
SELECT lives_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %s::jsonb, %L) $$,
    _s2k_tid(), quote_literal(_s2k_next_pairing('vorrunde')), 'vorrunde'),
  'r2: tournament_pair_round paart Runde 2 in die aktive Schoch-Stufe');
SELECT _s2k_as_pg();

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s2k_tid()
      AND stage_node_id = 'vorrunde' AND round_number = 2),
  4,
  'r2: 4 Matches in Runde 2 mit stage_node_id = vorrunde');

SELECT _s2k_finalize_round('vorrunde', 2);

SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = _s2k_tid() AND node_id = 'vorrunde'),
  'active',
  'r2<R: Schoch-Stufe bleibt active');
SELECT is(
  (SELECT (payload->>'awaiting')::int FROM public.tournament_audit_events
    WHERE tournament_id = _s2k_tid() AND kind = 'swiss_round_complete'
    ORDER BY created_at DESC, (payload->>'completed_round')::int DESC LIMIT 1),
  3,
  'r2<R: jüngstes swiss_round_complete erwartet Runde 3');

-- =====================================================================
-- (3) Runde 3 (= R) paaren + abschliessen. Der Runner schliesst jetzt die
-- Schoch-Stufe, routet top_k=4 in die KO-Stufe und aktiviert sie — KEIN
-- Hand-Insert, alles aus tournament_route_completed_stage +
-- tournament_generate_stage_matches.
-- =====================================================================
SELECT _s2k_as(_s2k_org());
SELECT lives_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %s::jsonb, %L) $$,
    _s2k_tid(), quote_literal(_s2k_next_pairing('vorrunde')), 'vorrunde'),
  'r3: tournament_pair_round paart Runde 3 (= R) in die Schoch-Stufe');
SELECT _s2k_as_pg();

SELECT _s2k_finalize_round('vorrunde', 3);

SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = _s2k_tid() AND node_id = 'vorrunde'),
  'completed',
  'r3=R: Schoch-Stufe schliesst (completed)');
SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = _s2k_tid() AND node_id = 'ko'),
  'active',
  'r3=R: KO-Stufe wird vom Runner aktiviert');
SELECT is(
  (SELECT count(*)::int FROM public.tournament_stage_inputs
    WHERE tournament_id = _s2k_tid() AND target_node_id = 'ko'),
  4,
  'r3=R: top_k(4) routet genau 4 Qualifizierte in die KO-Stufe');

-- Das KO-Bracket ist materialisiert: 4 Spieler -> Runde 1 = 2 Halbfinals.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s2k_tid()
      AND stage_node_id = 'ko' AND round_number = 1),
  2,
  'r3=R: KO-Bracket materialisiert (2 Halbfinals aus den 4 Qualifizierten)');

-- =====================================================================
-- (4) KO bis zum Champion durchspielen. Jede KO-Runde über den echten
-- Override-Pfad; tournament_advance_ko_winner schiebt die Sieger weiter.
-- Erst die Halbfinals, dann der vom Advance-Trigger befüllte Final.
-- =====================================================================
SELECT _s2k_finalize_round('ko', 1);
SELECT _s2k_finalize_round('ko', 2);

-- Das volle KO-Bracket steht: 4 Spieler -> 2 Halbfinals + 1 Final = 3 Matches.
-- Verankert die "keine offenen"-Prüfung gegen einen leeren KO — ohne dieses
-- Orakel wäre count(... offen) = 0 auch dann wahr, wenn gar kein KO lief.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s2k_tid() AND stage_node_id = 'ko'),
  3,
  'KO: ganzes Bracket materialisiert (2 Halbfinals + 1 Final = 3 Matches)');

-- Genau EIN Champion: das letzte KO-Match (höchste Runde) ist terminal und
-- hat genau einen winner_participant; keine offenen KO-Matches mehr.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s2k_tid() AND stage_node_id = 'ko'
      AND status NOT IN ('finalized','overridden','voided')),
  0,
  'KO: keine offenen Matches mehr (Bracket vollständig gespielt)');
SELECT is(
  (SELECT count(*)::int
     FROM public.tournament_matches m
    WHERE m.tournament_id = _s2k_tid() AND m.stage_node_id = 'ko'
      AND m.winner_participant IS NOT NULL
      AND m.round_number = (
        SELECT max(round_number) FROM public.tournament_matches
         WHERE tournament_id = _s2k_tid() AND stage_node_id = 'ko')),
  1,
  'KO: genau EIN Champion am Ende des Brackets');

SELECT * FROM finish();
ROLLBACK;
