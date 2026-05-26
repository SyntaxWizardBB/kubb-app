-- Tournament feature — M2 KO-phase start RPC.
--
-- `tournament_start_ko_phase(p_tournament_id, p_ko_config)` ist die
-- server-authoritative Phasen-Transition vom Round-Robin in die KO-
-- Phase. Folgt strikt dem `tournament_start`-Pattern (M1):
-- `SECURITY DEFINER`, `SET search_path`, `auth.uid()`-Check gegen
-- `tournaments.created_by`, `FOR UPDATE`-Lock auf der Turnier-Row.
--
-- Bezug: docs/adr/0017-ko-phase-semantics.md §7,
--        docs/plans/m2-ko-bracket/tasks.md TASK-M2.2-T3b.
--
-- Fehler-Mapping (Token im MESSAGE, SQLSTATE im ERRCODE):
--   NOT_AUTHENTICATED       — 42501
--   NOT_ORGANIZER           — 42501
--   INVALID_KO_CONFIG       — 22023
--   PHASE_NOT_COMPLETE      — 22023 (HTTP 422; details.match_ids[])
--   ALREADY_STARTED         — 40001 (serialization_failure; Client
--                                     behandelt idempotent: ref.invalidate,
--                                     kein Error-Toast — ADR-0017 §7)
--
-- Seeds-Reading-Strategie (Standings + Overrides):
--   1. Standings-Order: Veranstaltungs-Teilnehmer mit Vorrunden-
--      `phase='group'`-Matches gerankt nach (wins DESC, kubb_diff DESC,
--      registered_at ASC, id ASC) für deterministische Stabilität.
--   2. Override-Anwendung: Overrides aus `tournament_seeding_overrides`
--      werden auf die Standings-Order angewendet — Override-Seed-Position
--      (1-based) gewinnt; nicht-überschriebene Teilnehmer füllen die
--      verbleibenden Slots in Standings-Reihenfolge auf.
--   3. Top-N: Erste `qualifier_count` Seeds wandern in den Helper.
--
-- BYE-Auto-Advance: `_tournament_compute_ko_bracket` markiert R1-Pairings
-- mit `is_bye_pairing=true` falls einer der beiden Slots NULL ist. Diese
-- Row wird hier direkt mit `status='finalized'` und `winner_participant`
-- = real-seed angelegt, damit T4 (`tournament_advance_ko_winner`) den
-- BYE-Sieger in R2 schiebt.

CREATE OR REPLACE FUNCTION public.tournament_start_ko_phase(
  p_tournament_id uuid,
  p_ko_config     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller            uuid;
  v_creator           uuid;
  v_with_third_place  boolean;
  v_qualifier_count   int;
  v_incomplete        uuid[];
  v_ko_exists         int;
  v_seeds_jsonb       jsonb;
  v_match_count       int := 0;
  v_bye_count         int := 0;
BEGIN
  -- 1. Authentication + Organizer-Lock.
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by INTO v_creator
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL OR v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  -- 2. KO-Config validieren.
  IF p_ko_config IS NULL OR jsonb_typeof(p_ko_config) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: ko_config must be a JSON object'
      USING ERRCODE = '22023';
  END IF;
  v_with_third_place := coalesce(
    (p_ko_config ->> 'with_third_place_playoff')::boolean, false);
  v_qualifier_count := coalesce((p_ko_config ->> 'qualifier_count')::int, 0);
  IF v_qualifier_count < 2 OR v_qualifier_count > 64 THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count must be in [2, 64]'
      USING ERRCODE = '22023';
  END IF;

  -- 3. Idempotency-Guard: existieren bereits KO-Match-Rows? (ADR-0017 §7)
  SELECT count(*) INTO v_ko_exists
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','third_place','final');
  IF v_ko_exists > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: ko phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  -- 4. Vorrunde komplett? (`disputed`/`scheduled`/`awaiting_results` = blocker)
  SELECT coalesce(array_agg(id ORDER BY id), ARRAY[]::uuid[])
    INTO v_incomplete
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase = 'group'
      AND status NOT IN ('finalized','overridden','voided');
  IF array_length(v_incomplete, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'PHASE_NOT_COMPLETE: % group match(es) not terminal: %',
      array_length(v_incomplete, 1), v_incomplete
      USING ERRCODE = '22023';
  END IF;

  -- 5. Seeds bauen: Standings-Order + Overrides → JSONB-Array Top-N.
  WITH stats AS (
    SELECT p.id AS participant_id,
           p.registered_at,
           coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
           coalesce(sum(
             CASE WHEN m.participant_a = p.id THEN m.final_score_a - m.final_score_b
                  WHEN m.participant_b = p.id THEN m.final_score_b - m.final_score_a
                  ELSE 0 END), 0) AS kubb_diff
      FROM public.tournament_participants p
      LEFT JOIN public.tournament_matches m
        ON m.tournament_id = p.tournament_id
       AND m.phase = 'group'
       AND m.status IN ('finalized','overridden')
       AND (m.participant_a = p.id OR m.participant_b = p.id)
     WHERE p.tournament_id = p_tournament_id
       AND p.registration_status = 'confirmed'
     GROUP BY p.id, p.registered_at
  ),
  ranked AS (
    SELECT participant_id,
           row_number() OVER (
             ORDER BY wins DESC, kubb_diff DESC, registered_at ASC, participant_id ASC
           ) AS auto_seed
      FROM stats
  ),
  overrides AS (
    SELECT participant_id, seed_override
      FROM public.tournament_seeding_overrides
     WHERE tournament_id = p_tournament_id
  ),
  -- Override-Slots haben Vorrang; Rest füllt die Lücken in Standings-Order.
  combined AS (
    SELECT r.participant_id,
           coalesce(o.seed_override::numeric,
                    r.auto_seed::numeric + 1000) AS effective_seed,
           r.auto_seed
      FROM ranked r
      LEFT JOIN overrides o USING (participant_id)
  ),
  seeded AS (
    SELECT participant_id,
           row_number() OVER (ORDER BY effective_seed, auto_seed) AS final_seed
      FROM combined
  )
  SELECT coalesce(jsonb_agg(to_jsonb(participant_id::text) ORDER BY final_seed), '[]'::jsonb)
    INTO v_seeds_jsonb
    FROM seeded
   WHERE final_seed <= v_qualifier_count;

  IF jsonb_array_length(v_seeds_jsonb) < v_qualifier_count THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count % exceeds confirmed participants',
      v_qualifier_count USING ERRCODE = '22023';
  END IF;

  -- 6. Persistiere ko_config auf der Turnier-Row.
  UPDATE public.tournaments
    SET ko_config = p_ko_config
    WHERE id = p_tournament_id;

  -- 7. Bracket via Helper berechnen und Match-Rows inserten.
  --    BYE-Auto-Advance: is_bye_pairing → status='finalized' + winner.
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      bracket_position, participant_a, participant_b,
      phase, status, winner_participant, pitch_number, finalized_at)
  SELECT p_tournament_id,
         b.round_number::smallint,
         b.bracket_position::smallint,
         b.bracket_position,
         b.participant_a,
         b.participant_b,
         b.phase,
         CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
         CASE WHEN b.is_bye_pairing
              THEN coalesce(b.participant_a, b.participant_b) END,
         1,
         CASE WHEN b.is_bye_pairing THEN now() END
    FROM public._tournament_compute_ko_bracket(v_seeds_jsonb, v_with_third_place) b;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  SELECT count(*) INTO v_bye_count
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','final')
      AND status = 'finalized';

  -- 8. Audit-Event `ko_phase_started`.
  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'ko_phase_started',
      v_caller,
      jsonb_build_object(
        'qualifier_count',        v_qualifier_count,
        'with_third_place_playoff', v_with_third_place,
        'match_count',            v_match_count,
        'bye_count',              v_bye_count,
        'seeds',                  v_seeds_jsonb));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'match_count',   v_match_count,
    'bye_count',     v_bye_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start_ko_phase(uuid, jsonb)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_start_ko_phase(uuid, jsonb) IS
  'Phasen-Transition Round-Robin → KO. SECURITY DEFINER mit FOR UPDATE-Lock '
  'auf tournaments-Row, Idempotency-Guard via ERRCODE 40001 wenn KO-Matches '
  'bereits existieren. Liest Standings + tournament_seeding_overrides, ruft '
  '_tournament_compute_ko_bracket, persistiert ko_config und schreibt '
  'kind=ko_phase_started Audit-Event. Siehe ADR-0017 §7.';
