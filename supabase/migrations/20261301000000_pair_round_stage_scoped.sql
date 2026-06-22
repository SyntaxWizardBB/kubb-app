-- Stage-scoped tournament_pair_round — ADR-0039 §3 (HIGH-2/3, Server-Seite).
--
-- Der Schoch-Loop schliesst sich so: der Client rechnet die Paarung der
-- nächsten Runde (planRound, Dart) und schickt sie an tournament_pair_round;
-- das RPC validiert + materialisiert die Runde stage-scoped; beim Finalisieren
-- der eingefügten Matches feuert der Runner-Trigger (20261300000000) das
-- nächste 'swiss_round_complete'. Diese Migration ist NUR die Server-Erweiterung.
--
-- ADDITIV: ein neuer Parameter p_stage_node_id text DEFAULT NULL auf
-- tournament_pair_round, plus eine neue 3-arg-Variante von
-- validate_swiss_pairing. Basis ist der zuletzt angewendete Body von
-- tournament_pair_round (20261283000000_rename_organizer_teams.sql, Z. ~2144).
--
--   * p_stage_node_id IS NULL  -> BYTE-IDENTISCHES Verhalten zum 20261283-Body.
--     Der flache (Nicht-Stufen-)Pfad bleibt unverändert; alle bestehenden
--     Aufrufer und Tests laufen weiter. Das ist Pflicht.
--   * p_stage_node_id NOT NULL -> STAGE-SCOPED. Manage-Gate wie bisher, dann:
--       (i)   Stufe muss type IN ('schoch','swiss') und status 'active' sein.
--       (ii)  Progression-Gate runden-scoped: max(round_number) NUR über
--             Matches dieser Stufe; alle terminal, sonst round_not_complete.
--       (iii) validate_swiss_pairing STAGE-SCOPED (Repeat/Bye nur über Matches
--             mit stage_node_id = p_stage_node_id; Roster bleibt tournament-weit).
--       (iv)  INSERT mit stage_node_id = p_stage_node_id, round_number =
--             stage-scoped max+1, status 'scheduled', phase 'group'. Schedule +
--             per-pitch-notify wie der Stufen-Generator (20261293000000).
--       (v)   Audit 'swiss_round_paired' (payload mit stage_node_id, round).
--
-- CREATE OR REPLACE, GRANTs unverändert (authenticated). Keine fremde Migration
-- editiert.
-- =====================================================================

-- ---- 1. validate_swiss_pairing — neue stage-scoped 3-arg-Variante ----
-- Die alte 2-arg-Variante bleibt für den NULL-Pfad unverändert in
-- 20260801000001_pair_round_swiss.sql. Diese Variante prüft Repeat und Bye
-- NUR über Matches der gegebenen Stufe, sonst zählten Paarungen anderer Stufen
-- fälschlich als Wiederholung. Die Roster-Prüfung bleibt tournament-weit, weil
-- Teilnehmer am Turnier hängen, nicht an einer Stufe.
CREATE OR REPLACE FUNCTION public.validate_swiss_pairing(
  p_tournament_id uuid,
  p_pairings      jsonb,
  p_stage_node_id text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_roster_count   int;
  v_unknown_count  int;
  v_dup_count      int;
  v_repeat_count   int;
  v_bye_conflict   int;
BEGIN
  IF p_pairings IS NULL OR jsonb_typeof(p_pairings) <> 'array' THEN
    RAISE EXCEPTION 'invalid_pairing: payload must be a JSON array'
      USING ERRCODE = '22023';
  END IF;

  WITH raw AS (
    SELECT (row_number() OVER ())::int AS slot,
           (elem ->> 'participant_a')::uuid AS pa,
           NULLIF(elem ->> 'participant_b','')::uuid AS pb
      FROM jsonb_array_elements(p_pairings) AS elem
  ),
  pieces AS (
    SELECT slot, pa AS pid, (pb IS NULL) AS is_bye FROM raw
    UNION ALL
    SELECT slot, pb AS pid, false AS is_bye FROM raw WHERE pb IS NOT NULL
  )
  SELECT
    count(*) FILTER (
      WHERE NOT EXISTS (
        SELECT 1 FROM public.tournament_participants tp
         WHERE tp.id = pieces.pid
           AND tp.tournament_id = p_tournament_id
           AND tp.registration_status = 'confirmed'
      )
    ),
    (SELECT count(*) FROM (
        SELECT pid FROM pieces GROUP BY pid HAVING count(*) > 1
     ) d)
  INTO v_unknown_count, v_dup_count
  FROM pieces;

  IF v_unknown_count > 0 THEN
    RAISE EXCEPTION 'invalid_pairing: participant not on tournament roster'
      USING ERRCODE = '22023';
  END IF;

  IF v_dup_count > 0 THEN
    RAISE EXCEPTION 'invalid_pairing: duplicate participant in round'
      USING ERRCODE = '22023';
  END IF;

  -- Repeat detection — stage-scoped: only prior matches of THIS stage count.
  SELECT count(*)
    INTO v_repeat_count
    FROM jsonb_array_elements(p_pairings) AS elem
    JOIN public.tournament_matches m
      ON m.tournament_id = p_tournament_id
     AND m.stage_node_id = p_stage_node_id
     AND m.participant_b IS NOT NULL
     AND (
       (m.participant_a = (elem ->> 'participant_a')::uuid
        AND m.participant_b = NULLIF(elem ->> 'participant_b','')::uuid)
       OR
       (m.participant_b = (elem ->> 'participant_a')::uuid
        AND m.participant_a = NULLIF(elem ->> 'participant_b','')::uuid)
     )
   WHERE NULLIF(elem ->> 'participant_b','') IS NOT NULL;

  IF v_repeat_count > 0 THEN
    RAISE EXCEPTION 'invalid_pairing: pairing already played in earlier round'
      USING ERRCODE = '22023';
  END IF;

  -- Bye conflict — stage-scoped: only prior byes of THIS stage count.
  SELECT count(*)
    INTO v_bye_conflict
    FROM jsonb_array_elements(p_pairings) AS elem
    JOIN public.tournament_matches m
      ON m.tournament_id = p_tournament_id
     AND m.stage_node_id = p_stage_node_id
     AND m.participant_b IS NULL
     AND m.participant_a = (elem ->> 'participant_a')::uuid
   WHERE NULLIF(elem ->> 'participant_b','') IS NULL;

  IF v_bye_conflict > 0 THEN
    RAISE EXCEPTION 'invalid_pairing: participant already received a bye'
      USING ERRCODE = '22023';
  END IF;

  PERFORM v_roster_count;
END;
$$;

REVOKE ALL ON FUNCTION public.validate_swiss_pairing(uuid, jsonb, text) FROM public;
GRANT EXECUTE ON FUNCTION public.validate_swiss_pairing(uuid, jsonb, text) TO authenticated;

COMMENT ON FUNCTION public.validate_swiss_pairing(uuid, jsonb, text) IS
  'Stage-scoped pairing validation (ADR-0039 §3). Roster check is '
  'tournament-wide; repeat and bye checks count ONLY prior matches with '
  'stage_node_id = p_stage_node_id, so pairings from other stages do not '
  'falsely register as repeats. The 2-arg variant (flat path) is unchanged.';

-- ---- 2. tournament_pair_round — additiver p_stage_node_id-Parameter ----
-- Der neue optionale Parameter wird über DEFAULT NULL angehängt. Postgres würde
-- bei zwei Overloads (3-arg und 4-arg-mit-Default) einen 3-arg-Aufruf als
-- ambig ablehnen, darum wird die alte 3-arg-Signatur fallengelassen. Ein
-- 3-arg-Aufruf (alle bestehenden Aufrufer/Tests) löst danach eindeutig auf den
-- 4-arg-Body mit p_stage_node_id := NULL auf -> byte-identisches Verhalten.
DROP FUNCTION IF EXISTS public.tournament_pair_round(uuid, text, jsonb);

CREATE OR REPLACE FUNCTION public.tournament_pair_round(
  p_tournament_id uuid,
  p_strategy      text,
  p_pairings      jsonb DEFAULT NULL::jsonb,
  p_stage_node_id text  DEFAULT NULL)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller        uuid;
  v_creator       uuid;
  v_status        text;
  v_next_round    int;
  v_inserted      int := 0;
  v_current_round int;
  v_open_count    int;
  v_name          text;
  v_stage_type    text;
  v_stage_status  text;
  v_ms            int;
  v_bs            int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, status, display_name INTO v_creator, v_status, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the organizer_team_id.
  IF NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'live' THEN
    RAISE EXCEPTION 'tournament must be in status live' USING ERRCODE = '22023';
  END IF;

  IF p_strategy IS DISTINCT FROM 'swiss_system' OR p_pairings IS NULL THEN
    RETURN;
  END IF;

  IF p_stage_node_id IS NOT NULL THEN
    -- ============ STAGE-SCOPED PATH (ADR-0039 §3) ============
    -- The stage must be a live schoch stage; pairing any other type/state is
    -- a misuse vector.
    SELECT s.type, s.status
      INTO v_stage_type, v_stage_status
      FROM public.tournament_stages s
      WHERE s.tournament_id = p_tournament_id
        AND s.node_id = p_stage_node_id;

    IF v_stage_type IS NULL THEN
      RAISE EXCEPTION 'stage_not_found: % has no stage node %',
        p_tournament_id, p_stage_node_id
        USING ERRCODE = 'P0002';
    END IF;
    IF v_stage_type NOT IN ('schoch', 'swiss') THEN
      RAISE EXCEPTION
        'invalid_stage_type: stage % is %, only schoch stages can be paired',
        p_stage_node_id, v_stage_type
        USING ERRCODE = '22023';
    END IF;
    IF v_stage_status <> 'active' THEN
      RAISE EXCEPTION 'stage_not_active: stage % is %',
        p_stage_node_id, v_stage_status
        USING ERRCODE = '22023';
    END IF;

    -- Progression-Gate, round-scoped over THIS stage only.
    SELECT max(round_number) INTO v_current_round
      FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND stage_node_id = p_stage_node_id;

    IF v_current_round IS NOT NULL THEN
      SELECT count(*) INTO v_open_count
        FROM public.tournament_matches
        WHERE tournament_id = p_tournament_id
          AND stage_node_id = p_stage_node_id
          AND round_number  = v_current_round
          AND status NOT IN ('finalized','overridden','voided');

      IF v_open_count > 0 THEN
        RAISE EXCEPTION
          'round_not_complete: round % of stage % still has % open match(es); finalize them before pairing the next round',
          v_current_round, p_stage_node_id, v_open_count
          USING ERRCODE = '22023';
      END IF;
    END IF;

    PERFORM public.validate_swiss_pairing(p_tournament_id, p_pairings, p_stage_node_id);

    SELECT coalesce(max(round_number), 0) + 1
      INTO v_next_round
      FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND stage_node_id = p_stage_node_id;

    WITH ins AS (
      INSERT INTO public.tournament_matches(
          tournament_id, stage_node_id, round_number, match_number_in_round,
          participant_a, participant_b, phase, pitch_number, status)
      SELECT
        p_tournament_id,
        p_stage_node_id,
        v_next_round::smallint,
        (row_number() OVER ())::smallint,
        (elem ->> 'participant_a')::uuid,
        NULLIF(elem ->> 'participant_b','')::uuid,
        'group',
        1,
        'scheduled'
      FROM jsonb_array_elements(p_pairings) AS elem
      RETURNING 1
    )
    SELECT count(*) INTO v_inserted FROM ins;

    -- Schedule + per-pitch notify mirror the stage generator (20261293000000):
    -- one schedule row per (tournament, round, stage), prelim timing.
    SELECT p.match_seconds, p.break_seconds
      INTO v_ms, v_bs
      FROM public._tournament_schedule_prelim_seconds(p_tournament_id) p;
    PERFORM public._tournament_upsert_round_schedule(
      p_tournament_id, p_stage_node_id, v_next_round, 'group',
      v_ms, v_bs, NULL, now());

    PERFORM public._tournament_notify_round_per_pitch(
      p_tournament_id, v_next_round, 'group', 'round_published',
      'Runde ' || v_next_round || ' veröffentlicht',
      'Turnier "' || coalesce(v_name, '') || '": Runde ' || v_next_round
        || ' ist da.');

    INSERT INTO public.tournament_audit_events(
        tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'swiss_round_paired',
        v_caller,
        jsonb_build_object(
          'stage_node_id', p_stage_node_id,
          'round_number',  v_next_round,
          'match_count',   v_inserted,
          'strategy',      p_strategy
        )
      );

    PERFORM public._tournament_notify_participants(
      p_tournament_id,
      'tournament_round',
      'Neue Runde',
      'Turnier "' || coalesce(v_name, '') || '": Runde ' || v_next_round
        || ' — dein Platz ist da, leg los!',
      jsonb_build_object(
        'tournament_id', p_tournament_id,
        'round_number',  v_next_round));
    RETURN;
  END IF;

  -- ============ FLAT PATH — BYTE-IDENTICAL to 20261283000000 ============
  SELECT max(round_number) INTO v_current_round
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id;

  IF v_current_round IS NOT NULL THEN
    SELECT count(*) INTO v_open_count
      FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND round_number  = v_current_round
        AND status NOT IN ('finalized','overridden','voided');

    IF v_open_count > 0 THEN
      RAISE EXCEPTION
        'round_not_complete: round % still has % open match(es); finalize them before pairing the next round',
        v_current_round, v_open_count
        USING ERRCODE = '22023';
    END IF;
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

  PERFORM public._tournament_assign_pitches(p_tournament_id, v_next_round::smallint);

  -- ADR-0031 A1: materialise the newly paired swiss round (phase 'group').
  PERFORM public._tournament_upsert_round_schedule(
    p_tournament_id, NULL, v_next_round, 'group',
    (public._tournament_schedule_prelim_seconds(p_tournament_id)).match_seconds,
    (public._tournament_schedule_prelim_seconds(p_tournament_id)).break_seconds,
    NULL, now());

  -- ADR-0031 C1 (E1): per-pitch publish-notify of the newly paired round
  -- (v_next_round, phase 'group'). After pitches + schedule exist.
  PERFORM public._tournament_notify_round_per_pitch(
    p_tournament_id, v_next_round, 'group', 'round_published',
    'Runde ' || v_next_round || ' veröffentlicht',
    'Turnier "' || coalesce(v_name, '') || '": Runde ' || v_next_round
      || ' ist da.');

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

  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_round',
    'Neue Runde',
    'Turnier "' || coalesce(v_name, '') || '": Runde ' || v_next_round
      || ' — dein Platz ist da, leg los!',
    jsonb_build_object(
      'tournament_id', p_tournament_id,
      'round_number',  v_next_round));
END;
$function$;

REVOKE ALL ON FUNCTION public.tournament_pair_round(uuid, text, jsonb, text) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_pair_round(uuid, text, jsonb, text) TO authenticated;

COMMENT ON FUNCTION public.tournament_pair_round(uuid, text, jsonb, text) IS
  'Pairs the next swiss round (ADR-0039 §3). With p_stage_node_id NULL the body '
  'is byte-identical to the flat 20261283000000 path. With p_stage_node_id set '
  'it is stage-scoped: the stage must be a live schoch stage, the progression '
  'gate and validate_swiss_pairing count only this stage''s matches, and the '
  'inserted round carries stage_node_id so the runner trigger picks it up when '
  'finalized. GRANTs unchanged (authenticated).';
