-- Tournament feature — M2a follow-up: project `phase` from
-- tournament_match_get.
--
-- ROOT-CAUSE for the M2a UI-2 gap: the match-detail screen reads
-- match.phase via getMatch() -> RPC public.tournament_match_get. The
-- latest body of that RPC (20261208000000_cf3_single_player_name.sql)
-- never projected `phase`, so row['phase'] was always NULL and
-- matchPhaseFromWire(null) ALWAYS resolved to MatchPhase.group. The
-- canonical client set-winner derivation therefore treated every match —
-- including KO matches — as group phase, diverging from the server
-- derivation for KO. (For the actual group-phase consensus bug the fix
-- already worked; this closes the KO gap so client == server everywhere.)
--
-- Additive only: CREATE OR REPLACE of tournament_match_get, restated
-- VERBATIM from 20261208000000 EXCEPT the single added projection field
-- `'phase' -> m.phase` in the jsonb_build_object. No DROP / DELETE /
-- TRUNCATE / schema removal. The grant is restated unchanged.

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
           -- M2a follow-up: project the match phase so the detail-screen
           -- client derivation (resolveSetWinnerForSide) sees the real
           -- group/KO phase instead of the non-forcing 'group' default.
           'phase',                 m.phase,
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
