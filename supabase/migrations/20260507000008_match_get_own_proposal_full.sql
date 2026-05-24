-- Extend `match_get`'s `own_proposal` payload so the Dart parser
-- (MatchResultProposal.fromRow) gets all the fields it expects.
--
-- Before: { round, winner_team_id, score_a, score_b } — four fields.
-- After:  + user_id, proposed_at — six fields, matching the parser.
--
-- Without this, the moment the caller has already submitted a proposal
-- the next match_get response trips a `type Null is not a subtype of
-- type String in type cast` in `MatchResultProposal.fromRow` because
-- `row['user_id']` is missing.

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

  SELECT jsonb_build_object(
           'match_id',       m.id,
           'created_by',     m.created_by,
           'format',         m.format,
           'scoring',        m.scoring,
           'status',         m.status,
           'current_round',  m.current_round,
           'winner_team_id', m.winner_team_id,
           'final_score_a',  m.final_score_a,
           'final_score_b',  m.final_score_b,
           'settings',       m.settings,
           'started_at',     m.started_at,
           'completed_at',   m.completed_at,
           'voided_at',      m.voided_at
         )
    INTO v_match
    FROM public.matches m WHERE m.id = p_match_id;
  IF v_match IS NULL THEN
    RETURN NULL;
  END IF;

  v_round := (v_match ->> 'current_round')::smallint;

  SELECT coalesce(jsonb_agg(to_jsonb(t.*) ORDER BY t.team_id), '[]'::jsonb)
    INTO v_teams
    FROM public.match_teams t
    WHERE t.match_id = p_match_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'participant_id',    p.participant_id,
           'team_id',           p.team_id,
           'kind',              p.kind,
           'user_id',           p.user_id,
           'nickname',          up.nickname,
           'invitation_status', p.invitation_status,
           'joined_at',         p.joined_at,
           'responded_at',      p.responded_at
         ) ORDER BY p.team_id, p.joined_at), '[]'::jsonb)
    INTO v_participants
    FROM public.match_participants p
    LEFT JOIN public.user_profiles up ON up.user_id = p.user_id
    WHERE p.match_id = p_match_id;

  -- Project own_proposal explicitly so the JSON keys exactly match the
  -- Dart parser's expectations (round, user_id, winner_team_id, score_a,
  -- score_b, proposed_at). Older revisions of this RPC omitted user_id
  -- and proposed_at, which would null-crash the cast in the client.
  SELECT jsonb_build_object(
           'round',          pr.round,
           'user_id',        pr.user_id,
           'winner_team_id', pr.winner_team_id,
           'score_a',        pr.score_a,
           'score_b',        pr.score_b,
           'proposed_at',    pr.proposed_at
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

GRANT EXECUTE ON FUNCTION public.match_get(uuid) TO authenticated;
