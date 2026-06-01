-- P6 "TournierStart" — pitch_number assignment from tournaments.pitch_plan.
--
-- Until now every materialisation path inserted matches with a hardcoded
-- pitch_number = 1 (a placeholder, see DEPENDENCIES). The P6 setup wizard
-- persists a `pitch_plan` JSONB on the tournament header
-- (20261001000001_tournament_setup_fields.sql §4). This migration adds a
-- plpgsql helper `_tournament_assign_pitches(p_tournament_id, p_round)`
-- that mirrors the pure-Dart `assignPitches`
-- (packages/kubb_domain/lib/src/tournament/pitch_assignment.dart) and
-- patches the existing insert RPCs to call it once per round, AFTER the
-- matches of that round have been inserted.
--
-- When `tournaments.pitch_plan IS NULL` the helper is a no-op, so the
-- pre-existing default behaviour (pitch_number = 1, set by every INSERT)
-- is left UNTOUCHED. The helper only ever overwrites pitch_number when a
-- plan exists.
--
-- ============================ DEPENDENCIES ============================
-- Functions REPLACED (CREATE OR REPLACE — full bodies re-stated to keep
-- the latest definition authoritative; only the post-insert
-- `_tournament_assign_pitches` call is added):
--   * public.tournament_start(uuid)
--       — latest body: 20261001000010_tournament_start_formats.sql
--         (round_robin circle rotation + swiss/schoch round 1; hybrid
--          formats delegate to tournament_start_pool_phase).
--   * public.tournament_start_pool_phase(uuid, jsonb)
--       — latest body: 20260615000009_tournament_pool_phase.sql §4.
--   * public.tournament_pair_round(uuid, text, jsonb)
--       — latest body: 20260801000001_pair_round_swiss.sql §2
--         (swiss_system dispatch). Helper validate_swiss_pairing untouched.
--   * public.tournament_start_ko_phase(uuid, jsonb)
--       — latest body: 20261101000002_double_elim_server.sql §4
--         (single- + double-elimination branch). THIS is the current
--         definition, superseding 20260601000015 and 20260615000010.
-- Function NEW:
--   * public._tournament_assign_pitches(uuid, smallint) RETURNS void.
-- Tables / columns read:
--   * public.tournaments.pitch_plan (jsonb)
--       — 20261001000001_tournament_setup_fields.sql §4.
--   * public.tournament_matches(id, tournament_id, round_number,
--       match_number_in_round, bracket_position, group_label, phase)
--       — id/round_number/match_number_in_round:
--         20260525000001_tournament_schema.sql
--       — phase/bracket_position: 20260601000010_tournament_ko_phase.sql
--       — group_label:             20260615000009_tournament_pool_phase.sql
-- Tables / columns written:
--   * public.tournament_matches.pitch_number (smallint, nullable)
--       — 20260525000001_tournament_schema.sql.
--
-- pitch_plan JSONB shape (mirror of Dart PitchPlan.toJson):
--   { "mode": "range" | "manual",
--     "range_from": int, "range_to": int,
--     "numbers": [int, ...],
--     "order": [int, ...],
--     "sort_strategy": "top_seeds_low_numbers" | "manual",
--     "group_assignment": { "A": [int,...], "B": [int,...] } }
-- =====================================================================


-- ---- 1. _tournament_pitch_available -----------------------------------
--
-- Mirror of Dart PitchPlan.availablePitches(): expands range/manual and
-- applies the explicit `order` (ordered numbers first, then the rest in
-- base order). Returns an ordered int[] (1-indexed for the round-robin
-- modulo below). Returns an EMPTY array for an absent/invalid plan, which
-- the caller treats as "no assignment".
CREATE OR REPLACE FUNCTION public._tournament_pitch_available(
  p_plan jsonb
)
RETURNS int[]
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_mode    text;
  v_from    int;
  v_to      int;
  v_base    int[] := ARRAY[]::int[];
  v_order   int[] := ARRAY[]::int[];
  v_result  int[] := ARRAY[]::int[];
  v_n       int;
  i         int;
BEGIN
  IF p_plan IS NULL OR jsonb_typeof(p_plan) <> 'object' THEN
    RETURN ARRAY[]::int[];
  END IF;

  v_mode := p_plan ->> 'mode';

  IF v_mode = 'range' THEN
    v_from := (p_plan ->> 'range_from')::int;
    v_to   := (p_plan ->> 'range_to')::int;
    IF v_from IS NOT NULL AND v_to IS NOT NULL THEN
      FOR i IN v_from .. v_to LOOP
        v_base := v_base || i;
      END LOOP;
    END IF;
  ELSIF v_mode = 'manual' THEN
    IF jsonb_typeof(p_plan -> 'numbers') = 'array' THEN
      SELECT coalesce(array_agg((val #>> '{}')::int ORDER BY ord), ARRAY[]::int[])
        INTO v_base
        FROM jsonb_array_elements(p_plan -> 'numbers')
             WITH ORDINALITY AS t(val, ord);
    END IF;
  ELSE
    RETURN ARRAY[]::int[];
  END IF;

  -- Apply explicit display order (Dart: ordered ∩ base first, then the
  -- remaining base entries in base order). `order` may reference pitches
  -- outside `base` — those are dropped (Dart `order.where(base.contains)`).
  IF jsonb_typeof(p_plan -> 'order') = 'array' THEN
    SELECT coalesce(array_agg((val #>> '{}')::int ORDER BY ord), ARRAY[]::int[])
      INTO v_order
      FROM jsonb_array_elements(p_plan -> 'order')
           WITH ORDINALITY AS t(val, ord);
  END IF;

  IF array_length(v_order, 1) IS NULL THEN
    RETURN v_base;
  END IF;

  -- ordered-and-in-base, preserving `order`'s sequence.
  FOREACH i IN ARRAY v_order LOOP
    IF i = ANY (v_base) THEN
      v_result := v_result || i;
    END IF;
  END LOOP;
  -- then base entries not named in order, preserving base sequence.
  FOREACH i IN ARRAY v_base LOOP
    IF NOT (i = ANY (v_order)) THEN
      v_result := v_result || i;
    END IF;
  END LOOP;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_pitch_available(jsonb) FROM PUBLIC;

COMMENT ON FUNCTION public._tournament_pitch_available(jsonb) IS
  'Mirror of Dart PitchPlan.availablePitches(): expands range/manual and '
  'applies the explicit order. Empty array for an absent/invalid plan.';


-- ---- 2. _tournament_assign_pitches ------------------------------------
--
-- Mirror of Dart assignPitches(List<RoundMatch>, PitchPlan). Sets
-- pitch_number on every match of round `p_round` of the given tournament
-- from tournaments.pitch_plan. No-op when pitch_plan IS NULL (default
-- pitch_number=1 preserved).
--
-- Mapping of the Dart RoundMatch fields onto tournament_matches columns:
--   * key   = the matched row's id (we UPDATE per row, so the abstract
--             map "key" never materialises; we just write each row).
--   * order = the rank used by top_seeds_low_numbers. We use
--             bracket_position when present (KO/DE rounds), otherwise
--             match_number_in_round (round-robin / pool / swiss). Both are
--             the natural "strongest pairing first" order in their path:
--             the KO bracket emits bracket_position 1 = top seed pairing,
--             and the pool/RR/swiss insert paths number matches from 1.
--   * group = group_label (pool phase). NULL for bracket / RR / swiss.
--
-- Wave partitioning (important divergence note vs. Dart, see PARITY):
--   Dart's `assignPitches` is called with the matches of ONE logical
--   round (matches that play concurrently). Server rounds are keyed by
--   round_number, but for double-elimination a single round_number spans
--   several phases (wb / lb / grand_final[_reset]) whose matches are NOT
--   concurrent. To keep the round-robin modulo from colliding across
--   those phases, we partition the assignment by (group_label, phase) and
--   run the Dart index logic INDEPENDENTLY per partition. For all
--   non-DE paths there is exactly one phase per round_number, so this
--   collapses to plain per-round (and, for pools, per-group) assignment —
--   identical to feeding the Dart helper that round's matches.
CREATE OR REPLACE FUNCTION public._tournament_assign_pitches(
  p_tournament_id uuid,
  p_round         smallint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_plan        jsonb;
  v_all         int[];
  v_has_groups  boolean;
  v_strategy    text;
BEGIN
  SELECT pitch_plan INTO v_plan
    FROM public.tournaments
    WHERE id = p_tournament_id;

  -- No plan -> leave the inserted default (pitch_number = 1) untouched.
  IF v_plan IS NULL OR jsonb_typeof(v_plan) <> 'object' THEN
    RETURN;
  END IF;

  v_all := public._tournament_pitch_available(v_plan);
  IF array_length(v_all, 1) IS NULL THEN
    RETURN;   -- empty plan -> no assignment (Dart: result smaller/empty)
  END IF;

  v_has_groups := (jsonb_typeof(v_plan -> 'group_assignment') = 'object')
              AND ((SELECT count(*) FROM jsonb_object_keys(v_plan -> 'group_assignment')) > 0);
  v_strategy   := coalesce(v_plan ->> 'sort_strategy', 'top_seeds_low_numbers');

  -- Per-partition (pool key, phase) assignment. The pool key is the
  -- group_label only when the plan has a group_assignment AND the match
  -- carries a group_label; otherwise the synthetic plan-wide pool (Dart's
  -- `null` poolKey). For each partition we build the ordered pitch list,
  -- order the matches, then assign pitch[(i-1) % len] round-robin.
  WITH src AS (
    SELECT
      m.id,
      m.phase,
      -- pool key: NULL = plan-wide pool.
      CASE WHEN v_has_groups AND m.group_label IS NOT NULL
           THEN m.group_label END                                  AS pool_key,
      -- Dart RoundMatch.order: bracket_position when present, else
      -- match_number_in_round.
      coalesce(m.bracket_position, m.match_number_in_round)         AS ord,
      -- stable tiebreaker for equal `ord` (mirror Dart "ties keep input
      -- order"): input order here is the row's natural numbering.
      m.match_number_in_round                                       AS in_order
    FROM public.tournament_matches m
    WHERE m.tournament_id = p_tournament_id
      AND m.round_number  = p_round
  ),
  -- Ordered pitch list per pool: plan-wide list for pool_key IS NULL;
  -- for a group pool, the group's assigned pitches intersected with the
  -- plan-wide list (Dart _pitchesForPool), preserving the group list's
  -- own order. A group with no/invalid assigned pitches -> empty -> no
  -- assignment for that partition.
  pool_pitch AS (
    SELECT DISTINCT s.pool_key
      FROM src s
  ),
  pitches AS (
    SELECT
      pp.pool_key,
      CASE
        WHEN pp.pool_key IS NULL THEN v_all
        ELSE (
          -- group's list, in the group's own order, kept only if also in
          -- the plan-wide available set.
          SELECT coalesce(
                   array_agg((g.val #>> '{}')::int ORDER BY g.ord)
                     FILTER (WHERE (g.val #>> '{}')::int = ANY (v_all)),
                   ARRAY[]::int[])
            FROM jsonb_array_elements(
                   v_plan -> 'group_assignment' -> pp.pool_key)
                 WITH ORDINALITY AS g(val, ord)
        )
      END AS list
      FROM pool_pitch pp
  ),
  -- Rank matches within each (pool_key, phase) partition. top_seeds_low_
  -- numbers -> order by ord asc (ties by in_order). manual -> caller list
  -- order == the row's natural (match_number_in_round / bracket_position)
  -- order, which is in_order asc.
  ranked AS (
    SELECT
      s.id,
      s.pool_key,
      s.phase,
      row_number() OVER (
        PARTITION BY s.pool_key, s.phase
        ORDER BY
          CASE WHEN v_strategy = 'top_seeds_low_numbers'
               THEN s.ord ELSE s.in_order END,
          s.in_order
      ) AS rn
    FROM src s
  )
  UPDATE public.tournament_matches t
     SET pitch_number = p.list[ ((r.rn - 1) % array_length(p.list, 1)) + 1 ]
    FROM ranked r
    JOIN pitches p ON p.pool_key IS NOT DISTINCT FROM r.pool_key
   WHERE t.id = r.id
     AND array_length(p.list, 1) IS NOT NULL;  -- empty pool -> skip (Dart: no entry)
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_assign_pitches(uuid, smallint) FROM PUBLIC;

COMMENT ON FUNCTION public._tournament_assign_pitches(uuid, smallint) IS
  'Mirror of Dart assignPitches: sets tournament_matches.pitch_number for '
  'one round from tournaments.pitch_plan (range/manual expansion, '
  'top_seeds_low_numbers ordering, per-group restriction, round-robin '
  'wrap). No-op when pitch_plan IS NULL (default pitch_number=1 kept). '
  'Partitions by (group_label, phase) so double-elim wb/lb/grand_final '
  'rows sharing a round_number do not collide.';


-- ======================================================================
-- 3. tournament_start — call the helper after each round materialises.
--    Body re-stated VERBATIM from 20261001000010 with only the
--    _tournament_assign_pitches calls added (marked PITCH-PLAN).
-- ======================================================================
CREATE OR REPLACE FUNCTION public.tournament_start(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller         uuid;
  v_status         text;
  v_format         text;
  v_pool_config    jsonb;
  v_confirmed      int;
  v_slot_count     int;
  v_round_count    int;
  v_match_count    int := 0;
  v_round          int;
  v_i              int;
  v_a_idx          int;
  v_b_idx          int;
  v_a_pid          uuid;
  v_b_pid          uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, format, pool_phase_config
    INTO v_status, v_format, v_pool_config
    FROM public.tournaments
    WHERE id = p_tournament_id AND created_by = v_caller
    FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'registration_closed' THEN
    RAISE EXCEPTION 'tournament must be in status registration_closed'
      USING ERRCODE = '22023';
  END IF;
  IF v_format NOT IN (
       'round_robin','swiss','schoch',
       'round_robin_then_ko','schoch_then_ko','swiss_then_ko') THEN
    RAISE EXCEPTION 'format not yet supported' USING ERRCODE = '0A000';
  END IF;

  -- ---- Hybrid (*_then_ko): delegate the pool phase ------------------
  IF v_format IN ('round_robin_then_ko','schoch_then_ko','swiss_then_ko') THEN
    IF v_pool_config IS NULL OR jsonb_typeof(v_pool_config) <> 'object' THEN
      RAISE EXCEPTION 'pool_phase_config required for hybrid format'
        USING ERRCODE = '22023';
    END IF;

    -- tournament_start_pool_phase assigns pitches itself (see §4).
    PERFORM public.tournament_start_pool_phase(p_tournament_id, v_pool_config);

    INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'started',
        v_caller,
        jsonb_build_object('format', v_format, 'phase', 'pool'));
    RETURN;
  END IF;

  -- ---- Non-hybrid formats: confirmed-participant precondition -------
  SELECT count(*) INTO v_confirmed
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status = 'confirmed';

  IF v_confirmed < 2 THEN
    RAISE EXCEPTION 'at least 2 confirmed participants required'
      USING ERRCODE = '22023';
  END IF;

  CREATE TEMP TABLE _tstart_slots (
    slot_idx int PRIMARY KEY,
    participant_id uuid NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _tstart_slots(slot_idx, participant_id)
  SELECT row_number() OVER (ORDER BY p.registered_at, p.id), p.id
    FROM public.tournament_participants p
    WHERE p.tournament_id = p_tournament_id
      AND p.registration_status = 'confirmed';

  UPDATE public.tournament_participants p
    SET seed = s.slot_idx
    FROM _tstart_slots s
    WHERE p.id = s.participant_id;

  -- ---- swiss / schoch: materialise ROUND 1 only ---------------------
  IF v_format IN ('swiss','schoch') THEN
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        participant_a, participant_b, pitch_number, status)
    SELECT
      p_tournament_id,
      1::smallint,
      (((s.slot_idx - 1) / 2) + 1)::smallint,
      s.participant_id,
      part.participant_id,
      1,
      'scheduled'
    FROM _tstart_slots s
    LEFT JOIN _tstart_slots part
      ON part.slot_idx = s.slot_idx + 1
    WHERE (s.slot_idx % 2) = 1;

    GET DIAGNOSTICS v_match_count = ROW_COUNT;

    DROP TABLE _tstart_slots;

    -- PITCH-PLAN: assign pitch_number for round 1 (no-op if plan NULL).
    PERFORM public._tournament_assign_pitches(p_tournament_id, 1::smallint);

    UPDATE public.tournaments
      SET status = 'live', started_at = now()
      WHERE id = p_tournament_id;

    INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'started',
        v_caller,
        jsonb_build_object(
          'format',      v_format,
          'round_count', 1,
          'match_count', v_match_count));
    RETURN;
  END IF;

  -- ---- round_robin: original circle-rotation materialisation --------
  IF (v_confirmed % 2) = 1 THEN
    v_slot_count := v_confirmed + 1;
    INSERT INTO _tstart_slots(slot_idx, participant_id) VALUES (v_slot_count, NULL);
  ELSE
    v_slot_count := v_confirmed;
  END IF;

  v_round_count := v_slot_count - 1;

  CREATE TEMP TABLE _tstart_ring (
    pos int PRIMARY KEY,
    participant_id uuid NULL
  ) ON COMMIT DROP;

  INSERT INTO _tstart_ring(pos, participant_id)
    SELECT slot_idx, participant_id FROM _tstart_slots;

  FOR v_round IN 1..v_round_count LOOP
    FOR v_i IN 0..((v_slot_count / 2) - 1) LOOP
      v_a_idx := v_i + 1;
      v_b_idx := v_slot_count - v_i;

      SELECT participant_id INTO v_a_pid FROM _tstart_ring WHERE pos = v_a_idx;
      SELECT participant_id INTO v_b_pid FROM _tstart_ring WHERE pos = v_b_idx;

      IF v_a_pid IS NULL AND v_b_pid IS NULL THEN
        CONTINUE;
      END IF;
      IF v_a_pid IS NULL THEN
        v_a_pid := v_b_pid;
        v_b_pid := NULL;
      END IF;

      INSERT INTO public.tournament_matches(
          tournament_id, round_number, match_number_in_round,
          participant_a, participant_b, pitch_number, status)
        VALUES (
          p_tournament_id, v_round::smallint, (v_i + 1)::smallint,
          v_a_pid, v_b_pid, 1, 'scheduled');

      v_match_count := v_match_count + 1;
    END LOOP;

    -- PITCH-PLAN: assign pitch_number for this round's matches once the
    -- round is fully inserted (no-op if plan NULL).
    PERFORM public._tournament_assign_pitches(p_tournament_id, v_round::smallint);

    UPDATE _tstart_ring
      SET pos = CASE
                  WHEN pos = 1 THEN 1
                  WHEN pos = v_slot_count THEN 2
                  ELSE pos + 1
                END;
  END LOOP;

  DROP TABLE _tstart_ring;
  DROP TABLE _tstart_slots;

  UPDATE public.tournaments
    SET status = 'live', started_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'started',
      v_caller,
      jsonb_build_object(
        'format',      v_format,
        'round_count', v_round_count,
        'match_count', v_match_count));
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start(uuid) TO authenticated;


-- ======================================================================
-- 4. tournament_start_pool_phase — assign pitches per round after insert.
--    Body re-stated VERBATIM from 20260615000009 §4 with only the
--    _tournament_assign_pitches call added (marked PITCH-PLAN). Pool-RR
--    inserts everything as round_number = 1, so a single call covers all
--    group matches; the helper partitions by group_label internally.
-- ======================================================================
CREATE OR REPLACE FUNCTION public.tournament_start_pool_phase(
  p_tournament_id uuid,
  p_config        jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_creator       uuid;
  v_pools         jsonb;
  v_participants  jsonb;
  v_assignments   int := 0;
  v_match_count   int := 0;
  v_existing      int;
  v_labels        text[];
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

  SELECT count(*) INTO v_existing
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase = 'group';
  IF v_existing > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: pool phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(id::text)
                            ORDER BY registered_at ASC, id ASC),
                  '[]'::jsonb)
    INTO v_participants
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status = 'confirmed';

  IF jsonb_array_length(v_participants) < 2 THEN
    RAISE EXCEPTION 'INVALID_POOL_CONFIG: at least 2 confirmed participants required'
      USING ERRCODE = '22023';
  END IF;

  v_pools := public._tournament_compute_pools(v_participants, p_config);

  WITH assignments AS (
    SELECT (elem ->> 'participant_id')::uuid AS pid,
           (elem ->> 'group_label')          AS lbl
      FROM jsonb_array_elements(v_pools) AS elem
  )
  UPDATE public.tournament_participants tp
     SET group_label = a.lbl
    FROM assignments a
   WHERE tp.id = a.pid
     AND tp.tournament_id = p_tournament_id;
  GET DIAGNOSTICS v_assignments = ROW_COUNT;

  SELECT array_agg(DISTINCT (elem ->> 'group_label') ORDER BY (elem ->> 'group_label'))
    INTO v_labels
    FROM jsonb_array_elements(v_pools) AS elem;

  WITH members AS (
    SELECT (elem ->> 'participant_id')::uuid AS pid,
           (elem ->> 'group_label')          AS lbl,
           (elem ->> 'group_position')::int  AS pos
      FROM jsonb_array_elements(v_pools) AS elem
  ),
  pairs AS (
    SELECT m1.lbl, m1.pid AS pid_a, m2.pid AS pid_b,
           m1.pos AS pos_a, m2.pos AS pos_b,
           row_number() OVER (
             PARTITION BY m1.lbl
             ORDER BY m1.pos, m2.pos
           ) AS pair_no
      FROM members m1
      JOIN members m2 ON m1.lbl = m2.lbl AND m1.pos < m2.pos
  )
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b,
      phase, group_label, status, pitch_number)
  SELECT p_tournament_id,
         1::smallint,
         pair_no::smallint,
         pid_a, pid_b,
         'group',
         lbl,
         'scheduled',
         1
    FROM pairs;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  -- PITCH-PLAN: pool round-robin uses round_number = 1 for all groups;
  -- the helper partitions by group_label and honours group_assignment
  -- (no-op if plan NULL).
  PERFORM public._tournament_assign_pitches(p_tournament_id, 1::smallint);

  UPDATE public.tournaments
     SET status     = 'live',
         started_at = coalesce(started_at, now())
   WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'pool_phase_started',
      v_caller,
      jsonb_build_object(
        'group_count',           coalesce(array_length(v_labels, 1), 0),
        'assignments',           v_assignments,
        'match_count',           v_match_count,
        'config',                p_config));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'group_count',   coalesce(array_length(v_labels, 1), 0),
    'assignments',   v_assignments,
    'match_count',   v_match_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start_pool_phase(uuid, jsonb)
  TO authenticated;


-- ======================================================================
-- 5. tournament_pair_round — assign pitches for the newly paired round.
--    Body re-stated VERBATIM from 20260801000001 §2 with only the
--    _tournament_assign_pitches call added (marked PITCH-PLAN).
--    validate_swiss_pairing is untouched.
-- ======================================================================
CREATE OR REPLACE FUNCTION public.tournament_pair_round(
  p_tournament_id uuid,
  p_strategy      text,
  p_pairings      jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_creator    uuid;
  v_status     text;
  v_next_round int;
  v_inserted   int := 0;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, status INTO v_creator, v_status
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_creator <> v_caller THEN
    RAISE EXCEPTION 'not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'live' THEN
    RAISE EXCEPTION 'tournament must be in status live' USING ERRCODE = '22023';
  END IF;

  IF p_strategy IS DISTINCT FROM 'swiss_system' OR p_pairings IS NULL THEN
    RETURN;
  END IF;

  PERFORM public.validate_swiss_pairing(p_tournament_id, p_pairings);

  SELECT coalesce(max(round_number), 0) + 1
    INTO v_next_round
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id;

  WITH ins AS (
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        participant_a, participant_b, pitch_number, status)
    SELECT
      p_tournament_id,
      v_next_round::smallint,
      (row_number() OVER ())::smallint,
      (elem ->> 'participant_a')::uuid,
      NULLIF(elem ->> 'participant_b','')::uuid,
      1,
      'scheduled'
    FROM jsonb_array_elements(p_pairings) AS elem
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM ins;

  -- PITCH-PLAN: assign pitch_number for the freshly paired round (no-op
  -- if plan NULL).
  PERFORM public._tournament_assign_pitches(p_tournament_id, v_next_round::smallint);

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'swiss_round_paired',
      v_caller,
      jsonb_build_object(
        'round_number', v_next_round,
        'match_count',  v_inserted,
        'strategy',     p_strategy
      )
    );
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_pair_round(uuid, text, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_pair_round(uuid, text, jsonb) TO authenticated;


-- ======================================================================
-- 6. tournament_start_ko_phase — assign pitches across every KO/DE round.
--    Body re-stated VERBATIM from 20261101000002 §4 (the CURRENT
--    definition, single- + double-elimination) with only the per-round
--    _tournament_assign_pitches loop added (marked PITCH-PLAN). The
--    bracket helpers emit several round_number values (and, for DE,
--    several phases per round_number); we iterate over the DISTINCT
--    round_number values just inserted and let the helper partition by
--    (group_label, phase). BYE-walkover rows are finalized with a pitch
--    too — harmless, and keeps the column consistent.
-- ======================================================================
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
  v_bracket_type      text;
  v_with_reset        boolean;
  v_round             smallint;   -- PITCH-PLAN loop variable
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, bracket_type,
         coalesce((ko_config ->> 'with_bracket_reset')::boolean, true)
    INTO v_creator, v_bracket_type, v_with_reset
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL OR v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

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

  IF v_bracket_type = 'double_elimination' THEN
    v_with_reset := coalesce(
      (p_ko_config ->> 'with_bracket_reset')::boolean, v_with_reset);
    IF v_with_third_place THEN
      RAISE EXCEPTION 'INVALID_KO_CONFIG: with_third_place_playoff is not allowed for double_elimination'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  SELECT count(*) INTO v_ko_exists
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','third_place','final',
                    'wb','lb','grand_final','grand_final_reset');
  IF v_ko_exists > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: ko phase already initialised'
      USING ERRCODE = '40001';
  END IF;

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

  SELECT EXISTS (
    SELECT 1 FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL
  ) INTO v_has_pool_phase;

  IF v_has_pool_phase THEN
    SELECT coalesce(array_agg(participant_id), ARRAY[]::uuid[])
      INTO v_override_ids
      FROM public.tournament_seeding_overrides
     WHERE tournament_id = p_tournament_id;

    SELECT count(DISTINCT group_label) INTO v_pool_count
      FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL;
    v_top_n := greatest(1, ((v_qualifier_count + v_pool_count - 1) / v_pool_count));

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

  UPDATE public.tournaments
    SET ko_config = p_ko_config
    WHERE id = p_tournament_id;

  IF v_bracket_type = 'double_elimination' THEN
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
      FROM public._tournament_compute_de_bracket(v_seeds_jsonb, v_with_reset) b;
  ELSE
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
  END IF;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  -- PITCH-PLAN: assign pitch_number for every round just inserted. The
  -- bracket helpers number rounds from 1; for DE several phases share a
  -- round_number and the helper partitions by (group_label, phase).
  -- No-op per round if pitch_plan IS NULL.
  FOR v_round IN
    SELECT DISTINCT round_number
      FROM public.tournament_matches
     WHERE tournament_id = p_tournament_id
       AND phase IN ('ko','third_place','final',
                     'wb','lb','grand_final','grand_final_reset')
     ORDER BY round_number
  LOOP
    PERFORM public._tournament_assign_pitches(p_tournament_id, v_round);
  END LOOP;

  SELECT count(*) INTO v_bye_count
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','final','wb','lb')
      AND status = 'finalized';

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'ko_phase_started',
      v_caller,
      jsonb_build_object(
        'qualifier_count',          v_qualifier_count,
        'with_third_place_playoff', v_with_third_place,
        'bracket_type',             v_bracket_type,
        'with_bracket_reset',       v_with_reset,
        'match_count',              v_match_count,
        'bye_count',                v_bye_count,
        'pool_phase_present',       v_has_pool_phase,
        'seeds',                    v_seeds_jsonb));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'match_count',   v_match_count,
    'bye_count',     v_bye_count,
    'pool_phase',    v_has_pool_phase,
    'bracket_type',  v_bracket_type);
END;
$$;
