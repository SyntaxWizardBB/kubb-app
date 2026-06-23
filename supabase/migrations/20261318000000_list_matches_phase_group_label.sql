-- Project tournament_matches.phase and tournament_matches.group_label through
-- the match-list RPC.
--
-- Both columns already exist on the table: `phase` since 20260601000010
-- (NOT NULL DEFAULT 'group', CHECK group/ko/third_place/final) and
-- `group_label` since 20260615000009 (pool-phase group, NULL outside the group
-- phase, stamped by tournament_start_pool_phase / the group_phase materializer).
-- The live "Übersicht" tab labels group-phase matches "Gruppe A · Runde 1"
-- (live-views-and-inbox-spec §5.2), but tournament_list_matches never exposed
-- either column, so the client could only group by round.
--
-- This re-bases the latest list body (from 20261317000000) 1:1 and adds
-- m.phase + m.group_label to the jsonb_build_object. Additive only — no schema
-- change. tournament_match_get already projects 'phase' (since 20261239000000),
-- so only the list body needs the addition; group_label is read straight off
-- the match row, no join.

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
    WITH agreed_sets AS (
      -- FF2 / Finding B: same consensus-row pick as tournament_pool_standings.
      SELECT DISTINCT ON (sp.match_id, sp.set_number)
             sp.match_id,
             sp.set_number,
             sp.set_winner
        FROM public.tournament_set_score_proposals sp
        JOIN public.tournament_matches m
          ON m.id = sp.match_id
         AND sp.consensus_round = m.consensus_round
       WHERE m.tournament_id = p_tournament_id
         AND m.status        IN ('finalized','overridden')
       ORDER BY sp.match_id, sp.set_number, sp.submitter_user_id
    ),
    match_set_wins AS (
      SELECT s.match_id,
             coalesce(count(*) FILTER (WHERE s.set_winner = 'A'), 0) AS sets_a,
             coalesce(count(*) FILTER (WHERE s.set_winner = 'B'), 0) AS sets_b
        FROM agreed_sets s
       GROUP BY s.match_id
    )
    SELECT jsonb_build_object(
             'match_id',              m.id,
             'tournament_id',         m.tournament_id,
             'round_number',          m.round_number,
             'match_number_in_round', m.match_number_in_round,
             'participant_a_id',      m.participant_a,
             'participant_b_id',      m.participant_b,
             -- CF3: team_id-driven (single nickname vs team name).
             'participant_a_display_name',
               CASE WHEN pa.team_id IS NULL THEN upa.nickname
                    ELSE tma.display_name END,
             'participant_b_display_name',
               CASE WHEN pb.team_id IS NULL THEN upb.nickname
                    ELSE tmb.display_name END,
             'status',                m.status,
             'consensus_round',       m.consensus_round,
             'started_at',            m.started_at,
             'completed_at',          m.finalized_at,
             'winner_participant_id', m.winner_participant,
             'final_score_a',         m.final_score_a,
             'final_score_b',         m.final_score_b,
             -- The assigned pitch (tournament_matches.pitch_number), so the
             -- match list / live dashboard can show "Pitch n" per row without
             -- re-deriving it from the PitchPlan.
             'pitch_number',          m.pitch_number,
             -- W3-T06: per-match phase (group/ko/third_place/final) and the
             -- pool-phase group label, so the "Übersicht" tab can render
             -- "Gruppe A · Runde 1" instead of a bare round number. group_label
             -- is NULL outside the group phase; both read straight off the row.
             'phase',                 m.phase,
             'group_label',           m.group_label,
             -- FF2 / Finding B: real per-side set wins (null-safe -> 0).
             'sets_won_a',            coalesce(sw.sets_a, 0),
             'sets_won_b',            coalesce(sw.sets_b, 0)
           )
      FROM public.tournament_matches m
      LEFT JOIN public.tournament_participants pa ON pa.id = m.participant_a
      LEFT JOIN public.user_profiles            upa ON upa.user_id = pa.user_id
      LEFT JOIN public.teams                    tma ON tma.id      = pa.team_id
      LEFT JOIN public.tournament_participants pb ON pb.id = m.participant_b
      LEFT JOIN public.user_profiles            upb ON upb.user_id = pb.user_id
      LEFT JOIN public.teams                    tmb ON tmb.id      = pb.team_id
      LEFT JOIN match_set_wins sw ON sw.match_id = m.id
     WHERE m.tournament_id = p_tournament_id
     ORDER BY m.round_number ASC, m.match_number_in_round ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.tournament_list_matches(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_list_matches(uuid) IS
  'Match-list RPC (re-based 20261318000000). Adds phase + group_label to the '
  'per-row projection so the live overview can label group-phase matches '
  '("Gruppe A · Runde 1"). Additive, no schema change.';
