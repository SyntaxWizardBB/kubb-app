-- Tournament feature — re-gate lifecycle/update RPCs onto the per-tournament
-- manage helper, and persist tournaments.club_id on create/update.
--
-- USER DECISION: management/edit/start authority is now PER-TOURNAMENT —
-- the creator OR an active owner/admin/organizer of the tournament's
-- club_id. This REPLACES the global capability from
-- 20261201000030 (tournament_caller_is_organizer(), true for ~everyone
-- because user_profiles.is_organizer DEFAULTs true).
--
-- Every RPC below is RE-STATED VERBATIM from its latest on-disk definition
-- (20261201000030 is the latest for all lifecycle/update RPCs;
-- tournament_create is 20261001000002; tournament_get is 20261201000021)
-- with ONLY the authorisation predicate changed:
--   OLD:  created_by = caller  OR  tournament_caller_is_organizer()
--   NEW:  public.tournament_caller_can_manage(p_tournament_id)
-- The new helper itself ORs creator + per-tournament club role, so the
-- creator's behaviour is byte-for-byte unchanged; the global capability is
-- gone. After this migration NOTHING calls tournament_caller_is_organizer().
--
-- ============================ DEPENDENCIES ============================
-- Requires (all earlier on disk):
--   * public.tournament_caller_can_manage(uuid) — 20261201000031 (this
--     migration's companion; MUST sort before it — it does: 31 < 32).
--   * public.tournaments.club_id — 20261201000031.
--   * public.clubs / public.club_memberships — 20260901000012.
--   * tournament_create latest body: 20261001000002_tournament_create_setup.
--   * tournament_get latest body: 20261201000021_tournament_get_setup_fields
--     (P7 edit-prefill projection — preserved verbatim, only club_id added).
--   * Lifecycle/update RPC latest bodies: 20261201000030.
-- Helpers called UNCHANGED (must already exist):
--   public.tournament_start_pool_phase, public._tournament_compute_pools,
--   public._tournament_compute_pool_cut, public._tournament_compute_ko_bracket,
--   public._tournament_compute_de_bracket, public._tournament_assign_pitches,
--   public.validate_swiss_pairing, public._tournament_notify_participants.
--
-- ============================ RISK / SCOPE ============================
--   * Authority is no longer global. A profile organizer who is NOT the
--     creator and NOT an owner/admin/organizer of the tournament's club can
--     no longer manage it. This is the explicit ask.
--   * club_caller_can_publish() (the create-FAB gate, 20260901000016) is
--     LEFT AS-IS — it only governs who may create tournaments, not who may
--     manage an existing one.
--   * tournament_caller_is_organizer() (20261201000030) is intentionally
--     left DEFINED but UNREFERENCED (harmless). Re-stating every body here
--     means no call site survives; verified by grep before shipping.
--   * Defence-in-depth: tournament_create rejects a club_id the caller is
--     not owner/admin/organizer of (42501), so a client cannot stamp an
--     unrelated club onto a tournament to borrow its managers.
-- =====================================================================


-- ====================================================================
-- 1. tournament_create — 20261001000002 body + club_id persistence and
--    the defence-in-depth club-membership check.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_create(
  p_display_name        text,
  p_team_size           int,
  p_min_participants    int,
  p_max_participants    int,
  p_format              text,
  p_match_format_config jsonb,
  p_tiebreaker_order    text[],
  p_setup               jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_tournament_id uuid;
  v_scoring       text;
  v_setup         jsonb;
  v_club_id       uuid;   -- CLUB-LINK
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  v_setup := coalesce(p_setup, '{}'::jsonb);
  IF jsonb_typeof(v_setup) <> 'object' THEN
    RAISE EXCEPTION 'setup must be a JSON object' USING ERRCODE = '22023';
  END IF;

  IF p_display_name IS NULL OR length(p_display_name) < 1 OR length(p_display_name) > 60 THEN
    RAISE EXCEPTION 'display_name length must be 1..60' USING ERRCODE = '22023';
  END IF;
  IF p_team_size IS NULL OR p_team_size < 1 OR p_team_size > 6 THEN
    RAISE EXCEPTION 'team_size must be 1..6' USING ERRCODE = '22023';
  END IF;
  IF p_min_participants IS NULL OR p_min_participants < 2 THEN
    RAISE EXCEPTION 'min_participants must be >= 2' USING ERRCODE = '22023';
  END IF;
  IF p_max_participants IS NULL
     OR p_max_participants < p_min_participants
     OR p_max_participants > 200 THEN
    RAISE EXCEPTION 'max_participants must be in [min_participants, 200]'
      USING ERRCODE = '22023';
  END IF;
  IF p_format IS NULL OR p_format NOT IN (
       'round_robin','single_elimination','round_robin_then_ko',
       'schoch','swiss','schoch_then_ko','swiss_then_ko') THEN
    RAISE EXCEPTION 'invalid format' USING ERRCODE = '22023';
  END IF;
  IF p_match_format_config IS NULL OR jsonb_typeof(p_match_format_config) <> 'object' THEN
    RAISE EXCEPTION 'match_format_config must be a JSON object' USING ERRCODE = '22023';
  END IF;
  IF p_tiebreaker_order IS NULL OR array_length(p_tiebreaker_order, 1) IS NULL THEN
    RAISE EXCEPTION 'tiebreaker_order must be a non-empty array' USING ERRCODE = '22023';
  END IF;

  v_scoring := coalesce(v_setup->>'scoring', 'ekc');
  IF v_scoring NOT IN ('ekc','classic') THEN
    RAISE EXCEPTION 'scoring must be ekc or classic' USING ERRCODE = '22023';
  END IF;

  -- CLUB-LINK: optional organizing club from p_setup. If supplied, the
  -- caller must be an active owner/admin/organizer of it (defence in depth
  -- — the same role the manage helper later trusts).
  v_club_id := NULLIF(v_setup->>'club_id', '')::uuid;
  IF v_club_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.club_memberships cm
       WHERE cm.club_id = v_club_id
         AND cm.user_id = v_caller
         AND cm.removed_at IS NULL
         AND (cm.roles && ARRAY['owner','admin','organizer']::text[])
    ) THEN
      RAISE EXCEPTION 'not authorised for the requested club'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  INSERT INTO public.tournaments(
      created_by, club_id, display_name, team_size, min_participants, max_participants,
      format, scoring, match_format, tiebreaker_order, status,
      -- P6 setup fields
      location, venue_address, event_starts_at, checkin_until,
      registration_closes_at, weather_note, info_food, info_travel,
      info_accommodation, contact_name, contact_phone, entry_fee_cents,
      currency, payment_methods, rules_pdf_url, site_map_pdf_url,
      league_categories, rule_variants, ko_match_format, ko_round_formats,
      pitch_plan, mighty_finisher_quali, consolation_bracket, max_team_size,
      bracket_type, ko_matchup, ko_tiebreak_method,
      pool_phase_config, ko_config)
    VALUES (
      v_caller, v_club_id, p_display_name, p_team_size::smallint,
      p_min_participants::smallint, p_max_participants::smallint,
      p_format, v_scoring, p_match_format_config, p_tiebreaker_order, 'draft',
      v_setup->>'location',
      v_setup->>'venue_address',
      (v_setup->>'event_starts_at')::timestamptz,
      (v_setup->>'checkin_until')::timestamptz,
      (v_setup->>'registration_closes_at')::timestamptz,
      v_setup->>'weather_note',
      v_setup->>'info_food',
      v_setup->>'info_travel',
      v_setup->>'info_accommodation',
      v_setup->>'contact_name',
      v_setup->>'contact_phone',
      (v_setup->>'entry_fee_cents')::int,
      coalesce(v_setup->>'currency', 'CHF'),
      coalesce(
        array(SELECT jsonb_array_elements_text(v_setup->'payment_methods')),
        '{}'::text[]),
      v_setup->>'rules_pdf_url',
      v_setup->>'site_map_pdf_url',
      coalesce(
        array(SELECT jsonb_array_elements_text(v_setup->'league_categories')),
        '{}'::text[]),
      coalesce(v_setup->'rule_variants', jsonb_build_object(
        'sureshot', false, 'diggy', false,
        'opening_rule', '2-4-6', 'strafkubb_off_baseline', true)),
      v_setup->'ko_match_format',
      coalesce(v_setup->'ko_round_formats', '[]'::jsonb),
      v_setup->'pitch_plan',
      v_setup->'mighty_finisher_quali',
      v_setup->'consolation_bracket',
      (v_setup->>'max_team_size')::smallint,
      coalesce(v_setup->>'bracket_type', 'single_elimination'),
      coalesce(v_setup->>'ko_matchup', 'seed_high_vs_low'),
      coalesce(v_setup->>'ko_tiebreak_method', 'classic_kingtoss_removal'),
      v_setup->'pool_phase_config',
      v_setup->'ko_config')
    RETURNING id INTO v_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'created',
      v_caller,
      jsonb_build_object(
        'display_name',     p_display_name,
        'team_size',        p_team_size,
        'min_participants', p_min_participants,
        'max_participants', p_max_participants,
        'format',           p_format,
        'scoring',          v_scoring,
        'league_categories', coalesce(v_setup->'league_categories', '[]'::jsonb)
      )
    );

  RETURN jsonb_build_object('tournament_id', v_tournament_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_create(
  text, int, int, int, text, jsonb, text[], jsonb) TO authenticated;


-- ====================================================================
-- 2. tournament_get — 20261201000021 body (P7 edit-prefill projection,
--    preserved verbatim) + 'club_id' added to the tournament block so the
--    client can compute the per-tournament manage check.
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


-- ====================================================================
-- 3. tournament_publish — 20261201000030 §1 + per-tournament gate.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_publish(p_tournament_id uuid)
RETURNS void
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
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'tournament must be in status draft' USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status = 'published', published_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'published', v_caller, '{}'::jsonb);
END;
$$;


-- ====================================================================
-- 4. tournament_open_registration — 20261201000030 §2 + per-tournament gate.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_open_registration(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller         uuid;
  v_status         text;
  v_created_by     uuid;
  v_existing_opens timestamptz;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by, registration_opens_at
    INTO v_status, v_created_by, v_existing_opens
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status NOT IN ('published', 'registration_closed') THEN
    RAISE EXCEPTION 'tournament must be in status published or registration_closed'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status                = 'registration_open',
        registration_opens_at = coalesce(v_existing_opens, now())
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'registration_opened', v_caller, '{}'::jsonb);
END;
$$;


-- ====================================================================
-- 5. tournament_close_registration — 20261201000030 §3 + per-tournament gate.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_close_registration(p_tournament_id uuid)
RETURNS void
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
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'registration_open' THEN
    RAISE EXCEPTION 'tournament must be in status registration_open'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status                 = 'registration_closed',
        registration_closes_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'registration_closed', v_caller, '{}'::jsonb);
END;
$$;


-- ====================================================================
-- 6. tournament_finalize — 20261201000030 §4 + per-tournament gate.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_finalize(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_created_by uuid;
  v_total      int;
  v_terminal   int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'live' THEN
    RAISE EXCEPTION 'tournament must be in status live' USING ERRCODE = '22023';
  END IF;

  SELECT count(*) INTO v_total
    FROM public.tournament_matches WHERE tournament_id = p_tournament_id;

  SELECT count(*) INTO v_terminal
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND status IN ('finalized', 'overridden', 'voided');

  IF v_total = 0 THEN
    RAISE EXCEPTION 'tournament has no matches to finalize' USING ERRCODE = '22023';
  END IF;
  IF v_terminal < v_total THEN
    RAISE EXCEPTION 'cannot finalize: % of % matches are not yet terminal',
      v_total - v_terminal, v_total USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status = 'finalized', completed_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'finalized',
      v_caller,
      jsonb_build_object('match_count', v_total)
    );
END;
$$;


-- ====================================================================
-- 7. tournament_abort — 20261201000030 §5 + per-tournament gate.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_abort(p_tournament_id uuid)
RETURNS void
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
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status NOT IN (
       'draft','published','registration_open','registration_closed','live') THEN
    RAISE EXCEPTION 'tournament cannot be aborted in its current state'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET status = 'aborted', completed_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'aborted', v_caller, '{}'::jsonb);
END;
$$;


-- ====================================================================
-- 8. tournament_update — 20261201000030 §6 + per-tournament gate, and
--    club_id persistence from p_setup ('club_id').
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_update(
  p_tournament_id       uuid,
  p_display_name        text,
  p_team_size           int,
  p_min_participants    int,
  p_max_participants    int,
  p_format              text,
  p_match_format_config jsonb,
  p_tiebreaker_order    text[],
  p_setup               jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_created_by uuid;
  v_scoring    text;
  v_setup      jsonb;
  v_club_id    uuid;   -- CLUB-LINK
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  -- Status gate: only pre-start tournaments may be edited.
  IF v_status NOT IN (
       'draft','published','registration_open','registration_closed') THEN
    RAISE EXCEPTION 'tournament can only be edited before it goes live'
      USING ERRCODE = '22023', HINT = 'TOURNAMENT_LOCKED';
  END IF;

  v_setup := coalesce(p_setup, '{}'::jsonb);
  IF jsonb_typeof(v_setup) <> 'object' THEN
    RAISE EXCEPTION 'setup must be a JSON object' USING ERRCODE = '22023';
  END IF;

  IF p_display_name IS NULL OR length(p_display_name) < 1
     OR length(p_display_name) > 60 THEN
    RAISE EXCEPTION 'display_name length must be 1..60' USING ERRCODE = '22023';
  END IF;
  IF p_team_size IS NULL OR p_team_size < 1 OR p_team_size > 6 THEN
    RAISE EXCEPTION 'team_size must be 1..6' USING ERRCODE = '22023';
  END IF;
  IF p_min_participants IS NULL OR p_min_participants < 2 THEN
    RAISE EXCEPTION 'min_participants must be >= 2' USING ERRCODE = '22023';
  END IF;
  IF p_max_participants IS NULL
     OR p_max_participants < p_min_participants
     OR p_max_participants > 200 THEN
    RAISE EXCEPTION 'max_participants must be in [min_participants, 200]'
      USING ERRCODE = '22023';
  END IF;
  IF p_format IS NULL OR p_format NOT IN (
       'round_robin','single_elimination','round_robin_then_ko',
       'schoch','swiss','schoch_then_ko','swiss_then_ko') THEN
    RAISE EXCEPTION 'invalid format' USING ERRCODE = '22023';
  END IF;
  IF p_match_format_config IS NULL
     OR jsonb_typeof(p_match_format_config) <> 'object' THEN
    RAISE EXCEPTION 'match_format_config must be a JSON object'
      USING ERRCODE = '22023';
  END IF;
  IF p_tiebreaker_order IS NULL
     OR array_length(p_tiebreaker_order, 1) IS NULL THEN
    RAISE EXCEPTION 'tiebreaker_order must be a non-empty array'
      USING ERRCODE = '22023';
  END IF;

  v_scoring := coalesce(v_setup->>'scoring', 'ekc');
  IF v_scoring NOT IN ('ekc','classic') THEN
    RAISE EXCEPTION 'scoring must be ekc or classic' USING ERRCODE = '22023';
  END IF;

  -- CLUB-LINK: re-target / clear the organizing club. If a new club_id is
  -- supplied, the caller must be an active owner/admin/organizer of it
  -- (defence in depth — same role the manage helper trusts). A NULL/absent
  -- key clears the link.
  v_club_id := NULLIF(v_setup->>'club_id', '')::uuid;
  IF v_club_id IS NOT NULL
     AND v_club_id IS DISTINCT FROM (
       SELECT club_id FROM public.tournaments WHERE id = p_tournament_id) THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.club_memberships cm
       WHERE cm.club_id = v_club_id
         AND cm.user_id = v_caller
         AND cm.removed_at IS NULL
         AND (cm.roles && ARRAY['owner','admin','organizer']::text[])
    ) THEN
      RAISE EXCEPTION 'not authorised for the requested club'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  UPDATE public.tournaments SET
      club_id                = v_club_id,
      display_name           = p_display_name,
      team_size              = p_team_size::smallint,
      min_participants       = p_min_participants::smallint,
      max_participants       = p_max_participants::smallint,
      format                 = p_format,
      scoring                = v_scoring,
      match_format           = p_match_format_config,
      tiebreaker_order       = p_tiebreaker_order,
      location               = v_setup->>'location',
      venue_address          = v_setup->>'venue_address',
      event_starts_at        = (v_setup->>'event_starts_at')::timestamptz,
      checkin_until          = (v_setup->>'checkin_until')::timestamptz,
      registration_closes_at = (v_setup->>'registration_closes_at')::timestamptz,
      weather_note           = v_setup->>'weather_note',
      info_food              = v_setup->>'info_food',
      info_travel            = v_setup->>'info_travel',
      info_accommodation     = v_setup->>'info_accommodation',
      contact_name           = v_setup->>'contact_name',
      contact_phone          = v_setup->>'contact_phone',
      entry_fee_cents        = (v_setup->>'entry_fee_cents')::int,
      currency               = coalesce(v_setup->>'currency', 'CHF'),
      payment_methods        = coalesce(
        array(SELECT jsonb_array_elements_text(v_setup->'payment_methods')),
        '{}'::text[]),
      rules_pdf_url          = v_setup->>'rules_pdf_url',
      site_map_pdf_url       = v_setup->>'site_map_pdf_url',
      league_categories      = coalesce(
        array(SELECT jsonb_array_elements_text(v_setup->'league_categories')),
        '{}'::text[]),
      rule_variants          = coalesce(v_setup->'rule_variants', jsonb_build_object(
        'sureshot', false, 'diggy', false,
        'opening_rule', '2-4-6', 'strafkubb_off_baseline', true)),
      ko_match_format        = v_setup->'ko_match_format',
      ko_round_formats       = coalesce(v_setup->'ko_round_formats', '[]'::jsonb),
      pitch_plan             = v_setup->'pitch_plan',
      mighty_finisher_quali  = v_setup->'mighty_finisher_quali',
      consolation_bracket    = v_setup->'consolation_bracket',
      max_team_size          = (v_setup->>'max_team_size')::smallint,
      bracket_type           = coalesce(v_setup->>'bracket_type', 'single_elimination'),
      ko_matchup             = coalesce(v_setup->>'ko_matchup', 'seed_high_vs_low'),
      ko_tiebreak_method     = coalesce(
        v_setup->>'ko_tiebreak_method', 'classic_kingtoss_removal'),
      pool_phase_config      = v_setup->'pool_phase_config',
      ko_config              = v_setup->'ko_config'
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'updated',
      v_caller,
      jsonb_build_object(
        'display_name',     p_display_name,
        'team_size',        p_team_size,
        'min_participants', p_min_participants,
        'max_participants', p_max_participants,
        'format',           p_format,
        'scoring',          v_scoring,
        'league_categories', coalesce(v_setup->'league_categories', '[]'::jsonb)
      )
    );

  RETURN jsonb_build_object('tournament_id', p_tournament_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_update(
  uuid, text, int, int, int, text, jsonb, text[], jsonb) TO authenticated;


-- ====================================================================
-- 9. tournament_start — 20261201000030 §7 + per-tournament gate.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_start(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller         uuid;
  v_status         text;
  v_format         text;
  v_pool_config    jsonb;
  v_confirmed      int;
  v_slot_count     int;
  v_round_count    int;
  v_match_count    int := 0;
  v_round          int;
  v_i              int;
  v_a_idx          int;
  v_b_idx          int;
  v_a_pid          uuid;
  v_b_pid          uuid;
  v_name           text;
  v_created_by     uuid;   -- PER-TOURNAMENT
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, format, pool_phase_config, display_name, created_by
    INTO v_status, v_format, v_pool_config, v_name, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'registration_closed' THEN
    RAISE EXCEPTION 'tournament must be in status registration_closed'
      USING ERRCODE = '22023';
  END IF;
  IF v_format NOT IN (
       'round_robin','swiss','schoch',
       'round_robin_then_ko','schoch_then_ko','swiss_then_ko') THEN
    RAISE EXCEPTION 'format not yet supported' USING ERRCODE = '0A000';
  END IF;

  -- ---- Hybrid (*_then_ko): delegate the pool phase ------------------
  IF v_format IN ('round_robin_then_ko','schoch_then_ko','swiss_then_ko') THEN
    IF v_pool_config IS NULL OR jsonb_typeof(v_pool_config) <> 'object' THEN
      RAISE EXCEPTION 'pool_phase_config required for hybrid format'
        USING ERRCODE = '22023';
    END IF;

    PERFORM public.tournament_start_pool_phase(p_tournament_id, v_pool_config);

    INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'started',
        v_caller,
        jsonb_build_object('format', v_format, 'phase', 'pool'));
    RETURN;
  END IF;

  -- ---- Non-hybrid formats: confirmed-participant precondition -------
  SELECT count(*) INTO v_confirmed
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status = 'confirmed';

  IF v_confirmed < 2 THEN
    RAISE EXCEPTION 'at least 2 confirmed participants required'
      USING ERRCODE = '22023';
  END IF;

  CREATE TEMP TABLE _tstart_slots (
    slot_idx int PRIMARY KEY,
    participant_id uuid NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _tstart_slots(slot_idx, participant_id)
  SELECT row_number() OVER (ORDER BY p.registered_at, p.id), p.id
    FROM public.tournament_participants p
    WHERE p.tournament_id = p_tournament_id
      AND p.registration_status = 'confirmed';

  UPDATE public.tournament_participants p
    SET seed = s.slot_idx
    FROM _tstart_slots s
    WHERE p.id = s.participant_id;

  -- ---- swiss / schoch: materialise ROUND 1 only ---------------------
  IF v_format IN ('swiss','schoch') THEN
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        participant_a, participant_b, pitch_number, status)
    SELECT
      p_tournament_id,
      1::smallint,
      (((s.slot_idx - 1) / 2) + 1)::smallint,
      s.participant_id,
      part.participant_id,
      1,
      'scheduled'
    FROM _tstart_slots s
    LEFT JOIN _tstart_slots part
      ON part.slot_idx = s.slot_idx + 1
    WHERE (s.slot_idx % 2) = 1;

    GET DIAGNOSTICS v_match_count = ROW_COUNT;

    DROP TABLE _tstart_slots;

    PERFORM public._tournament_assign_pitches(p_tournament_id, 1::smallint);

    UPDATE public.tournaments
      SET status = 'live', started_at = now()
      WHERE id = p_tournament_id;

    INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'started',
        v_caller,
        jsonb_build_object(
          'format',      v_format,
          'round_count', 1,
          'match_count', v_match_count));

    PERFORM public._tournament_notify_participants(
      p_tournament_id,
      'tournament_started',
      'Turnier gestartet',
      'Turnier "' || coalesce(v_name, '') || '" ist gestartet — dein Platz ist da, leg los!',
      jsonb_build_object('tournament_id', p_tournament_id, 'format', v_format));
    RETURN;
  END IF;

  -- ---- round_robin: original circle-rotation materialisation --------
  IF (v_confirmed % 2) = 1 THEN
    v_slot_count := v_confirmed + 1;
    INSERT INTO _tstart_slots(slot_idx, participant_id) VALUES (v_slot_count, NULL);
  ELSE
    v_slot_count := v_confirmed;
  END IF;

  v_round_count := v_slot_count - 1;

  CREATE TEMP TABLE _tstart_ring (
    pos int PRIMARY KEY,
    participant_id uuid NULL
  ) ON COMMIT DROP;

  INSERT INTO _tstart_ring(pos, participant_id)
    SELECT slot_idx, participant_id FROM _tstart_slots;

  FOR v_round IN 1..v_round_count LOOP
    FOR v_i IN 0..((v_slot_count / 2) - 1) LOOP
      v_a_idx := v_i + 1;
      v_b_idx := v_slot_count - v_i;

      SELECT participant_id INTO v_a_pid FROM _tstart_ring WHERE pos = v_a_idx;
      SELECT participant_id INTO v_b_pid FROM _tstart_ring WHERE pos = v_b_idx;

      IF v_a_pid IS NULL AND v_b_pid IS NULL THEN
        CONTINUE;
      END IF;
      IF v_a_pid IS NULL THEN
        v_a_pid := v_b_pid;
        v_b_pid := NULL;
      END IF;

      INSERT INTO public.tournament_matches(
          tournament_id, round_number, match_number_in_round,
          participant_a, participant_b, pitch_number, status)
        VALUES (
          p_tournament_id, v_round::smallint, (v_i + 1)::smallint,
          v_a_pid, v_b_pid, 1, 'scheduled');

      v_match_count := v_match_count + 1;
    END LOOP;

    PERFORM public._tournament_assign_pitches(p_tournament_id, v_round::smallint);

    UPDATE _tstart_ring
      SET pos = CASE
                  WHEN pos = 1 THEN 1
                  WHEN pos = v_slot_count THEN 2
                  ELSE pos + 1
                END;
  END LOOP;

  DROP TABLE _tstart_ring;
  DROP TABLE _tstart_slots;

  UPDATE public.tournaments
    SET status = 'live', started_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'started',
      v_caller,
      jsonb_build_object(
        'format',      v_format,
        'round_count', v_round_count,
        'match_count', v_match_count));

  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_started',
    'Turnier gestartet',
    'Turnier "' || coalesce(v_name, '') || '" ist gestartet — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'format', v_format));
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start(uuid) TO authenticated;


-- ====================================================================
-- 10. tournament_start_pool_phase — 20261201000030 §8 + per-tournament gate.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_start_pool_phase(
  p_tournament_id uuid,
  p_config        jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_creator       uuid;
  v_pools         jsonb;
  v_participants  jsonb;
  v_assignments   int := 0;
  v_match_count   int := 0;
  v_existing      int;
  v_labels        text[];
  v_name          text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, display_name INTO v_creator, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF v_creator IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_existing
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase = 'group';
  IF v_existing > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: pool phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  SELECT coalesce(jsonb_agg(to_jsonb(id::text)
                            ORDER BY registered_at ASC, id ASC),
                  '[]'::jsonb)
    INTO v_participants
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status = 'confirmed';

  IF jsonb_array_length(v_participants) < 2 THEN
    RAISE EXCEPTION 'INVALID_POOL_CONFIG: at least 2 confirmed participants required'
      USING ERRCODE = '22023';
  END IF;

  v_pools := public._tournament_compute_pools(v_participants, p_config);

  WITH assignments AS (
    SELECT (elem ->> 'participant_id')::uuid AS pid,
           (elem ->> 'group_label')          AS lbl
      FROM jsonb_array_elements(v_pools) AS elem
  )
  UPDATE public.tournament_participants tp
     SET group_label = a.lbl
    FROM assignments a
   WHERE tp.id = a.pid
     AND tp.tournament_id = p_tournament_id;
  GET DIAGNOSTICS v_assignments = ROW_COUNT;

  SELECT array_agg(DISTINCT (elem ->> 'group_label') ORDER BY (elem ->> 'group_label'))
    INTO v_labels
    FROM jsonb_array_elements(v_pools) AS elem;

  WITH members AS (
    SELECT (elem ->> 'participant_id')::uuid AS pid,
           (elem ->> 'group_label')          AS lbl,
           (elem ->> 'group_position')::int  AS pos
      FROM jsonb_array_elements(v_pools) AS elem
  ),
  pairs AS (
    SELECT m1.lbl, m1.pid AS pid_a, m2.pid AS pid_b,
           m1.pos AS pos_a, m2.pos AS pos_b,
           row_number() OVER (
             PARTITION BY m1.lbl
             ORDER BY m1.pos, m2.pos
           ) AS pair_no
      FROM members m1
      JOIN members m2 ON m1.lbl = m2.lbl AND m1.pos < m2.pos
  )
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b,
      phase, group_label, status, pitch_number)
  SELECT p_tournament_id,
         1::smallint,
         pair_no::smallint,
         pid_a, pid_b,
         'group',
         lbl,
         'scheduled',
         1
    FROM pairs;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  PERFORM public._tournament_assign_pitches(p_tournament_id, 1::smallint);

  UPDATE public.tournaments
     SET status     = 'live',
         started_at = coalesce(started_at, now())
   WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'pool_phase_started',
      v_caller,
      jsonb_build_object(
        'group_count',           coalesce(array_length(v_labels, 1), 0),
        'assignments',           v_assignments,
        'match_count',           v_match_count,
        'config',                p_config));

  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_started',
    'Turnier gestartet',
    'Turnier "' || coalesce(v_name, '') || '" ist gestartet — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'phase', 'pool'));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'group_count',   coalesce(array_length(v_labels, 1), 0),
    'assignments',   v_assignments,
    'match_count',   v_match_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start_pool_phase(uuid, jsonb)
  TO authenticated;


-- ====================================================================
-- 11. tournament_pair_round — 20261201000030 §9 + per-tournament gate.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_pair_round(
  p_tournament_id uuid,
  p_strategy      text,
  p_pairings      jsonb DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_creator       uuid;
  v_status        text;
  v_next_round    int;
  v_inserted      int := 0;
  v_current_round int;
  v_open_count    int;
  v_name          text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, status, display_name INTO v_creator, v_status, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'live' THEN
    RAISE EXCEPTION 'tournament must be in status live' USING ERRCODE = '22023';
  END IF;

  IF p_strategy IS DISTINCT FROM 'swiss_system' OR p_pairings IS NULL THEN
    RETURN;
  END IF;

  SELECT max(round_number) INTO v_current_round
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id;

  IF v_current_round IS NOT NULL THEN
    SELECT count(*) INTO v_open_count
      FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND round_number  = v_current_round
        AND status NOT IN ('finalized','overridden','voided');

    IF v_open_count > 0 THEN
      RAISE EXCEPTION
        'round_not_complete: round % still has % open match(es); finalize them before pairing the next round',
        v_current_round, v_open_count
        USING ERRCODE = '22023';
    END IF;
  END IF;

  PERFORM public.validate_swiss_pairing(p_tournament_id, p_pairings);

  SELECT coalesce(max(round_number), 0) + 1
    INTO v_next_round
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id;

  WITH ins AS (
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        participant_a, participant_b, pitch_number, status)
    SELECT
      p_tournament_id,
      v_next_round::smallint,
      (row_number() OVER ())::smallint,
      (elem ->> 'participant_a')::uuid,
      NULLIF(elem ->> 'participant_b','')::uuid,
      1,
      'scheduled'
    FROM jsonb_array_elements(p_pairings) AS elem
    RETURNING 1
  )
  SELECT count(*) INTO v_inserted FROM ins;

  PERFORM public._tournament_assign_pitches(p_tournament_id, v_next_round::smallint);

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'swiss_round_paired',
      v_caller,
      jsonb_build_object(
        'round_number', v_next_round,
        'match_count',  v_inserted,
        'strategy',     p_strategy
      )
    );

  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_round',
    'Neue Runde',
    'Turnier "' || coalesce(v_name, '') || '": Runde ' || v_next_round
      || ' — dein Platz ist da, leg los!',
    jsonb_build_object(
      'tournament_id', p_tournament_id,
      'round_number',  v_next_round));
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_pair_round(uuid, text, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_pair_round(uuid, text, jsonb) TO authenticated;


-- ====================================================================
-- 12. tournament_start_ko_phase — 20261201000030 §10 + per-tournament gate.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_start_ko_phase(
  p_tournament_id uuid,
  p_ko_config     jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller            uuid;
  v_creator           uuid;
  v_with_third_place  boolean;
  v_qualifier_count   int;
  v_incomplete        uuid[];
  v_ko_exists         int;
  v_has_pool_phase    boolean;
  v_seeds_jsonb       jsonb;
  v_match_count       int := 0;
  v_bye_count         int := 0;
  v_group_label       text;
  v_top_n             int;
  v_cut_result        jsonb;
  v_conflict_ids      jsonb := '[]'::jsonb;
  v_override_ids      uuid[];
  v_pool_count        int;
  v_bracket_type      text;
  v_with_reset        boolean;
  v_round             smallint;
  v_name              text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, bracket_type,
         coalesce((ko_config ->> 'with_bracket_reset')::boolean, true),
         display_name
    INTO v_creator, v_bracket_type, v_with_reset, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF v_creator IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  IF p_ko_config IS NULL OR jsonb_typeof(p_ko_config) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: ko_config must be a JSON object'
      USING ERRCODE = '22023';
  END IF;
  v_with_third_place := coalesce(
    (p_ko_config ->> 'with_third_place_playoff')::boolean, false);
  v_qualifier_count := coalesce((p_ko_config ->> 'qualifier_count')::int, 0);
  IF v_qualifier_count < 2 OR v_qualifier_count > 64 THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count must be in [2, 64]'
      USING ERRCODE = '22023';
  END IF;

  IF v_bracket_type = 'double_elimination' THEN
    v_with_reset := coalesce(
      (p_ko_config ->> 'with_bracket_reset')::boolean, v_with_reset);
    IF v_with_third_place THEN
      RAISE EXCEPTION 'INVALID_KO_CONFIG: with_third_place_playoff is not allowed for double_elimination'
        USING ERRCODE = '22023';
    END IF;
  END IF;

  SELECT count(*) INTO v_ko_exists
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','third_place','final',
                    'wb','lb','grand_final','grand_final_reset');
  IF v_ko_exists > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: ko phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  SELECT coalesce(array_agg(id ORDER BY id), ARRAY[]::uuid[])
    INTO v_incomplete
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase = 'group'
      AND status NOT IN ('finalized','overridden','voided');
  IF array_length(v_incomplete, 1) IS NOT NULL THEN
    RAISE EXCEPTION 'PHASE_NOT_COMPLETE: % group match(es) not terminal: %',
      array_length(v_incomplete, 1), v_incomplete
      USING ERRCODE = '22023';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL
  ) INTO v_has_pool_phase;

  IF v_has_pool_phase THEN
    SELECT coalesce(array_agg(participant_id), ARRAY[]::uuid[])
      INTO v_override_ids
      FROM public.tournament_seeding_overrides
     WHERE tournament_id = p_tournament_id;

    SELECT count(DISTINCT group_label) INTO v_pool_count
      FROM public.tournament_participants
     WHERE tournament_id = p_tournament_id
       AND group_label IS NOT NULL;
    v_top_n := greatest(1, ((v_qualifier_count + v_pool_count - 1) / v_pool_count));

    CREATE TEMP TABLE IF NOT EXISTS _tmp_pool_cuts (
      group_label text,
      rank_in_pool int,
      participant_id uuid
    ) ON COMMIT DROP;
    TRUNCATE _tmp_pool_cuts;

    FOR v_group_label IN
      SELECT DISTINCT group_label
        FROM public.tournament_participants
       WHERE tournament_id = p_tournament_id
         AND group_label IS NOT NULL
       ORDER BY 1
    LOOP
      v_cut_result := public._tournament_compute_pool_cut(
        p_tournament_id, v_group_label, v_top_n);

      IF coalesce((v_cut_result ->> 'tie_resolution_needed')::boolean, false) THEN
        v_conflict_ids := v_conflict_ids
          || coalesce(v_cut_result -> 'conflicting_participants', '[]'::jsonb);
      END IF;

      INSERT INTO _tmp_pool_cuts(group_label, rank_in_pool, participant_id)
      SELECT v_group_label,
             (ord)::int,
             (val #>> '{}')::uuid
        FROM jsonb_array_elements(v_cut_result -> 'qualifiers')
             WITH ORDINALITY AS t(val, ord);
    END LOOP;

    IF jsonb_array_length(v_conflict_ids) > 0 THEN
      SELECT coalesce(jsonb_agg(elem ORDER BY elem), '[]'::jsonb)
        INTO v_conflict_ids
        FROM (
          SELECT DISTINCT elem
            FROM jsonb_array_elements_text(v_conflict_ids) AS elem
           WHERE (elem)::uuid <> ALL (v_override_ids)
        ) sub;

      IF jsonb_array_length(v_conflict_ids) > 0 THEN
        RAISE EXCEPTION 'TIEBREAKER_NEEDS_RESOLUTION'
          USING ERRCODE = 'P0001',
                DETAIL = jsonb_build_object(
                  'conflicting_participants', v_conflict_ids)::text;
      END IF;
    END IF;

    WITH labels AS (
      SELECT group_label,
             dense_rank() OVER (ORDER BY group_label) AS label_idx
        FROM (SELECT DISTINCT group_label FROM _tmp_pool_cuts) g
    ),
    base AS (
      SELECT c.participant_id,
             (c.rank_in_pool - 1) * 1000 + l.label_idx AS interleave_seed
        FROM _tmp_pool_cuts c
        JOIN labels l USING (group_label)
    ),
    overrides AS (
      SELECT participant_id, seed_override
        FROM public.tournament_seeding_overrides
       WHERE tournament_id = p_tournament_id
    ),
    combined AS (
      SELECT b.participant_id,
             coalesce(o.seed_override::numeric,
                      b.interleave_seed::numeric + 1000000) AS effective_seed,
             b.interleave_seed
        FROM base b
        LEFT JOIN overrides o USING (participant_id)
    ),
    seeded AS (
      SELECT participant_id,
             row_number() OVER (ORDER BY effective_seed, interleave_seed) AS final_seed
        FROM combined
    )
    SELECT coalesce(jsonb_agg(to_jsonb(participant_id::text) ORDER BY final_seed), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM seeded
     WHERE final_seed <= v_qualifier_count;

  ELSE
    WITH stats AS (
      SELECT p.id AS participant_id,
             p.registered_at,
             coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id THEN m.final_score_a - m.final_score_b
                    WHEN m.participant_b = p.id THEN m.final_score_b - m.final_score_a
                    ELSE 0 END), 0) AS kubb_diff
        FROM public.tournament_participants p
        LEFT JOIN public.tournament_matches m
          ON m.tournament_id = p.tournament_id
         AND m.phase = 'group'
         AND m.status IN ('finalized','overridden')
         AND (m.participant_a = p.id OR m.participant_b = p.id)
       WHERE p.tournament_id = p_tournament_id
         AND p.registration_status = 'confirmed'
       GROUP BY p.id, p.registered_at
    ),
    ranked AS (
      SELECT participant_id,
             row_number() OVER (
               ORDER BY wins DESC, kubb_diff DESC, registered_at ASC, participant_id ASC
             ) AS auto_seed
        FROM stats
    ),
    overrides AS (
      SELECT participant_id, seed_override
        FROM public.tournament_seeding_overrides
       WHERE tournament_id = p_tournament_id
    ),
    combined AS (
      SELECT r.participant_id,
             coalesce(o.seed_override::numeric,
                      r.auto_seed::numeric + 1000) AS effective_seed,
             r.auto_seed
        FROM ranked r
        LEFT JOIN overrides o USING (participant_id)
    ),
    seeded AS (
      SELECT participant_id,
             row_number() OVER (ORDER BY effective_seed, auto_seed) AS final_seed
        FROM combined
    )
    SELECT coalesce(jsonb_agg(to_jsonb(participant_id::text) ORDER BY final_seed), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM seeded
     WHERE final_seed <= v_qualifier_count;
  END IF;

  IF jsonb_array_length(v_seeds_jsonb) < v_qualifier_count THEN
    RAISE EXCEPTION 'INVALID_KO_CONFIG: qualifier_count % exceeds confirmed participants',
      v_qualifier_count USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournaments
    SET ko_config = p_ko_config
    WHERE id = p_tournament_id;

  IF v_bracket_type = 'double_elimination' THEN
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           b.round_number::smallint,
           b.bracket_position::smallint,
           b.bracket_position,
           b.participant_a,
           b.participant_b,
           b.phase,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END
      FROM public._tournament_compute_de_bracket(v_seeds_jsonb, v_with_reset) b;
  ELSE
    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           b.round_number::smallint,
           b.bracket_position::smallint,
           b.bracket_position,
           b.participant_a,
           b.participant_b,
           b.phase,
           CASE WHEN b.is_bye_pairing THEN 'finalized' ELSE 'scheduled' END,
           CASE WHEN b.is_bye_pairing
                THEN coalesce(b.participant_a, b.participant_b) END,
           1,
           CASE WHEN b.is_bye_pairing THEN now() END
      FROM public._tournament_compute_ko_bracket(v_seeds_jsonb, v_with_third_place) b;
  END IF;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  FOR v_round IN
    SELECT DISTINCT round_number
      FROM public.tournament_matches
     WHERE tournament_id = p_tournament_id
       AND phase IN ('ko','third_place','final',
                     'wb','lb','grand_final','grand_final_reset')
     ORDER BY round_number
  LOOP
    PERFORM public._tournament_assign_pitches(p_tournament_id, v_round);
  END LOOP;

  SELECT count(*) INTO v_bye_count
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','final','wb','lb')
      AND status = 'finalized';

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'ko_phase_started',
      v_caller,
      jsonb_build_object(
        'qualifier_count',          v_qualifier_count,
        'with_third_place_playoff', v_with_third_place,
        'bracket_type',             v_bracket_type,
        'with_bracket_reset',       v_with_reset,
        'match_count',              v_match_count,
        'bye_count',                v_bye_count,
        'pool_phase_present',       v_has_pool_phase,
        'seeds',                    v_seeds_jsonb));

  PERFORM public._tournament_notify_participants(
    p_tournament_id,
    'tournament_round',
    'Neue Runde',
    'Turnier "' || coalesce(v_name, '') || '": K.-o.-Phase — dein Platz ist da, leg los!',
    jsonb_build_object('tournament_id', p_tournament_id, 'phase', 'ko'));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'match_count',   v_match_count,
    'bye_count',     v_bye_count,
    'pool_phase',    v_has_pool_phase,
    'bracket_type',  v_bracket_type);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start_ko_phase(uuid, jsonb)
  TO authenticated;
