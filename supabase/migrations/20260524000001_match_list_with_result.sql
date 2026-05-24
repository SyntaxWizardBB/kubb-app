-- Expose final-result columns on match_list_for_caller so the history
-- and stats views can render outcomes without a per-row match_get
-- roundtrip. The columns are NULL until the match is finalized.

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
             'my_role',            my_mp.invitation_status,
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
