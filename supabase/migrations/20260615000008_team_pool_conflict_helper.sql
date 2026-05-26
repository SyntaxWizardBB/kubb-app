-- M3.2-T12: Pool-Conflict-Helper-RPC.
--
-- Returns the active pool of a team annotated with a `conflicted` flag
-- per member. A member is conflicted relative to a tournament when they
-- already hold an open roster slot in another participant of the same
-- tournament (BR-5 mitigation, see R-M3-G2).
--
-- Contract for T13 (`RosterCompositionWidget`):
--   `[{user_id, display_name, conflicted}]`
--
-- Spec: docs/plans/m3-teams-pools-roster/tasks.md TASK-M3.2-T12.


CREATE OR REPLACE FUNCTION public.team_pool_with_tournament_conflicts(
  p_team_id       uuid,
  p_tournament_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_result jsonb;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'user_id',      m.user_id,
           'display_name', up.nickname,
           'conflicted',   EXISTS (
             SELECT 1
               FROM public.tournament_roster_slots s
               JOIN public.tournament_participants p ON p.id = s.participant_id
              WHERE s.member_user_id = m.user_id
                AND s.replaced_at IS NULL
                AND p.tournament_id = p_tournament_id
                AND (p.team_id IS NULL OR p.team_id <> p_team_id)
           )
         ) ORDER BY up.nickname NULLS LAST, m.user_id), '[]'::jsonb)
    INTO v_result
    FROM public.team_memberships m
    LEFT JOIN public.user_profiles up ON up.user_id = m.user_id
   WHERE m.team_id = p_team_id
     AND m.removed_at IS NULL;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.team_pool_with_tournament_conflicts(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.team_pool_with_tournament_conflicts(uuid, uuid) TO authenticated;
