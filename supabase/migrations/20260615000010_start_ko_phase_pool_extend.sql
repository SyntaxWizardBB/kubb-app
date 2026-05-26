-- Tournament feature — M3.3 KO-phase start extended for pool cut.
--
-- Erweitert `tournament_start_ko_phase` aus M2: wenn das Turnier eine
-- Pool-Phase hat (mindestens ein `tournament_participants`-Eintrag mit
-- `group_label IS NOT NULL`), wird Top-N pro Gruppe via Helper
-- `_tournament_compute_pool_cut(uuid, text, int)` ermittelt und via
-- Cross-Pool-Interleave (Rang-1 aller Gruppen, dann Rang-2, ...) in das
-- Bracket-Seeding gemergt. Vorhandene `tournament_seeding_overrides`
-- gewinnen (manuelle Auflösung eines vorherigen TIEBREAKER_NEEDS_RESOLUTION).
--
-- Ohne Pool-Phase fällt der Code-Pfad auf das M2-Standings-Verhalten
-- zurück (Acceptance: "ohne Pool-Phase Then RPC verhält sich wie M2").
--
-- Bezug: docs/plans/m3-teams-pools-roster/tasks.md TASK-M3.3-T6,
--        docs/plans/m3-teams-pools-roster/sprint-plan.md OD-M3-03/-05,
--        ADR-0019 §Vollständiger Tie.
--
-- Fehler-Mapping (zusätzlich zu M2):
--   TIEBREAKER_NEEDS_RESOLUTION — P0001
--     DETAIL ist jsonb-string-encoded `{conflicting_participants: [...]}`.
--     Frontend (T8/T11) extrahiert die Liste und zeigt den
--     Veranstalter-Eskalations-Dialog.
--
-- Ein zweiter RPC `tournament_resolve_cross_pool_tie` schreibt die
-- manuelle Sortierung in `tournament_seeding_overrides`. Beim nächsten
-- `tournament_start_ko_phase`-Aufruf gewinnen diese Overrides und der
-- Tie wird nicht erneut geworfen (Acceptance §4).

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
  v_has_pool_phase    boolean;
  v_seeds_jsonb       jsonb;
  v_match_count       int := 0;
  v_bye_count         int := 0;
  v_group_label       text;
  v_top_n             int;
  v_cut_result        jsonb;
  v_conflict_ids      jsonb := '[]'::jsonb;
  v_override_ids      uuid[];
  v_pool_count        int;
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

  -- 3. Idempotency-Guard.
  SELECT count(*) INTO v_ko_exists
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','third_place','final');
  IF v_ko_exists > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: ko phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  -- 4. Vorrunde komplett?
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

  -- 5. Pool-Phase erkennen: mindestens ein Participant mit group_label.
  SELECT EXISTS (
    SELECT 1 FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL
  ) INTO v_has_pool_phase;

  IF v_has_pool_phase THEN
    -- 5a. Pre-existing manual overrides (aus Resolve-RPC) merken — diese
    --     Participants gelten als bereits aufgelöst und triggern keinen
    --     erneuten TIEBREAKER_NEEDS_RESOLUTION (Acceptance §4).
    SELECT coalesce(array_agg(participant_id), ARRAY[]::uuid[])
      INTO v_override_ids
      FROM public.tournament_seeding_overrides
     WHERE tournament_id = p_tournament_id;

    -- 5b. Top-N pro Gruppe via Helper (T5). Die Anzahl der Pools
    --     bestimmt den Per-Gruppe-Cut: ceil(qualifier_count / pool_count).
    SELECT count(DISTINCT group_label) INTO v_pool_count
      FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL;
    v_top_n := greatest(1, ((v_qualifier_count + v_pool_count - 1) / v_pool_count));

    -- 5c. Für jede Gruppe Helper aufrufen, Konflikt-Sammlung + Per-Pool-
    --     Rangliste in einer Temp-Struktur ablegen.
    CREATE TEMP TABLE IF NOT EXISTS _tmp_pool_cuts (
      group_label text,
      rank_in_pool int,
      participant_id uuid
    ) ON COMMIT DROP;
    TRUNCATE _tmp_pool_cuts;

    FOR v_group_label IN
      SELECT DISTINCT group_label
        FROM public.tournament_participants
       WHERE tournament_id = p_tournament_id
         AND group_label IS NOT NULL
       ORDER BY 1
    LOOP
      v_cut_result := public._tournament_compute_pool_cut(
        p_tournament_id, v_group_label, v_top_n);

      IF coalesce((v_cut_result ->> 'tie_resolution_needed')::boolean, false) THEN
        -- Sammle Konflikt-Participants. Helper liefert sie in
        -- `conflicting_participants` (Array von uuid-strings).
        v_conflict_ids := v_conflict_ids
          || coalesce(v_cut_result -> 'conflicting_participants', '[]'::jsonb);
      END IF;

      INSERT INTO _tmp_pool_cuts(group_label, rank_in_pool, participant_id)
      SELECT v_group_label,
             (ord)::int,
             (val #>> '{}')::uuid
        FROM jsonb_array_elements(v_cut_result -> 'qualifiers')
             WITH ORDINALITY AS t(val, ord);
    END LOOP;

    -- 5d. Konflikt-Filter: nur Participants ohne Override eskalieren.
    IF jsonb_array_length(v_conflict_ids) > 0 THEN
      SELECT coalesce(jsonb_agg(elem ORDER BY elem), '[]'::jsonb)
        INTO v_conflict_ids
        FROM (
          SELECT DISTINCT elem
            FROM jsonb_array_elements_text(v_conflict_ids) AS elem
           WHERE (elem)::uuid <> ALL (v_override_ids)
        ) sub;

      IF jsonb_array_length(v_conflict_ids) > 0 THEN
        RAISE EXCEPTION 'TIEBREAKER_NEEDS_RESOLUTION'
          USING ERRCODE = 'P0001',
                DETAIL = jsonb_build_object(
                  'conflicting_participants', v_conflict_ids)::text;
      END IF;
    END IF;

    -- 5e. Cross-Pool-Interleave: rank-1 aller Gruppen zuerst (group_label
    --     ASC, deterministisch via dense_rank), dann rank-2 usw.
    --     Overrides aus der M2-Tabelle gewinnen.
    WITH labels AS (
      SELECT group_label,
             dense_rank() OVER (ORDER BY group_label) AS label_idx
        FROM (SELECT DISTINCT group_label FROM _tmp_pool_cuts) g
    ),
    base AS (
      SELECT c.participant_id,
             (c.rank_in_pool - 1) * 1000 + l.label_idx AS interleave_seed
        FROM _tmp_pool_cuts c
        JOIN labels l USING (group_label)
    ),
    overrides AS (
      SELECT participant_id, seed_override
        FROM public.tournament_seeding_overrides
       WHERE tournament_id = p_tournament_id
    ),
    combined AS (
      SELECT b.participant_id,
             coalesce(o.seed_override::numeric,
                      b.interleave_seed::numeric + 1000000) AS effective_seed,
             b.interleave_seed
        FROM base b
        LEFT JOIN overrides o USING (participant_id)
    ),
    seeded AS (
      SELECT participant_id,
             row_number() OVER (ORDER BY effective_seed, interleave_seed) AS final_seed
        FROM combined
    )
    SELECT coalesce(jsonb_agg(to_jsonb(participant_id::text) ORDER BY final_seed), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM seeded
     WHERE final_seed <= v_qualifier_count;

  ELSE
    -- 6a. M2-Pfad: Standings-Order + Overrides → Top-N (unverändert).
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
  END IF;

  IF jsonb_array_length(v_seeds_jsonb) < v_qualifier_count THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count % exceeds confirmed participants',
      v_qualifier_count USING ERRCODE = '22023';
  END IF;

  -- 7. Persistiere ko_config.
  UPDATE public.tournaments
    SET ko_config = p_ko_config
    WHERE id = p_tournament_id;

  -- 8. Bracket via Helper berechnen und Match-Rows inserten.
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

  -- 9. Audit-Event ko_phase_started (mit pool-Marker).
  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'ko_phase_started',
      v_caller,
      jsonb_build_object(
        'qualifier_count',         v_qualifier_count,
        'with_third_place_playoff', v_with_third_place,
        'match_count',             v_match_count,
        'bye_count',               v_bye_count,
        'pool_phase_present',      v_has_pool_phase,
        'seeds',                   v_seeds_jsonb));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'match_count',   v_match_count,
    'bye_count',     v_bye_count,
    'pool_phase',    v_has_pool_phase);
END;
$$;

COMMENT ON FUNCTION public.tournament_start_ko_phase(uuid, jsonb) IS
  'M3.3-erweitert: bei Pool-Phase (group_label IS NOT NULL) wird Top-N '
  'pro Gruppe via _tournament_compute_pool_cut ermittelt und cross-pool '
  'interleaved; tournament_seeding_overrides gewinnen (manuelle Auflösung '
  'eines TIEBREAKER_NEEDS_RESOLUTION-Eskalations-Dialogs). Ohne Pool-Phase '
  'unverändert M2-Verhalten. Siehe ADR-0017 §7 + ADR-0019 §Vollständiger Tie.';


-- ---- Resolve-RPC für Cross-Pool-Tie -----------------------------------
--
-- Veranstalter übergibt eine geordnete Liste der `conflicting_participants`
-- aus dem TIEBREAKER_NEEDS_RESOLUTION-Payload. Wir schreiben pro
-- Participant einen `seed_override`-Eintrag, der beim nächsten
-- `tournament_start_ko_phase`-Aufruf den Tie auflöst. Die seed-Zahlen
-- selbst sind opak — sie müssen lediglich die gewünschte Reihenfolge
-- erzwingen; deshalb verwenden wir 1, 2, 3, ... in Reihenfolge der
-- Eingabe-Liste, gewichtet mit einem hohen Basis-Offset damit M2-Overrides
-- (die typischerweise ab seed 1 starten) nicht kollidieren.

CREATE OR REPLACE FUNCTION public.tournament_resolve_cross_pool_tie(
  p_tournament_id            uuid,
  p_ordered_participant_ids  jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller   uuid;
  v_creator  uuid;
  v_count    int := 0;
  v_pid      uuid;
  v_ord      int;
BEGIN
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

  IF p_ordered_participant_ids IS NULL
     OR jsonb_typeof(p_ordered_participant_ids) <> 'array'
     OR jsonb_array_length(p_ordered_participant_ids) < 2 THEN
    RAISE EXCEPTION 'INVALID_INPUT: ordered_participant_ids must be a JSON array of length >= 2'
      USING ERRCODE = '22023';
  END IF;

  -- Hoher Basis-Offset (10000), damit die per-Tie-Auflösung gesetzten
  -- Seeds nicht mit M2-`tournament_set_seeding`-Overrides kollidieren.
  FOR v_ord, v_pid IN
    SELECT ord::int, (val #>> '{}')::uuid
      FROM jsonb_array_elements(p_ordered_participant_ids)
           WITH ORDINALITY AS t(val, ord)
  LOOP
    INSERT INTO public.tournament_seeding_overrides(
        tournament_id, participant_id, seed_override, set_by, set_at)
      VALUES (p_tournament_id, v_pid, 10000 + v_ord, v_caller, now())
      ON CONFLICT (tournament_id, participant_id)
      DO UPDATE SET seed_override = EXCLUDED.seed_override,
                    set_by        = EXCLUDED.set_by,
                    set_at        = EXCLUDED.set_at;
    v_count := v_count + 1;
  END LOOP;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'cross_pool_tie_resolved',
      v_caller,
      jsonb_build_object(
        'ordered_participant_ids', p_ordered_participant_ids,
        'override_count',          v_count));

  RETURN jsonb_build_object(
    'tournament_id',  p_tournament_id,
    'override_count', v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_resolve_cross_pool_tie(uuid, jsonb)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_resolve_cross_pool_tie(uuid, jsonb) IS
  'Veranstalter-Auflösung eines TIEBREAKER_NEEDS_RESOLUTION-Events. Schreibt '
  'die manuelle Sortierung als seed_override (Offset 10000) in '
  'tournament_seeding_overrides. Nächster tournament_start_ko_phase-Aufruf '
  'nutzt die Reihenfolge und eskaliert nicht erneut. Siehe ADR-0019.';
