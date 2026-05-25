-- Tournament feature — M1 lifecycle RPCs.
--
-- Seven SECURITY DEFINER RPCs that drive the tournament header
-- through its status machine:
--
--   draft -> published -> registration_open -> registration_closed
--         -> live -> finalized
--
-- Plus tournament_abort as a terminal escape hatch from any pre-
-- terminal state. tournament_start materialises the round-robin
-- schedule into public.tournament_matches using the standard circle-
-- rotation algorithm (the slot-0 anchor variant, matching the Dart
-- reference in packages/kubb_domain/lib/src/tournament/pool.dart).
--
-- Every mutation writes a row to public.tournament_audit_events. All
-- callers must be the tournament creator (RLS plus an explicit check
-- inside each RPC for defence in depth).


-- ---- 1. tournament_create --------------------------------------------

CREATE OR REPLACE FUNCTION public.tournament_create(
  p_display_name        text,
  p_team_size           int,
  p_min_participants    int,
  p_max_participants    int,
  p_format              text,
  p_match_format_config jsonb,
  p_tiebreaker_order    text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_tournament_id uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF p_display_name IS NULL OR length(p_display_name) < 1 OR length(p_display_name) > 60 THEN
    RAISE EXCEPTION 'display_name length must be 1..60' USING ERRCODE = '22023';
  END IF;
  IF p_team_size IS NULL OR p_team_size < 1 OR p_team_size > 6 THEN
    RAISE EXCEPTION 'team_size must be 1..6' USING ERRCODE = '22023';
  END IF;
  IF p_min_participants IS NULL OR p_min_participants < 2 THEN
    RAISE EXCEPTION 'min_participants must be >= 2' USING ERRCODE = '22023';
  END IF;
  IF p_max_participants IS NULL
     OR p_max_participants < p_min_participants
     OR p_max_participants > 200 THEN
    RAISE EXCEPTION 'max_participants must be in [min_participants, 200]'
      USING ERRCODE = '22023';
  END IF;
  IF p_format IS NULL OR p_format NOT IN (
       'round_robin','single_elimination','round_robin_then_ko',
       'schoch','swiss','schoch_then_ko','swiss_then_ko') THEN
    RAISE EXCEPTION 'invalid format' USING ERRCODE = '22023';
  END IF;
  IF p_match_format_config IS NULL OR jsonb_typeof(p_match_format_config) <> 'object' THEN
    RAISE EXCEPTION 'match_format_config must be a JSON object' USING ERRCODE = '22023';
  END IF;
  IF p_tiebreaker_order IS NULL OR array_length(p_tiebreaker_order, 1) IS NULL THEN
    RAISE EXCEPTION 'tiebreaker_order must be a non-empty array' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.tournaments(
      created_by, display_name, team_size, min_participants, max_participants,
      format, scoring, match_format, tiebreaker_order, status)
    VALUES (
      v_caller, p_display_name, p_team_size::smallint,
      p_min_participants::smallint, p_max_participants::smallint,
      p_format, 'ekc', p_match_format_config, p_tiebreaker_order, 'draft')
    RETURNING id INTO v_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'created',
      v_caller,
      jsonb_build_object(
        'display_name',     p_display_name,
        'team_size',        p_team_size,
        'min_participants', p_min_participants,
        'max_participants', p_max_participants,
        'format',           p_format
      )
    );

  RETURN jsonb_build_object('tournament_id', v_tournament_id);
END;
$$;


-- ---- 2. tournament_publish -------------------------------------------

CREATE OR REPLACE FUNCTION public.tournament_publish(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_status text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_status
    FROM public.tournaments
    WHERE id = p_tournament_id AND created_by = v_caller
    FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'tournament must be in status draft' USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status = 'published', published_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'published', v_caller, '{}'::jsonb);
END;
$$;


-- ---- 3. tournament_open_registration ---------------------------------

CREATE OR REPLACE FUNCTION public.tournament_open_registration(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_status       text;
  v_existing_opens timestamptz;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, registration_opens_at
    INTO v_status, v_existing_opens
    FROM public.tournaments
    WHERE id = p_tournament_id AND created_by = v_caller
    FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status NOT IN ('published', 'registration_closed') THEN
    RAISE EXCEPTION 'tournament must be in status published or registration_closed'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status                = 'registration_open',
        registration_opens_at = coalesce(v_existing_opens, now())
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'registration_opened', v_caller, '{}'::jsonb);
END;
$$;


-- ---- 4. tournament_close_registration --------------------------------

CREATE OR REPLACE FUNCTION public.tournament_close_registration(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_status text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_status
    FROM public.tournaments
    WHERE id = p_tournament_id AND created_by = v_caller
    FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'registration_open' THEN
    RAISE EXCEPTION 'tournament must be in status registration_open'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status                 = 'registration_closed',
        registration_closes_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'registration_closed', v_caller, '{}'::jsonb);
END;
$$;


-- ---- 5. tournament_start ---------------------------------------------

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

  SELECT status, format INTO v_status, v_format
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
  IF v_format <> 'round_robin' THEN
    RAISE EXCEPTION 'format not yet supported' USING ERRCODE = '0A000';
  END IF;

  SELECT count(*) INTO v_confirmed
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status = 'confirmed';

  IF v_confirmed < 2 THEN
    RAISE EXCEPTION 'at least 2 confirmed participants required'
      USING ERRCODE = '22023';
  END IF;

  -- Materialise confirmed participants into a temp slot table, indexed
  -- 1..v_confirmed in registered_at order. seed = slot index (M1 has no
  -- pre-seeding; seed is purely the registration order).
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

  -- Pad to an even number of slots with a virtual NULL bye slot.
  IF (v_confirmed % 2) = 1 THEN
    v_slot_count := v_confirmed + 1;
    INSERT INTO _tstart_slots(slot_idx, participant_id) VALUES (v_slot_count, NULL);
  ELSE
    v_slot_count := v_confirmed;
  END IF;

  v_round_count := v_slot_count - 1;

  -- Working ring used by the rotation. The slot at position 1 stays
  -- fixed; positions 2..v_slot_count rotate clockwise after each round.
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

      -- Normalise so participant_a is always the real participant; bye
      -- matches store NULL in participant_b. Skip the pairing entirely
      -- if both slots are NULL (cannot happen since we pad at most one).
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

    -- Rotate: keep pos 1 fixed, move last into pos 2, shift the rest
    -- down by one. Implemented by re-numbering positions in-place.
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
        'round_count', v_round_count,
        'match_count', v_match_count
      )
    );
END;
$$;


-- ---- 6. tournament_finalize ------------------------------------------

CREATE OR REPLACE FUNCTION public.tournament_finalize(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_status       text;
  v_total        int;
  v_terminal     int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_status
    FROM public.tournaments
    WHERE id = p_tournament_id AND created_by = v_caller
    FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'live' THEN
    RAISE EXCEPTION 'tournament must be in status live' USING ERRCODE = '22023';
  END IF;

  SELECT count(*) INTO v_total
    FROM public.tournament_matches WHERE tournament_id = p_tournament_id;

  SELECT count(*) INTO v_terminal
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND status IN ('finalized', 'overridden', 'voided');

  IF v_total = 0 THEN
    RAISE EXCEPTION 'tournament has no matches to finalize' USING ERRCODE = '22023';
  END IF;
  IF v_terminal < v_total THEN
    RAISE EXCEPTION 'cannot finalize: % of % matches are not yet terminal',
      v_total - v_terminal, v_total USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status = 'finalized', completed_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'finalized',
      v_caller,
      jsonb_build_object('match_count', v_total)
    );
END;
$$;


-- ---- 7. tournament_abort ---------------------------------------------

CREATE OR REPLACE FUNCTION public.tournament_abort(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_status text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_status
    FROM public.tournaments
    WHERE id = p_tournament_id AND created_by = v_caller
    FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status NOT IN (
       'draft','published','registration_open','registration_closed','live') THEN
    RAISE EXCEPTION 'tournament cannot be aborted in its current state'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status = 'aborted', completed_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'aborted', v_caller, '{}'::jsonb);
END;
$$;


-- ---- 8. Grants -------------------------------------------------------

GRANT EXECUTE ON FUNCTION public.tournament_create(
  text, int, int, int, text, jsonb, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tournament_publish(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tournament_open_registration(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tournament_close_registration(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tournament_start(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tournament_finalize(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tournament_abort(uuid) TO authenticated;
