-- Tournament feature — M1 discovery & registration RPCs.
--
-- Funnels all read-traffic for the tournament list / detail screens
-- plus the participant-lifecycle writes (FR-REG-1..7, FR-PUB-1..2)
-- through SECURITY DEFINER functions. The underlying tables stay
-- locked down by RLS (see 20260525000001_tournament_schema.sql) — only
-- the narrow self-register / self-withdraw paths are reachable from
-- the client; everything else is gated by the RPCs below.
--
-- Conventions match the existing match-feature RPCs
-- (20260507000004_match_rpcs.sql, 20260507000005_match_followups.sql):
--   - SECURITY DEFINER, SET search_path = public, auth
--   - auth.uid() guard at function top, ERRCODE '42501' on missing
--   - jsonb projection mirrors the Dart wire-model contract in
--     lib/features/tournament/data/tournament_models.dart
--
-- Wire-shape adjustments vs. raw column names:
--   tournaments.match_format         -> match_format_config
--   tournament_matches.participant_a -> participant_a_id
--   tournament_matches.participant_b -> participant_b_id
--   tournament_matches.winner_participant -> winner_participant_id
--   tournament_matches.finalized_at  -> completed_at
--   tournament_audit_events.created_at -> at

-- ---- 1. tournament_list_for_caller -----------------------------------

CREATE OR REPLACE FUNCTION public.tournament_list_for_caller(
  p_status_filter text DEFAULT NULL,
  p_limit         int  DEFAULT 50
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_limit  int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  v_limit := COALESCE(p_limit, 50);
  IF v_limit < 1 OR v_limit > 500 THEN
    RAISE EXCEPTION 'limit out of range' USING ERRCODE = '22023';
  END IF;

  RETURN QUERY
    SELECT jsonb_build_object(
             'tournament_id',     t.id,
             'display_name',      t.display_name,
             'format',            t.format,
             'status',            t.status,
             'started_at',        t.started_at,
             'completed_at',      t.completed_at,
             'participant_count', (
               SELECT count(*)::int FROM public.tournament_participants p
                WHERE p.tournament_id = t.id
                  AND p.registration_status = 'confirmed'
             )
           )
      FROM public.tournaments t
     WHERE (p_status_filter IS NULL OR t.status = p_status_filter)
       AND (t.status <> 'draft' OR t.created_by = v_caller)
     ORDER BY t.started_at DESC NULLS FIRST, t.created_at DESC
     LIMIT v_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_list_for_caller(text, int)
  TO authenticated;


-- ---- 2. tournament_get -----------------------------------------------

CREATE OR REPLACE FUNCTION public.tournament_get(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_status       text;
  v_created_by   uuid;
  v_tournament   jsonb;
  v_participants jsonb;
  v_matches      jsonb;
  v_audit        jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments WHERE id = p_tournament_id;
  IF v_status IS NULL THEN
    RETURN NULL;
  END IF;
  IF v_status = 'draft' AND v_created_by IS DISTINCT FROM v_caller THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
           'tournament_id',        t.id,
           'created_by',           t.created_by,
           'display_name',         t.display_name,
           'team_size',            t.team_size,
           'min_participants',     t.min_participants,
           'max_participants',     t.max_participants,
           'format',               t.format,
           'scoring',              t.scoring,
           'match_format_config',  t.match_format,
           'tiebreaker_order',     t.tiebreaker_order,
           'bye_points',           t.bye_points,
           'forfeit_points',       t.forfeit_points,
           'status',               t.status,
           'registration_opens_at',  t.registration_opens_at,
           'registration_closes_at', t.registration_closes_at,
           'started_at',           t.started_at,
           'completed_at',         t.completed_at,
           'published_at',         t.published_at,
           'created_at',           t.created_at,
           'updated_at',           t.updated_at
         )
    INTO v_tournament
    FROM public.tournaments t WHERE t.id = p_tournament_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'participant_id',      p.id,
           'tournament_id',       p.tournament_id,
           'user_id',             p.user_id,
           'nickname',            up.nickname,
           'registration_status', p.registration_status,
           'seed',                p.seed,
           'registered_at',       p.registered_at,
           'responded_at',        p.responded_at,
           'withdrew_at',         p.withdrew_at
         ) ORDER BY p.registered_at), '[]'::jsonb)
    INTO v_participants
    FROM public.tournament_participants p
    LEFT JOIN public.user_profiles up ON up.user_id = p.user_id
    WHERE p.tournament_id = p_tournament_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'match_id',              m.id,
           'tournament_id',         m.tournament_id,
           'round_number',          m.round_number,
           'match_number_in_round', m.match_number_in_round,
           'participant_a_id',      m.participant_a,
           'participant_b_id',      m.participant_b,
           'status',                m.status,
           'consensus_round',       m.consensus_round,
           'started_at',            m.started_at,
           'completed_at',          m.finalized_at,
           'winner_participant_id', m.winner_participant,
           'final_score_a',         m.final_score_a,
           'final_score_b',         m.final_score_b
         ) ORDER BY m.round_number, m.match_number_in_round), '[]'::jsonb)
    INTO v_matches
    FROM public.tournament_matches m
    WHERE m.tournament_id = p_tournament_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'kind',          e.kind,
           'actor_user_id', e.actor_user_id,
           'payload',       e.payload,
           'at',            e.created_at
         ) ORDER BY e.created_at DESC), '[]'::jsonb)
    INTO v_audit
    FROM (
      SELECT kind, actor_user_id, payload, created_at
        FROM public.tournament_audit_events
       WHERE tournament_id = p_tournament_id
       ORDER BY created_at DESC
       LIMIT 50
    ) e;

  RETURN jsonb_build_object(
    'tournament',   v_tournament,
    'participants', v_participants,
    'matches',      v_matches,
    'audit_tail',   v_audit
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_get(uuid) TO authenticated;


-- ---- 3. tournament_list_matches --------------------------------------

CREATE OR REPLACE FUNCTION public.tournament_list_matches(
  p_tournament_id uuid
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_created_by uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments WHERE id = p_tournament_id;
  IF v_status IS NULL THEN
    RETURN;
  END IF;
  IF v_status = 'draft' AND v_created_by IS DISTINCT FROM v_caller THEN
    RETURN;
  END IF;

  RETURN QUERY
    SELECT jsonb_build_object(
             'match_id',              m.id,
             'tournament_id',         m.tournament_id,
             'round_number',          m.round_number,
             'match_number_in_round', m.match_number_in_round,
             'participant_a_id',      m.participant_a,
             'participant_b_id',      m.participant_b,
             'status',                m.status,
             'consensus_round',       m.consensus_round,
             'started_at',            m.started_at,
             'completed_at',          m.finalized_at,
             'winner_participant_id', m.winner_participant,
             'final_score_a',         m.final_score_a,
             'final_score_b',         m.final_score_b
           )
      FROM public.tournament_matches m
     WHERE m.tournament_id = p_tournament_id
     ORDER BY m.round_number ASC, m.match_number_in_round ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_list_matches(uuid) TO authenticated;


-- ---- 4. tournament_match_get -----------------------------------------

CREATE OR REPLACE FUNCTION public.tournament_match_get(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_tournament   uuid;
  v_status       text;
  v_created_by   uuid;
  v_consensus    smallint;
  v_match        jsonb;
  v_proposals    jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT m.tournament_id, m.consensus_round, t.status, t.created_by
    INTO v_tournament, v_consensus, v_status, v_created_by
    FROM public.tournament_matches m
    JOIN public.tournaments t ON t.id = m.tournament_id
   WHERE m.id = p_match_id;
  IF v_tournament IS NULL THEN
    RETURN NULL;
  END IF;
  IF v_status = 'draft' AND v_created_by IS DISTINCT FROM v_caller THEN
    RETURN NULL;
  END IF;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'proposal_id',            pr.id,
           'set_number',             pr.set_number,
           'submitter_user_id',      pr.submitter_user_id,
           'basekubbs_knocked_by_a', pr.basekubbs_knocked_by_a,
           'basekubbs_knocked_by_b', pr.basekubbs_knocked_by_b,
           'set_winner',             pr.set_winner,
           'proposed_at',            pr.proposed_at
         ) ORDER BY pr.set_number, pr.proposed_at), '[]'::jsonb)
    INTO v_proposals
    FROM public.tournament_set_score_proposals pr
    WHERE pr.match_id = p_match_id
      AND pr.consensus_round = v_consensus;

  SELECT jsonb_build_object(
           'match_id',              m.id,
           'tournament_id',         m.tournament_id,
           'round_number',          m.round_number,
           'match_number_in_round', m.match_number_in_round,
           'participant_a_id',      m.participant_a,
           'participant_b_id',      m.participant_b,
           'status',                m.status,
           'consensus_round',       m.consensus_round,
           'started_at',            m.started_at,
           'completed_at',          m.finalized_at,
           'winner_participant_id', m.winner_participant,
           'final_score_a',         m.final_score_a,
           'final_score_b',         m.final_score_b,
           'set_score_proposals',   v_proposals
         )
    INTO v_match
    FROM public.tournament_matches m
    WHERE m.id = p_match_id;

  RETURN v_match;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_match_get(uuid) TO authenticated;


-- ---- 5. tournament_register_single -----------------------------------

CREATE OR REPLACE FUNCTION public.tournament_register_single(
  p_tournament_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller          uuid;
  v_status          text;
  v_max             smallint;
  v_active_count    int;
  v_new_status      text;
  v_auto_waitlist   boolean;
  v_participant_id  uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Lock the tournament row so the capacity count + insert are
  -- evaluated against a stable snapshot. This serialises concurrent
  -- registrations on the same tournament — the (N+1)-th caller blocks
  -- until the prior INSERT commits, then sees the updated count and
  -- gets routed to the waitlist deterministically.
  SELECT status, max_participants
    INTO v_status, v_max
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status <> 'registration_open' THEN
    RAISE EXCEPTION 'registration is not open' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND user_id = v_caller
       AND registration_status IN ('pending','confirmed','waitlist')
  ) THEN
    RAISE EXCEPTION 'already registered' USING ERRCODE = '23505';
  END IF;

  SELECT count(*)::int INTO v_active_count
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status IN ('pending','confirmed');

  IF v_active_count >= v_max THEN
    v_new_status    := 'waitlist';
    v_auto_waitlist := true;
  ELSE
    v_new_status    := 'pending';
    v_auto_waitlist := false;
  END IF;

  INSERT INTO public.tournament_participants(
      tournament_id, user_id, registration_status)
    VALUES (p_tournament_id, v_caller, v_new_status)
    RETURNING id INTO v_participant_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'registration_received',
      v_caller,
      jsonb_build_object(
        'participant_id', v_participant_id,
        'auto_waitlist',  v_auto_waitlist
      )
    );

  RETURN jsonb_build_object('participant_id', v_participant_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_register_single(uuid)
  TO authenticated;


-- ---- 6. tournament_withdraw ------------------------------------------

CREATE OR REPLACE FUNCTION public.tournament_withdraw(
  p_participant_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_user_id       uuid;
  v_tournament_id uuid;
  v_status        text;
  v_prior         text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT p.user_id, p.tournament_id, p.registration_status
    INTO v_user_id, v_tournament_id, v_prior
    FROM public.tournament_participants p
    WHERE p.id = p_participant_id
    FOR UPDATE;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'participant not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_user_id IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'only the participant can withdraw'
      USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_status
    FROM public.tournaments WHERE id = v_tournament_id;
  IF v_status NOT IN ('registration_open','registration_closed','live') THEN
    RAISE EXCEPTION 'withdrawal not allowed in current tournament state'
      USING ERRCODE = '22023';
  END IF;

  IF v_prior = 'withdrawn' THEN
    RAISE EXCEPTION 'already withdrawn' USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournament_participants
    SET registration_status = 'withdrawn',
        withdrew_at         = now()
    WHERE id = p_participant_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'withdrawn',
      v_caller,
      jsonb_build_object(
        'participant_id', p_participant_id,
        'prior_status',   v_prior
      )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_withdraw(uuid) TO authenticated;


-- ---- 7. tournament_confirm_registration ------------------------------

CREATE OR REPLACE FUNCTION public.tournament_confirm_registration(
  p_participant_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_tournament_id uuid;
  v_prior         text;
  v_creator       uuid;
  v_status        text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT p.tournament_id, p.registration_status
    INTO v_tournament_id, v_prior
    FROM public.tournament_participants p
    WHERE p.id = p_participant_id
    FOR UPDATE;
  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'participant not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT created_by, status INTO v_creator, v_status
    FROM public.tournaments WHERE id = v_tournament_id;
  IF v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'only the creator can confirm registrations'
      USING ERRCODE = '42501';
  END IF;
  IF v_status NOT IN ('registration_open','registration_closed') THEN
    RAISE EXCEPTION 'confirmation not allowed in current tournament state'
      USING ERRCODE = '22023';
  END IF;
  IF v_prior NOT IN ('pending','waitlist') THEN
    RAISE EXCEPTION 'participant is not in pending or waitlist state'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournament_participants
    SET registration_status = 'confirmed',
        responded_at        = now()
    WHERE id = p_participant_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'registration_confirmed',
      v_caller,
      jsonb_build_object(
        'participant_id', p_participant_id,
        'prior_status',   v_prior
      )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_confirm_registration(uuid)
  TO authenticated;


-- ---- 8. tournament_reject_registration -------------------------------

CREATE OR REPLACE FUNCTION public.tournament_reject_registration(
  p_participant_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_tournament_id uuid;
  v_prior         text;
  v_creator       uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT p.tournament_id, p.registration_status
    INTO v_tournament_id, v_prior
    FROM public.tournament_participants p
    WHERE p.id = p_participant_id
    FOR UPDATE;
  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'participant not found' USING ERRCODE = 'P0002';
  END IF;

  SELECT created_by INTO v_creator
    FROM public.tournaments WHERE id = v_tournament_id;
  IF v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'only the creator can reject registrations'
      USING ERRCODE = '42501';
  END IF;
  IF v_prior NOT IN ('pending','waitlist') THEN
    RAISE EXCEPTION 'participant is not in pending or waitlist state'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournament_participants
    SET registration_status = 'rejected',
        responded_at        = now()
    WHERE id = p_participant_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'registration_rejected',
      v_caller,
      jsonb_build_object(
        'participant_id', p_participant_id,
        'prior_status',   v_prior
      )
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_reject_registration(uuid)
  TO authenticated;
