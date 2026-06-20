-- Let tournament_update edit an aborted tournament (the "Bearbeiten" path).
--
-- An aborted tournament was frozen for editing. The product wants the organizer
-- to be able to re-open it in the setup wizard and save. Saving an aborted
-- tournament leaves the aborted state: status returns to
-- coalesce(pre_abort_status,'draft'), completed_at and pre_abort_status are
-- cleared (same restore tournament_reactivate does), alongside the normal
-- field update.
--
-- Base body: 20261283000000_rename_organizer_teams.sql (latest tournament_update
-- on disk). Changes vs. that body:
--   * status gate also admits 'aborted'
--   * a v_reactivate flag is set when the row was aborted
--   * the UPDATE resets status/completed_at/pre_abort_status on reactivate
-- The live-edit / structural-recompute block is unchanged and never runs for an
-- aborted row (v_is_live stays false), so no phase regeneration is triggered by
-- this path.
--
-- Authorisation (tournament_caller_can_setup) is UNCHANGED. Widening the edit
-- authority to club roles beyond owner/admin is out of scope here.

CREATE OR REPLACE FUNCTION public.tournament_update(p_tournament_id uuid, p_display_name text, p_team_size integer, p_min_participants integer, p_max_participants integer, p_format text, p_match_format_config jsonb, p_tiebreaker_order text[], p_setup jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_created_by uuid;
  v_scoring    text;
  v_setup      jsonb;
  v_club_id    uuid;   -- CLUB-LINK
  v_reactivate boolean := false;
  v_restored   text;
  -- V2-B1 live-edit / recompute state:
  v_is_live          boolean;
  -- old (stored) structural values:
  v_old_format       text;
  v_old_bracket_type text;
  v_old_ko_matchup   text;
  v_old_pool_cfg     jsonb;
  v_old_ko_cfg       jsonb;
  -- new (incoming) structural values, computed exactly like the UPDATE below:
  v_new_bracket_type text;
  v_new_ko_matchup   text;
  v_new_pool_cfg     jsonb;
  v_new_ko_cfg       jsonb;
  -- per-phase change flags:
  v_group_changed    boolean;
  v_ko_changed       boolean;
  -- phase state:
  v_grp_generated    boolean;
  v_grp_played       boolean;
  v_ko_generated     boolean;
  v_ko_played        boolean;
  -- recompute flags:
  v_recompute_group  boolean := false;
  v_recompute_ko     boolean := false;
  v_pre_audit_ids    uuid[];
  v_pre_inbox_ids    uuid[];
  v_pre_abort_status text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by,
         format, bracket_type, ko_matchup, pool_phase_config, ko_config,
         pre_abort_status
    INTO v_status, v_created_by,
         v_old_format, v_old_bracket_type, v_old_ko_matchup,
         v_old_pool_cfg, v_old_ko_cfg,
         v_pre_abort_status
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  -- Status gate: pre-start statuses, 'live' AND 'aborted' may be edited.
  -- 'finalized' stays frozen. Editing an aborted tournament leaves the
  -- aborted state (status returns to its pre-abort value below).
  IF v_status NOT IN (
       'draft','published','registration_open','registration_closed',
       'live','aborted') THEN
    RAISE EXCEPTION 'tournament can only be edited before it is finalized'
      USING ERRCODE = '22023', HINT = 'TOURNAMENT_LOCKED';
  END IF;

  v_reactivate := (v_status = 'aborted');
  v_restored   := coalesce(v_pre_abort_status, 'draft');
  v_is_live    := (v_status = 'live');

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

  v_club_id := NULLIF(v_setup->>'organizer_team_id', '')::uuid;
  IF v_club_id IS NOT NULL
     AND v_club_id IS DISTINCT FROM (
       SELECT organizer_team_id FROM public.tournaments WHERE id = p_tournament_id) THEN
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

  IF v_is_live THEN
    v_new_bracket_type := coalesce(v_setup->>'bracket_type', 'single_elimination');
    v_new_ko_matchup   := coalesce(v_setup->>'ko_matchup', 'seed_high_vs_low');
    v_new_pool_cfg     := v_setup->'pool_phase_config';
    v_new_ko_cfg       := v_setup->'ko_config';

    IF p_format IS DISTINCT FROM v_old_format
       AND public._tournament_format_family(p_format)
           IS DISTINCT FROM public._tournament_format_family(v_old_format) THEN
      RAISE EXCEPTION
        'Formatwechsel nicht moeglich, das gewaehlte Format passt nicht zur '
        'laufenden Turnierstruktur'
        USING ERRCODE = '22023', HINT = 'STRUCTURE_LOCKED';
    END IF;

    v_group_changed :=
         (p_format        IS DISTINCT FROM v_old_format)
      OR (v_new_pool_cfg  IS DISTINCT FROM v_old_pool_cfg);

    v_ko_changed :=
         (p_format          IS DISTINCT FROM v_old_format)
      OR (v_new_bracket_type IS DISTINCT FROM v_old_bracket_type)
      OR (v_new_ko_matchup   IS DISTINCT FROM v_old_ko_matchup)
      OR (v_new_ko_cfg       IS DISTINCT FROM v_old_ko_cfg);

    IF v_group_changed THEN
      SELECT generated, has_played
        INTO v_grp_generated, v_grp_played
        FROM public._tournament_phase_state(p_tournament_id, 'group');
      IF v_grp_played THEN
        RAISE EXCEPTION
          'Strukturaenderung nicht moeglich, Phase laeuft bereits'
          USING ERRCODE = '22023', HINT = 'STRUCTURE_LOCKED';
      END IF;
      IF v_grp_generated THEN
        v_recompute_group := true;
      END IF;
    END IF;

    IF v_ko_changed THEN
      SELECT generated, has_played
        INTO v_ko_generated, v_ko_played
        FROM public._tournament_phase_state(p_tournament_id, 'ko');
      IF v_ko_played THEN
        RAISE EXCEPTION
          'Strukturaenderung nicht moeglich, Phase laeuft bereits'
          USING ERRCODE = '22023', HINT = 'STRUCTURE_LOCKED';
      END IF;
      IF v_ko_generated THEN
        v_recompute_ko := true;
      END IF;
    END IF;
  END IF;

  UPDATE public.tournaments SET
      organizer_team_id                = v_club_id,
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
      ko_config              = v_setup->'ko_config',
      invite_only            = coalesce((v_setup->>'invite_only')::boolean,
                                        public.tournaments.invite_only),
      -- Leave the aborted state when an aborted tournament is edited.
      status                 = CASE WHEN v_reactivate THEN v_restored
                                    ELSE public.tournaments.status END,
      completed_at           = CASE WHEN v_reactivate THEN NULL
                                    ELSE public.tournaments.completed_at END,
      pre_abort_status       = CASE WHEN v_reactivate THEN NULL
                                    ELSE public.tournaments.pre_abort_status END
    WHERE id = p_tournament_id;

  IF v_recompute_group THEN
    DELETE FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND phase = 'group'
        AND status = 'scheduled';

    SELECT coalesce(array_agg(id), '{}')
      INTO v_pre_audit_ids
      FROM public.tournament_audit_events
      WHERE tournament_id = p_tournament_id;
    SELECT coalesce(array_agg(id), '{}')
      INTO v_pre_inbox_ids
      FROM public.user_inbox_messages
      WHERE (action_payload->>'tournament_id')::uuid = p_tournament_id;

    PERFORM public.tournament_start_pool_phase(
      p_tournament_id, coalesce(v_new_pool_cfg, '{}'::jsonb));

    DELETE FROM public.user_inbox_messages
      WHERE kind = 'tournament_started'
        AND (action_payload->>'tournament_id')::uuid = p_tournament_id
        AND NOT (id = ANY (v_pre_inbox_ids));
    UPDATE public.tournament_audit_events
      SET kind = 'phase_recomputed',
          payload = coalesce(payload, '{}'::jsonb)
            || jsonb_build_object('phase', 'group', 'recompute', true)
      WHERE tournament_id = p_tournament_id
        AND kind = 'pool_phase_started'
        AND NOT (id = ANY (v_pre_audit_ids));
  END IF;

  IF v_recompute_ko THEN
    DELETE FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND phase IN ('ko','third_place','final','wb','lb','grand_final',
                      'grand_final_reset','consolation','consolation_third_place')
        AND status = 'scheduled';

    SELECT coalesce(array_agg(id), '{}')
      INTO v_pre_audit_ids
      FROM public.tournament_audit_events
      WHERE tournament_id = p_tournament_id;
    SELECT coalesce(array_agg(id), '{}')
      INTO v_pre_inbox_ids
      FROM public.user_inbox_messages
      WHERE (action_payload->>'tournament_id')::uuid = p_tournament_id;

    PERFORM public.tournament_start_ko_phase(
      p_tournament_id, coalesce(v_new_ko_cfg, '{}'::jsonb));

    DELETE FROM public.user_inbox_messages
      WHERE kind IN ('tournament_started', 'tournament_round')
        AND (action_payload->>'tournament_id')::uuid = p_tournament_id
        AND NOT (id = ANY (v_pre_inbox_ids));
    UPDATE public.tournament_audit_events
      SET kind = 'phase_recomputed',
          payload = coalesce(payload, '{}'::jsonb)
            || jsonb_build_object('phase', 'ko', 'recompute', true)
      WHERE tournament_id = p_tournament_id
        AND kind = 'ko_phase_started'
        AND NOT (id = ANY (v_pre_audit_ids));
  END IF;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      CASE WHEN v_reactivate THEN 'reactivated' ELSE 'updated' END,
      v_caller,
      jsonb_build_object(
        'display_name',     p_display_name,
        'team_size',        p_team_size,
        'min_participants', p_min_participants,
        'max_participants', p_max_participants,
        'format',           p_format,
        'scoring',          v_scoring,
        'league_categories', coalesce(v_setup->'league_categories', '[]'::jsonb),
        'live_edit',         v_is_live,
        'recompute_group',   v_recompute_group,
        'recompute_ko',      v_recompute_ko,
        'reactivated',       v_reactivate,
        'restored_status',   CASE WHEN v_reactivate THEN v_restored ELSE NULL END
      )
    );

  RETURN jsonb_build_object(
    'tournament_id',   p_tournament_id,
    'recompute_group', v_recompute_group,
    'recompute_ko',    v_recompute_ko,
    'reactivated',     v_reactivate);
END;
$function$;
