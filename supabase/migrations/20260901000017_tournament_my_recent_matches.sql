-- Caller's recent finished tournament matches (P7 — Home "Zuletzt").
--
-- Returns the caller's most recently finalized tournament matches with the
-- outcome (won/lost/tie), the opponent's nickname and the tournament name, so
-- the home "Zuletzt" list can show tournament results alongside training and
-- match-mode games. SECURITY DEFINER so it can resolve opponents/nicknames
-- without per-row RLS gymnastics; it only ever returns rows the caller played.

CREATE OR REPLACE FUNCTION public.tournament_my_recent_matches(p_limit int DEFAULT 10)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_out    jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(jsonb_agg(row ORDER BY (row->>'finalized_at') DESC), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT jsonb_build_object(
             'match_id',     m.id,
             'tournament',   t.display_name,
             'opponent',     COALESCE(op.nickname, 'Gegner'),
             'outcome',      CASE
                               WHEN m.winner_participant IS NULL THEN 'tie'
                               WHEN m.winner_participant = mine.id THEN 'won'
                               ELSE 'lost'
                             END,
             'finalized_at', COALESCE(m.finalized_at, m.created_at)
           ) AS row
      FROM public.tournament_participants mine
      JOIN public.tournament_matches m
        ON (m.participant_a = mine.id OR m.participant_b = mine.id)
      JOIN public.tournaments t ON t.id = m.tournament_id
      LEFT JOIN public.tournament_participants opp
        ON opp.id = CASE WHEN m.participant_a = mine.id
                         THEN m.participant_b ELSE m.participant_a END
      LEFT JOIN public.user_profiles op ON op.user_id = opp.user_id
     WHERE mine.user_id = v_caller
       AND m.status IN ('finalized', 'overridden')
     ORDER BY COALESCE(m.finalized_at, m.created_at) DESC
     LIMIT GREATEST(p_limit, 1)
  ) sub;

  RETURN v_out;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_my_recent_matches(int) TO authenticated;
