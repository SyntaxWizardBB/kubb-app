-- Kubb Match feature — Phase 1 RPCs.
--
-- All match mutations are funnelled through these SECURITY DEFINER
-- functions so RLS on the underlying tables can stay restrictive
-- (SELECT-only). The internal `_match_try_reconcile` helper is the
-- single place that decides whether a round is finalized, bumped, or
-- voided after a proposal arrives.

-- ---- 1. Internal helper ----------------------------------------------

CREATE OR REPLACE FUNCTION public._match_try_reconcile(p_match_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_status        text;
  v_current_round smallint;
  v_required      int;
  v_voted         int;
  v_distinct      int;
  v_winner        text;
  v_score_a       int;
  v_score_b       int;
  v_participant   record;
BEGIN
  SELECT status, current_round
    INTO v_status, v_current_round
    FROM public.matches
    WHERE id = p_match_id
    FOR UPDATE;

  IF v_status IS NULL OR v_status <> 'awaiting_results' THEN
    RETURN;
  END IF;

  SELECT count(*) INTO v_required
    FROM public.match_participants
    WHERE match_id = p_match_id
      AND kind = 'in_app'
      AND invitation_status = 'accepted';

  SELECT count(*) INTO v_voted
    FROM public.match_result_proposals
    WHERE match_id = p_match_id
      AND round = v_current_round;

  IF v_voted < v_required THEN
    RETURN;
  END IF;

  -- Distinct count using IS NOT DISTINCT FROM semantics: NULL winner
  -- with identical scores still counts as the same tuple.
  SELECT count(*) INTO v_distinct
    FROM (
      SELECT DISTINCT winner_team_id, score_a, score_b
        FROM public.match_result_proposals
        WHERE match_id = p_match_id
          AND round = v_current_round
    ) t;

  IF v_distinct = 1 THEN
    SELECT winner_team_id, score_a, score_b
      INTO v_winner, v_score_a, v_score_b
      FROM public.match_result_proposals
      WHERE match_id = p_match_id
        AND round = v_current_round
      LIMIT 1;

    UPDATE public.matches
      SET status         = 'finalized',
          winner_team_id = v_winner,
          final_score_a  = v_score_a,
          final_score_b  = v_score_b,
          completed_at   = now()
      WHERE id = p_match_id;

    INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
      VALUES (
        p_match_id,
        'finalized',
        NULL,
        jsonb_build_object(
          'winner_team_id', v_winner,
          'score_a', v_score_a,
          'score_b', v_score_b,
          'round', v_current_round
        )
      );

    FOR v_participant IN
      SELECT user_id FROM public.match_participants
      WHERE match_id = p_match_id
        AND kind = 'in_app'
        AND invitation_status = 'accepted'
        AND user_id IS NOT NULL
    LOOP
      INSERT INTO public.user_inbox_messages(
          user_id, kind, subject, body, action_payload)
        VALUES (
          v_participant.user_id,
          'notice',
          'Match abgeschlossen',
          'Das Match wurde abgeschlossen.',
          jsonb_build_object(
            'kind', 'match_finalized',
            'match_id', p_match_id
          )
        );
    END LOOP;

    RETURN;
  END IF;

  -- Disagreement branch.
  IF v_current_round < 3 THEN
    UPDATE public.matches
      SET current_round = v_current_round + 1
      WHERE id = p_match_id;

    INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
      VALUES (
        p_match_id,
        'round_bumped',
        NULL,
        jsonb_build_object('from', v_current_round, 'to', v_current_round + 1)
      );

    FOR v_participant IN
      SELECT user_id FROM public.match_participants
      WHERE match_id = p_match_id
        AND kind = 'in_app'
        AND invitation_status = 'accepted'
        AND user_id IS NOT NULL
    LOOP
      INSERT INTO public.user_inbox_messages(
          user_id, kind, subject, body, action_payload)
        VALUES (
          v_participant.user_id,
          'verification_request',
          'Resultat bestätigen',
          'Resultat neu eintragen — Round ' || (v_current_round + 1) || '/3',
          jsonb_build_object(
            'kind', 'match_round_prompt',
            'match_id', p_match_id,
            'round', v_current_round + 1
          )
        );
    END LOOP;
  ELSE
    UPDATE public.matches
      SET status    = 'voided',
          voided_at = now()
      WHERE id = p_match_id;

    INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
      VALUES (
        p_match_id,
        'voided',
        NULL,
        jsonb_build_object('reason', 'round_3_disagreement')
      );

    FOR v_participant IN
      SELECT user_id FROM public.match_participants
      WHERE match_id = p_match_id
        AND kind = 'in_app'
        AND invitation_status = 'accepted'
        AND user_id IS NOT NULL
    LOOP
      INSERT INTO public.user_inbox_messages(
          user_id, kind, subject, body, action_payload)
        VALUES (
          v_participant.user_id,
          'notice',
          'Match annulliert',
          'Das Match wurde nach drei Runden ohne Einigung annulliert.',
          jsonb_build_object(
            'kind', 'match_voided',
            'match_id', p_match_id,
            'reason', 'round_3_disagreement'
          )
        );
    END LOOP;
  END IF;
END;
$$;

-- Defense-in-depth: even though we never grant EXECUTE on this internal
-- helper, Postgres' default `GRANT EXECUTE ... TO PUBLIC` semantics on
-- functions can leak callability to `authenticated`. REVOKE explicitly so
-- the only legitimate caller is `match_propose_result` (running as
-- SECURITY DEFINER, where auth.role() is irrelevant).
REVOKE EXECUTE ON FUNCTION public._match_try_reconcile(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._match_try_reconcile(uuid) FROM authenticated;


-- ---- 2. match_create -------------------------------------------------

CREATE OR REPLACE FUNCTION public.match_create(
  p_format  text,
  p_scoring text,
  p_team_a  jsonb,
  p_team_b  jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_caller_nick   text;
  v_match_id      uuid;
  v_team          text;
  v_arr           jsonb;
  v_elem          jsonb;
  v_kind          text;
  v_user_id       uuid;
  v_walkin        text;
  v_status        text;
  v_caller_seen   boolean := false;
  v_in_app_total  int := 0;
  v_count_a       int;
  v_count_b       int;
  v_pending_left  int;
  v_pid           uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF p_format NOT IN ('bo1','bo3','bo5') THEN
    RAISE EXCEPTION 'invalid format' USING ERRCODE = '22023';
  END IF;
  IF p_scoring NOT IN ('wins','points') THEN
    RAISE EXCEPTION 'invalid scoring' USING ERRCODE = '22023';
  END IF;
  IF p_team_a IS NULL OR jsonb_typeof(p_team_a) <> 'array' THEN
    RAISE EXCEPTION 'team A must be a JSON array' USING ERRCODE = '22023';
  END IF;
  IF p_team_b IS NULL OR jsonb_typeof(p_team_b) <> 'array' THEN
    RAISE EXCEPTION 'team B must be a JSON array' USING ERRCODE = '22023';
  END IF;

  v_count_a := jsonb_array_length(p_team_a);
  v_count_b := jsonb_array_length(p_team_b);
  IF v_count_a < 1 OR v_count_a > 6 THEN
    RAISE EXCEPTION 'team A size must be 1..6' USING ERRCODE = '22023';
  END IF;
  IF v_count_b < 1 OR v_count_b > 6 THEN
    RAISE EXCEPTION 'team B size must be 1..6' USING ERRCODE = '22023';
  END IF;

  -- Create the match shell first so we can FK participants to it.
  INSERT INTO public.matches(created_by, format, scoring, status)
    VALUES (v_caller, p_format, p_scoring, 'pending_invites')
    RETURNING id INTO v_match_id;

  INSERT INTO public.match_teams(match_id, team_id) VALUES (v_match_id, 'A');
  INSERT INTO public.match_teams(match_id, team_id) VALUES (v_match_id, 'B');

  INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
    VALUES (
      v_match_id,
      'created',
      v_caller,
      jsonb_build_object('format', p_format, 'scoring', p_scoring)
    );

  SELECT nickname::text INTO v_caller_nick
    FROM public.user_profiles WHERE user_id = v_caller;

  -- Iterate both teams; team_id stays in scope via outer loop.
  FOR v_team, v_arr IN
    SELECT * FROM (VALUES ('A', p_team_a), ('B', p_team_b)) AS t(team_id, arr)
  LOOP
    FOR v_elem IN SELECT * FROM jsonb_array_elements(v_arr)
    LOOP
      v_kind := v_elem ->> 'kind';
      IF v_kind = 'in_app' THEN
        v_user_id := nullif(v_elem ->> 'user_id', '')::uuid;
        IF v_user_id IS NULL THEN
          RAISE EXCEPTION 'in_app participant requires user_id' USING ERRCODE = '22023';
        END IF;
        v_in_app_total := v_in_app_total + 1;

        IF v_user_id = v_caller THEN
          v_caller_seen := true;
          v_status := 'accepted';
        ELSE
          -- Server-side enforcement: only accepted friends may be invited.
          IF NOT EXISTS (
            SELECT 1 FROM public.friendships
             WHERE status = 'accepted'
               AND ((low_user_id = v_caller AND high_user_id = v_user_id)
                 OR (low_user_id = v_user_id AND high_user_id = v_caller))
          ) THEN
            RAISE EXCEPTION 'can only invite accepted friends'
              USING ERRCODE = '42501';
          END IF;
          v_status := 'pending';
        END IF;

        INSERT INTO public.match_participants(
            match_id, team_id, kind, user_id, invitation_status, responded_at)
          VALUES (
            v_match_id, v_team, 'in_app', v_user_id, v_status,
            CASE WHEN v_status = 'accepted' THEN now() ELSE NULL END
          )
          RETURNING participant_id INTO v_pid;

        INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
          VALUES (
            v_match_id,
            'participant_invited',
            v_caller,
            jsonb_build_object(
              'participant_id', v_pid,
              'team_id', v_team,
              'kind', 'in_app',
              'user_id', v_user_id,
              'invitation_status', v_status
            )
          );

        IF v_status = 'pending' THEN
          INSERT INTO public.user_inbox_messages(
              user_id, kind, subject, body, action_payload)
            VALUES (
              v_user_id,
              'verification_request',
              'Match-Einladung',
              coalesce(v_caller_nick, 'Ein Spieler') ||
                ' lädt dich zu einem Kubb-Match ein.',
              jsonb_build_object(
                'kind', 'match_invite',
                'match_id', v_match_id,
                'invited_by_user_id', v_caller,
                'format', p_format,
                'scoring', p_scoring
              )
            );
        END IF;

      ELSIF v_kind = 'walk_in' THEN
        v_walkin := v_elem ->> 'display_name';
        IF v_walkin IS NULL OR length(v_walkin) < 1 OR length(v_walkin) > 40 THEN
          RAISE EXCEPTION 'walk_in display_name length must be 1..40'
            USING ERRCODE = '22023';
        END IF;

        INSERT INTO public.match_participants(
            match_id, team_id, kind, walkin_name, invitation_status, responded_at)
          VALUES (
            v_match_id, v_team, 'walk_in', v_walkin, 'accepted', now()
          )
          RETURNING participant_id INTO v_pid;

        INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
          VALUES (
            v_match_id,
            'participant_invited',
            v_caller,
            jsonb_build_object(
              'participant_id', v_pid,
              'team_id', v_team,
              'kind', 'walk_in',
              'walkin_name', v_walkin,
              'invitation_status', 'accepted'
            )
          );
      ELSE
        RAISE EXCEPTION 'invalid participant kind' USING ERRCODE = '22023';
      END IF;
    END LOOP;
  END LOOP;

  IF NOT v_caller_seen THEN
    RAISE EXCEPTION 'caller must be an in_app participant on one team'
      USING ERRCODE = '22023';
  END IF;
  IF v_in_app_total < 1 THEN
    RAISE EXCEPTION 'at least one in_app participant required'
      USING ERRCODE = '22023';
  END IF;

  -- If the only in_app participant was the caller (auto-accepted), skip
  -- the pending phase and go straight to active.
  SELECT count(*) INTO v_pending_left
    FROM public.match_participants
    WHERE match_id = v_match_id
      AND kind = 'in_app'
      AND invitation_status = 'pending';

  IF v_pending_left = 0 THEN
    UPDATE public.matches SET status = 'active' WHERE id = v_match_id;
    INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
      VALUES (v_match_id, 'started', v_caller, '{}'::jsonb);
  END IF;

  RETURN jsonb_build_object('match_id', v_match_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_create TO authenticated;


-- ---- 3. match_invite_response ----------------------------------------

CREATE OR REPLACE FUNCTION public.match_invite_response(
  p_match_id uuid,
  p_accept   boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_new_status    text;
  v_updated       int;
  v_pending_left  int;
  v_accepted_in   int;
  v_match_status  text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  v_new_status := CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END;

  UPDATE public.match_participants
    SET invitation_status = v_new_status,
        responded_at      = now()
    WHERE match_id = p_match_id
      AND user_id  = v_caller
      AND kind     = 'in_app'
      AND invitation_status = 'pending';
  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RAISE EXCEPTION 'no pending invitation for caller on this match'
      USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
    VALUES (
      p_match_id,
      CASE WHEN p_accept THEN 'participant_accepted' ELSE 'participant_declined' END,
      v_caller,
      '{}'::jsonb
    );

  SELECT count(*) INTO v_pending_left
    FROM public.match_participants
    WHERE match_id = p_match_id
      AND kind = 'in_app'
      AND invitation_status = 'pending';

  SELECT count(*) INTO v_accepted_in
    FROM public.match_participants
    WHERE match_id = p_match_id
      AND kind = 'in_app'
      AND invitation_status = 'accepted';

  SELECT status INTO v_match_status FROM public.matches WHERE id = p_match_id;

  IF v_match_status = 'pending_invites' AND v_pending_left = 0 THEN
    IF v_accepted_in >= 1 THEN
      UPDATE public.matches SET status = 'active' WHERE id = p_match_id;
      INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
        VALUES (p_match_id, 'started', NULL, '{}'::jsonb);
      v_match_status := 'active';
    ELSE
      UPDATE public.matches
        SET status = 'voided', voided_at = now()
        WHERE id = p_match_id;
      INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
        VALUES (
          p_match_id,
          'voided',
          NULL,
          jsonb_build_object('reason', 'no_proposers')
        );
      v_match_status := 'voided';
    END IF;
  END IF;

  RETURN jsonb_build_object('status', v_match_status);
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_invite_response TO authenticated;


-- ---- 4. match_finish_play --------------------------------------------

CREATE OR REPLACE FUNCTION public.match_finish_play(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_status       text;
  v_participant  record;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_status FROM public.matches
    WHERE id = p_match_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'match not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status <> 'active' THEN
    RAISE EXCEPTION 'match is not active' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.match_participants
    WHERE match_id = p_match_id
      AND user_id  = v_caller
      AND kind     = 'in_app'
      AND invitation_status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'caller is not an accepted in_app participant'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.matches
    SET status = 'awaiting_results', current_round = 1
    WHERE id = p_match_id;

  INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
    VALUES (
      p_match_id,
      'awaiting_results_started',
      v_caller,
      jsonb_build_object('round', 1)
    );

  FOR v_participant IN
    SELECT user_id FROM public.match_participants
    WHERE match_id = p_match_id
      AND kind = 'in_app'
      AND invitation_status = 'accepted'
      AND user_id IS NOT NULL
  LOOP
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
      VALUES (
        v_participant.user_id,
        'verification_request',
        'Resultat eintragen',
        'Bitte das Resultat des Matches eintragen.',
        jsonb_build_object(
          'kind', 'match_round_prompt',
          'match_id', p_match_id,
          'round', 1
        )
      );
  END LOOP;

  RETURN jsonb_build_object('status', 'awaiting_results', 'round', 1);
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_finish_play TO authenticated;


-- ---- 5. match_propose_result -----------------------------------------

CREATE OR REPLACE FUNCTION public.match_propose_result(
  p_match_id      uuid,
  p_winner_team_id text,
  p_score_a       int,
  p_score_b       int
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_round      smallint;
  v_changed    int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, current_round INTO v_status, v_round
    FROM public.matches WHERE id = p_match_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'match not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status <> 'awaiting_results' THEN
    RAISE EXCEPTION 'match is not awaiting results' USING ERRCODE = '22023';
  END IF;

  IF p_winner_team_id IS NOT NULL AND p_winner_team_id NOT IN ('A','B') THEN
    RAISE EXCEPTION 'invalid winner_team_id' USING ERRCODE = '22023';
  END IF;
  IF p_score_a IS NULL OR p_score_a < 0 OR p_score_b IS NULL OR p_score_b < 0 THEN
    RAISE EXCEPTION 'scores must be non-negative integers' USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.match_participants
    WHERE match_id = p_match_id
      AND user_id  = v_caller
      AND kind     = 'in_app'
      AND invitation_status = 'accepted'
  ) THEN
    RAISE EXCEPTION 'caller is not an accepted in_app participant'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.match_result_proposals(
      match_id, round, user_id, winner_team_id, score_a, score_b)
    VALUES (
      p_match_id, v_round, v_caller, p_winner_team_id, p_score_a, p_score_b)
    ON CONFLICT (match_id, round, user_id) DO UPDATE
      SET winner_team_id = EXCLUDED.winner_team_id,
          score_a        = EXCLUDED.score_a,
          score_b        = EXCLUDED.score_b,
          proposed_at    = now()
      WHERE
        match_result_proposals.winner_team_id IS DISTINCT FROM EXCLUDED.winner_team_id
        OR match_result_proposals.score_a IS DISTINCT FROM EXCLUDED.score_a
        OR match_result_proposals.score_b IS DISTINCT FROM EXCLUDED.score_b;
  GET DIAGNOSTICS v_changed = ROW_COUNT;

  IF v_changed > 0 THEN
    INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
      VALUES (
        p_match_id,
        'proposal_received',
        v_caller,
        jsonb_build_object(
          'round', v_round,
          'winner_team_id', p_winner_team_id,
          'score_a', p_score_a,
          'score_b', p_score_b
        )
      );
  END IF;

  PERFORM public._match_try_reconcile(p_match_id);

  SELECT status, current_round INTO v_status, v_round
    FROM public.matches WHERE id = p_match_id;

  RETURN jsonb_build_object('status', v_status, 'round', v_round);
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_propose_result TO authenticated;


-- ---- 6. match_cancel -------------------------------------------------

CREATE OR REPLACE FUNCTION public.match_cancel(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_creator      uuid;
  v_status       text;
  v_participant  record;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, status INTO v_creator, v_status
    FROM public.matches WHERE id = p_match_id FOR UPDATE;
  IF v_creator IS NULL AND v_status IS NULL THEN
    RAISE EXCEPTION 'match not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'only the creator can cancel' USING ERRCODE = '42501';
  END IF;
  IF v_status NOT IN ('pending_invites','active') THEN
    RAISE EXCEPTION 'match cannot be cancelled in its current state'
      USING ERRCODE = '22023';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.match_result_proposals WHERE match_id = p_match_id
  ) THEN
    RAISE EXCEPTION 'match has result proposals — cannot cancel'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.matches
    SET status = 'voided', voided_at = now()
    WHERE id = p_match_id;

  INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
    VALUES (
      p_match_id,
      'voided',
      v_caller,
      jsonb_build_object('reason', 'cancelled')
    );

  FOR v_participant IN
    SELECT user_id FROM public.match_participants
    WHERE match_id = p_match_id
      AND kind = 'in_app'
      AND user_id IS NOT NULL
  LOOP
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
      VALUES (
        v_participant.user_id,
        'notice',
        'Match abgebrochen',
        'Das Match wurde vom Organisator abgebrochen.',
        jsonb_build_object(
          'kind', 'match_cancelled',
          'match_id', p_match_id
        )
      );
  END LOOP;

  RETURN jsonb_build_object('status', 'voided');
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_cancel TO authenticated;


-- ---- 7. match_get ----------------------------------------------------

CREATE OR REPLACE FUNCTION public.match_get(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_match        jsonb;
  v_teams        jsonb;
  v_participants jsonb;
  v_own          jsonb;
  v_audit        jsonb;
  v_round        smallint;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.match_participants
    WHERE match_id = p_match_id AND user_id = v_caller
  ) THEN
    RETURN NULL;
  END IF;

  SELECT to_jsonb(m.*) INTO v_match
    FROM public.matches m WHERE m.id = p_match_id;
  IF v_match IS NULL THEN
    RETURN NULL;
  END IF;

  v_round := (v_match ->> 'current_round')::smallint;

  SELECT coalesce(jsonb_agg(to_jsonb(t.*) ORDER BY t.team_id), '[]'::jsonb)
    INTO v_teams
    FROM public.match_teams t
    WHERE t.match_id = p_match_id;

  SELECT coalesce(jsonb_agg(to_jsonb(p.*) ORDER BY p.team_id, p.joined_at), '[]'::jsonb)
    INTO v_participants
    FROM public.match_participants p
    WHERE p.match_id = p_match_id;

  SELECT jsonb_build_object(
           'round',          pr.round,
           'winner_team_id', pr.winner_team_id,
           'score_a',        pr.score_a,
           'score_b',        pr.score_b
         )
    INTO v_own
    FROM public.match_result_proposals pr
    WHERE pr.match_id = p_match_id
      AND pr.user_id  = v_caller
      AND pr.round    = v_round;

  SELECT coalesce(jsonb_agg(to_jsonb(e.*) ORDER BY e.at DESC), '[]'::jsonb)
    INTO v_audit
    FROM (
      SELECT * FROM public.match_audit_events
       WHERE match_id = p_match_id
       ORDER BY at DESC
       LIMIT 20
    ) e;

  RETURN jsonb_build_object(
    'match',         v_match,
    'teams',         v_teams,
    'participants',  v_participants,
    'own_proposal',  v_own,
    'audit_tail',    v_audit
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_get TO authenticated;


-- ---- 8. match_list_for_caller ----------------------------------------

CREATE OR REPLACE FUNCTION public.match_list_for_caller(
  p_status_filter text DEFAULT NULL
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
    SELECT jsonb_build_object(
             'match_id',           m.id,
             'format',             m.format,
             'scoring',            m.scoring,
             'status',             m.status,
             'started_at',         m.started_at,
             'completed_at',       m.completed_at,
             'my_team_id',         my_mp.team_id,
             'opponent_team_size', (
               SELECT count(*)::int FROM public.match_participants opp
               WHERE opp.match_id = m.id AND opp.team_id <> my_mp.team_id
             ),
             'my_role',            my_mp.invitation_status
           )
      FROM public.matches m
      JOIN public.match_participants my_mp
        ON my_mp.match_id = m.id AND my_mp.user_id = v_caller
     WHERE p_status_filter IS NULL OR m.status = p_status_filter
     ORDER BY m.started_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_list_for_caller TO authenticated;
