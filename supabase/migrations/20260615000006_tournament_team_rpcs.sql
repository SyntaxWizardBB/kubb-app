-- M3.2-T6: Tournament-Team-RPCs.
--
-- Three SECURITY DEFINER RPCs to register a team participant with an
-- initial roster, replace individual roster slots mid-tournament, and
-- read the current/historical roster of a participant.
--
-- Errcodes per OD-M3-07 (see docs/adr/0020-roster-substitution-rules.md):
--   - MIN_ONE_REGISTERED          (FR-REG-12)
--   - ROSTER_LOCKED_DURING_MATCH  (OD-M3-07, awaiting_results match)
--   - ROSTER_LOCKED               (FR-TEAM-15, tournament finalized)
--   - 42501                       authentication / authorization
--   - BR_5_VIOLATION              raised by trigger from migration T1
--
-- Conventions match the M2 tournament RPCs:
--   - LANGUAGE plpgsql, SECURITY DEFINER, SET search_path = public, auth
--   - auth.uid() guard at function top
--   - audit-events into tournament_audit_events
--
-- Spec: docs/plans/m3-teams-pools-roster/tasks.md TASK-M3.2-T6.


-- ---- 1. tournament_register_team -------------------------------------

CREATE OR REPLACE FUNCTION public.tournament_register_team(
  p_tournament_id uuid,
  p_team_id       uuid,
  p_roster_json   jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller         uuid;
  v_team_size      smallint;
  v_status         text;
  v_slot_count     int;
  v_member_count   int;
  v_participant_id uuid;
  v_slot           jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Caller must be an active pool member of the team (FR-REG-2, BR-29).
  IF NOT EXISTS (
    SELECT 1 FROM public.team_memberships
     WHERE team_id = p_team_id
       AND user_id = v_caller
       AND removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'caller is not an active member of team %', p_team_id
      USING ERRCODE = '42501';
  END IF;

  SELECT status, team_size INTO v_status, v_team_size
    FROM public.tournaments WHERE id = p_tournament_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status <> 'registration_open' THEN
    RAISE EXCEPTION 'registration is not open' USING ERRCODE = '22023';
  END IF;

  v_slot_count := jsonb_array_length(p_roster_json);
  IF v_slot_count <> v_team_size THEN
    RAISE EXCEPTION 'roster slot count % does not match tournament team_size %',
      v_slot_count, v_team_size USING ERRCODE = '22023';
  END IF;

  -- FR-REG-12: at least one slot must be a registered member.
  SELECT count(*) INTO v_member_count
    FROM jsonb_array_elements(p_roster_json) AS e
    WHERE (e->>'member_user_id') IS NOT NULL;
  IF v_member_count < 1 THEN
    RAISE EXCEPTION 'roster must contain at least one registered member'
      USING ERRCODE = '22023', HINT = 'MIN_ONE_REGISTERED';
  END IF;

  INSERT INTO public.tournament_participants(
      tournament_id, team_id, user_id, registration_status)
    VALUES (p_tournament_id, p_team_id, v_caller, 'pending')
    RETURNING id INTO v_participant_id;

  -- Insert one row per slot. BR-5 / pool-membership / xor-check fire
  -- via constraints + the t1 trigger.
  FOR v_slot IN SELECT * FROM jsonb_array_elements(p_roster_json) LOOP
    -- Pool-membership of the occupant.
    IF (v_slot->>'member_user_id') IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.team_memberships
         WHERE team_id = p_team_id
           AND user_id = (v_slot->>'member_user_id')::uuid
           AND removed_at IS NULL
      ) THEN
        RAISE EXCEPTION 'slot member % is not in team pool',
          v_slot->>'member_user_id' USING ERRCODE = '22023';
      END IF;
    ELSIF (v_slot->>'guest_player_id') IS NOT NULL THEN
      IF NOT EXISTS (
        SELECT 1 FROM public.team_guest_players
         WHERE id = (v_slot->>'guest_player_id')::uuid
           AND team_id = p_team_id
           AND removed_at IS NULL
      ) THEN
        RAISE EXCEPTION 'slot guest % is not in team pool',
          v_slot->>'guest_player_id' USING ERRCODE = '22023';
      END IF;
    END IF;

    INSERT INTO public.tournament_roster_slots(
        participant_id, slot_index, member_user_id, guest_player_id,
        assigned_by)
      VALUES (
        v_participant_id,
        (v_slot->>'slot_index')::smallint,
        NULLIF(v_slot->>'member_user_id','')::uuid,
        NULLIF(v_slot->>'guest_player_id','')::uuid,
        v_caller);
  END LOOP;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'team_registered',
      v_caller,
      jsonb_build_object(
        'participant_id', v_participant_id,
        'team_id',        p_team_id,
        'roster',         p_roster_json
      ));

  RETURN jsonb_build_object('participant_id', v_participant_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_register_team(uuid, uuid, jsonb)
  TO authenticated;


-- ---- 2. tournament_roster_replace ------------------------------------

CREATE OR REPLACE FUNCTION public.tournament_roster_replace(
  p_participant_id        uuid,
  p_slot_index            smallint,
  p_new_member_user_id    uuid,
  p_new_guest_player_id   uuid,
  p_reason                text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller         uuid;
  v_team_id        uuid;
  v_tournament_id  uuid;
  v_locked_at      timestamptz;
  v_t_status       text;
  v_old_slot_id    uuid;
  v_old_member     uuid;
  v_old_guest      uuid;
  v_new_slot_id    uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF (p_new_member_user_id IS NULL) = (p_new_guest_player_id IS NULL) THEN
    RAISE EXCEPTION 'exactly one of member or guest must be provided'
      USING ERRCODE = '22023';
  END IF;

  SELECT tp.team_id, tp.tournament_id, tp.roster_locked_at
    INTO v_team_id, v_tournament_id, v_locked_at
    FROM public.tournament_participants tp
    WHERE tp.id = p_participant_id
    FOR UPDATE;
  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'participant not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_team_id IS NULL THEN
    RAISE EXCEPTION 'participant is not a team participant'
      USING ERRCODE = '22023';
  END IF;

  -- Caller must be an active pool member of the participant's team.
  IF NOT EXISTS (
    SELECT 1 FROM public.team_memberships
     WHERE team_id = v_team_id
       AND user_id = v_caller
       AND removed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'caller is not an active member of team %', v_team_id
      USING ERRCODE = '42501';
  END IF;

  -- FR-TEAM-15: roster locks once tournament is finalized.
  SELECT status INTO v_t_status
    FROM public.tournaments WHERE id = v_tournament_id;
  IF v_t_status = 'finalized' OR v_locked_at IS NOT NULL THEN
    RAISE EXCEPTION 'roster is locked' USING ERRCODE = '22023',
      HINT = 'ROSTER_LOCKED';
  END IF;

  -- OD-M3-07: substitution forbidden while a match is awaiting results.
  IF EXISTS (
    SELECT 1 FROM public.tournament_matches m
     WHERE (m.participant_a = p_participant_id
            OR m.participant_b = p_participant_id)
       AND m.status = 'awaiting_results'
  ) THEN
    RAISE EXCEPTION 'roster locked while match is awaiting results'
      USING ERRCODE = '22023', HINT = 'ROSTER_LOCKED_DURING_MATCH';
  END IF;

  -- Pool-membership of the replacement occupant.
  IF p_new_member_user_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.team_memberships
       WHERE team_id = v_team_id
         AND user_id = p_new_member_user_id
         AND removed_at IS NULL
    ) THEN
      RAISE EXCEPTION 'replacement member % is not in team pool',
        p_new_member_user_id USING ERRCODE = '22023';
    END IF;
  ELSE
    IF NOT EXISTS (
      SELECT 1 FROM public.team_guest_players
       WHERE id = p_new_guest_player_id
         AND team_id = v_team_id
         AND removed_at IS NULL
    ) THEN
      RAISE EXCEPTION 'replacement guest % is not in team pool',
        p_new_guest_player_id USING ERRCODE = '22023';
    END IF;
  END IF;

  SELECT id, member_user_id, guest_player_id
    INTO v_old_slot_id, v_old_member, v_old_guest
    FROM public.tournament_roster_slots
    WHERE participant_id = p_participant_id
      AND slot_index = p_slot_index
      AND replaced_at IS NULL
    FOR UPDATE;
  IF v_old_slot_id IS NULL THEN
    RAISE EXCEPTION 'no open slot % for participant', p_slot_index
      USING ERRCODE = 'P0002';
  END IF;

  -- Close the old slot first so the partial-unique-index frees up.
  UPDATE public.tournament_roster_slots
     SET replaced_at = now(),
         replaced_by = v_caller,
         reason      = p_reason
   WHERE id = v_old_slot_id;

  INSERT INTO public.tournament_roster_slots(
      participant_id, slot_index, member_user_id, guest_player_id,
      assigned_by)
    VALUES (
      p_participant_id, p_slot_index,
      p_new_member_user_id, p_new_guest_player_id, v_caller)
    RETURNING id INTO v_new_slot_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'roster_slot_replaced',
      v_caller,
      jsonb_build_object(
        'participant_id', p_participant_id,
        'slot_index',     p_slot_index,
        'old',            jsonb_build_object(
                            'member_user_id',  v_old_member,
                            'guest_player_id', v_old_guest),
        'new',            jsonb_build_object(
                            'member_user_id',  p_new_member_user_id,
                            'guest_player_id', p_new_guest_player_id),
        'reason',         p_reason
      ));

  RETURN jsonb_build_object(
    'old_slot_id', v_old_slot_id,
    'new_slot_id', v_new_slot_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_roster_replace(
  uuid, smallint, uuid, uuid, text) TO authenticated;


-- ---- 3. tournament_roster_list ---------------------------------------
--
-- Returns the full slot history of a participant (open + closed). The
-- caller must be authenticated; the participant's tournament must be
-- visible to the caller (non-draft, or owned draft).

CREATE OR REPLACE FUNCTION public.tournament_roster_list(
  p_tournament_id  uuid,
  p_participant_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_t_status   text;
  v_t_creator  uuid;
  v_p_tid      uuid;
  v_slots      jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_t_status, v_t_creator
    FROM public.tournaments WHERE id = p_tournament_id;
  IF v_t_status IS NULL THEN
    RETURN NULL;
  END IF;
  IF v_t_status = 'draft' AND v_t_creator IS DISTINCT FROM v_caller THEN
    RETURN NULL;
  END IF;

  SELECT tournament_id INTO v_p_tid
    FROM public.tournament_participants WHERE id = p_participant_id;
  IF v_p_tid IS NULL OR v_p_tid <> p_tournament_id THEN
    RETURN NULL;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'slot_id',         s.id,
           'participant_id',  s.participant_id,
           'slot_index',      s.slot_index,
           'member_user_id',  s.member_user_id,
           'guest_player_id', s.guest_player_id,
           'assigned_at',     s.assigned_at,
           'assigned_by',     s.assigned_by,
           'replaced_at',     s.replaced_at,
           'replaced_by',     s.replaced_by,
           'reason',          s.reason
         ) ORDER BY s.slot_index, s.assigned_at), '[]'::jsonb)
    INTO v_slots
    FROM public.tournament_roster_slots s
    WHERE s.participant_id = p_participant_id;

  RETURN jsonb_build_object('slots', v_slots);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_roster_list(uuid, uuid)
  TO authenticated;
