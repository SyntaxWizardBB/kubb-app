-- End-to-End des Schoch->KO-Pfads MIT 3.-Platz-Spiel — ADR-0039 §4 (M4 T19b).
--
-- Schwester-Test zu schoch_to_ko_full_path_test.sql. Jener fädelt den vollen Weg
-- vom Start bis zum Champion mit with_third_place_playoff=FALSE. Dieser hier deckt
-- den ko_config-aware Fix ab: with_third_place_playoff=TRUE muss die Auto-Route
-- (die EINZIGE KO-Materialisierungs-Quelle auf dem Stage-Graph-Pfad) dazu bringen,
-- ein 3.-Platz-Match anzulegen, das vom advance-Trigger mit den Halbfinal-
-- Verlierern befüllt wird und genau EINEN 3.-Platz-Sieger liefert.
--
-- Wie beim T19: EINZIGER manueller Insert ist das Seeding (Turnier + 8 confirmed
-- Teilnehmer, als postgres). Alles weitere entsteht aus den echten RPCs:
--   * tournament_start            -> bootet den Graph, Runde 1 (Seed-Slide).
--   * tournament_pair_round(...)  -> paart Runde 2 und 3 stage-scoped.
--   * tournament_organizer_override -> schliesst jedes Match ab (overridden);
--       der AFTER-UPDATE-Trigger feuert den Schoch-Runner bzw. den KO-Advance.
--   * Nach Runde R routet der Runner top_k=4 in die KO-Stufe und generiert das
--     Bracket. Mit with_third_place_playoff=true legt tournament_generate_stage_
--     matches NEBEN dem Final ein third_place-Match an (bracket_position NULL).
--   * tournament_advance_ko_winner spiegelt die beiden Halbfinal-Verlierer ins
--     third_place-Match (Phasen-Sonderbehandlung) und die Sieger in den Final.
--
-- N=8, R=3, top_k=4: 4-Spieler-single_elim = 2 Halbfinals + 1 Final + 1 3.-Platz.
-- Kein BYE -> die Orakel bleiben scharf. Soll-Werte hartkodiert, BEGIN..ROLLBACK.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(13);

-- ---------------------------------------------------------------------
-- Auth-actor-switching + Helfer wie schoch_to_ko_full_path_test, eigene
-- _s3p-Präfixe und eine eigene Turnier-UUID, damit die Suiten unabhängig laufen.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _s3p_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _s3p_as_pg() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

CREATE OR REPLACE FUNCTION _s3p_tid() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5c0d0000-0000-0000-0000-0000000003e1'::uuid $$;
CREATE OR REPLACE FUNCTION _s3p_org() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '5c0d0000-0000-0000-0000-0000000003f1'::uuid $$;

-- Eine valide EKC-Set-Wertung mit A als Set-Sieger.
CREATE OR REPLACE FUNCTION _s3p_score_a() RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_array(
    jsonb_build_object('basekubbs_a', 5, 'basekubbs_b', 2, 'winner', 'A'))
$$;

-- Schliesst JEDES offene Match einer Stufen-Runde über den echten Override-Pfad
-- ab (participant_a gewinnt). Der Override setzt overridden und feuert den
-- AFTER-UPDATE-Trigger. third_place-Matches tragen bracket_position NULL — die
-- ORDER BY toleriert das (NULLS LAST), der Filter verlangt beide Teilnehmer.
CREATE OR REPLACE FUNCTION _s3p_finalize_round(p_stage text, p_round int)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_ids uuid[];
  v_id  uuid;
BEGIN
  PERFORM _s3p_as_pg();
  SELECT array_agg(id ORDER BY match_number_in_round, bracket_position NULLS LAST)
    INTO v_ids
    FROM public.tournament_matches
   WHERE tournament_id = _s3p_tid()
     AND stage_node_id = p_stage
     AND round_number = p_round
     AND status IN ('scheduled','awaiting_results','disputed')
     AND participant_a IS NOT NULL
     AND participant_b IS NOT NULL;

  PERFORM _s3p_as(_s3p_org());
  FOREACH v_id IN ARRAY coalesce(v_ids, ARRAY[]::uuid[]) LOOP
    PERFORM public.tournament_organizer_override(
      v_id, _s3p_score_a(), 'on-site result entry');
  END LOOP;
  PERFORM _s3p_as_pg();
END;
$$;

-- Nicht-wiederholende Paarung aller 8 Teilnehmer für die nächste Schoch-Runde
-- (greedy, 1-Faktor existiert bei N=8/R=3). Gibt pairings-jsonb zurück.
CREATE OR REPLACE FUNCTION _s3p_next_pairing(p_stage text) RETURNS jsonb
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
    WHERE tournament_id = _s3p_tid()
      AND registration_status = 'confirmed';

  n := array_length(v_players, 1);
  v_used := array_fill(false, ARRAY[n]);

  FOR i IN 1 .. n LOOP
    IF v_used[i] THEN CONTINUE; END IF;
    FOR j IN i + 1 .. n LOOP
      IF v_used[j] THEN CONTINUE; END IF;
      PERFORM 1 FROM public.tournament_matches m
        WHERE m.tournament_id = _s3p_tid()
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
-- Seeding (EINZIGER manueller Insert): schoch_then_ko, 8 confirmed,
-- schoch_rounds=3, qualifier_count=4, with_third_place_playoff=TRUE.
-- =====================================================================
SELECT _s3p_as_pg();

DO $fixture$
DECLARE
  v_tid uuid := _s3p_tid();
  v_org uuid := _s3p_org();
  v_u   uuid;
  i     int;
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (v_org, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated', 'org@s3p.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public,
      pool_phase_config, ko_config, ko_matchup)
    VALUES (v_tid, v_org, 'Schoch nach KO — mit 3. Platz', 1, 2, 32,
            'schoch_then_ko', 'ekc',
            jsonb_build_object('round_time_seconds', 1800),
            'registration_closed', true,
            jsonb_build_object('group_count', 1, 'qualifiers_per_group', 4,
                               'strategy', 'snake', 'schoch_rounds', 3),
            jsonb_build_object('qualifier_count', 4,
                               'with_third_place_playoff', true,
                               'seeding_mode', 'auto'),
            'seed_high_vs_low');

  FOR i IN 1..8 LOOP
    v_u := ('00000000-0000-0000-03e0-' || lpad(i::text, 12, '0'))::uuid;
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_u, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated', 'p' || i || '@s3p.local',
              '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, seed, registered_at)
      VALUES (('00000000-0000-0000-03e1-' || lpad(i::text, 12, '0'))::uuid,
              v_tid, v_u, 'confirmed', i,
              '2026-06-01 09:00:00+00'::timestamptz + (i || ' seconds')::interval);
  END LOOP;
END;
$fixture$;

-- =====================================================================
-- (1) START + Schoch-Stufe: der KO-Knoten trägt jetzt with_third_place=true.
-- =====================================================================
SELECT _s3p_as(_s3p_org());
SELECT lives_ok(
  format($$ SELECT public.tournament_start(%L::uuid) $$, _s3p_tid()),
  'tournament_start fädelt schoch_then_ko mit 3.-Platz ohne Fehler');
SELECT _s3p_as_pg();

SELECT is(
  (SELECT (config->>'with_third_place')::boolean FROM public.tournament_stages
    WHERE tournament_id = _s3p_tid() AND node_id = 'ko'),
  true,
  'Start: KO-Stufe trägt with_third_place=true (aus ko_config abgeleitet)');
SELECT is(
  (SELECT type FROM public.tournament_stages
    WHERE tournament_id = _s3p_tid() AND node_id = 'ko'),
  'single_elim',
  'Start: KO-Stufe bleibt single_elim');

-- =====================================================================
-- (2) Vorrunde R1..R3 durchspielen; nach R3 routet der Runner top_k=4 ins KO.
-- =====================================================================
SELECT _s3p_finalize_round('vorrunde', 1);

SELECT _s3p_as(_s3p_org());
SELECT lives_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %s::jsonb, %L) $$,
    _s3p_tid(), quote_literal(_s3p_next_pairing('vorrunde')), 'vorrunde'),
  'r2: Paarung Runde 2 in die aktive Schoch-Stufe');
SELECT _s3p_as_pg();
SELECT _s3p_finalize_round('vorrunde', 2);

SELECT _s3p_as(_s3p_org());
SELECT lives_ok(
  format($$ SELECT public.tournament_pair_round(%L::uuid, 'swiss_system', %s::jsonb, %L) $$,
    _s3p_tid(), quote_literal(_s3p_next_pairing('vorrunde')), 'vorrunde'),
  'r3: Paarung Runde 3 (= R) in die Schoch-Stufe');
SELECT _s3p_as_pg();
SELECT _s3p_finalize_round('vorrunde', 3);

SELECT is(
  (SELECT status FROM public.tournament_stages
    WHERE tournament_id = _s3p_tid() AND node_id = 'ko'),
  'active',
  'r3=R: KO-Stufe wird vom Runner aktiviert');

-- Das KO-Bracket: 4 Qualifizierte -> 2 Halbfinals (round 1) + 1 Final + 1
-- 3.-Platz (beide round 2). Genau EIN third_place-Match, mit bracket_position
-- NULL (aus dem Slot-Index gehalten, kollidiert nicht mit dem Final auf bp=1).
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s3p_tid()
      AND stage_node_id = 'ko' AND phase = 'third_place'),
  1,
  'KO: genau ein third_place-Match materialisiert (Auto-Route honoriert ko_config)');
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s3p_tid()
      AND stage_node_id = 'ko' AND phase = 'third_place'
      AND bracket_position IS NULL),
  1,
  'KO: das third_place-Match trägt bracket_position NULL (Slot-Index-frei)');
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s3p_tid()
      AND stage_node_id = 'ko' AND phase = 'final'),
  1,
  'KO: genau ein Final (kollidiert nicht mit dem third_place)');

-- =====================================================================
-- (3) Halbfinals abschliessen -> advance-Trigger spiegelt die beiden Verlierer
-- ins third_place-Match. Danach ist es mit beiden Teilnehmern befüllt.
-- =====================================================================
SELECT _s3p_finalize_round('ko', 1);

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s3p_tid()
      AND stage_node_id = 'ko' AND phase = 'third_place'
      AND participant_a IS NOT NULL AND participant_b IS NOT NULL),
  1,
  'KO: advance-Trigger spiegelt beide Halbfinal-Verlierer ins 3.-Platz-Match');

-- =====================================================================
-- (4) Runde 2 (Final + 3.-Platz) abschliessen -> ein Champion + ein 3.-Sieger.
-- =====================================================================
SELECT _s3p_finalize_round('ko', 2);

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s3p_tid() AND stage_node_id = 'ko'
      AND status NOT IN ('finalized','overridden','voided')),
  0,
  'KO: keine offenen Matches mehr (Final + 3.-Platz gespielt)');
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s3p_tid() AND stage_node_id = 'ko'
      AND phase = 'final' AND winner_participant IS NOT NULL),
  1,
  'KO: genau EIN Champion (Final-Sieger)');
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = _s3p_tid() AND stage_node_id = 'ko'
      AND phase = 'third_place' AND winner_participant IS NOT NULL),
  1,
  'KO: genau EIN 3.-Platz-Sieger');

SELECT * FROM finish();
ROLLBACK;
