-- Loosen the match.format CHECK from {bo1,bo3,bo5} to bo1..bo99 so the
-- user can configure long matches (e.g., friends playing through a
-- whole afternoon). The Dart MatchFormat type becomes a wrapper class
-- around an int rather than a sealed enum.
--
-- Even values (bo2, bo4, ...) are technically permitted: the consensus
-- engine handles ties through the proposal-comparison logic. In wins
-- mode an even-numbered set count can end as a draw, which the result
-- screen surfaces as a "Unentschieden" choice.

-- 1. Loosen the column-level CHECK on matches.format.
ALTER TABLE public.matches DROP CONSTRAINT IF EXISTS matches_format_check;
ALTER TABLE public.matches
  ADD CONSTRAINT matches_format_check
    CHECK (format ~ '^bo[1-9][0-9]?$');

-- 2. Replace match_create's hard-coded format whitelist with the same
--    pattern check so RPC validation matches the column constraint.
CREATE OR REPLACE FUNCTION public.match_create(
  p_format  text,
  p_scoring text,
  p_team_a  jsonb,
  p_team_b  jsonb
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_match_id     uuid;
  v_team         text;
  v_arr          jsonb;
  v_elem         jsonb;
  v_user_id      uuid;
  v_caller_seen  boolean := false;
  v_pending      int := 0;
  v_caller_nick  text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF p_format !~ '^bo[1-9][0-9]?$' THEN
    RAISE EXCEPTION 'invalid format: % (expected bo1..bo99)', p_format
      USING ERRCODE = '22023';
  END IF;
  IF p_scoring NOT IN ('wins','points') THEN
    RAISE EXCEPTION 'invalid scoring: %', p_scoring USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_team_a) NOT BETWEEN 1 AND 6
     OR jsonb_array_length(p_team_b) NOT BETWEEN 1 AND 6 THEN
    RAISE EXCEPTION 'each team must have 1..6 players' USING ERRCODE = '22023';
  END IF;

  v_match_id := gen_random_uuid();
  INSERT INTO public.matches(
      id, created_by, format, scoring, status, current_round, started_at)
    VALUES (v_match_id, v_caller, p_format, p_scoring, 'pending_invites', 0, now());

  INSERT INTO public.match_teams(match_id, team_id) VALUES (v_match_id, 'A'), (v_match_id, 'B');

  INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
    VALUES (v_match_id, 'created', v_caller,
            jsonb_build_object('format', p_format, 'scoring', p_scoring));

  SELECT nickname::text INTO v_caller_nick
    FROM public.user_profiles WHERE user_id = v_caller;

  FOR v_team IN SELECT unnest(ARRAY['A','B']) LOOP
    v_arr := CASE v_team WHEN 'A' THEN p_team_a ELSE p_team_b END;
    FOR v_elem IN SELECT jsonb_array_elements(v_arr) LOOP
      IF (v_elem->>'kind') <> 'in_app' THEN
        RAISE EXCEPTION 'walk-in participants are not supported'
          USING ERRCODE = '22023';
      END IF;
      v_user_id := (v_elem->>'user_id')::uuid;
      IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'in_app participant requires user_id'
          USING ERRCODE = '22023';
      END IF;

      IF v_user_id = v_caller THEN
        v_caller_seen := true;
        INSERT INTO public.match_participants(
            match_id, team_id, kind, user_id, invitation_status, responded_at)
          VALUES (v_match_id, v_team, 'in_app', v_user_id, 'accepted', now());
      ELSE
        IF NOT EXISTS (
          SELECT 1 FROM public.friendships
            WHERE status = 'accepted'
              AND ((low_user_id  = v_caller  AND high_user_id = v_user_id) OR
                   (low_user_id  = v_user_id AND high_user_id = v_caller))
        ) THEN
          RAISE EXCEPTION 'can only invite accepted friends'
            USING ERRCODE = '42501';
        END IF;
        INSERT INTO public.match_participants(
            match_id, team_id, kind, user_id, invitation_status)
          VALUES (v_match_id, v_team, 'in_app', v_user_id, 'pending');
        v_pending := v_pending + 1;

        INSERT INTO public.user_inbox_messages(
            user_id, kind, subject, body, action_payload)
          VALUES (
            v_user_id,
            'verification_request',
            'Match-Einladung',
            coalesce(v_caller_nick, 'Ein Spieler') ||
              ' lädt dich zu einem ' || p_format || '-Match ein.',
            jsonb_build_object(
              'kind', 'match_invite',
              'match_id', v_match_id,
              'invited_by_user_id', v_caller,
              'invited_by_nickname', v_caller_nick,
              'format', p_format,
              'scoring', p_scoring
            )
          );
      END IF;

      INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
        VALUES (v_match_id, 'participant_invited', v_caller,
          jsonb_build_object('user_id', v_user_id, 'team_id', v_team,
                             'kind', 'in_app'));
    END LOOP;
  END LOOP;

  IF NOT v_caller_seen THEN
    RAISE EXCEPTION 'creator must be a participant' USING ERRCODE = '22023';
  END IF;

  IF v_pending = 0 THEN
    UPDATE public.matches SET status = 'active' WHERE id = v_match_id;
    INSERT INTO public.match_audit_events(match_id, kind, actor_user_id, payload)
      VALUES (v_match_id, 'started', v_caller, jsonb_build_object('auto', true));
  END IF;

  RETURN jsonb_build_object('match_id', v_match_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_create(text, text, jsonb, jsonb) TO authenticated;
