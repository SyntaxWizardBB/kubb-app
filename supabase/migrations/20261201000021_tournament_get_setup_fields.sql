-- Tournament feature — P7: project the P6 setup fields from tournament_get.
--
-- The edit-after-publish flow needs to read the CURRENT values back to
-- pre-fill the setup wizard. `tournament_get`
-- (20260601000003_tournament_get_with_display_names) only projected the
-- M1 header; this migration extends the `tournament` block with every P6
-- setup column added in 20261001000001 so the client can build a
-- TournamentConfigDraft.fromDetail(...) prefill. Purely additive: the
-- participants / matches / audit blocks and the access gate are unchanged
-- (copied verbatim from the prior revision).

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
           'max_team_size',        t.max_team_size,
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
           'updated_at',           t.updated_at,
           -- P7: P6 setup fields, projected so the edit screen can
           -- pre-fill the wizard from the current values.
           'location',             t.location,
           'venue_address',        t.venue_address,
           'event_starts_at',      t.event_starts_at,
           'checkin_until',        t.checkin_until,
           'weather_note',         t.weather_note,
           'info_food',            t.info_food,
           'info_travel',          t.info_travel,
           'info_accommodation',   t.info_accommodation,
           'contact_name',         t.contact_name,
           'contact_phone',        t.contact_phone,
           'entry_fee_cents',      t.entry_fee_cents,
           'currency',             t.currency,
           'payment_methods',      to_jsonb(t.payment_methods),
           'rules_pdf_url',        t.rules_pdf_url,
           'site_map_pdf_url',     t.site_map_pdf_url,
           'league_categories',    to_jsonb(t.league_categories),
           'rule_variants',        t.rule_variants,
           'ko_match_format',      t.ko_match_format,
           'ko_round_formats',     t.ko_round_formats,
           'pitch_plan',           t.pitch_plan,
           'mighty_finisher_quali', t.mighty_finisher_quali,
           'consolation_bracket',  t.consolation_bracket,
           'bracket_type',         t.bracket_type,
           'ko_matchup',           t.ko_matchup,
           'ko_tiebreak_method',   t.ko_tiebreak_method,
           'pool_phase_config',    t.pool_phase_config,
           'ko_config',            t.ko_config
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
