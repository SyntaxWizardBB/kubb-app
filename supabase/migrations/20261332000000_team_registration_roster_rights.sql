-- Team registration: roster members are first-class (owner feedback 2026-07-06).
--
-- A team registration must be manageable by EVERY player selected on the
-- roster — withdraw, seeing the registration under "Meine Anmeldungen",
-- reaching the matches — exactly as if they had registered the team
-- themselves. Score entry already allows any active team member
-- (tournament_propose_set_scores, 20261238000000) and is unchanged.
--
-- Three re-based functions (stale-body check done against the newest
-- CREATE OR REPLACE of each):
--   1. tournament_withdraw            (basis 20261201000040) — gate widened
--      from "registrant only" to "registrant OR active roster member".
--   2. tournament_list_my_registrations (basis 20260901000004) — also
--      returns registrations where the caller sits on the active roster,
--      and projects team_id + team_display_name.
--   3. tournament_get                 (basis 20261283000000) — participants
--      gain team_id / team_display_name / roster_member_ids (client "me"
--      gate), and the display_name regression from the 20261283 rename is
--      fixed: back to CASE WHEN team_id IS NULL THEN nickname ELSE team
--      name END (20261208 semantics) for participants AND match sides —
--      a team registration must render as the TEAM's name, not as the
--      registrant's nickname.


-- ---- 1. tournament_withdraw: registrant OR active roster member -------

CREATE OR REPLACE FUNCTION public.tournament_withdraw(
  p_participant_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_user_id       uuid;
  v_tournament_id uuid;
  v_status        text;
  v_prior         text;
  v_promoted_id   uuid;
  v_promoted_user uuid;
  v_promoted_team uuid;
  v_name          text;
  v_member        uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT p.user_id, p.tournament_id, p.registration_status
    INTO v_user_id, v_tournament_id, v_prior
    FROM public.tournament_participants p
    WHERE p.id = p_participant_id
    FOR UPDATE;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'participant not found' USING ERRCODE = 'P0002';
  END IF;
  -- Roster members manage the registration like the registrant: any player
  -- currently selected on the active roster may withdraw the team.
  IF v_user_id IS DISTINCT FROM v_caller
     AND NOT EXISTS (
       SELECT 1 FROM public.tournament_roster_slots s
        WHERE s.participant_id = p_participant_id
          AND s.member_user_id = v_caller
          AND s.replaced_at IS NULL
     ) THEN
    RAISE EXCEPTION 'only the participant or a roster member can withdraw'
      USING ERRCODE = '42501';
  END IF;

  SELECT status, display_name INTO v_status, v_name
    FROM public.tournaments WHERE id = v_tournament_id;
  IF v_status NOT IN ('registration_open','registration_closed','live') THEN
    RAISE EXCEPTION 'withdrawal not allowed in current tournament state'
      USING ERRCODE = '22023';
  END IF;

  IF v_prior = 'withdrawn' THEN
    RAISE EXCEPTION 'already withdrawn' USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournament_participants
    SET registration_status = 'withdrawn',
        withdrew_at         = now()
    WHERE id = p_participant_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'withdrawn',
      v_caller,
      jsonb_build_object(
        'participant_id', p_participant_id,
        'prior_status',   v_prior
      )
    );

  -- DYNAMIC PROMOTION: only a CONFIRMED withdrawal frees a real slot. A
  -- waitlist withdrawal changes nothing for the confirmed pool, so we do
  -- nothing extra. Promote the OLDEST waitlisted participant
  -- (ORDER BY registered_at, id) and lock that row to avoid a double-promote
  -- race with a concurrent withdrawal in the same tournament.
  IF v_prior = 'confirmed' THEN
    SELECT p.id, p.user_id, p.team_id
      INTO v_promoted_id, v_promoted_user, v_promoted_team
      FROM public.tournament_participants p
      WHERE p.tournament_id = v_tournament_id
        AND p.registration_status = 'waitlist'
      ORDER BY p.registered_at, p.id
      LIMIT 1
      FOR UPDATE;

    IF v_promoted_id IS NOT NULL THEN
      UPDATE public.tournament_participants
        SET registration_status = 'confirmed',
            responded_at        = now()
        WHERE id = v_promoted_id;

      INSERT INTO public.tournament_audit_events(
          tournament_id, kind, actor_user_id, payload)
        VALUES (
          v_tournament_id,
          'waitlist_promoted',
          v_caller,
          jsonb_build_object(
            'participant_id',     v_promoted_id,
            'freed_by',           p_participant_id
          )
        );

      -- Notify the promoted unit. For a team participant, fan out to every
      -- registered roster member; for a solo, the participant's user_id.
      IF v_promoted_team IS NOT NULL THEN
        FOR v_member IN
          SELECT DISTINCT s.member_user_id
            FROM public.tournament_roster_slots s
           WHERE s.participant_id = v_promoted_id
             AND s.member_user_id IS NOT NULL
        LOOP
          INSERT INTO public.user_inbox_messages(
              user_id, kind, subject, body, action_payload)
            VALUES (
              v_member,
              'tournament_promoted',
              'Du bist nachgerückt',
              'Ein Platz bei "' || coalesce(v_name, '')
                || '" ist frei geworden — euer Team ist nachgerückt. Ihr seid dabei!',
              jsonb_build_object(
                'tournament_id',  v_tournament_id,
                'participant_id', v_promoted_id
              )
            );
        END LOOP;
      ELSE
        INSERT INTO public.user_inbox_messages(
            user_id, kind, subject, body, action_payload)
          VALUES (
            v_promoted_user,
            'tournament_promoted',
            'Du bist nachgerückt',
            'Ein Platz bei "' || coalesce(v_name, '')
              || '" ist frei geworden — du bist nachgerückt. Du bist dabei!',
            jsonb_build_object(
              'tournament_id',  v_tournament_id,
              'participant_id', v_promoted_id
            )
          );
      END IF;
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_withdraw(uuid) TO authenticated;


-- ---- 2. tournament_list_my_registrations: roster-aware + team name ----

CREATE OR REPLACE FUNCTION public.tournament_list_my_registrations(
  p_limit int DEFAULT 50
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_limit  int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  v_limit := COALESCE(p_limit, 50);
  IF v_limit < 1 OR v_limit > 500 THEN
    RAISE EXCEPTION 'limit out of range' USING ERRCODE = '22023';
  END IF;

  -- One row per participant the caller belongs to — as the registrant OR
  -- as an active roster member (team registrations belong to the whole
  -- roster, not just whoever tapped "register"). The EXISTS keeps it one
  -- row per participant, no join fan-out, so no dedupe is needed.
  RETURN QUERY
    SELECT jsonb_build_object(
             'tournament_id',       t.id,
             'created_by',          t.created_by,
             'display_name',        t.display_name,
             'format',              t.format,
             'status',              t.status,
             'started_at',          t.started_at,
             'completed_at',        t.completed_at,
             'participant_count',   (
               SELECT count(*)::int FROM public.tournament_participants pc
                WHERE pc.tournament_id = t.id
                  AND pc.registration_status = 'confirmed'
             ),
             'participant_id',      p.id,
             'registration_status', p.registration_status,
             'team_id',             p.team_id,
             'team_display_name',   tm.display_name
           )
      FROM public.tournament_participants p
      JOIN public.tournaments t ON t.id = p.tournament_id
      LEFT JOIN public.teams tm ON tm.id = p.team_id
     WHERE (
             p.user_id = v_caller
             OR EXISTS (
               SELECT 1 FROM public.tournament_roster_slots s
                WHERE s.participant_id = p.id
                  AND s.member_user_id = v_caller
                  AND s.replaced_at IS NULL
             )
           )
       AND p.registration_status IN ('pending', 'confirmed', 'waitlist')
     ORDER BY t.started_at DESC NULLS FIRST, t.created_at DESC
     LIMIT v_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_list_my_registrations(int)
  TO authenticated;


-- ---- 3. tournament_get: team fields + roster ids + display-name fix ---

CREATE OR REPLACE FUNCTION public.tournament_get(p_tournament_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
           -- CF5 (K28): organizing club so the detail screen can render the
           -- Verein / Spasstournier category. NULL = personal tournament.
           'organizer_team_id',              t.organizer_team_id,
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

  -- display_name: 20261208 semantics restored — a team registration renders
  -- as the TEAM name; the registrant's nickname must not shadow it (the
  -- 20261283 re-base regressed this to COALESCE(nickname, team)).
  -- roster_member_ids: active roster (replaced_at IS NULL) so the client can
  -- treat every selected player as "me" for manage/matches surfaces.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'participant_id',      p.id,
           'tournament_id',       p.tournament_id,
           'user_id',             p.user_id,
           'nickname',            up.nickname,
           'display_name',
             CASE WHEN p.team_id IS NULL THEN up.nickname
                  ELSE tm.display_name END,
           'team_id',             p.team_id,
           'team_display_name',   tm.display_name,
           'roster_member_ids',   (
             SELECT coalesce(jsonb_agg(DISTINCT s.member_user_id), '[]'::jsonb)
               FROM public.tournament_roster_slots s
              WHERE s.participant_id = p.id
                AND s.member_user_id IS NOT NULL
                AND s.replaced_at IS NULL
           ),
           'checked_in_at',       p.checked_in_at,
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
$function$;
