-- Project tournament_matches.pitch_number through the two match read RPCs.
--
-- The column exists since 20260525000001 and is fed by _tournament_assign_
-- pitches / _from_stage_node, but neither tournament_match_get nor
-- tournament_list_matches exposed it, so the client could not show the
-- player-facing pitch ("Dein Platz: Pitch n") without re-deriving it from the
-- PitchPlan. This re-bases both latest bodies 1:1 and adds m.pitch_number to
-- their jsonb_build_object. Additive only — no schema change.
--
-- match_get body re-based from 20261306000000; list body from 20261212000000.

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
           'phase',                 m.phase,
           'stage_node_id',         m.stage_node_id,
           -- The assigned pitch (tournament_matches.pitch_number, fed by
           -- _tournament_assign_pitches / _from_stage_node), so the detail
           -- screen and the player banner read the server value directly.
           'pitch_number',          m.pitch_number,
           -- U10c (T18): the server-authoritative per-match KO tiebreak method
           -- (set from the match's TypeRound for a type_graph KO match, NULL for
           -- classic). The detail screen prefers this over a client-computed one.
           'ko_tiebreak_method',    m.ko_tiebreak_method,
           'set_score_proposals',   v_proposals
         )
    INTO v_match
    FROM public.tournament_matches m
    LEFT JOIN public.tournament_participants pa ON pa.id = m.participant_a
    LEFT JOIN public.user_profiles            upa ON upa.user_id = pa.user_id
    LEFT JOIN public.teams                    tma ON tma.id      = pa.team_id
    LEFT JOIN public.tournament_participants pb ON pb.id = m.participant_b
    LEFT JOIN public.user_profiles            upb ON upb.user_id = pb.user_id
    LEFT JOIN public.teams                    tmb ON tmb.id      = pb.team_id
    WHERE m.id = p_match_id;

  RETURN v_match;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_match_get(uuid) TO authenticated;

COMMENT ON FUNCTION public.tournament_match_get(uuid) IS
  'Match-detail RPC (re-based 20261317000000). Projects pitch_number (the '
  'assigned pitch fed by _tournament_assign_pitches) alongside ko_tiebreak_'
  'method so the detail screen and the player banner read the server value '
  'instead of re-deriving the pitch from the PitchPlan.';

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
