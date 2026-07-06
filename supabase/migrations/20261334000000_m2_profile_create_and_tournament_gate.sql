-- Auth-Redesign M2 (Block A) - profile-create RPC + tournament-create gate.
--
-- Spec docs/specs/auth-redesign-admin-onboarding-spec.md 3.1/3.2:
--   * caller_can_create_tournament(): can_found_clubs OR organizer-team role.
--   * profile_create_for_current_user(): OAuth/onboarding profile insert
--     (no early-access code; can_found_clubs starts false).
--   * tournament_create re-based (body byte-copied from the live definition
--     via pg_get_functiondef) with ONE added gate line after the auth check.
-- Additive.


CREATE OR REPLACE FUNCTION public.caller_can_create_tournament()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $fn$
  SELECT coalesce((
    SELECT up.can_found_clubs
      FROM public.user_profiles up
     WHERE up.user_id = auth.uid()
  ), false)
  OR public.organizer_team_caller_can_publish();
$fn$;

REVOKE ALL ON FUNCTION public.caller_can_create_tournament() FROM public;
GRANT EXECUTE ON FUNCTION public.caller_can_create_tournament() TO authenticated;

COMMENT ON FUNCTION public.caller_can_create_tournament() IS
  'M2: TRUE iff the caller may create a tournament - has can_found_clubs OR '
  'an active organizer-team role (owner/admin/organizer). Drives the client '
  'FAB and is enforced inside tournament_create.';


CREATE OR REPLACE FUNCTION public.profile_create_for_current_user(
  p_nickname     text,
  p_avatar_color text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $fn$
DECLARE
  v_user     uuid;
  v_nickname text;
BEGIN
  v_user := auth.uid();
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF length(p_nickname) < 3 OR length(p_nickname) > 30 THEN
    RAISE EXCEPTION 'nickname length must be between 3 and 30 chars'
      USING ERRCODE = '22023';
  END IF;
  IF p_nickname !~ '^[A-Za-z0-9_-]+$' THEN
    RAISE EXCEPTION 'nickname may only contain alphanumerics, _ and -'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.user_profiles (user_id, nickname, avatar_color, can_found_clubs)
    VALUES (v_user, p_nickname, p_avatar_color, false)
    ON CONFLICT (user_id) DO NOTHING;

  SELECT nickname INTO v_nickname
    FROM public.user_profiles WHERE user_id = v_user;

  RETURN jsonb_build_object('user_id', v_user, 'nickname', v_nickname);
END;
$fn$;

REVOKE ALL ON FUNCTION public.profile_create_for_current_user(text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.profile_create_for_current_user(text, text) TO authenticated;


-- ---- tournament_create re-based with the create gate ------------------

CREATE OR REPLACE FUNCTION public.tournament_create(p_display_name text, p_team_size integer, p_min_participants integer, p_max_participants integer, p_format text, p_match_format_config jsonb, p_tiebreaker_order text[], p_setup jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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

  -- M2: creating a tournament requires the organizer capability
  -- (can_found_clubs) OR an active organizer-team role. Defence in
  -- depth; the client FAB gates on caller_can_create_tournament() too.
  IF NOT public.caller_can_create_tournament() THEN
    RAISE EXCEPTION 'not allowed to create tournaments'
      USING ERRCODE = '42501';
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
  v_club_id := NULLIF(v_setup->>'organizer_team_id', '')::uuid;
  IF v_club_id IS NOT NULL THEN
    IF NOT EXISTS (
      SELECT 1 FROM public.team_members cm
       WHERE cm.organizer_team_id = v_club_id
         AND cm.user_id = v_caller
         AND cm.removed_at IS NULL
         AND (cm.roles && ARRAY['owner','admin','organizer']::text[])
    ) THEN
      RAISE EXCEPTION 'not authorised for the requested club'
        USING ERRCODE = '42501';
    END IF;
  END IF;

  INSERT INTO public.tournaments(
      created_by, organizer_team_id, display_name, team_size, min_participants, max_participants,
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
$function$;

GRANT EXECUTE ON FUNCTION public.tournament_create(
  text, int, int, int, text, jsonb, text[], jsonb) TO authenticated;
