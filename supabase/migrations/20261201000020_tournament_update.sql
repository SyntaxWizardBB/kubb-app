-- Tournament feature — P7: edit a tournament after publish.
--
-- USER SPEC: organiser / club-admin must be able to edit the tournament
-- details AFTER publishing (and start it). This migration adds the WRITE
-- path that was missing: a `tournament_update` SECURITY DEFINER RPC that
-- mutates the same header + P6 setup columns `tournament_create` writes.
--
-- Authorisation: the creator only. There is NO `tournaments.club_id`
-- link in the schema, so a per-tournament "club admin may manage" rule
-- cannot be expressed safely at the DB level today (it would let an
-- unrelated club admin edit any tournament). Every existing lifecycle
-- RPC (publish/open/close/start/finalize/abort) already hard-gates on
-- `created_by = v_caller`; this RPC matches that contract so the edit
-- capability lines up 1:1 with who can already drive the lifecycle. When
-- a `club_id` FK + a `tournament_caller_can_manage(...)` helper are added
-- later, only the single authorisation check below needs to change.
--
-- Status gate: edits are allowed ONLY while the tournament is pre-start
-- (draft / published / registration_open / registration_closed). Once it
-- goes live (and for finalized / aborted) the structure is frozen — the
-- bracket / schedule already exist and must not shift under players.
--
-- Editable columns mirror `tournament_create` (20261001000002): the M1
-- header (display_name, sizes, format, scoring, match_format,
-- tiebreaker_order) PLUS every P6 setup column incl. ko_round_formats.
-- The lifecycle timestamps, created_by, created_at and status are NOT
-- touched here — those flow through the lifecycle RPCs.

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
  v_caller  uuid;
  v_status  text;
  v_scoring text;
  v_setup   jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Authorise + lock the row. Creator-only, matching the lifecycle RPCs.
  SELECT status INTO v_status
    FROM public.tournaments
    WHERE id = p_tournament_id AND created_by = v_caller
    FOR UPDATE;

  IF v_status IS NULL THEN
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

  -- Same input validation as tournament_create.
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

  UPDATE public.tournaments SET
      display_name           = p_display_name,
      team_size              = p_team_size::smallint,
      min_participants       = p_min_participants::smallint,
      max_participants       = p_max_participants::smallint,
      format                 = p_format,
      scoring                = v_scoring,
      match_format           = p_match_format_config,
      tiebreaker_order       = p_tiebreaker_order,
      -- P6 setup fields (same column set as tournament_create).
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
