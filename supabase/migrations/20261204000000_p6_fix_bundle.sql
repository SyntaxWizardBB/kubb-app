-- ======================================================================
-- 20261204000000_p6_fix_bundle — P6 review fixes C5/C6/C9/C11.
--
-- This migration ONLY re-states (CREATE OR REPLACE) the latest bodies of the
-- affected functions from 20261202000000 / 20261203000000 with the surgical
-- fixes applied. No reset, no destructive DDL. Each replaced body is the latest
-- version with the change clearly marked "P6-FIX Cnn".
--
--   C5  [major]   tournament_report_shootout_winners / tournament_confirm_shootout
--                 + NEW column tournament_shootouts.reported_participant_id
--                 + NEW helper _tournament_shootout_participant_of:
--                 enforce REAL two-sided consensus (a different PARTICIPANT/TEAM
--                 must confirm, not just a different user of the SAME team).
--   C6  [major]   tournament_start_ko_phase default (non-pool) seed CTE:
--                 rank chain-gated total_points-first (matching the detector /
--                 SHOOTOUT-RESOLVE / pool_standings), not "wins DESC, kubb_diff".
--   C9  [blocker] tournament_advance_ko_winner consolation-internal progression:
--                 auto-resolve structural byes in consolation rounds r>=2 as
--                 walkovers (ADR-0028 §4) so survivors are never stranded.
--   C11 [major]   tournament_start_ko_phase consolation mainSize: honour the
--                 persisted consolation_bracket->>'main_bracket_size' (ADR-0028
--                 §5) instead of always next_pow2(qualifier_count).
--
-- Code comments English; UI/doc strings German (project convention).
-- ======================================================================


-- ======================================================================
-- C5 — column + helper for participant-level shoot-out consensus.
-- ======================================================================

-- The participant (solo/team) the reporter belongs to. Consensus must come
-- from a DIFFERENT participant, not merely a different app-user (two members of
-- the same open team are distinct users but the SAME participant).
ALTER TABLE public.tournament_shootouts
  ADD COLUMN IF NOT EXISTS reported_participant_id uuid NULL
    REFERENCES public.tournament_participants(id) ON DELETE SET NULL;

-- Resolves the tied participant of the group p_tied that p_user belongs to:
--   * solo: tournament_participants.user_id = p_user
--   * team: an ACTIVE roster slot (replaced_at IS NULL) with member_user_id
-- Returns NULL when the user is not part of any tied participant.
CREATE OR REPLACE FUNCTION public._tournament_shootout_participant_of(
  p_tournament_id uuid,
  p_tied          uuid[],
  p_user          uuid
)
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT pid FROM (
    -- Solo participants.
    SELECT p.id AS pid
      FROM public.tournament_participants p
     WHERE p.tournament_id = p_tournament_id
       AND p.id = ANY(p_tied)
       AND p.user_id = p_user
    UNION
    -- Team participants: active open roster members.
    SELECT p.id AS pid
      FROM public.tournament_participants p
      JOIN public.tournament_roster_slots s
        ON s.participant_id = p.id
     WHERE p.tournament_id = p_tournament_id
       AND p.id = ANY(p_tied)
       AND p.team_id IS NOT NULL
       AND s.replaced_at IS NULL
       AND s.member_user_id = p_user
  ) q
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public._tournament_shootout_participant_of(uuid, uuid[], uuid) FROM PUBLIC;

COMMENT ON FUNCTION public._tournament_shootout_participant_of(uuid, uuid[], uuid) IS
  'C5: resolves the tied PARTICIPANT (solo via user_id, team via active roster '
  'slot) a user belongs to within a shoot-out group, NULL if none. Used to '
  'enforce real two-sided consensus (report/confirm by different participants).';


CREATE OR REPLACE FUNCTION public.tournament_report_shootout_winners(
  p_shootout_id     uuid,
  p_ordered_winners uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller    uuid;
  v_tid       uuid;
  v_tied      uuid[];
  v_status    text;
  v_reporter_part uuid;   -- P6-FIX C5
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT tournament_id, tied_participant_ids, status
    INTO v_tid, v_tied, v_status
    FROM public.tournament_shootouts
   WHERE id = p_shootout_id
   FOR UPDATE;

  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'shoot-out not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status = 'resolved' THEN
    RAISE EXCEPTION 'ALREADY_RESOLVED: shoot-out already resolved'
      USING ERRCODE = '22023';
  END IF;

  -- P6-FIX C5: resolve the reporter's PARTICIPANT (not just user) and store it,
  -- so confirmation can require a different participant/team.
  v_reporter_part := public._tournament_shootout_participant_of(v_tid, v_tied, v_caller);
  IF v_reporter_part IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHORISED: caller is not part of this shoot-out group'
      USING ERRCODE = '42501';
  END IF;

  PERFORM public._tournament_validate_shootout_order(v_tied, p_ordered_winners);

  -- Record the report; reset any prior (mismatched) confirmation.
  UPDATE public.tournament_shootouts
     SET ordered_winners = p_ordered_winners,
         status          = 'reported',
         reported_by     = v_caller,
         reported_participant_id = v_reporter_part,   -- P6-FIX C5
         reported_at     = now(),
         confirmed_by    = NULL,
         confirmed_at    = NULL
   WHERE id = p_shootout_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (v_tid, 'shootout_reported', v_caller,
            jsonb_build_object(
              'shootout_id',     p_shootout_id,
              'ordered_winners', to_jsonb(p_ordered_winners)));

  RETURN jsonb_build_object(
    'shootout_id', p_shootout_id,
    'status',      'reported',
    'ordered_winners', to_jsonb(p_ordered_winners));
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_report_shootout_winners(uuid, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tournament_report_shootout_winners(uuid, uuid[]) TO authenticated;


CREATE OR REPLACE FUNCTION public.tournament_confirm_shootout(
  p_shootout_id     uuid,
  p_ordered_winners uuid[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_tid        uuid;
  v_tied       uuid[];
  v_status     text;
  v_reported   uuid[];
  v_reported_part uuid;     -- P6-FIX C5
  v_confirmer_part uuid;    -- P6-FIX C5
  v_match      boolean;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT tournament_id, tied_participant_ids, status,
         ordered_winners, reported_participant_id
    INTO v_tid, v_tied, v_status, v_reported, v_reported_part
    FROM public.tournament_shootouts
   WHERE id = p_shootout_id
   FOR UPDATE;

  IF v_tid IS NULL THEN
    RAISE EXCEPTION 'shoot-out not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_status = 'resolved' THEN
    -- Idempotent: already resolved.
    RETURN jsonb_build_object(
      'shootout_id', p_shootout_id, 'status', 'resolved',
      'ordered_winners', to_jsonb(v_reported));
  END IF;
  IF v_status <> 'reported' OR v_reported IS NULL THEN
    RAISE EXCEPTION 'NOT_REPORTED: no winner ordering has been reported yet'
      USING ERRCODE = '22023';
  END IF;

  -- P6-FIX C5: real two-sided consensus. The confirmer must belong to a
  -- DIFFERENT tied participant (team/solo) than the reporter. Two members of
  -- the SAME open team are distinct users but the same participant and must NOT
  -- be able to resolve a shoot-out between the participating teams (spec
  -- P6_SHOOTOUT_TIEBREAK §4: the involved TEAMS confirm each other).
  v_confirmer_part := public._tournament_shootout_participant_of(v_tid, v_tied, v_caller);
  IF v_confirmer_part IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHORISED: caller is not part of this shoot-out group'
      USING ERRCODE = '42501';
  END IF;
  IF v_confirmer_part IS NOT DISTINCT FROM v_reported_part THEN
    RAISE EXCEPTION 'NOT_AUTHORISED: confirmation must come from a different participant/team'
      USING ERRCODE = '42501';
  END IF;

  -- The confirmation must agree with the reported ordering exactly.
  v_match := (p_ordered_winners = v_reported);
  IF NOT v_match THEN
    RAISE EXCEPTION 'ORDER_MISMATCH: confirmation does not match the reported ordering'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.tournament_shootouts
     SET status       = 'resolved',
         confirmed_by = v_caller,
         confirmed_at = now()
   WHERE id = p_shootout_id;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (v_tid, 'shootout_resolved', v_caller,
            jsonb_build_object(
              'shootout_id',     p_shootout_id,
              'ordered_winners', to_jsonb(v_reported)));

  RETURN jsonb_build_object(
    'shootout_id', p_shootout_id,
    'status',      'resolved',
    'ordered_winners', to_jsonb(v_reported));
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_confirm_shootout(uuid, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.tournament_confirm_shootout(uuid, uuid[]) TO authenticated;


-- ======================================================================
-- C6 + C11 — tournament_start_ko_phase (latest body from 20261203000000,
-- re-stated verbatim with two surgical fixes):
--   * C6 : the default (non-pool) seed ranking is chain-gated total_points-first
--          (matching the detector / SHOOTOUT-RESOLVE / pool_standings) instead
--          of "wins DESC, kubb_diff DESC". v_chain is now loaded BEFORE the seed
--          block so both pool and non-pool paths share one canonical order.
--   * C11: the consolation main-bracket size honours the persisted
--          consolation_bracket->>'main_bracket_size' (ADR-0028 §5) when present,
--          falling back to next_pow2(qualifier_count).
-- ======================================================================
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
  v_round             smallint;   -- PITCH-PLAN loop variable
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
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start_ko_phase(uuid, jsonb)
  TO authenticated;


-- ======================================================================
-- C9 — tournament_advance_ko_winner (latest body from 20261203000000,
-- re-stated verbatim) + a bye-walkover resolver for consolation rounds r>=2.
--
-- ADR-0028 §4 requires per-entry-round byes (P_r - E_r) to auto-advance as
-- walkovers, exactly like R1 byes. The original body only materialised/resolved
-- R1 byes; in rounds r>=2 a structural bye match (A=survivor, B never fed)
-- stayed 'scheduled' forever, stranding the survivor (32er D=0 and every
-- non-pow2 entry population). The fix: when a consolation survivor is written
-- into the A-slot of a MAJOR (fresh-feed) next round whose B-slot is a
-- structural bye (never fed), finalize that match kampflos so the AFTER-UPDATE
-- trigger fires recursively and carries the bye winner onward.
--
-- Bye identification (parity with _tournament_compute_cons_bracket /
-- _tournament_cons_drop_slot): main-round-r losers dock B-slots via reflection
-- starting at the HIGHEST consPairing, so the L_{r} fed B-slots are the top
-- (high-index) pairings. The unfed (bye) B-slots are therefore the low-index
-- pairings 1..(matches_r - L_r), where L_r = mainSize / 2^r (number of main
-- round-r matches). A match at v_next_position is a bye iff
-- v_next_position <= matches_{next} - L_{next}.
-- ======================================================================
CREATE OR REPLACE FUNCTION public.tournament_advance_ko_winner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public, auth
AS $$
DECLARE
  v_loser_part      uuid;
  v_next_round      int;
  v_next_position   int;
  v_is_odd          boolean;
  v_third_enabled   boolean;
  v_final_round     int;
  v_next_a          uuid;
  v_next_b          uuid;
  v_next_status     text;
  v_tp_a            uuid;
  v_tp_b            uuid;
  v_tp_status       text;
  -- DE locals:
  v_wb_count        int;
  v_size            int;
  v_lb_count        int;
  v_lb_target_round int;
  v_lb_slot0        int;
  v_lb_target_pos   int;
  v_lb_side_b       boolean;
  v_with_reset      boolean;
  v_gf_round        int;
  -- CONSOLATION (E2) locals:
  v_cons_exists     int;
  v_main_rounds     int;
  v_main_size       int;
  v_cons_target     int;
  v_cons_matches    int;
  v_cons_slot0      int;
  v_cons_pos        int;
  v_cons_side_b     boolean;
  v_cons_rounds     int;
  v_cons_p1         int;
  v_e1              int;
  -- P6-FIX C9 locals:
  v_next_matches    int;       -- pairings in the next consolation round
  v_next_lr         int;       -- L_{next} fed losers into the next cons round
BEGIN
  IF NEW.winner_participant IS NULL THEN
    RETURN NEW;
  END IF;

  v_loser_part := CASE
    WHEN NEW.winner_participant = NEW.participant_a THEN NEW.participant_b
    WHEN NEW.winner_participant = NEW.participant_b THEN NEW.participant_a
    ELSE NULL
  END;

  v_next_round    := NEW.round_number + 1;
  v_next_position := (NEW.bracket_position + 1) / 2;
  v_is_odd        := (NEW.bracket_position % 2) = 1;

  -- =====================================================================
  -- SINGLE-ELIMINATION PATH (verbatim).
  -- =====================================================================
  IF NEW.phase IN ('ko','final') THEN
    SELECT participant_a, participant_b, status
      INTO v_next_a, v_next_b, v_next_status
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND round_number  = v_next_round
        AND bracket_position = v_next_position
        AND phase IN ('ko','final')
      FOR UPDATE;

    IF FOUND THEN
      IF v_is_odd THEN
        v_next_a := NEW.winner_participant;
      ELSE
        v_next_b := NEW.winner_participant;
      END IF;

      IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
         AND v_next_status = 'scheduled' THEN
        v_next_status := 'awaiting_results';
      END IF;

      UPDATE public.tournament_matches
        SET participant_a = v_next_a,
            participant_b = v_next_b,
            status        = v_next_status
        WHERE tournament_id = NEW.tournament_id
          AND round_number  = v_next_round
          AND bracket_position = v_next_position
          AND phase IN ('ko','final');
    END IF;
  END IF;

  IF NEW.phase = 'ko' AND v_loser_part IS NOT NULL THEN
    SELECT (t.ko_config ->> 'with_third_place_playoff')::boolean
      INTO v_third_enabled
      FROM public.tournaments t
      WHERE t.id = NEW.tournament_id;

    IF COALESCE(v_third_enabled, false) THEN
      SELECT MAX(round_number)
        INTO v_final_round
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'final';

      IF v_final_round IS NOT NULL AND v_next_round = v_final_round THEN
        SELECT participant_a, participant_b, status
          INTO v_tp_a, v_tp_b, v_tp_status
          FROM public.tournament_matches
          WHERE tournament_id    = NEW.tournament_id
            AND round_number     = v_final_round
            AND bracket_position = 1
            AND phase            = 'third_place'
          FOR UPDATE;

        IF FOUND THEN
          IF v_is_odd THEN
            v_tp_a := v_loser_part;
          ELSE
            v_tp_b := v_loser_part;
          END IF;

          IF v_tp_a IS NOT NULL AND v_tp_b IS NOT NULL
             AND v_tp_status = 'scheduled' THEN
            v_tp_status := 'awaiting_results';
          END IF;

          UPDATE public.tournament_matches
            SET participant_a = v_tp_a,
                participant_b = v_tp_b,
                status        = v_tp_status
            WHERE tournament_id    = NEW.tournament_id
              AND round_number     = v_final_round
              AND bracket_position = 1
              AND phase            = 'third_place';
        END IF;
      END IF;
    END IF;
  END IF;

  -- =====================================================================
  -- DOUBLE-ELIMINATION PATH (verbatim).
  -- =====================================================================
  IF NEW.phase IN ('wb','lb','grand_final','grand_final_reset') THEN
    SELECT MAX(round_number) INTO v_wb_count
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND phase = 'wb';
    v_size := (1 << v_wb_count);
    v_lb_count := 2 * (v_wb_count - 1);
  END IF;

  IF NEW.phase = 'wb' THEN
    IF NEW.round_number < v_wb_count THEN
      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND round_number  = v_next_round
          AND bracket_position = v_next_position
          AND phase = 'wb'
        FOR UPDATE;
      IF FOUND THEN
        IF v_is_odd THEN v_next_a := NEW.winner_participant;
        ELSE             v_next_b := NEW.winner_participant; END IF;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_next_a,
              participant_b = v_next_b,
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND round_number  = v_next_round
            AND bracket_position = v_next_position
            AND phase = 'wb';
      END IF;
    ELSE
      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'grand_final'
          AND round_number = 1
          AND bracket_position = 1
        FOR UPDATE;
      IF FOUND THEN
        v_next_a := NEW.winner_participant;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_next_a, status = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'grand_final'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;

    IF v_loser_part IS NOT NULL AND v_lb_count > 0 THEN
      IF NEW.round_number = 1 THEN
        v_lb_target_round := 1;
        v_lb_target_pos   := ((v_size >> 2) - 1) - ((NEW.bracket_position - 1) / 2) + 1;
        v_lb_side_b       := ((NEW.bracket_position - 1) % 2) = 1;
      ELSE
        v_lb_target_round := 2 * NEW.round_number - 2;
        v_lb_slot0        := public._tournament_de_lb_target(
                               NEW.round_number, NEW.bracket_position, v_size);
        v_lb_target_pos   := (v_lb_slot0 / 2) + 1;
        v_lb_side_b       := (v_lb_slot0 % 2) = 1;
      END IF;

      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'lb'
          AND round_number = v_lb_target_round
          AND bracket_position = v_lb_target_pos
        FOR UPDATE;
      IF FOUND THEN
        IF v_lb_side_b THEN v_next_b := v_loser_part;
        ELSE                v_next_a := v_loser_part; END IF;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_next_a,
              participant_b = v_next_b,
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'lb'
            AND round_number = v_lb_target_round
            AND bracket_position = v_lb_target_pos;
      END IF;
    END IF;
  END IF;

  IF NEW.phase = 'lb' THEN
    IF NEW.round_number < v_lb_count THEN
      IF (NEW.round_number % 2) = 1 THEN
        v_lb_target_round := NEW.round_number + 1;
        v_lb_target_pos   := NEW.bracket_position;
        v_lb_side_b       := false;
      ELSE
        v_lb_target_round := NEW.round_number + 1;
        v_lb_target_pos   := (NEW.bracket_position + 1) / 2;
        v_lb_side_b       := (NEW.bracket_position % 2) = 0;
      END IF;

      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'lb'
          AND round_number = v_lb_target_round
          AND bracket_position = v_lb_target_pos
        FOR UPDATE;
      IF FOUND THEN
        IF v_lb_side_b THEN v_next_b := NEW.winner_participant;
        ELSE                v_next_a := NEW.winner_participant; END IF;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_next_a,
              participant_b = v_next_b,
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'lb'
            AND round_number = v_lb_target_round
            AND bracket_position = v_lb_target_pos;
      END IF;
    ELSE
      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'grand_final'
          AND round_number = 1
          AND bracket_position = 1
        FOR UPDATE;
      IF FOUND THEN
        v_next_b := NEW.winner_participant;
        IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
           AND v_next_status = 'scheduled' THEN
          v_next_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_b = v_next_b, status = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'grand_final'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;
  END IF;

  IF NEW.phase = 'grand_final' THEN
    SELECT coalesce((t.ko_config ->> 'with_bracket_reset')::boolean, true)
      INTO v_with_reset
      FROM public.tournaments t
      WHERE t.id = NEW.tournament_id;

    IF NEW.winner_participant = NEW.participant_b AND COALESCE(v_with_reset, true) THEN
      SELECT status INTO v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'grand_final_reset'
          AND round_number = 1
          AND bracket_position = 1
        FOR UPDATE;
      IF FOUND THEN
        v_next_status := CASE WHEN v_next_status = 'scheduled'
                              THEN 'awaiting_results' ELSE v_next_status END;
        UPDATE public.tournament_matches
          SET participant_a = NEW.participant_a,
              participant_b = NEW.participant_b,
              status        = v_next_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'grand_final_reset'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;
  END IF;

  -- =====================================================================
  -- CONSOLATION ROUTING (E2, ADR-0028 §7.4).
  -- =====================================================================

  -- (A) MAIN-LOSER FEED.
  IF NEW.phase IN ('ko','final') AND v_loser_part IS NOT NULL THEN
    SELECT count(*) INTO v_cons_exists
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND phase = 'consolation';

    IF v_cons_exists > 0 THEN
      SELECT MAX(round_number) INTO v_main_rounds
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase IN ('ko','final');
      v_main_size := (1 << v_main_rounds);

      v_cons_target := public._tournament_cons_drop_target(
                         NEW.round_number, v_main_size);

      IF v_cons_target >= 1 THEN
        IF v_cons_target = 1 THEN
          SELECT count(*) * 2 INTO v_cons_p1
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = 1;
          SELECT entrants INTO v_e1
            FROM public._tournament_cons_shape(
                   v_main_size,
                   greatest(0,
                     coalesce((SELECT (consolation_bracket ->> 'direct_count')::int
                                 FROM public.tournaments
                                WHERE id = NEW.tournament_id), 0)))
           WHERE round = 1;
          v_cons_slot0 := public._tournament_cons_seed_slot(
                            (v_e1 - (v_main_size / 2)) + (NEW.bracket_position - 1),
                            v_cons_p1);
          v_cons_pos    := (v_cons_slot0 / 2) + 1;
          v_cons_side_b := (v_cons_slot0 % 2) = 1;

          SELECT participant_a, participant_b, status
            INTO v_next_a, v_next_b, v_next_status
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = 1
              AND bracket_position = v_cons_pos
            FOR UPDATE;
          IF FOUND THEN
            IF v_cons_side_b THEN v_next_b := v_loser_part;
            ELSE                  v_next_a := v_loser_part; END IF;
            IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
               AND v_next_status = 'scheduled' THEN
              v_next_status := 'awaiting_results';
            END IF;
            UPDATE public.tournament_matches
              SET participant_a = v_next_a,
                  participant_b = v_next_b,
                  status        = v_next_status
              WHERE tournament_id = NEW.tournament_id
                AND phase = 'consolation'
                AND round_number = 1
                AND bracket_position = v_cons_pos;
          END IF;
        ELSE
          SELECT count(*) INTO v_cons_matches
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = v_cons_target;
          v_cons_slot0 := public._tournament_cons_drop_slot(
                            NEW.bracket_position, v_cons_matches);
          v_cons_pos    := (v_cons_slot0 / 2) + 1;
          v_cons_side_b := (v_cons_slot0 % 2) = 1;

          SELECT participant_a, participant_b, status
            INTO v_next_a, v_next_b, v_next_status
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = v_cons_target
              AND bracket_position = v_cons_pos
            FOR UPDATE;
          IF FOUND THEN
            IF v_cons_side_b THEN v_next_b := v_loser_part;
            ELSE                  v_next_a := v_loser_part; END IF;
            IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
               AND v_next_status = 'scheduled' THEN
              v_next_status := 'awaiting_results';
            END IF;
            UPDATE public.tournament_matches
              SET participant_a = v_next_a,
                  participant_b = v_next_b,
                  status        = v_next_status
              WHERE tournament_id = NEW.tournament_id
                AND phase = 'consolation'
                AND round_number = v_cons_target
                AND bracket_position = v_cons_pos;
          END IF;
        END IF;
      END IF;
    END IF;
  END IF;

  -- (B) CONSOLATION-INTERNAL progression + consolation 3rd-place mirror.
  IF NEW.phase = 'consolation' THEN
    SELECT MAX(round_number) INTO v_cons_rounds
      FROM public.tournament_matches
      WHERE tournament_id = NEW.tournament_id
        AND phase = 'consolation';

    IF NEW.round_number < v_cons_rounds THEN
      SELECT MAX(round_number) INTO v_main_rounds
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase IN ('ko','final');
      v_main_size := (1 << v_main_rounds);

      IF public._tournament_cons_drop_target(v_next_round, v_main_size) >= 1 THEN
        -- MAJOR (fresh-feed) round: survivor maps 1:1 into the A-slot.
        v_next_position := NEW.bracket_position;
        v_is_odd        := true;  -- A-slot
      END IF;

      SELECT participant_a, participant_b, status
        INTO v_next_a, v_next_b, v_next_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'consolation'
          AND round_number = v_next_round
          AND bracket_position = v_next_position
        FOR UPDATE;
      IF FOUND THEN
        IF v_is_odd THEN v_next_a := NEW.winner_participant;
        ELSE             v_next_b := NEW.winner_participant; END IF;

        -- P6-FIX C9: if this MAJOR next-round match's B-slot is a structural
        -- bye (never fed by a staggered main loser), resolve it kampflos so the
        -- AFTER-UPDATE trigger fires recursively and the bye survivor advances.
        -- The fed B-slots are the top (high-index) L_{next} pairings; the unfed
        -- bye pairings are the low-index 1..(matches_next - L_next). L_{next} =
        -- mainSize / 2^v_next_round (number of main round-(v_next_round) matches,
        -- which is also the count of consolation losers fed into that round).
        IF v_is_odd AND v_next_a IS NOT NULL AND v_next_b IS NULL THEN
          SELECT count(*) INTO v_next_matches
            FROM public.tournament_matches
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = v_next_round;
          v_next_lr := v_main_size / (1 << v_next_round);
          IF v_next_position <= (v_next_matches - v_next_lr) THEN
            -- Structural bye: A advances kampflos. Set status 'scheduled' ->
            -- 'finalized' transition so the trigger re-fires for this row.
            UPDATE public.tournament_matches
              SET participant_a      = v_next_a,
                  winner_participant = v_next_a,
                  status             = 'finalized',
                  finalized_at       = now()
              WHERE tournament_id = NEW.tournament_id
                AND phase = 'consolation'
                AND round_number = v_next_round
                AND bracket_position = v_next_position;
            -- Skip the normal scheduled/awaiting update for this row.
            v_next_status := NULL;
          END IF;
        END IF;

        IF v_next_status IS NOT NULL THEN
          IF v_next_a IS NOT NULL AND v_next_b IS NOT NULL
             AND v_next_status = 'scheduled' THEN
            v_next_status := 'awaiting_results';
          END IF;
          UPDATE public.tournament_matches
            SET participant_a = v_next_a,
                participant_b = v_next_b,
                status        = v_next_status
            WHERE tournament_id = NEW.tournament_id
              AND phase = 'consolation'
              AND round_number = v_next_round
              AND bracket_position = v_next_position;
        END IF;
      END IF;
    END IF;

    IF v_loser_part IS NOT NULL
       AND v_cons_rounds >= 2
       AND NEW.round_number = v_cons_rounds - 1 THEN
      SELECT participant_a, participant_b, status
        INTO v_tp_a, v_tp_b, v_tp_status
        FROM public.tournament_matches
        WHERE tournament_id = NEW.tournament_id
          AND phase = 'consolation_third_place'
          AND round_number = 1
          AND bracket_position = 1
        FOR UPDATE;
      IF FOUND THEN
        IF (NEW.bracket_position % 2) = 1 THEN
          v_tp_a := v_loser_part;
        ELSE
          v_tp_b := v_loser_part;
        END IF;
        IF v_tp_a IS NOT NULL AND v_tp_b IS NOT NULL
           AND v_tp_status = 'scheduled' THEN
          v_tp_status := 'awaiting_results';
        END IF;
        UPDATE public.tournament_matches
          SET participant_a = v_tp_a,
              participant_b = v_tp_b,
              status        = v_tp_status
          WHERE tournament_id = NEW.tournament_id
            AND phase = 'consolation_third_place'
            AND round_number = 1
            AND bracket_position = 1;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tournament_advance_ko_winner ON public.tournament_matches;
CREATE TRIGGER tournament_advance_ko_winner
  AFTER UPDATE ON public.tournament_matches
  FOR EACH ROW
  WHEN (
    OLD.status NOT IN ('finalized','overridden')
    AND NEW.status     IN ('finalized','overridden')
    AND NEW.phase      IN ('ko','third_place','final',
                           'wb','lb','grand_final','grand_final_reset',
                           'consolation','consolation_third_place')
  )
  EXECUTE FUNCTION public.tournament_advance_ko_winner();
