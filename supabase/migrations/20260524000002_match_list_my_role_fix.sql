-- Fix `match_list_for_caller`'s `my_role` projection.
--
-- The previous revisions of this RPC bound `my_role` to
-- `match_participants.invitation_status`, which holds values like
-- 'pending'/'accepted'/'declined'/'left'. The Dart parser
-- (`MatchSummary.fromRow` → `MatchRole.fromWire`) expects one of
-- 'creator', 'participant', or 'observer' and throws on anything else,
-- which broke the stats screen the moment we filtered on finalized
-- matches (the only matches whose status reliably reaches 'accepted').
--
-- New semantics:
--   - 'creator'      if the caller is the match's `created_by` user
--   - 'participant'  otherwise (all rows here are join-matched on the
--                    caller's user id in match_participants)
--
-- We never project 'observer' here because the JOIN restricts the
-- result set to actual participants. The observer role is reserved for
-- a future variant of this RPC if/when we expose match visibility to
-- non-participants.

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
             'my_role',            CASE
                                     WHEN m.created_by = v_caller
                                       THEN 'creator'
                                     ELSE 'participant'
                                   END,
             'winner_team_id',     m.winner_team_id,
             'final_score_a',      m.final_score_a,
             'final_score_b',      m.final_score_b
           )
      FROM public.matches m
      JOIN public.match_participants my_mp
        ON my_mp.match_id = m.id AND my_mp.user_id = v_caller
     WHERE p_status_filter IS NULL OR m.status = p_status_filter
     ORDER BY m.started_at DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.match_list_for_caller TO authenticated;
