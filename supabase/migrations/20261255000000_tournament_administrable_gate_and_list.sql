-- Phase B (ADR-0031) Block B1s — administrable-gate referee + dashboard list RPC.
--
-- PURELY ADDITIVE. Two CREATE OR REPLACE FUNCTION statements (+ their REVOKE/
-- GRANT) and nothing else: no table/column/policy is altered or dropped, no
-- DELETE/TRUNCATE/db reset. Migration band starts at 20261255000000 (B).
--
-- ============================ PART A (K1 + K4) ===========================
-- tournament_caller_can_manage(uuid) is RE-BASED on its genuine latest on-disk
-- definition in 20261201000031_tournament_club_link.sql (Z.60-88) — NOT the
-- 20261201000032 companion, which only CALLS the helper (README K1). The
-- ONLY change vs that source is the role overlap array (K4): the organizer-
-- dashboard / schedule-control gate now also admits the club 'referee' role.
--   ARRAY['owner','admin','organizer']        (031)
--   ARRAY['owner','admin','organizer','referee'] (here)
-- Signature, RETURNS boolean, LANGUAGE sql, SECURITY DEFINER, STABLE,
-- SET search_path = public, auth, the Creator branch, the whole EXISTS body and
-- the REVOKE/GRANT are byte-identical to the 031 source. Verified via gate
-- body-diff vs 031 (only the role-array line differs).
--
-- ============================ PART B =====================================
-- tournament_list_administrable(p_limit) RETURNS SETOF jsonb — the multi-
-- tournament organizer-dashboard overview. Auth-guard mirrors
-- tournament_list_for_caller (20260525000005): auth.uid() NULL -> 42501,
-- limit range 1..500 -> 22023. Filters WHERE t.status IN ('published','live')
-- AND public.tournament_caller_can_manage(t.id) so only administrable
-- published/live tournaments surface (draft/finalized/etc. excluded). A
-- LEFT JOIN onto tournament_round_schedule keeps tournaments without a schedule
-- row (schedule-derived fields then NULL). remaining_seconds uses the ADR-0031
-- server restzeit formula on app_server_now() (effective_elapsed with
-- paused_accum_seconds and paused_at). open_match_count counts matches in
-- scheduled|awaiting_results, disputed_match_count counts disputed.
--
-- ============================ DEPENDENCIES ===============================
-- Requires (all earlier on disk):
--   * public.tournament_caller_can_manage(uuid) — 20261201000031 (re-based here).
--   * public.tournament_round_schedule — 20261251000000 (LEFT JOIN source).
--   * public.app_server_now() — 20261254000000 (server clock for the formula).
--   * public.tournament_matches(status) — 20260525000001 (count source).
-- =====================================================================


-- ====================================================================
-- PART A — gate: admit club 'referee' (K1 re-base on 031, K4 role set).
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_caller_can_manage(
  p_tournament_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
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
               AND (cm.roles && ARRAY['owner','admin','organizer','referee']::text[])
         ))
       )
  );
$$;

REVOKE ALL ON FUNCTION public.tournament_caller_can_manage(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_caller_can_manage(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_caller_can_manage(uuid) IS
  'Per-tournament manage authority: caller is created_by OR an active '
  'owner/admin/organizer/referee of the tournament''s club_id. NULL club_id '
  '=> creator only. Re-based on 20261201000031 (README K1); referee added per '
  'K4 (ADR-0031). See 20261255000000_tournament_administrable_gate_and_list.sql.';


-- ====================================================================
-- PART B — tournament_list_administrable: organizer-dashboard overview.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_list_administrable(
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
      -- LEFT JOIN: keep administrable tournaments that have no schedule row yet
      -- (ON true preserves schedule-less rows -> semantically the plan's plain
      -- "LEFT JOIN tournament_round_schedule"). The LATERAL sub-select is an
      -- intentional refinement beyond the bare plan wording: a tournament can
      -- have several schedule rows (one per round), so we pick the *active round*
      -- = the highest round_number whose status is not 'completed' (created_at
      -- breaks ties). That single row feeds current_round / schedule_status /
      -- remaining_seconds; schedule-less tournaments still surface with NULLs.
      LEFT JOIN LATERAL (
        SELECT srs.*
          FROM public.tournament_round_schedule srs
         WHERE srs.tournament_id = t.id
           AND srs.status <> 'completed'
         ORDER BY srs.round_number DESC, srs.created_at DESC
         LIMIT 1
      ) s ON true
     WHERE t.status IN ('published','live')
       AND public.tournament_caller_can_manage(t.id)
     ORDER BY t.started_at DESC NULLS FIRST, t.created_at DESC
     LIMIT v_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.tournament_list_administrable(int) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_list_administrable(int)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_list_administrable(int) IS
  'ADR-0031 Block B1s: multi-tournament organizer-dashboard overview. Returns '
  'administrable published/live tournaments (gate tournament_caller_can_manage, '
  'K4 roles) with current_round, schedule_status, remaining_seconds (server '
  'restzeit formula on app_server_now()), open/disputed match counts, paused_at. '
  'LEFT JOIN tournament_round_schedule keeps schedule-less tournaments. '
  'Auth-guard mirrors tournament_list_for_caller.';
