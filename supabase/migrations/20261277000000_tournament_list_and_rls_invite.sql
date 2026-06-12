-- Spaßturnier „auf Einladung" — S4: list visibility, update persist, RLS.
--
-- Three re-based CREATE OR REPLACE / policy changes, each touching exactly the
-- one specified line:
--   * tournament_update          (re-based from 20261243000000 §2): add
--     invite_only to the UPDATE-SET, sourced from p_setup.
--   * tournament_list_for_caller (re-based from 20261240000000): hide
--     invite-only tournaments from non-invited callers.
--   * tournaments_public_read    (RLS): same visibility rule for direct SELECT.


-- ====================================================================
-- 1. tournament_update — verbatim re-base of 20261243000000 §2. ONLY change:
--    one extra column in the UPDATE-SET:
--      invite_only = coalesce((v_setup->>'invite_only')::boolean,
--                             public.tournaments.invite_only)
--      (preserve the existing flag when p_setup omits the key, so a plain
--       Stammdaten-update never silently clears it).
--    Everything else (helpers, gate, safety classes, recompute) byte-identical.
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
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
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
$$;

GRANT EXECUTE ON FUNCTION public.tournament_update(
  uuid, text, int, int, int, text, jsonb, text[], jsonb) TO authenticated;


-- ====================================================================
-- 2. tournament_list_for_caller — verbatim re-base of 20261240000000. ONLY
--    change: the WHERE gains an invite-only visibility clause; an invite-only
--    tournament is listed only for its creator or a non-revoked invitee.
--    Non-invite_only listing is unchanged.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_list_for_caller(
  p_status_filter text DEFAULT NULL::text,
  p_limit integer DEFAULT 50
)
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
             'tournament_id',     t.id,
             'created_by',        t.created_by,
             'display_name',      t.display_name,
             'format',            t.format,
             'status',            t.status,
             'started_at',        t.started_at,
             'event_starts_at',   t.event_starts_at,
             'completed_at',      t.completed_at,
             'participant_count', (
               SELECT count(*)::int FROM public.tournament_participants p
                WHERE p.tournament_id = t.id
                  AND p.registration_status = 'confirmed'
             )
           )
      FROM public.tournaments t
     WHERE (p_status_filter IS NULL OR t.status = p_status_filter)
       AND (t.status <> 'draft' OR t.created_by = v_caller)
       AND (
         t.invite_only = false
         OR t.created_by = v_caller
         OR EXISTS (
           SELECT 1 FROM public.tournament_invitations i
            WHERE i.tournament_id = t.id
              AND i.invitee_user_id = v_caller
              AND i.state <> 'revoked'
         )
       )
     ORDER BY t.started_at DESC NULLS FIRST, t.created_at DESC
     LIMIT v_limit;
END;
$function$;


-- ====================================================================
-- 3. RLS tournaments_public_read — extend with the same invite-only
--    visibility (DROP POLICY IF EXISTS + CREATE). Spec S4 Z.110-113.
--
--    The invitation EXISTS is routed through a SECURITY DEFINER helper rather
--    than an inline subquery on tournament_invitations: that table's own
--    SELECT policy references tournaments (creator check), so an inline
--    subquery here would create a mutual RLS-recursion loop between the two
--    policies. The definer helper bypasses RLS and breaks the cycle. (The
--    tournament_invitations creator check is likewise routed through
--    tournament_is_created_by_caller in S2 for the same reason.)
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_caller_has_active_invitation(
  p_tournament_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tournament_invitations i
     WHERE i.tournament_id = p_tournament_id
       AND i.invitee_user_id = auth.uid()
       AND i.state <> 'revoked'
  );
$$;
GRANT EXECUTE ON FUNCTION public.tournament_caller_has_active_invitation(uuid)
  TO authenticated;

DROP POLICY IF EXISTS tournaments_public_read ON public.tournaments;
CREATE POLICY tournaments_public_read
  ON public.tournaments FOR SELECT
  USING (
    created_by = auth.uid()
    OR (
      status <> 'draft'
      AND (
        invite_only = false
        OR public.tournament_caller_has_active_invitation(tournaments.id)
      )
    )
  );
