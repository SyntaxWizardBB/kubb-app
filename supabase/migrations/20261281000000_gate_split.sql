-- P2-S (ADR-0032 / docs/plans/permissions-organizer-teams PLAN) — gate split.
--
-- Splits the single tournament manage gate into two gates:
--   * tournament_caller_can_setup(uuid)      — creator OR active club
--     membership with a role in {owner, admin}. Structural / pre-live
--     authority (publish, start, seeding, finalize, abort, invites, ...).
--     A club 'referee' does NOT pass this gate.
--   * tournament_caller_can_administer(uuid) — creator OR active club
--     membership with a role in {owner, admin, referee}. Live intervention
--     authority (override, forfeit, pause/resume, skip, check-in, list).
--
-- Classification rule (PLAN P2): structure-changing / pre-live = setup;
-- live intervention (score/time/check-in) = administer.
-- Locked decision OE-2: tournament_start is SETUP (a referee does not start).
--
-- PURELY ADDITIVE: only CREATE OR REPLACE FUNCTION, REVOKE/GRANT and
-- COMMENT ON FUNCTION statements. No table/column/policy is altered or
-- dropped, no DELETE/TRUNCATE.
--
-- Stale-body rule (PLAN, verified via
--   grep -rln "FUNCTION public.<fn>(" supabase/migrations/ | sort | tail -1):
-- every CREATE OR REPLACE below is based on the genuine latest on-disk body;
-- the ONLY change per function is the gate call (can_manage -> can_setup or
-- can_administer; for the two organizer-override RPCs the creator-only check
-- block -> can_administer). Latest-body anchors:
--   * gate base (both new gates)        20261255000000_tournament_administrable_gate_and_list.sql
--   * tournament_update                 20261277000000_tournament_list_and_rls_invite.sql
--   * tournament_publish                20261201000040_tournament_open_registration_model.sql
--   * tournament_open/close_registration, tournament_finalize, tournament_abort
--                                       20261201000032_tournament_per_tournament_manage_gate.sql
--   * tournament_start, tournament_start_pool_phase, tournament_pair_round,
--     tournament_start_ko_phase         20261261000000_round_publish_notify.sql
--   * tournament_detect_shootouts       20261202000000_tournament_shootout_server.sql
--   * tournament_start_stage_graph      20261249000000_start_stage_graph_multi_root.sql
--   * apply_stage_graph_template        20261230000000_tournament_stage_graph_templates.sql
--   * tournament_invite_user, tournament_revoke_invitation
--                                       20261276000000_tournament_invitation_rpcs.sql
--   * tournament_organizer_override     20261250000000_organizer_override_scheduled.sql
--   * tournament_organizer_override_pairing
--                                       20260601000013_rpc_tournament_organizer_override_pairing.sql
--   * tournament_match_forfeit          20261267000000_forfeit_caller_can_manage.sql
--   * tournament_pause, tournament_resume
--                                       20261262000000_pause_resume_notify.sql
--   * tournament_skip_forward, tournament_skip_back
--                                       20261256000000_tournament_schedule_control_rpcs.sql
--   * tournament_checkin_participant, tournament_undo_checkin
--                                       20261265000000_tournament_participant_checkin.sql
--   * tournament_list_administrable     20261255000000_tournament_administrable_gate_and_list.sql
-- Note: function headers below are pg_get_functiondef-normalized (e.g.
-- "SET search_path TO 'public', 'auth'"); the bodies between the dollar
-- quotes are byte-identical to the anchor bodies except for the gate call.
-- Pre-existing (German) comments inside copied legacy bodies are preserved
-- verbatim to keep the stale-body diff minimal.
--
-- tournament_caller_can_manage is re-defined at the end as a DEPRECATED
-- pure alias of tournament_caller_can_administer (fail-safe for missed
-- call-sites, locked decision OE-4).


-- ====================================================================
-- PART A — the two new gates (base: gate body 20261255000000).
-- Only change vs. that body: function name + role array
--   can_setup:      ARRAY['owner','admin','organizer','referee'] -> ARRAY['owner','admin']
--   can_administer: ARRAY['owner','admin','organizer','referee'] -> ARRAY['owner','admin','referee']
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_caller_can_setup(p_tournament_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.tournaments t
     WHERE t.id = p_tournament_id
       AND (
         -- Creator: unchanged behaviour.
         t.created_by = auth.uid()
         OR
         -- Club owner/admin/organizer of THIS tournament's club.
         (t.club_id IS NOT NULL AND EXISTS (
            SELECT 1
              FROM public.club_memberships cm
             WHERE cm.club_id = t.club_id
               AND cm.user_id = auth.uid()
               AND cm.removed_at IS NULL
               AND (cm.roles && ARRAY['owner','admin']::text[])
         ))
       )
  );
$function$
;

REVOKE ALL ON FUNCTION public.tournament_caller_can_setup(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_caller_can_setup(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_caller_can_setup(uuid) IS
  'P2-S gate split (ADR-0032): structural / pre-live tournament authority. '
  'True when the caller is created_by OR an active owner/admin of the '
  'tournament''s club_id. A club referee does NOT pass. NULL club_id => '
  'creator only. Base body: 20261255000000.';

CREATE OR REPLACE FUNCTION public.tournament_caller_can_administer(p_tournament_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  SELECT EXISTS (
    SELECT 1
      FROM public.tournaments t
     WHERE t.id = p_tournament_id
       AND (
         -- Creator: unchanged behaviour.
         t.created_by = auth.uid()
         OR
         -- Club owner/admin/organizer of THIS tournament's club.
         (t.club_id IS NOT NULL AND EXISTS (
            SELECT 1
              FROM public.club_memberships cm
             WHERE cm.club_id = t.club_id
               AND cm.user_id = auth.uid()
               AND cm.removed_at IS NULL
               AND (cm.roles && ARRAY['owner','admin','referee']::text[])
         ))
       )
  );
$function$
;

REVOKE ALL ON FUNCTION public.tournament_caller_can_administer(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_caller_can_administer(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_caller_can_administer(uuid) IS
  'P2-S gate split (ADR-0032): live-intervention tournament authority. True '
  'when the caller is created_by OR an active owner/admin/referee of the '
  'tournament''s club_id. NULL club_id => creator only. Base body: '
  '20261255000000.';


-- ====================================================================
-- PART B — SETUP call-sites: gate can_manage -> can_setup.
-- Structure-changing / pre-live RPCs. Each body is the latest on-disk
-- body (anchor in the header); only the gate call changed.
-- ====================================================================

-- ---- tournament_update: can_manage -> can_setup ----
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
  -- recompute side-effect suppression: snapshots of pre-existing row ids so
  -- only the generator's freshly-inserted rows are cleaned up (created_at /
  -- sent_at default to now() = transaction start, so a timestamp marker is
  -- unreliable inside one transaction — we diff by id instead).
  v_pre_audit_ids    uuid[];
  v_pre_inbox_ids    uuid[];
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by,
         format, bracket_type, ko_matchup, pool_phase_config, ko_config
    INTO v_status, v_created_by,
         v_old_format, v_old_bracket_type, v_old_ko_matchup,
         v_old_pool_cfg, v_old_ko_cfg
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the club_id.
  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  -- V2-B1 status gate: pre-start statuses AND 'live' may be edited.
  -- 'finalized' and 'aborted' stay frozen.
  IF v_status NOT IN (
       'draft','published','registration_open','registration_closed',
       'live') THEN
    RAISE EXCEPTION 'tournament can only be edited before it is finalized'
      USING ERRCODE = '22023', HINT = 'TOURNAMENT_LOCKED';
  END IF;

  v_is_live := (v_status = 'live');

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

  -- ==================================================================
  -- V2-B1 STRUCTURAL SAFETY (live only). Pre-start edits skip this block
  -- entirely and behave exactly like the 20261201000032 baseline: no
  -- phase exists yet, the UPDATE just persists everything.
  --
  -- Future-format fields (match_format, ko_match_format, ko_round_formats,
  -- ko_tiebreak_method) are NOT inspected here — they are always-allowed
  -- live and never trigger regeneration (matches read their round format
  -- at evaluation time). Always-safe fields likewise pass through.
  -- ==================================================================
  IF v_is_live THEN
    -- New structural values, mirrored from the UPDATE column expressions
    -- below so the comparison is exact.
    v_new_bracket_type := coalesce(v_setup->>'bracket_type', 'single_elimination');
    v_new_ko_matchup   := coalesce(v_setup->>'ko_matchup', 'seed_high_vs_low');
    v_new_pool_cfg     := v_setup->'pool_phase_config';
    v_new_ko_cfg       := v_setup->'ko_config';

    -- FORMAT-FAMILY consistency (live only). A live format switch must stay
    -- within the same phase family. The generators read the format implicitly
    -- (pool generator always builds a group phase; pure-KO is generated by a
    -- different path), so crossing families while a phase already exists would
    -- regenerate the WRONG kind of phase and leave an inconsistent tournament
    -- (e.g. a pure-KO format carrying group matches). Reject such a switch with
    -- a clear German message rather than blindly regenerating. Families:
    --   pool-based / hybrid (has a group phase): round_robin, schoch, swiss and
    --   their *_then_ko variants -> _tournament_format_family() = 'pool'
    --   pure KO: single_elimination -> 'ko'
    IF p_format IS DISTINCT FROM v_old_format
       AND public._tournament_format_family(p_format)
           IS DISTINCT FROM public._tournament_format_family(v_old_format) THEN
      RAISE EXCEPTION
        'Formatwechsel nicht moeglich, das gewaehlte Format passt nicht zur '
        'laufenden Turnierstruktur'
        USING ERRCODE = '22023', HINT = 'STRUCTURE_LOCKED';
    END IF;

    -- GROUP-phase structural inputs: format, pool_phase_config.
    v_group_changed :=
         (p_format        IS DISTINCT FROM v_old_format)
      OR (v_new_pool_cfg  IS DISTINCT FROM v_old_pool_cfg);

    -- KO-phase structural inputs: format, bracket_type, ko_matchup, ko_config.
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
      -- generated + fully unplayed -> safe recompute of the group phase.
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
      -- generated + fully unplayed -> safe recompute of the ko phase.
      IF v_ko_generated THEN
        v_recompute_ko := true;
      END IF;
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
      ko_config              = v_setup->'ko_config',
      invite_only            = coalesce((v_setup->>'invite_only')::boolean,
                                        public.tournaments.invite_only)
    WHERE id = p_tournament_id;

  -- ==================================================================
  -- V2-B1 RECOMPUTE (safe, unplayed-only). Reached ONLY when a structural
  -- field changed AND the affected phase is generated + fully unplayed.
  -- We delete only the 'scheduled' (unplayed) matches of that phase and
  -- re-run the EXISTING generation RPC. Finalised / played matches are
  -- never deleted (none exist in a fully-unplayed phase, but the DELETE is
  -- scoped to status 'scheduled' as defence in depth).
  --
  -- SIDE-EFFECT SUPPRESSION: the canonical generators were written for the
  -- FIRST start of a phase and, as a side effect, push a 'Turnier gestartet'
  -- inbox notification to every participant and emit a 'pool_phase_started' /
  -- 'ko_phase_started' audit event. A pure structural correction of an
  -- UNPLAYED phase must not spam participants ("the tournament already
  -- started") nor pollute the audit trail with a fake start. We must keep
  -- REUSING the generators verbatim (no new pairing logic, no signature
  -- change that would ripple into other callers), so instead we mark the
  -- transaction time before the call and, after it returns, remove exactly
  -- the inbox messages it just sent and relabel the start audit event to the
  -- dedicated 'phase_recomputed' kind. All within this transaction; on
  -- ROLLBACK nothing leaks. We diff by row id (not timestamp) because the
  -- defaults stamp now() = transaction start.
  -- ==================================================================
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

    -- Re-uses the canonical pool-phase generator with the freshly stored
    -- pool_phase_config. It re-asserts the manage gate, re-builds pools and
    -- round-1 group matches and keeps status='live'/started_at.
    PERFORM public.tournament_start_pool_phase(
      p_tournament_id, coalesce(v_new_pool_cfg, '{}'::jsonb));

    -- Suppress the generator's "started" notifications (newly inserted only).
    DELETE FROM public.user_inbox_messages
      WHERE kind = 'tournament_started'
        AND (action_payload->>'tournament_id')::uuid = p_tournament_id
        AND NOT (id = ANY (v_pre_inbox_ids));
    -- Relabel the generator's start audit event into a recompute event.
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

    -- Re-uses the canonical KO-phase generator with the freshly stored
    -- ko_config. It re-asserts the manage gate, requires the group phase to
    -- be complete (untouched here) and that no KO match exists (the unplayed
    -- bracket was just deleted), and rebuilds the bracket.
    PERFORM public.tournament_start_ko_phase(
      p_tournament_id, coalesce(v_new_ko_cfg, '{}'::jsonb));

    -- Suppress the generator's "new round / started" notifications.
    DELETE FROM public.user_inbox_messages
      WHERE kind IN ('tournament_started', 'tournament_round')
        AND (action_payload->>'tournament_id')::uuid = p_tournament_id
        AND NOT (id = ANY (v_pre_inbox_ids));
    -- Relabel the generator's start audit event into a recompute event.
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
      'updated',
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
        'recompute_ko',      v_recompute_ko
      )
    );

  RETURN jsonb_build_object(
    'tournament_id',   p_tournament_id,
    'recompute_group', v_recompute_group,
    'recompute_ko',    v_recompute_ko);
END;
$function$
;

-- ---- tournament_publish: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_publish(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'tournament must be in status draft' USING ERRCODE = '22023';
  END IF;

  -- NEW MODEL: publishing opens registration immediately (no separate
  -- manual 'Anmeldung öffnen' step). registration_opens_at is stamped now.
  UPDATE public.tournaments
    SET status                = 'registration_open',
        published_at          = now(),
        registration_opens_at = coalesce(registration_opens_at, now())
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'published', v_caller, '{}'::jsonb);
  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'registration_opened', v_caller, '{}'::jsonb);
END;
$function$
;

-- ---- tournament_start: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_start(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  -- NEW MODEL: registration is always open once published; starting
  -- implicitly closes it. Accept both open and closed states.
  IF v_status NOT IN ('registration_open','registration_closed') THEN
    RAISE EXCEPTION 'tournament must be in status registration_open or registration_closed'
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

    -- ADR-0031 A1: materialise the active round 1 schedule (phase 'group').
    PERFORM public._tournament_upsert_round_schedule(
      p_tournament_id, NULL, 1, 'group',
      (public._tournament_schedule_prelim_seconds(p_tournament_id)).match_seconds,
      (public._tournament_schedule_prelim_seconds(p_tournament_id)).break_seconds,
      NULL, now());

    -- ADR-0031 C1 (E1): per-pitch publish-notify of round 1 (phase 'group').
    -- After pitches + schedule exist; starts_at resolved inside the helper.
    PERFORM public._tournament_notify_round_per_pitch(
      p_tournament_id, 1, 'group', 'round_published',
      'Runde 1 veröffentlicht',
      'Turnier "' || coalesce(v_name, '') || '": Runde 1 ist da.');

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

    -- ADR-0031 A1 (OE-2): only the active round 1 gets a schedule row.
    IF v_round = 1 THEN
      PERFORM public._tournament_upsert_round_schedule(
        p_tournament_id, NULL, 1, 'group',
        (public._tournament_schedule_prelim_seconds(p_tournament_id)).match_seconds,
        (public._tournament_schedule_prelim_seconds(p_tournament_id)).break_seconds,
        NULL, now());

      -- ADR-0031 C1 (E1): per-pitch publish-notify of the active round 1
      -- (phase 'group'). After pitches + schedule exist for round 1.
      PERFORM public._tournament_notify_round_per_pitch(
        p_tournament_id, 1, 'group', 'round_published',
        'Runde 1 veröffentlicht',
        'Turnier "' || coalesce(v_name, '') || '": Runde 1 ist da.');
    END IF;

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
$function$
;

-- ---- tournament_open_registration: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_open_registration(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
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
$function$
;

-- ---- tournament_close_registration: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_close_registration(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
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
$function$
;

-- ---- tournament_start_pool_phase: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_start_pool_phase(p_tournament_id uuid, p_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
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

  -- ADR-0031 A1: materialise the group phase round 1 schedule.
  PERFORM public._tournament_upsert_round_schedule(
    p_tournament_id, NULL, 1, 'group',
    (public._tournament_schedule_prelim_seconds(p_tournament_id)).match_seconds,
    (public._tournament_schedule_prelim_seconds(p_tournament_id)).break_seconds,
    NULL, now());

  -- ADR-0031 C1 (E1): per-pitch publish-notify of round 1 (phase 'group').
  -- After pitches + schedule exist; starts_at resolved inside the helper.
  PERFORM public._tournament_notify_round_per_pitch(
    p_tournament_id, 1, 'group', 'round_published',
    'Runde 1 veröffentlicht',
    'Turnier "' || coalesce(v_name, '') || '": Runde 1 ist da.');

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
$function$
;

-- ---- tournament_pair_round: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_pair_round(p_tournament_id uuid, p_strategy text, p_pairings jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
  IF NOT public.tournament_caller_can_setup(p_tournament_id) THEN
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

  -- ADR-0031 A1: materialise the newly paired swiss round (phase 'group').
  PERFORM public._tournament_upsert_round_schedule(
    p_tournament_id, NULL, v_next_round, 'group',
    (public._tournament_schedule_prelim_seconds(p_tournament_id)).match_seconds,
    (public._tournament_schedule_prelim_seconds(p_tournament_id)).break_seconds,
    NULL, now());

  -- ADR-0031 C1 (E1): per-pitch publish-notify of the newly paired round
  -- (v_next_round, phase 'group'). After pitches + schedule exist.
  PERFORM public._tournament_notify_round_per_pitch(
    p_tournament_id, v_next_round, 'group', 'round_published',
    'Runde ' || v_next_round || ' veröffentlicht',
    'Turnier "' || coalesce(v_name, '') || '": Runde ' || v_next_round
      || ' ist da.');

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
$function$
;

-- ---- tournament_start_ko_phase: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_start_ko_phase(p_tournament_id uuid, p_ko_config jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
  v_round             smallint;   -- PITCH-PLAN loop variable
  v_max_round         smallint;   -- ADR-0031 A1: final-round discriminator
  v_name              text;       -- GO-LIVE-NOTIFY
  v_grp               record;     -- SHOOTOUT-GATE
  v_pending_shootouts int := 0;   -- SHOOTOUT-GATE
  v_full_order        uuid[];     -- SHOOTOUT-RESOLVE
  v_chain             text[];     -- SHOOTOUT-RESOLVE / C6
  v_so                record;     -- SHOOTOUT-RESOLVE
  v_k                 int;        -- SHOOTOUT-RESOLVE
  -- CONSOLATION (E2):
  v_cons_cfg          jsonb;      -- tournaments.consolation_bracket
  v_cons_enabled      boolean;
  v_cons_main_size    int;
  v_cons_direct_cnt   int;
  v_cons_direct_ids   jsonb := '[]'::jsonb;
  -- CF6 manual-seeding gate:
  v_seeding_mode      text;
  v_seed_override_cnt int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, bracket_type,
         coalesce((ko_config ->> 'with_bracket_reset')::boolean, true),
         display_name, consolation_bracket, tiebreaker_order
    INTO v_creator, v_bracket_type, v_with_reset, v_name, v_cons_cfg, v_chain
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
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

  v_cons_enabled := coalesce((v_cons_cfg ->> 'enabled')::boolean, false)
                    AND v_bracket_type <> 'double_elimination';

  SELECT count(*) INTO v_ko_exists
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','third_place','final',
                    'wb','lb','grand_final','grand_final_reset',
                    'consolation','consolation_third_place');
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

  -- ==================================================================
  -- CF6 manual-seeding gate. SINGLE functional addition vs the
  -- 20261204000000_p6_fix_bundle baseline. When the tournament is
  -- configured for manual seeding (ko_config.seeding_mode = 'manual'),
  -- the organizer MUST set a complete seed list before the KO can
  -- start. We treat the seeding as "set" once at least
  -- `qualifier_count` overrides exist in tournament_seeding_overrides
  -- (the seeding screen writes one row per qualifier via
  -- tournament_set_seeding). For auto seeding (or a missing
  -- discriminator = default auto) no gate fires. Position: after the
  -- 40001 idempotency guard and the 22023 phase-complete guard, before
  -- the SHOOTOUT-GATE / pool detection / bracket insert, so it only
  -- fires on a legitimate Vorrunde->KO transition. The exception is
  -- machine-readable: ERRCODE 22023 + 'seeding_required' prefix, so the
  -- client can route the organizer to the seeding screen instead of
  -- showing a raw error.
  -- ==================================================================
  v_seeding_mode := coalesce(p_ko_config ->> 'seeding_mode', 'auto');
  IF v_seeding_mode = 'manual' THEN
    SELECT count(*) INTO v_seed_override_cnt
      FROM public.tournament_seeding_overrides
      WHERE tournament_id = p_tournament_id;
    IF v_seed_override_cnt < v_qualifier_count THEN
      RAISE EXCEPTION
        'seeding_required: manual seeding must be set before KO start'
        USING ERRCODE = '22023';
    END IF;
  END IF;
  -- ==================== end CF6 manual-seeding gate =================

  -- ==================================================================
  -- SHOOTOUT-GATE (P6 D2a). VERBATIM.
  -- ==================================================================
  FOR v_grp IN
    SELECT * FROM public._tournament_detect_shootout_groups(
                     p_tournament_id, v_qualifier_count)
  LOOP
    INSERT INTO public.tournament_shootouts(
        tournament_id, start_rank, tied_participant_ids)
      VALUES (p_tournament_id, v_grp.start_rank, v_grp.participant_ids)
      ON CONFLICT (tournament_id, tie_key) DO NOTHING;

    IF FOUND THEN
      PERFORM public._tournament_notify_shootout_group(
        p_tournament_id,
        v_grp.participant_ids,
        'Shoot-Out nötig',
        'Turnier "' || coalesce(v_name, '')
          || '": Gleichstand an der Qualifikations-Grenze — tragt den '
          || 'Shoot-Out-Sieger ein.',
        jsonb_build_object(
          'tournament_id', p_tournament_id,
          'kind',          'shootout',
          'start_rank',    v_grp.start_rank,
          'tied',          to_jsonb(v_grp.participant_ids)));
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.tournament_shootouts s
       WHERE s.tournament_id = p_tournament_id
         AND s.status = 'resolved'
         AND s.tied_participant_ids @> v_grp.participant_ids
         AND s.tied_participant_ids <@ v_grp.participant_ids
    ) THEN
      v_pending_shootouts := v_pending_shootouts + 1;
    END IF;
  END LOOP;

  IF v_pending_shootouts > 0 THEN
    RAISE EXCEPTION 'SHOOTOUT_PENDING: % qualification-relevant shoot-out(s) unresolved',
      v_pending_shootouts USING ERRCODE = 'P0001';
  END IF;
  -- ==================== end SHOOTOUT-GATE ===========================

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
    -- ============================================================
    -- P6-FIX C6: chain-gated, total_points-first default seed ranking. This
    -- matches _tournament_detect_shootout_groups, SHOOTOUT-RESOLVE's v_full_order
    -- and tournament_pool_standings (the canonical order). Previously this CTE
    -- ranked "wins DESC, kubb_diff DESC" without total_points and without chain
    -- gating, so the cut line (detector) and the actual seeds could diverge.
    -- v_chain was loaded above (tiebreaker_order). registered_at/participant_id
    -- remain the deterministic ID-fallback tail, not a separating criterion.
    -- ============================================================
    WITH stats AS (
      SELECT p.id AS participant_id,
             p.registered_at,
             coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                    WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                    ELSE 0 END), 0) AS total_points,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id
                      THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                    WHEN m.participant_b = p.id
                      THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
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
               ORDER BY
                 CASE WHEN 'total_points'    = ANY(v_chain) THEN -total_points ELSE 0 END,
                 CASE WHEN 'wins'            = ANY(v_chain) THEN -wins         ELSE 0 END,
                 CASE WHEN 'kubb_difference' = ANY(v_chain) THEN -kubb_diff    ELSE 0 END,
                 registered_at ASC,
                 participant_id ASC
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

  -- ==================================================================
  -- SHOOTOUT-RESOLVE (resolveWithShootouts). VERBATIM (v_chain already loaded).
  -- ==================================================================
  IF NOT v_has_pool_phase AND EXISTS (
    SELECT 1 FROM public.tournament_shootouts
     WHERE tournament_id = p_tournament_id AND status = 'resolved'
  ) THEN
    WITH stats AS (
      SELECT p.id AS pid,
             p.registered_at,
             coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                    WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                    ELSE 0 END), 0) AS total_points,
             coalesce(sum(
               CASE WHEN m.participant_a = p.id
                      THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                    WHEN m.participant_b = p.id
                      THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
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
    )
    SELECT array_agg(pid ORDER BY rnk)
      INTO v_full_order
      FROM (
        SELECT s.pid,
               row_number() OVER (
                 ORDER BY
                   CASE WHEN 'total_points'    = ANY(v_chain) THEN -s.total_points ELSE 0 END,
                   CASE WHEN 'wins'            = ANY(v_chain) THEN -s.wins         ELSE 0 END,
                   CASE WHEN 'kubb_difference' = ANY(v_chain) THEN -s.kubb_diff    ELSE 0 END,
                   s.registered_at ASC,
                   s.pid ASC
               ) AS rnk
          FROM stats s
      ) r;

    FOR v_so IN
      SELECT start_rank, ordered_winners
        FROM public.tournament_shootouts
       WHERE tournament_id = p_tournament_id
         AND status = 'resolved'
         AND ordered_winners IS NOT NULL
    LOOP
      FOR v_k IN 1 .. array_length(v_so.ordered_winners, 1) LOOP
        v_full_order[v_so.start_rank + v_k] := v_so.ordered_winners[v_k];
      END LOOP;
    END LOOP;

    SELECT coalesce(jsonb_agg(to_jsonb(pid::text) ORDER BY ord), '[]'::jsonb)
      INTO v_seeds_jsonb
      FROM (
        SELECT pid, ord
          FROM unnest(v_full_order) WITH ORDINALITY AS t(pid, ord)
         WHERE ord <= v_qualifier_count
      ) q;
  END IF;
  -- ==================== end SHOOTOUT-RESOLVE ========================

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

  -- ==================================================================
  -- CONSOLATION-MATERIALISE (E2, ADR-0028 §1.1/§3/§4).
  -- ==================================================================
  IF v_cons_enabled THEN
    -- P6-FIX C11: honour the persisted main_bracket_size (ADR-0028 §5) when set;
    -- fall back to next_pow2(qualifier_count) (== main bracket size) otherwise.
    v_cons_main_size := coalesce((v_cons_cfg ->> 'main_bracket_size')::int, 0);
    IF v_cons_main_size < 2 THEN
      v_cons_main_size := 1;
      WHILE v_cons_main_size < v_qualifier_count LOOP
        v_cons_main_size := v_cons_main_size * 2;
      END LOOP;
    END IF;

    -- direct_count (now persisted by the wire; defensive default 0).
    v_cons_direct_cnt := greatest(0, coalesce((v_cons_cfg ->> 'direct_count')::int, 0));
    -- Direct starters: the top prelim ranks NOT already seeded into the main
    -- bracket (seeds beyond qualifier_count), best-first, capped at direct_count.
    IF v_cons_direct_cnt > 0 AND NOT v_has_pool_phase THEN
      WITH stats AS (
        SELECT p.id AS pid,
               p.registered_at,
               coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
               coalesce(sum(
                 CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                      WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                      ELSE 0 END), 0) AS total_points,
               coalesce(sum(
                 CASE WHEN m.participant_a = p.id
                        THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                      WHEN m.participant_b = p.id
                        THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
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
        SELECT pid,
               row_number() OVER (
                 ORDER BY
                   CASE WHEN 'total_points'    = ANY(v_chain) THEN -total_points ELSE 0 END,
                   CASE WHEN 'wins'            = ANY(v_chain) THEN -wins         ELSE 0 END,
                   CASE WHEN 'kubb_difference' = ANY(v_chain) THEN -kubb_diff    ELSE 0 END,
                   registered_at ASC,
                   pid ASC
               ) AS rnk
          FROM stats
      )
      SELECT coalesce(jsonb_agg(to_jsonb(pid::text) ORDER BY rnk), '[]'::jsonb)
        INTO v_cons_direct_ids
        FROM ranked
       WHERE rnk > v_qualifier_count
         AND rnk <= v_qualifier_count + v_cons_direct_cnt;
    ELSE
      v_cons_direct_ids := '[]'::jsonb;
    END IF;

    INSERT INTO public.tournament_matches(
        tournament_id, round_number, match_number_in_round,
        bracket_position, participant_a, participant_b,
        phase, status, winner_participant, pitch_number, finalized_at)
    SELECT p_tournament_id,
           c.round_number::smallint,
           c.bracket_position::smallint,
           c.bracket_position,
           c.participant_a,
           c.participant_b,
           c.phase,
           CASE WHEN c.is_bye_pairing THEN 'awaiting_results' ELSE 'scheduled' END,
           CASE WHEN c.is_bye_pairing
                THEN coalesce(c.participant_a, c.participant_b) END,
           1,
           NULL
      FROM public._tournament_compute_cons_bracket(
             v_cons_main_size, v_cons_direct_ids, '[]'::jsonb) c;

    UPDATE public.tournament_matches
      SET status = 'finalized',
          finalized_at = now()
      WHERE tournament_id = p_tournament_id
        AND phase = 'consolation'
        AND winner_participant IS NOT NULL
        AND status = 'awaiting_results';

    SELECT count(*) INTO v_match_count
      FROM public.tournament_matches
      WHERE tournament_id = p_tournament_id
        AND phase IN ('ko','third_place','final',
                      'consolation','consolation_third_place');
  END IF;

  -- ADR-0031 A1: the highest KO round_number is the final (final-round
  -- discriminator for the schedule phase below).
  SELECT max(round_number) INTO v_max_round
    FROM public.tournament_matches
   WHERE tournament_id = p_tournament_id
     AND phase IN ('ko','third_place','final',
                   'wb','lb','grand_final','grand_final_reset',
                   'consolation','consolation_third_place');

  FOR v_round IN
    SELECT DISTINCT round_number
      FROM public.tournament_matches
     WHERE tournament_id = p_tournament_id
       AND phase IN ('ko','third_place','final',
                     'wb','lb','grand_final','grand_final_reset',
                     'consolation','consolation_third_place')
     ORDER BY round_number
  LOOP
    PERFORM public._tournament_assign_pitches(p_tournament_id, v_round);

    -- ADR-0031 A1: one schedule row per KO round (phase 'final' for the last
    -- round, else 'ko'); seconds from ko_round_formats[round-1] with fallback.
    PERFORM public._tournament_upsert_round_schedule(
      p_tournament_id, NULL, v_round,
      CASE WHEN v_round = v_max_round THEN 'final' ELSE 'ko' END,
      (public._tournament_schedule_ko_seconds(
         p_tournament_id, v_round, v_round = v_max_round)).match_seconds,
      (public._tournament_schedule_ko_seconds(
         p_tournament_id, v_round, v_round = v_max_round)).break_seconds,
      (public._tournament_schedule_ko_seconds(
         p_tournament_id, v_round, v_round = v_max_round)).tiebreak_after,
      now());

    -- ADR-0031 C1 (E1): one per-pitch publish-notify per KO round, phase
    -- mirroring the schedule row ('final' for the max round, else 'ko').
    -- After pitches + the schedule row exist for this round.
    PERFORM public._tournament_notify_round_per_pitch(
      p_tournament_id, v_round,
      CASE WHEN v_round = v_max_round THEN 'final' ELSE 'ko' END,
      'round_published',
      'Runde ' || v_round || ' veröffentlicht',
      'Turnier "' || coalesce(v_name, '') || '": K.-o.-Runde ' || v_round
        || ' ist da.');
  END LOOP;

  SELECT count(*) INTO v_bye_count
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase IN ('ko','final','wb','lb','consolation')
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
        'consolation_enabled',      v_cons_enabled,
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
    'bracket_type',  v_bracket_type,
    'consolation',   v_cons_enabled);
END;
$function$
;

-- ---- tournament_detect_shootouts: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_detect_shootouts(p_tournament_id uuid, p_qualifier_count integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller   uuid;
  v_creator  uuid;
  v_name     text;
  v_grp      record;
  v_created  int := 0;
  v_groups   jsonb := '[]'::jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by, display_name INTO v_creator, v_name
    FROM public.tournaments
   WHERE id = p_tournament_id
   FOR UPDATE;

  -- PER-TOURNAMENT manage gate (20261201000032 §12): creator OR
  -- owner/admin/organizer of the club_id, same as tournament_start_ko_phase.
  IF v_creator IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  FOR v_grp IN
    SELECT * FROM public._tournament_detect_shootout_groups(
                     p_tournament_id, p_qualifier_count)
  LOOP
    INSERT INTO public.tournament_shootouts(
        tournament_id, start_rank, tied_participant_ids)
      VALUES (p_tournament_id, v_grp.start_rank, v_grp.participant_ids)
      ON CONFLICT (tournament_id, tie_key) DO NOTHING;

    IF FOUND THEN
      v_created := v_created + 1;
      PERFORM public._tournament_notify_shootout_group(
        p_tournament_id,
        v_grp.participant_ids,
        'Shoot-Out nötig',
        'Turnier "' || coalesce(v_name, '')
          || '": Gleichstand an der Qualifikations-Grenze — tragt den '
          || 'Shoot-Out-Sieger ein.',
        jsonb_build_object(
          'tournament_id', p_tournament_id,
          'kind',          'shootout',
          'start_rank',    v_grp.start_rank,
          'tied',          to_jsonb(v_grp.participant_ids)));
    END IF;

    v_groups := v_groups || jsonb_build_object(
      'start_rank', v_grp.start_rank,
      'tied',       to_jsonb(v_grp.participant_ids));
  END LOOP;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'shootouts_detected',
      v_caller,
      jsonb_build_object(
        'qualifier_count', p_qualifier_count,
        'created',         v_created,
        'groups',          v_groups));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'created',       v_created,
    'groups',        v_groups);
END;
$function$
;

-- ---- tournament_start_stage_graph: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_start_stage_graph(p_tournament_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller       uuid;
  v_status       text;
  v_created_by   uuid;
  v_stage_count  int;
  v_unknown_node text;
  v_has_cycle    boolean;
  v_root_count   int;
  v_roots        text[];
  v_root_node    text;
  v_seeded       uuid[];
  v_booted       text[] := ARRAY[]::text[];
BEGIN
  -- 1. Auth gate.
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- 2. Load + lock the tournament (not-found OR not-authorised => one 42501).
  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;

  -- 3. Status gate: only non-terminal pre-live stati are startable.
  IF v_status NOT IN ('published', 'registration_open', 'registration_closed', 'draft') THEN
    RAISE EXCEPTION 'tournament is not in a startable status' USING ERRCODE = '22023';
  END IF;

  -- 4. NO_STAGES.
  SELECT count(*) INTO v_stage_count
    FROM public.tournament_stages
    WHERE tournament_id = p_tournament_id;
  IF v_stage_count = 0 THEN
    RAISE EXCEPTION 'NO_STAGES: tournament has no stages' USING ERRCODE = '22023';
  END IF;

  -- 5. UNKNOWN_NODE: every edge endpoint must reference an existing stage.
  SELECT missing INTO v_unknown_node
    FROM (
      SELECT e.from_node_id AS missing
        FROM public.tournament_stage_edges e
        WHERE e.tournament_id = p_tournament_id
          AND NOT EXISTS (
            SELECT 1 FROM public.tournament_stages s
             WHERE s.tournament_id = p_tournament_id
               AND s.node_id = e.from_node_id)
      UNION ALL
      SELECT e.to_node_id AS missing
        FROM public.tournament_stage_edges e
        WHERE e.tournament_id = p_tournament_id
          AND NOT EXISTS (
            SELECT 1 FROM public.tournament_stages s
             WHERE s.tournament_id = p_tournament_id
               AND s.node_id = e.to_node_id)
    ) q
    LIMIT 1;
  IF v_unknown_node IS NOT NULL THEN
    RAISE EXCEPTION 'UNKNOWN_NODE: edge references node % which is not a stage', v_unknown_node
      USING ERRCODE = '22023';
  END IF;

  -- 6. CYCLE: recursive-CTE detection with a path accumulator.
  WITH RECURSIVE walk(node, path, is_cycle) AS (
    SELECT s.node_id, ARRAY[s.node_id], false
      FROM public.tournament_stages s
      WHERE s.tournament_id = p_tournament_id
    UNION ALL
    SELECT e.to_node_id,
           w.path || e.to_node_id,
           e.to_node_id = ANY(w.path)
      FROM walk w
      JOIN public.tournament_stage_edges e
        ON e.tournament_id = p_tournament_id
       AND e.from_node_id = w.node
      WHERE NOT w.is_cycle
  )
  SELECT bool_or(is_cycle) INTO v_has_cycle FROM walk;
  IF coalesce(v_has_cycle, false) THEN
    RAISE EXCEPTION 'CYCLE: stage graph contains a cycle' USING ERRCODE = '22023';
  END IF;

  -- 7. ROOTS: all stages with no incoming edge. >=1 required (0 only via a
  --    cycle, already reported). Multiple roots are now allowed (F3).
  SELECT array_agg(s.node_id ORDER BY s.node_id) INTO v_roots
    FROM public.tournament_stages s
    WHERE s.tournament_id = p_tournament_id
      AND NOT EXISTS (
        SELECT 1 FROM public.tournament_stage_edges e
         WHERE e.tournament_id = p_tournament_id
           AND e.to_node_id = s.node_id);

  v_root_count := coalesce(array_length(v_roots, 1), 0);
  IF v_root_count = 0 THEN
    RAISE EXCEPTION 'NO_ROOT: no stage without an incoming edge' USING ERRCODE = '22023';
  END IF;

  -- 8. Idempotency: if ANY root is already started (active/completed or has
  --    matches), the whole start is a no-op error.
  IF EXISTS (
    SELECT 1
      FROM public.tournament_stages s
      WHERE s.tournament_id = p_tournament_id
        AND s.node_id = ANY(v_roots)
        AND (
          s.status IN ('active', 'completed')
          OR EXISTS (
            SELECT 1 FROM public.tournament_matches m
             WHERE m.tournament_id = p_tournament_id
               AND m.stage_node_id = s.node_id)
        )
  ) THEN
    RAISE EXCEPTION 'ALREADY_STARTED: a root stage is already started' USING ERRCODE = '22023';
  END IF;

  -- 9. The full confirmed field (index 0 = seed 1) — every root is fed this
  --    field. 'approved' is inert in this schema (only 'confirmed' matches);
  --    kept for forward-compat.
  SELECT array_agg(tp.id ORDER BY tp.seed NULLS LAST, tp.id) INTO v_seeded
    FROM public.tournament_participants tp
    WHERE tp.tournament_id = p_tournament_id
      AND tp.registration_status IN ('confirmed', 'approved');

  IF v_seeded IS NULL OR array_length(v_seeded, 1) IS NULL THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: no confirmed participants' USING ERRCODE = '22023';
  END IF;

  -- 10. Boot every root with the full field.
  FOREACH v_root_node IN ARRAY v_roots LOOP
    PERFORM public.tournament_generate_stage_matches(p_tournament_id, v_root_node, v_seeded);

    UPDATE public.tournament_stages
      SET status = 'active'
      WHERE tournament_id = p_tournament_id
        AND node_id = v_root_node;

    v_booted := v_booted || v_root_node;
  END LOOP;

  -- 11. Tournament goes live (mirror tournament_start).
  UPDATE public.tournaments
    SET status = 'live', started_at = now()
    WHERE id = p_tournament_id;

  -- 12. Audit.
  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'stage_graph_started',
      v_caller,
      jsonb_build_object('root_nodes', to_jsonb(v_booted)));

  RETURN array_to_string(v_booted, ',');
END;
$function$
;

-- ---- apply_stage_graph_template: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.apply_stage_graph_template(p_tournament_id uuid, p_template_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_uid          uuid;
  v_status       text;
  v_created_by   uuid;
  v_graph        jsonb;
  v_node_count   int;
  v_edge_count   int;
BEGIN
  -- 1. Auth gate.
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- 2. Load + lock the tournament. Not-found OR not-authorised collapse into
  --    one 42501 (no existence oracle) — same idiom as tournament_start_stage_graph.
  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;

  -- 3. Status gate: only a pre-start tournament may receive a stage graph.
  --    Formulated as the same ALLOWLIST as the sister RPC
  --    tournament_start_stage_graph (non-terminal pre-live stati of
  --    tournaments_status_check) so the two RPCs stay in lock-step: a future
  --    pre-start status added to the CHECK would NOT be silently admitted here
  --    by a stale denylist. Equivalent to the prior denylist over today's
  --    7-value CHECK {draft, published, registration_open, registration_closed,
  --    live, finalized, aborted}.
  IF v_status NOT IN ('published', 'registration_open', 'registration_closed', 'draft') THEN
    RAISE EXCEPTION 'TOURNAMENT_NOT_PRE_START: tournament is not in a pre-start status'
      USING ERRCODE = '22023';
  END IF;

  -- 4. Template visibility check. SECURITY DEFINER bypasses RLS, so we re-apply
  --    the B5 read predicate explicitly. Not readable / not existent ->
  --    TEMPLATE_NOT_FOUND.
  SELECT t.graph INTO v_graph
    FROM public.tournament_stage_graph_templates t
    WHERE t.id = p_template_id
      AND (
        t.visibility = 'public'
        OR t.owner_user_id = v_uid
        OR (
          t.visibility = 'club'
          AND t.club_id IS NOT NULL
          AND public.is_active_club_member(t.club_id, v_uid)
        )
      );

  IF v_graph IS NULL THEN
    RAISE EXCEPTION 'TEMPLATE_NOT_FOUND: template not found or not readable'
      USING ERRCODE = '22023';
  END IF;

  -- 5. Conflict gate (copy semantics, no merge): the tournament must have no
  --    stages yet.
  IF EXISTS (
    SELECT 1 FROM public.tournament_stages
     WHERE tournament_id = p_tournament_id
  ) THEN
    RAISE EXCEPTION 'ALREADY_HAS_STAGES: tournament already has stages'
      USING ERRCODE = '22023';
  END IF;

  -- 6. Materialize nodes. Wire keys map 1:1 onto the L1b columns; config
  --    defaults to {} and seeding to 'as_routed' when the node omits them.
  INSERT INTO public.tournament_stages (tournament_id, node_id, type, config, seeding)
  SELECT
    p_tournament_id,
    node ->> 'id',
    node ->> 'type',
    coalesce(node -> 'config', '{}'::jsonb),
    coalesce(node ->> 'seeding', 'as_routed')
  FROM jsonb_array_elements(v_graph -> 'nodes') AS node;
  GET DIAGNOSTICS v_node_count = ROW_COUNT;

  -- 7. Materialize edges. `selector` is jsonb NOT NULL — a well-formed template
  --    carries a selector object; a missing one would fail the NOT NULL cleanly.
  INSERT INTO public.tournament_stage_edges
    (tournament_id, from_node_id, to_node_id, selector, seeding_in)
  SELECT
    p_tournament_id,
    edge ->> 'from_node_id',
    edge ->> 'to_node_id',
    edge -> 'selector',
    coalesce(edge ->> 'seeding_in', 'order_preserving')
  FROM jsonb_array_elements(v_graph -> 'edges') AS edge;
  GET DIAGNOSTICS v_edge_count = ROW_COUNT;

  -- 8. Return total rows materialized (#nodes + #edges).
  RETURN v_node_count + v_edge_count;
END;
$function$
;

-- ---- tournament_finalize: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_finalize(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
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
$function$
;

-- ---- tournament_abort: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_abort(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
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
$function$
;

-- ---- tournament_invite_user: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_invite_user(p_tournament_id uuid, p_user_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller        uuid;
  v_invite_only   boolean;
  v_name          text;
  v_invitation    uuid;
  v_old_state     text;
  v_reactivated   boolean := false;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Manage gate (creator OR club owner/admin/organizer).
  IF NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  SELECT invite_only, display_name
    INTO v_invite_only, v_name
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;
  IF v_invite_only IS NULL THEN
    RAISE EXCEPTION 'tournament not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_invite_only IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'tournament is not invite-only' USING ERRCODE = '22023';
  END IF;

  -- Self-invitation forbidden.
  IF p_user_id = v_caller THEN
    RAISE EXCEPTION 'cannot invite yourself' USING ERRCODE = '22023';
  END IF;

  -- Invitee must be an existing user.
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'invitee user not found' USING ERRCODE = '22023';
  END IF;

  -- Upsert: a revoked/declined invitation is re-activated back to 'pending'
  -- with a fresh created_at; a pending/accepted one is a no-op (same id).
  SELECT id, state INTO v_invitation, v_old_state
    FROM public.tournament_invitations
    WHERE tournament_id = p_tournament_id
      AND invitee_user_id = p_user_id
    FOR UPDATE;

  IF v_invitation IS NULL THEN
    INSERT INTO public.tournament_invitations(
        tournament_id, invitee_user_id, invited_by, state)
      VALUES (p_tournament_id, p_user_id, v_caller, 'pending')
      RETURNING id INTO v_invitation;
    v_reactivated := true;
  ELSIF v_old_state IN ('revoked','declined') THEN
    UPDATE public.tournament_invitations
       SET state        = 'pending',
           invited_by   = v_caller,
           created_at   = now(),
           responded_at = NULL
     WHERE id = v_invitation;
    v_reactivated := true;
  ELSE
    -- already 'pending' or 'accepted' -> no-op, return the existing id.
    v_reactivated := false;
  END IF;

  -- Only notify / audit when the invitation is freshly active.
  IF v_reactivated THEN
    INSERT INTO public.user_inbox_messages(
        user_id, kind, subject, body, action_payload)
      VALUES (
        p_user_id,
        'tournament_invitation',
        'Turnier-Einladung',
        'Du wurdest zu einem Turnier eingeladen: "'
          || coalesce(v_name, '') || '".',
        jsonb_build_object(
          'tournament_id',   p_tournament_id,
          'invitation_id',   v_invitation,
          'tournament_name', v_name
        )
      );

    INSERT INTO public.tournament_audit_events(
        tournament_id, kind, actor_user_id, payload)
      VALUES (
        p_tournament_id,
        'invitation_sent',
        v_caller,
        jsonb_build_object(
          'invitation_id',   v_invitation,
          'invitee_user_id', p_user_id
        )
      );
  END IF;

  RETURN v_invitation;
END;
$function$
;

-- ---- tournament_revoke_invitation: can_manage -> can_setup ----
CREATE OR REPLACE FUNCTION public.tournament_revoke_invitation(p_invitation_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller        uuid;
  v_tournament_id uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT tournament_id INTO v_tournament_id
    FROM public.tournament_invitations
    WHERE id = p_invitation_id
    FOR UPDATE;
  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'invitation not found' USING ERRCODE = 'P0002';
  END IF;

  IF NOT public.tournament_caller_can_setup(v_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  UPDATE public.tournament_invitations
     SET state        = 'revoked',
         responded_at = now()
   WHERE id = p_invitation_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'invitation_revoked',
      v_caller,
      jsonb_build_object('invitation_id', p_invitation_id)
    );
END;
$function$
;


-- ====================================================================
-- PART C — ADMIN call-sites: gate can_manage -> can_administer.
-- Live-intervention RPCs. Each body is the latest on-disk body (anchor
-- in the header); only the gate call changed.
-- ====================================================================

-- ---- tournament_match_forfeit: can_manage -> can_administer ----
CREATE OR REPLACE FUNCTION public.tournament_match_forfeit(p_match_id uuid, p_absent_side text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller          uuid;
  v_tournament_id   uuid;
  v_match_status    text;
  v_round           smallint;
  v_part_a          uuid;
  v_part_b          uuid;
  v_t_status        text;
  v_forfeit_points  int;
  v_final_a         int;
  v_final_b         int;
  v_winner_part     uuid;
  v_absent_part     uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- DSCORE-63 absent-side validation up-front so the error surface is
  -- predictable before we touch the row lock.
  IF p_absent_side IS NULL OR p_absent_side NOT IN ('A','B') THEN
    RAISE EXCEPTION 'absent_side must be A or B' USING ERRCODE = '22023';
  END IF;

  -- DSCORE-65: free-text reason, min 10 chars (also caps to keep the
  -- audit-event payload bounded; mirrors the override RPC's 500 ceiling).
  IF p_reason IS NULL OR length(trim(p_reason)) < 10
     OR length(p_reason) > 500 THEN
    RAISE EXCEPTION 'forfeit reason length must be between 10 and 500 chars'
      USING ERRCODE = '22023';
  END IF;

  -- Lock the match row first so a concurrent score submission cannot
  -- race the forfeit declaration.
  SELECT m.tournament_id, m.status, m.consensus_round,
         m.participant_a, m.participant_b
    INTO v_tournament_id, v_match_status, v_round, v_part_a, v_part_b
    FROM public.tournament_matches m
    WHERE m.id = p_match_id
    FOR UPDATE;

  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'match not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_part_a IS NULL OR v_part_b IS NULL THEN
    RAISE EXCEPTION 'match has no two-sided pairing — forfeit not applicable'
      USING ERRCODE = '22023';
  END IF;
  IF v_match_status NOT IN ('scheduled','awaiting_results','disputed') THEN
    RAISE EXCEPTION 'match cannot be forfeited in status %', v_match_status
      USING ERRCODE = '22023';
  END IF;

  -- Status gate: a caller who can manage the tournament (Creator OR active
  -- club role in {owner, admin, organizer, referee} — K4/K6/OE-D2) may
  -- declare a forfeit, and only while the tournament is live (spec:
  -- "running").
  SELECT t.status, t.forfeit_points
    INTO v_t_status, v_forfeit_points
    FROM public.tournaments t
    WHERE t.id = v_tournament_id;
  IF NOT public.tournament_caller_can_administer(v_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to declare a forfeit'
      USING ERRCODE = '42501';
  END IF;
  IF v_t_status <> 'live' THEN
    RAISE EXCEPTION 'forfeit not allowed in tournament status %', v_t_status
      USING ERRCODE = '22023';
  END IF;

  -- FR-CFG-11: score is derived from the tournament's forfeit_points
  -- configuration. The absent side gets 0, the present side gets the
  -- configured points (default 18 per 20260525000001_tournament_schema).
  IF v_forfeit_points IS NULL OR v_forfeit_points < 0 THEN
    RAISE EXCEPTION 'tournament.forfeit_points is not configured'
      USING ERRCODE = '22023';
  END IF;

  IF p_absent_side = 'A' THEN
    v_final_a     := 0;
    v_final_b     := v_forfeit_points;
    v_winner_part := v_part_b;
    v_absent_part := v_part_a;
  ELSE
    v_final_a     := v_forfeit_points;
    v_final_b     := 0;
    v_winner_part := v_part_a;
    v_absent_part := v_part_b;
  END IF;

  UPDATE public.tournament_matches
    SET status              = 'finalized',
        winner_participant  = v_winner_part,
        final_score_a       = v_final_a,
        final_score_b       = v_final_b,
        finalized_at        = now(),
        started_at          = COALESCE(started_at, now())
    WHERE id = p_match_id;

  -- TODO(audit-log-sweep): the Sprint A audit-log sweep will consolidate
  -- cross-feature audit writes (currently scattered between
  -- tournament_audit_events and the per-match audit hooks); this insert
  -- is the canonical entry point for the `match_forfeit_declared` event
  -- and stays here until that sweep relocates it.
  INSERT INTO public.tournament_audit_events(
      tournament_id, match_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id, p_match_id, 'match_forfeit_declared', v_caller,
      jsonb_build_object(
        'absent_side',            p_absent_side,
        'absent_participant_id',  v_absent_part,
        'winner_participant_id',  v_winner_part,
        'final_score_a',          v_final_a,
        'final_score_b',          v_final_b,
        'forfeit_points',         v_forfeit_points,
        'reason',                 p_reason,
        'previous_status',        v_match_status,
        'consensus_round',        v_round
      ));

  RETURN jsonb_build_object(
    'match_id',              p_match_id,
    'status',                'finalized',
    'winner_participant_id', v_winner_part,
    'final_score_a',         v_final_a,
    'final_score_b',         v_final_b,
    'forfeit_points',        v_forfeit_points
  );
END;
$function$
;

-- ---- tournament_pause: can_manage -> can_administer ----
CREATE OR REPLACE FUNCTION public.tournament_pause(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_changed int := 0;  -- C2: rows actually transitioned unpaused -> paused
BEGIN
  IF NOT public.tournament_caller_can_administer(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  -- Serialise against the E cron tick and concurrent control calls.
  PERFORM pg_advisory_xact_lock(hashtext(p_tournament_id::text));

  -- Freeze the active round's clock: set paused_at only when not already paused
  -- (idempotent — a 2nd consecutive pause does not advance/overwrite paused_at
  -- and does not corrupt paused_accum_seconds). Active = non-terminal row.
  UPDATE public.tournament_round_schedule s
     SET paused_at = now()
   WHERE s.tournament_id = p_tournament_id
     AND s.status IN ('call','running','awaiting_results')
     AND s.paused_at IS NULL;

  -- C2 (E5): durable broadcast notify only on a REAL transition. A no-op pause
  -- (nothing active / already paused -> 0 rows) sends no second 'paused' notify.
  GET DIAGNOSTICS v_changed = ROW_COUNT;
  IF v_changed > 0 THEN
    PERFORM public._tournament_notify_paused(p_tournament_id, false);
  END IF;
END;
$function$
;

-- ---- tournament_resume: can_manage -> can_administer ----
CREATE OR REPLACE FUNCTION public.tournament_resume(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_changed int := 0;  -- C2: rows actually resumed (paused -> unpaused)
BEGIN
  IF NOT public.tournament_caller_can_administer(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_tournament_id::text));

  -- Add the frozen interval to paused_accum_seconds and clear paused_at.
  -- Guarded on paused_at IS NOT NULL so a resume while not paused is a no-op
  -- (no negative / garbage accumulation, idempotent).
  UPDATE public.tournament_round_schedule s
     SET paused_accum_seconds =
           s.paused_accum_seconds
           + EXTRACT(EPOCH FROM (now() - s.paused_at))::int,
         paused_at = NULL
   WHERE s.tournament_id = p_tournament_id
     AND s.status IN ('call','running','awaiting_results')
     AND s.paused_at IS NOT NULL;

  -- C2 (E6): durable broadcast notify only on a REAL resume. A no-op resume
  -- (not paused -> 0 rows) sends no 'resumed' notify.
  GET DIAGNOSTICS v_changed = ROW_COUNT;
  IF v_changed > 0 THEN
    PERFORM public._tournament_notify_paused(p_tournament_id, true);
  END IF;
END;
$function$
;

-- ---- tournament_skip_forward: can_manage -> can_administer ----
CREATE OR REPLACE FUNCTION public.tournament_skip_forward(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF NOT public.tournament_caller_can_administer(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_tournament_id::text));

  -- Skip the call/break window: start the match window now and transition to
  -- running. Per the skip/pause interaction rule, clear any pause state.
  UPDATE public.tournament_round_schedule s
     SET starts_at = now(),
         ends_at   = now() + make_interval(secs => s.match_seconds),
         status    = 'running',
         paused_at = NULL,
         paused_accum_seconds = 0
   WHERE s.tournament_id = p_tournament_id
     AND s.status IN ('call','running','awaiting_results');
END;
$function$
;

-- ---- tournament_skip_back: can_manage -> can_administer ----
CREATE OR REPLACE FUNCTION public.tournament_skip_back(p_tournament_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
BEGIN
  IF NOT public.tournament_caller_can_administer(p_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_tournament_id::text));

  -- Re-call the window (NOT a true rewind, OE-B4): the call/break window starts
  -- now, the match window follows it, status returns to 'call'. Clear any pause.
  UPDATE public.tournament_round_schedule s
     SET starts_at = now() + make_interval(secs => s.break_seconds),
         ends_at   = now() + make_interval(secs => s.break_seconds)
                          + make_interval(secs => s.match_seconds),
         status    = 'call',
         paused_at = NULL,
         paused_accum_seconds = 0
   WHERE s.tournament_id = p_tournament_id
     AND s.status IN ('call','running','awaiting_results');
END;
$function$
;

-- ---- tournament_checkin_participant: can_manage -> can_administer ----
CREATE OR REPLACE FUNCTION public.tournament_checkin_participant(p_participant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller        uuid;
  v_tournament_id uuid;
  v_reg_status    text;
  v_checked_in_at timestamptz;
  v_t_status      text;
  v_now           timestamptz;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Lock the participant row so a concurrent toggle cannot race us.
  SELECT p.tournament_id, p.registration_status, p.checked_in_at
    INTO v_tournament_id, v_reg_status, v_checked_in_at
    FROM public.tournament_participants p
    WHERE p.id = p_participant_id
    FOR UPDATE;

  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'participant not found' USING ERRCODE = 'P0002';
  END IF;

  -- Authority gate (K4): creator OR active owner/admin/organizer of the
  -- tournament's club. No bespoke role set here.
  IF NOT public.tournament_caller_can_administer(v_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  -- Tournament status gate (OE-D1): check-in only inside the registration /
  -- live window. draft/published/finalized/aborted are rejected.
  SELECT t.status INTO v_t_status
    FROM public.tournaments t
    WHERE t.id = v_tournament_id;
  IF v_t_status NOT IN ('registration_open','registration_closed','live') THEN
    RAISE EXCEPTION 'check-in not allowed in tournament status %', v_t_status
      USING ERRCODE = '22023';
  END IF;

  -- Participant status gate: only confirmed participants can be checked in.
  IF v_reg_status <> 'confirmed' THEN
    RAISE EXCEPTION 'check-in only allowed for confirmed participants (is %)',
      v_reg_status USING ERRCODE = '22023';
  END IF;

  -- Idempotent: already checked in => no-op, preserve the existing timestamp,
  -- write no audit event.
  IF v_checked_in_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'participant_id', p_participant_id,
      'checked_in_at',  v_checked_in_at,
      'changed',        false
    );
  END IF;

  v_now := now();
  UPDATE public.tournament_participants
    SET checked_in_at = v_now
    WHERE id = p_participant_id;

  -- Audit (mirrors the forfeit RPC pattern): one event per real state change.
  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id, 'participant_checked_in', v_caller,
      jsonb_build_object(
        'participant_id', p_participant_id,
        'checked_in_at',  v_now
      ));

  RETURN jsonb_build_object(
    'participant_id', p_participant_id,
    'checked_in_at',  v_now,
    'changed',        true
  );
END;
$function$
;

-- ---- tournament_undo_checkin: can_manage -> can_administer ----
CREATE OR REPLACE FUNCTION public.tournament_undo_checkin(p_participant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller        uuid;
  v_tournament_id uuid;
  v_reg_status    text;
  v_checked_in_at timestamptz;
  v_t_status      text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Lock the participant row so a concurrent toggle cannot race us.
  SELECT p.tournament_id, p.registration_status, p.checked_in_at
    INTO v_tournament_id, v_reg_status, v_checked_in_at
    FROM public.tournament_participants p
    WHERE p.id = p_participant_id
    FOR UPDATE;

  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'participant not found' USING ERRCODE = 'P0002';
  END IF;

  -- Authority gate (K4): same gate as check-in.
  IF NOT public.tournament_caller_can_administer(v_tournament_id) THEN
    RAISE EXCEPTION 'not authorised to manage this tournament'
      USING ERRCODE = '42501';
  END IF;

  -- Tournament status gate (OE-D1): same window as check-in.
  SELECT t.status INTO v_t_status
    FROM public.tournaments t
    WHERE t.id = v_tournament_id;
  IF v_t_status NOT IN ('registration_open','registration_closed','live') THEN
    RAISE EXCEPTION 'undo check-in not allowed in tournament status %', v_t_status
      USING ERRCODE = '22023';
  END IF;

  -- Participant status gate: only confirmed participants are check-in subjects.
  IF v_reg_status <> 'confirmed' THEN
    RAISE EXCEPTION 'undo check-in only allowed for confirmed participants (is %)',
      v_reg_status USING ERRCODE = '22023';
  END IF;

  -- Idempotent: already not checked in => no-op, write no audit event.
  IF v_checked_in_at IS NULL THEN
    RETURN jsonb_build_object(
      'participant_id', p_participant_id,
      'checked_in_at',  NULL,
      'changed',        false
    );
  END IF;

  UPDATE public.tournament_participants
    SET checked_in_at = NULL
    WHERE id = p_participant_id;

  -- Audit: one event per real state change.
  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id, 'participant_checkin_undone', v_caller,
      jsonb_build_object(
        'participant_id',         p_participant_id,
        'previous_checked_in_at', v_checked_in_at
      ));

  RETURN jsonb_build_object(
    'participant_id', p_participant_id,
    'checked_in_at',  NULL,
    'changed',        true
  );
END;
$function$
;

-- ---- tournament_list_administrable: can_manage -> can_administer ----
CREATE OR REPLACE FUNCTION public.tournament_list_administrable(p_limit integer DEFAULT 50)
 RETURNS SETOF jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
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

  RETURN QUERY
    SELECT jsonb_build_object(
             -- Identity fields.
             'tournament_id',         t.id,
             'display_name',          t.display_name,
             'format',                t.format,
             'status',                t.status,
             -- Schedule-derived fields (NULL when no schedule row — LEFT JOIN).
             'current_round',         s.round_number,
             'schedule_status',       s.status,
             'paused_at',             s.paused_at,
             -- ADR-0031 restzeit formula on the server clock. NULL without a
             -- schedule row; otherwise match_seconds - effective_elapsed where
             -- effective_elapsed = (now - starts_at) - paused_accum_seconds
             -- - (paused_at IS NOT NULL ? (now - paused_at) : 0).
             'remaining_seconds',
               CASE WHEN s.id IS NULL THEN NULL ELSE
                 s.match_seconds
                 - (
                     EXTRACT(EPOCH FROM (public.app_server_now() - s.starts_at))::int
                     - s.paused_accum_seconds
                     - CASE WHEN s.paused_at IS NOT NULL
                         THEN EXTRACT(EPOCH FROM (public.app_server_now() - s.paused_at))::int
                         ELSE 0 END
                   )
               END,
             -- Escalation counts over tournament_matches.
             'open_match_count',      (
               SELECT count(*)::int FROM public.tournament_matches m
                WHERE m.tournament_id = t.id
                  AND m.status IN ('scheduled','awaiting_results')
             ),
             'disputed_match_count',  (
               SELECT count(*)::int FROM public.tournament_matches m
                WHERE m.tournament_id = t.id
                  AND m.status = 'disputed'
             )
           )
      FROM public.tournaments t
      -- LEFT JOIN: keep administrable tournaments that have no schedule row yet.
      -- Bind to the active (non-completed) schedule row of the highest round.
      LEFT JOIN LATERAL (
        SELECT srs.*
          FROM public.tournament_round_schedule srs
         WHERE srs.tournament_id = t.id
           AND srs.status <> 'completed'
         ORDER BY srs.round_number DESC, srs.created_at DESC
         LIMIT 1
      ) s ON true
     WHERE t.status IN ('published','live')
       AND public.tournament_caller_can_administer(t.id)
     ORDER BY t.started_at DESC NULLS FIRST, t.created_at DESC
     LIMIT v_limit;
END;
$function$
;


-- ====================================================================
-- PART D — organizer-override RPCs: creator-only check -> can_administer.
-- These two RPCs gated on "caller == created_by" instead of the shared
-- gate helper; the creator-only block is replaced by the administer gate
-- (live intervention). Bodies otherwise byte-identical to their anchors.
-- ====================================================================

-- ---- tournament_organizer_override: creator-only -> can_administer ----
CREATE OR REPLACE FUNCTION public.tournament_organizer_override(p_match_id uuid, p_final_set_scores jsonb, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller         uuid;
  v_tournament_id  uuid;
  v_creator        uuid;
  v_status         text;
  v_round          smallint;
  v_part_a         uuid;
  v_part_b         uuid;
  v_final_a        int;
  v_final_b        int;
  v_match_winner   text;
  v_ekc            jsonb;
  v_winner_part    uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  IF p_reason IS NULL OR length(p_reason) < 1 OR length(p_reason) > 500 THEN
    RAISE EXCEPTION 'override reason length must be 1..500'
      USING ERRCODE = '22023';
  END IF;

  -- Lock the match row.
  SELECT m.tournament_id, m.status, m.consensus_round,
         m.participant_a, m.participant_b
    INTO v_tournament_id, v_status, v_round, v_part_a, v_part_b
    FROM public.tournament_matches m
    WHERE m.id = p_match_id
    FOR UPDATE;

  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'match not found' USING ERRCODE = 'P0002';
  END IF;

  -- P2-S gate split: live intervention gate tournament_caller_can_administer
  -- (creator OR club owner/admin/referee) replaces the creator-only check.
  IF NOT public.tournament_caller_can_administer(v_tournament_id) THEN
    RAISE EXCEPTION 'caller cannot administer this tournament'
      USING ERRCODE = '42501';
  END IF;

  -- T1: include 'scheduled' so the organizer can enter a result for a match
  -- that hasn't received any player proposal yet (on-site entry). Terminal
  -- states (finalized/overridden/voided) stay rejected.
  IF v_status NOT IN ('scheduled','awaiting_results','disputed') THEN
    RAISE EXCEPTION 'match cannot be overridden in status %', v_status
      USING ERRCODE = '22023';
  END IF;
  IF v_part_a IS NULL OR v_part_b IS NULL THEN
    RAISE EXCEPTION 'match has no two-sided pairing' USING ERRCODE = '22023';
  END IF;

  -- Compute EKC totals from the organizer's final set scores.
  v_ekc := public._tournament_compute_ekc(p_final_set_scores);
  v_final_a      := (v_ekc ->> 'final_score_a')::int;
  v_final_b      := (v_ekc ->> 'final_score_b')::int;
  v_match_winner :=  v_ekc ->> 'match_winner';

  IF v_match_winner IS NULL THEN
    RAISE EXCEPTION 'override result must have a set-count winner'
      USING ERRCODE = '22023';
  END IF;
  v_winner_part := CASE WHEN v_match_winner = 'A' THEN v_part_a
                        ELSE v_part_b END;

  UPDATE public.tournament_matches
    SET status              = 'overridden',
        winner_participant  = v_winner_part,
        final_score_a       = v_final_a,
        final_score_b       = v_final_b,
        finalized_at        = now()
    WHERE id = p_match_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, match_id, kind, actor_user_id, payload)
    VALUES (v_tournament_id, p_match_id, 'organizer_override', v_caller,
            jsonb_build_object(
              'reason',                p_reason,
              'final_set_scores',      p_final_set_scores,
              'final_score_a',         v_final_a,
              'final_score_b',         v_final_b,
              'winner_participant_id', v_winner_part,
              'previous_status',       v_status,
              'consensus_round',       v_round,
              'caller',                v_caller));
END;
$function$
;

-- ---- tournament_organizer_override_pairing: creator-only -> can_administer ----
CREATE OR REPLACE FUNCTION public.tournament_organizer_override_pairing(p_match_id uuid, p_participant_a uuid, p_participant_b uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller         uuid;
  v_tournament_id  uuid;
  v_creator        uuid;
  v_status         text;
  v_round          smallint;
  v_old_part_a     uuid;
  v_old_part_b     uuid;
  v_conflict_count int;
  v_valid_count    int;
BEGIN
  -- 1. Authentication.
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- 2. Pflicht-Begründung (MISSING_REASON).
  IF p_reason IS NULL OR length(btrim(p_reason)) < 1
     OR length(p_reason) > 500 THEN
    RAISE EXCEPTION 'MISSING_REASON: override reason must be 1..500 chars'
      USING ERRCODE = '22023';
  END IF;

  -- 3. Match-Row sperren und Stamm-Daten lesen.
  SELECT m.tournament_id, m.status, m.round_number,
         m.participant_a, m.participant_b
    INTO v_tournament_id, v_status, v_round, v_old_part_a, v_old_part_b
    FROM public.tournament_matches m
    WHERE m.id = p_match_id
    FOR UPDATE;

  IF v_tournament_id IS NULL THEN
    RAISE EXCEPTION 'MATCH_NOT_FOUND: match % does not exist', p_match_id
      USING ERRCODE = 'P0002';
  END IF;

  -- 4. Defense-in-depth: P2-S gate split — live intervention gate
  --    tournament_caller_can_administer (creator OR club owner/admin/referee),
  --    checked here because SECURITY DEFINER bypasses RLS.
  IF NOT public.tournament_caller_can_administer(v_tournament_id) THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: caller cannot administer this tournament'
      USING ERRCODE = '42501';
  END IF;

  -- 5. Match-Status muss `scheduled` sein.
  IF v_status <> 'scheduled' THEN
    RAISE EXCEPTION 'MATCH_ALREADY_STARTED: match status is %, expected scheduled', v_status
      USING ERRCODE = '22023';
  END IF;

  -- 6. Neue Teilnehmer-IDs validieren.
  IF p_participant_a IS NULL OR p_participant_b IS NULL THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: both participants must be non-null'
      USING ERRCODE = '22023';
  END IF;
  IF p_participant_a = p_participant_b THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: participants must be distinct'
      USING ERRCODE = '22023';
  END IF;

  -- Beide müssen Teilnehmer dieses Turniers sein.
  SELECT count(*) INTO v_valid_count
    FROM public.tournament_participants p
    WHERE p.tournament_id = v_tournament_id
      AND p.id IN (p_participant_a, p_participant_b);
  IF v_valid_count <> 2 THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: participants are not registered in tournament %', v_tournament_id
      USING ERRCODE = '22023';
  END IF;

  -- 7. Konflikt: einer der neuen Teilnehmer ist bereits in einem
  --    *anderen* Match derselben Runde gepaart.
  SELECT count(*) INTO v_conflict_count
    FROM public.tournament_matches m
    WHERE m.tournament_id = v_tournament_id
      AND m.round_number  = v_round
      AND m.id <> p_match_id
      AND (m.participant_a IN (p_participant_a, p_participant_b)
        OR m.participant_b IN (p_participant_a, p_participant_b));
  IF v_conflict_count > 0 THEN
    RAISE EXCEPTION 'PARTICIPANT_CONFLICT: participant already paired in round %', v_round
      USING ERRCODE = '22023';
  END IF;

  -- 8. Update + Audit.
  UPDATE public.tournament_matches
    SET participant_a = p_participant_a,
        participant_b = p_participant_b
    WHERE id = p_match_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, match_id, kind, actor_user_id, payload)
    VALUES (v_tournament_id, p_match_id, 'pairing_overridden', v_caller,
            jsonb_build_object(
              'reason',              p_reason,
              'round_number',        v_round,
              'old_participant_a',   v_old_part_a,
              'old_participant_b',   v_old_part_b,
              'new_participant_a',   p_participant_a,
              'new_participant_b',   p_participant_b));
END;
$function$
;


-- ====================================================================
-- PART E — DEPRECATED alias (fail-safe, locked decision OE-4).
-- tournament_caller_can_manage keeps its signature but now only
-- delegates to tournament_caller_can_administer, so any call-site
-- missed by the split keeps working with administer semantics.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_caller_can_manage(p_tournament_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
  -- DEPRECATED (P2-S gate split, ADR-0032): pure alias kept as a fail-safe
  -- for call-sites missed by the can_setup/can_administer split. Do not add
  -- new callers; use tournament_caller_can_setup or
  -- tournament_caller_can_administer instead.
  SELECT public.tournament_caller_can_administer(p_tournament_id);
$function$;

COMMENT ON FUNCTION public.tournament_caller_can_manage(uuid) IS
  'DEPRECATED (P2-S gate split, ADR-0032): pure alias of '
  'tournament_caller_can_administer, kept as a fail-safe for missed '
  'call-sites. Use tournament_caller_can_setup / '
  'tournament_caller_can_administer instead.';

