-- W3-T4 / Sprint A — expose participant display names from the read RPCs.
--
-- Both `tournament_get` and `tournament_match_get` previously returned
-- only `user_id` / `participant_a_id` / `participant_b_id` for each
-- participant slot. UI layers fell back to UUID substrings ("ba9c12…"),
-- which surfaced in the match-header, standings, live-dashboard and
-- public-roster screens (R10-F-06 / R13-F-02 / R14-F-10 / R19-F-09).
--
-- The fix sits on the data layer: project a `display_name` per slot,
-- COALESCEd in this order so single-user and team participants both
-- render correctly:
--   1. user_profiles.nickname  (single-user registration)
--   2. teams.display_name      (team registration, FR-REG-12)
--   3. NULL                    (caller renders a localized fallback)
--
-- The naming `display_name` (rather than `nickname`) is shared with the
-- team-pool-conflict helper (20260615000008) so all wire payloads speak
-- the same shape. Wave-B-Polish will swap the remaining UUID-substring
-- consumers (standings, live-dashboard, public-roster) onto this field;
-- the match-detail header is migrated in this sprint as a smoke test.

CREATE OR REPLACE FUNCTION public.tournament_get(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller       uuid;
  v_status       text;
  v_created_by   uuid;
  v_tournament   jsonb;
  v_participants jsonb;
  v_matches      jsonb;
  v_audit        jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments WHERE id = p_tournament_id;
  IF v_status IS NULL THEN
    RETURN NULL;
  END IF;
  IF v_status = 'draft' AND v_created_by IS DISTINCT FROM v_caller THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
           'tournament_id',        t.id,
           'created_by',           t.created_by,
           'display_name',         t.display_name,
           'team_size',            t.team_size,
           'min_participants',     t.min_participants,
           'max_participants',     t.max_participants,
           'format',               t.format,
           'scoring',              t.scoring,
           'match_format_config',  t.match_format,
           'tiebreaker_order',     t.tiebreaker_order,
           'bye_points',           t.bye_points,
           'forfeit_points',       t.forfeit_points,
           'status',               t.status,
           'registration_opens_at',  t.registration_opens_at,
           'registration_closes_at', t.registration_closes_at,
           'started_at',           t.started_at,
           'completed_at',         t.completed_at,
           'published_at',         t.published_at,
           'created_at',           t.created_at,
           'updated_at',           t.updated_at
         )
    INTO v_tournament
    FROM public.tournaments t WHERE t.id = p_tournament_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'participant_id',      p.id,
           'tournament_id',       p.tournament_id,
           'user_id',             p.user_id,
           'nickname',            up.nickname,
           'display_name',        COALESCE(up.nickname, tm.display_name),
           'registration_status', p.registration_status,
           'seed',                p.seed,
           'registered_at',       p.registered_at,
           'responded_at',        p.responded_at,
           'withdrew_at',         p.withdrew_at
         ) ORDER BY p.registered_at), '[]'::jsonb)
    INTO v_participants
    FROM public.tournament_participants p
    LEFT JOIN public.user_profiles up ON up.user_id = p.user_id
    LEFT JOIN public.teams         tm ON tm.id = p.team_id
    WHERE p.tournament_id = p_tournament_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'match_id',              m.id,
           'tournament_id',         m.tournament_id,
           'round_number',          m.round_number,
           'match_number_in_round', m.match_number_in_round,
           'participant_a_id',      m.participant_a,
           'participant_b_id',      m.participant_b,
           'participant_a_display_name',
             COALESCE(upa.nickname, tma.display_name),
           'participant_b_display_name',
             COALESCE(upb.nickname, tmb.display_name),
           'status',                m.status,
           'consensus_round',       m.consensus_round,
           'started_at',            m.started_at,
           'completed_at',          m.finalized_at,
           'winner_participant_id', m.winner_participant,
           'final_score_a',         m.final_score_a,
           'final_score_b',         m.final_score_b
         ) ORDER BY m.round_number, m.match_number_in_round), '[]'::jsonb)
    INTO v_matches
    FROM public.tournament_matches m
    LEFT JOIN public.tournament_participants pa ON pa.id = m.participant_a
    LEFT JOIN public.user_profiles            upa ON upa.user_id = pa.user_id
    LEFT JOIN public.teams                    tma ON tma.id      = pa.team_id
    LEFT JOIN public.tournament_participants pb ON pb.id = m.participant_b
    LEFT JOIN public.user_profiles            upb ON upb.user_id = pb.user_id
    LEFT JOIN public.teams                    tmb ON tmb.id      = pb.team_id
    WHERE m.tournament_id = p_tournament_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'kind',          e.kind,
           'actor_user_id', e.actor_user_id,
           'payload',       e.payload,
           'at',            e.created_at
         ) ORDER BY e.created_at DESC), '[]'::jsonb)
    INTO v_audit
    FROM (
      SELECT kind, actor_user_id, payload, created_at
        FROM public.tournament_audit_events
       WHERE tournament_id = p_tournament_id
       ORDER BY created_at DESC
       LIMIT 50
    ) e;

  RETURN jsonb_build_object(
    'tournament',   v_tournament,
    'participants', v_participants,
    'matches',      v_matches,
    'audit_tail',   v_audit
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_get(uuid) TO authenticated;


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
             COALESCE(upa.nickname, tma.display_name),
           'participant_b_display_name',
             COALESCE(upb.nickname, tmb.display_name),
           'status',                m.status,
           'consensus_round',       m.consensus_round,
           'started_at',            m.started_at,
           'completed_at',          m.finalized_at,
           'winner_participant_id', m.winner_participant,
           'final_score_a',         m.final_score_a,
           'final_score_b',         m.final_score_b,
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
