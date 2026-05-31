-- Tournament feature — P6 Phase 1a: persist the setup fields on create.
--
-- Extends `tournament_create` with an 8th `p_setup jsonb` parameter
-- (default '{}') that carries the P6 header fields added in
-- 20261001000001. The previous 7-arg body is otherwise preserved. The
-- parameter is defaulted so existing 7-arg callers keep working; the
-- Flutter caller now passes `p_setup` populated from
-- `TournamentConfigDraft.toSetupConfig()`.
--
-- `scoring` was hard-coded to 'ekc' in M1; it is now read from
-- `p_setup.scoring` (default 'ekc') so the organiser can pick the
-- classic system. Array and JSONB columns fall back to the table
-- defaults when the corresponding key is absent. Column CHECK
-- constraints (payment_methods / league_categories subset, fee >= 0)
-- enforce validity — no need to re-validate here.

-- The signature changes (extra parameter), so drop the old function
-- first; its GRANT is dropped with it and re-issued below.
DROP FUNCTION IF EXISTS public.tournament_create(
  text, int, int, int, text, jsonb, text[]);

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

  INSERT INTO public.tournaments(
      created_by, display_name, team_size, min_participants, max_participants,
      format, scoring, match_format, tiebreaker_order, status,
      -- P6 setup fields
      location, venue_address, event_starts_at, checkin_until,
      registration_closes_at, weather_note, info_food, info_travel,
      info_accommodation, contact_name, contact_phone, entry_fee_cents,
      currency, payment_methods, rules_pdf_url, site_map_pdf_url,
      league_categories, rule_variants, ko_match_format, pitch_plan,
      mighty_finisher_quali, consolation_bracket)
    VALUES (
      v_caller, p_display_name, p_team_size::smallint,
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
      v_setup->'pitch_plan',
      v_setup->'mighty_finisher_quali',
      v_setup->'consolation_bracket')
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
