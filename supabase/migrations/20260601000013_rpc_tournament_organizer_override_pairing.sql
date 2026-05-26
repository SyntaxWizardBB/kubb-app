-- Tournament feature — M2 organizer KO-pairing override.
--
-- SECURITY DEFINER RPC `tournament_organizer_override_pairing` erlaubt
-- es dem Veranstalter (`tournaments.created_by = auth.uid()`), die
-- Teilnehmer eines noch nicht gestarteten Match-Slots zu ändern. Pflicht-
-- Begründung wird ins Audit-Event geschrieben.
--
-- Bezug: docs/adr/0017-ko-phase-semantics.md §6,
--        docs/plans/m2-ko-bracket/tasks.md TASK-M2.2-T2b,
--        FR-PAIR-7.
--
-- Fehler-Mapping (Token im MESSAGE-String, SQLSTATE im ERRCODE — Client
-- liest beides):
--   MISSING_REASON          — ERRCODE 22023 (HTTP 400 äquivalent)
--   MATCH_NOT_FOUND         — ERRCODE P0002 (HTTP 404 äquivalent)
--   NOT_ORGANIZER           — ERRCODE 42501 (HTTP 403)
--   MATCH_ALREADY_STARTED   — ERRCODE 22023 (HTTP 422)
--   INVALID_PARTICIPANT     — ERRCODE 22023 (HTTP 422)
--   PARTICIPANT_CONFLICT    — ERRCODE 22023 (HTTP 422)
--
-- Audit-Payload schreibt alte und neue participant_a/b plus reason,
-- damit Rollback und Forensik möglich sind (ADR-0017 §6).

CREATE OR REPLACE FUNCTION public.tournament_organizer_override_pairing(
  p_match_id        uuid,
  p_participant_a   uuid,
  p_participant_b   uuid,
  p_reason          text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller         uuid;
  v_tournament_id  uuid;
  v_creator        uuid;
  v_status         text;
  v_round          smallint;
  v_old_part_a     uuid;
  v_old_part_b     uuid;
  v_conflict_count int;
  v_valid_count    int;
BEGIN
  -- 1. Authentication.
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- 2. Pflicht-Begründung (MISSING_REASON).
  IF p_reason IS NULL OR length(btrim(p_reason)) < 1
     OR length(p_reason) > 500 THEN
    RAISE EXCEPTION 'MISSING_REASON: override reason must be 1..500 chars'
      USING ERRCODE = '22023';
  END IF;

  -- 3. Match-Row sperren und Stamm-Daten lesen.
  SELECT m.tournament_id, m.status, m.round_number,
         m.participant_a, m.participant_b
    INTO v_tournament_id, v_status, v_round, v_old_part_a, v_old_part_b
    FROM public.tournament_matches m
    WHERE m.id = p_match_id
    FOR UPDATE;

  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'MATCH_NOT_FOUND: match % does not exist', p_match_id
      USING ERRCODE = 'P0002';
  END IF;

  -- 4. Defense-in-Depth: nur Veranstalter (RLS deckt das via
  --    `tournaments.created_by = auth.uid()` ab, hier doppelt geprüft
  --    weil SECURITY DEFINER an der RLS vorbei läuft).
  SELECT created_by INTO v_creator
    FROM public.tournaments WHERE id = v_tournament_id;
  IF v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: only the tournament creator may override pairings'
      USING ERRCODE = '42501';
  END IF;

  -- 5. Match-Status muss `scheduled` sein.
  IF v_status <> 'scheduled' THEN
    RAISE EXCEPTION 'MATCH_ALREADY_STARTED: match status is %, expected scheduled', v_status
      USING ERRCODE = '22023';
  END IF;

  -- 6. Neue Teilnehmer-IDs validieren.
  IF p_participant_a IS NULL OR p_participant_b IS NULL THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: both participants must be non-null'
      USING ERRCODE = '22023';
  END IF;
  IF p_participant_a = p_participant_b THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: participants must be distinct'
      USING ERRCODE = '22023';
  END IF;

  -- Beide müssen Teilnehmer dieses Turniers sein.
  SELECT count(*) INTO v_valid_count
    FROM public.tournament_participants p
    WHERE p.tournament_id = v_tournament_id
      AND p.id IN (p_participant_a, p_participant_b);
  IF v_valid_count <> 2 THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: participants are not registered in tournament %', v_tournament_id
      USING ERRCODE = '22023';
  END IF;

  -- 7. Konflikt: einer der neuen Teilnehmer ist bereits in einem
  --    *anderen* Match derselben Runde gepaart.
  SELECT count(*) INTO v_conflict_count
    FROM public.tournament_matches m
    WHERE m.tournament_id = v_tournament_id
      AND m.round_number  = v_round
      AND m.id <> p_match_id
      AND (m.participant_a IN (p_participant_a, p_participant_b)
        OR m.participant_b IN (p_participant_a, p_participant_b));
  IF v_conflict_count > 0 THEN
    RAISE EXCEPTION 'PARTICIPANT_CONFLICT: participant already paired in round %', v_round
      USING ERRCODE = '22023';
  END IF;

  -- 8. Update + Audit.
  UPDATE public.tournament_matches
    SET participant_a = p_participant_a,
        participant_b = p_participant_b
    WHERE id = p_match_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, match_id, kind, actor_user_id, payload)
    VALUES (v_tournament_id, p_match_id, 'pairing_overridden', v_caller,
            jsonb_build_object(
              'reason',              p_reason,
              'round_number',        v_round,
              'old_participant_a',   v_old_part_a,
              'old_participant_b',   v_old_part_b,
              'new_participant_a',   p_participant_a,
              'new_participant_b',   p_participant_b));
END;
$$;

REVOKE EXECUTE ON FUNCTION
  public.tournament_organizer_override_pairing(uuid, uuid, uuid, text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION
  public.tournament_organizer_override_pairing(uuid, uuid, uuid, text)
  TO authenticated;
