-- CF3 (ChangeSpec K08) — Single-Anmeldung: Spielername = Teamname ueberall.
--
-- WHY ----------------------------------------------------------------
-- A single registration (team_size == 1) creates ONE
-- tournament_participants row with user_id set and team_id NULL, and
-- writes NO tournament_roster_slots (see register_single latest body,
-- 20261201000050 §1 — the INSERT carries only tournament_id, user_id,
-- registration_status, responded_at). A team registration creates a row
-- with team_id set (and roster slots). So the participant's display name
-- MUST be team_id-driven:
--   * team_id IS NULL  -> the single's nickname (user_profiles.nickname)
--   * team_id IS NOT NULL -> the team's display name (teams.display_name)
--
-- The existing read RPCs (tournament_get / tournament_match_get,
-- 20260601000003, re-stated in 20261201000032) projected
--   COALESCE(up.nickname, tm.display_name)
-- which is WRONG for teams: a team participant row carries user_id = the
-- registrant (captain), so up.nickname is non-null and the captain's
-- nickname was shown instead of the team name. For singles the old order
-- happened to work (up.nickname set), but the rule was implicit. This
-- migration makes the rule EXPLICIT and team_id-driven everywhere, the
-- ONE canonical name source per display layer (no 'Team von X'
-- string-construction anywhere).
--
-- WHAT ---------------------------------------------------------------
--   1. tournament_get             — re-stated from 20261201000032 §2,
--      participants[] + matches[] display names become team_id-driven.
--   2. tournament_match_get       — re-stated from 20260601000003,
--      participant_a/b_display_name become team_id-driven.
--   3. tournament_list_matches    — re-stated from 20260525000003,
--      ADDS participant_a/b_display_name (team_id-driven) so the match
--      list renders names instead of UUID substrings.
--   4. public_tournament_get      — re-stated from 20260901000001,
--      ADDS single-participant display names to roster[] (singles have no
--      roster_slots, so the public_tournament_roster_view yields nothing
--      and the spectator screen showed 'Unbekannt'). Privacy unchanged:
--      only nickname + participant_id (+ slot_index 0) is surfaced; no
--      user_id / email / team metadata leaks.
--
-- DB-SAFE: additive CREATE OR REPLACE only; no destructive rewrite of
-- existing migration files, no db reset.


-- ====================================================================
-- 1. tournament_get — re-stated from 20261201000032 §2, ONLY the two
--    display-name projections changed to team_id-driven CASE expressions.
-- ====================================================================

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
           'club_id',              t.club_id,
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

  -- CF3: team_id-driven display name. Single (team_id IS NULL) -> the
  -- player's nickname; team (team_id set) -> the team name. NOT
  -- COALESCE(up.nickname, ...), which would surface the captain nickname
  -- for a team row whose user_id is the registrant.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'participant_id',      p.id,
           'tournament_id',       p.tournament_id,
           'user_id',             p.user_id,
           'nickname',            up.nickname,
           'display_name',
             CASE WHEN p.team_id IS NULL THEN up.nickname
                  ELSE tm.display_name END,
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
$$;

GRANT EXECUTE ON FUNCTION public.tournament_get(uuid) TO authenticated;


-- ====================================================================
-- 2. tournament_match_get — re-stated from 20260601000003, ONLY the two
--    display-name projections changed to team_id-driven.
-- ====================================================================

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


-- ====================================================================
-- 3. tournament_list_matches — re-stated from 20260525000003, ADDS the
--    two team_id-driven display-name fields (previously absent: the match
--    list fell back to a UUID substring client-side).
-- ====================================================================

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
             'final_score_b',         m.final_score_b
           )
      FROM public.tournament_matches m
      LEFT JOIN public.tournament_participants pa ON pa.id = m.participant_a
      LEFT JOIN public.user_profiles            upa ON upa.user_id = pa.user_id
      LEFT JOIN public.teams                    tma ON tma.id      = pa.team_id
      LEFT JOIN public.tournament_participants pb ON pb.id = m.participant_b
      LEFT JOIN public.user_profiles            upb ON upb.user_id = pb.user_id
      LEFT JOIN public.teams                    tmb ON tmb.id      = pb.team_id
     WHERE m.tournament_id = p_tournament_id
     ORDER BY m.round_number ASC, m.match_number_in_round ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.tournament_list_matches(uuid) TO authenticated;


-- ====================================================================
-- 4. public_tournament_get — re-stated from 20260901000001, ADDS single
--    participants to roster[] so the anon spectator screen shows the
--    single's nickname instead of 'Unbekannt'. Singles have no
--    tournament_roster_slots, so public_tournament_roster_view yields
--    nothing for them; we UNION a privacy-safe synthetic roster entry per
--    single participant (slot_index 0, display_name = nickname). Team
--    participants keep coming from the roster view unchanged. Privacy:
--    still only participant_id + slot_index + display_name; no user_id /
--    email / team metadata.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.public_tournament_get(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_tournament       jsonb;
  v_matches          jsonb;
  v_roster           jsonb;
  v_participant_cnt  int;
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM public.tournaments
     WHERE id = p_tournament_id
       AND public = true
       AND status IN (
         'published',
         'registration_open',
         'registration_closed',
         'live',
         'finalized'
       )
  ) THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
           'tournament_id',       t.id,
           'display_name',        t.display_name,
           'team_size',           t.team_size,
           'format',              t.format,
           'status',              t.status,
           'match_format_config', t.match_format,
           'started_at',          t.started_at,
           'completed_at',        t.completed_at
         )
    INTO v_tournament
    FROM public.tournaments t
   WHERE t.id = p_tournament_id;

  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'match_id',              m.id,
           'tournament_id',         m.tournament_id,
           'round_number',          m.round_number,
           'match_number_in_round', m.match_number_in_round,
           'participant_a_id',      m.participant_a,
           'participant_b_id',      m.participant_b,
           'status',                m.status,
           'consensus_round',       m.consensus_round,
           'started_at',            m.started_at,
           'completed_at',          m.finalized_at,
           'winner_participant_id', m.winner_participant,
           'final_score_a',         m.final_score_a,
           'final_score_b',         m.final_score_b,
           'phase',                 m.phase,
           'bracket_position',      m.bracket_position
         ) ORDER BY m.round_number, m.match_number_in_round), '[]'::jsonb)
    INTO v_matches
    FROM public.tournament_matches m
   WHERE m.tournament_id = p_tournament_id;

  -- Roster = team-roster slots (display_name only, via the privacy view)
  -- UNION single participants (no slots) projected with slot_index 0 and
  -- the player's nickname. Both branches expose only participant_id,
  -- slot_index and display_name — no user_id / email / team metadata.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'slot_id',        r.slot_id,
           'participant_id', r.participant_id,
           'slot_index',     r.slot_index,
           'display_name',   r.display_name
         ) ORDER BY r.participant_id, r.slot_index), '[]'::jsonb)
    INTO v_roster
    FROM (
      -- Team participants: existing privacy-projecting roster view.
      SELECT v.slot_id::text       AS slot_id,
             v.participant_id::text AS participant_id,
             v.slot_index          AS slot_index,
             v.display_name        AS display_name
        FROM public.public_tournament_roster_view v
        JOIN public.tournament_participants p ON p.id = v.participant_id
       WHERE p.tournament_id = p_tournament_id
      UNION ALL
      -- Single participants (team_id IS NULL): one synthetic entry with the
      -- player's nickname. These have no roster slots, so without this the
      -- spectator screen rendered 'Unbekannt' (CF3 / K08). slot_id is NULL
      -- (singles have no roster slot — the client treats slot_id as an
      -- opaque, optional identifier). Filtered to registration_status =
      -- 'confirmed' so the single roster matches participant_count and the
      -- 'angemeldete Teilnehmer' semantics (a withdrawn single must not show
      -- up in the spectator roster).
      SELECT NULL::text            AS slot_id,
             p.id::text            AS participant_id,
             0                     AS slot_index,
             COALESCE(up.nickname::text, 'Unbekannt') AS display_name
        FROM public.tournament_participants p
        LEFT JOIN public.user_profiles up ON up.user_id = p.user_id
       WHERE p.tournament_id = p_tournament_id
         AND p.team_id IS NULL
         AND p.registration_status = 'confirmed'
    ) r;

  SELECT count(*)::int
    INTO v_participant_cnt
    FROM public.tournament_participants p
   WHERE p.tournament_id = p_tournament_id
     AND p.registration_status = 'confirmed';

  RETURN jsonb_build_object(
    'tournament',        v_tournament,
    'matches',           v_matches,
    'roster',            v_roster,
    'participant_count', v_participant_cnt
  );
END;
$$;

REVOKE ALL ON FUNCTION public.public_tournament_get(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.public_tournament_get(uuid)
  TO anon, authenticated;

COMMENT ON FUNCTION public.public_tournament_get(uuid) IS
  'Anon-friendly read of a public tournament: header, matches, roster '
  '(display_name only — team slots via public_tournament_roster_view, '
  'singles synthesised from user_profiles.nickname per CF3). Returns NULL '
  'for non-public or draft tournaments. No user_id / created_by / email / '
  'team metadata / set_score_proposals leakage.';
