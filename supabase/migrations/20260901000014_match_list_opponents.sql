-- Expose opponents on `match_list_for_caller` (P5 — match stats filter).
--
-- The match stats screen gains a "filter by dueled player" control. The list
-- RPC previously only returned `opponent_team_size` (a count), so the client
-- had no opponent identities to filter on. This revision adds an `opponents`
-- jsonb array — the user_id + nickname of every participant on the opposing
-- team(s) — alongside the existing fields. Everything else is unchanged from
-- 20260524000002_match_list_my_role_fix.sql.

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
             'opponents',          (
               SELECT COALESCE(jsonb_agg(jsonb_build_object(
                        'user_id',      opp.user_id,
                        'display_name', p.nickname
                      ) ORDER BY p.nickname), '[]'::jsonb)
                 FROM public.match_participants opp
                 LEFT JOIN public.user_profiles p ON p.user_id = opp.user_id
                WHERE opp.match_id = m.id
                  AND opp.team_id IS DISTINCT FROM my_mp.team_id
                  AND opp.user_id IS NOT NULL
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
