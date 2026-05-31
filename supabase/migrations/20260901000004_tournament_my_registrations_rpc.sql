-- P1 (Tournament-Hub): "my registrations" discovery RPC.
--
-- Returns every tournament the caller is actively registered for (status
-- in pending/confirmed/waitlist — i.e. not rejected/withdrawn), so the
-- hub's "Angemeldete Turniere" tile can list them with a self-withdraw
-- action. Mirrors the projection of tournament_list_for_caller and adds
-- the caller's own participant_id + registration_status so the client can
-- drive tournament_withdraw without a second lookup.
--
-- SECURITY DEFINER + the explicit `user_id = auth.uid()` filter means a
-- caller only ever sees their own registration rows; no foreign data leaks.

CREATE OR REPLACE FUNCTION public.tournament_list_my_registrations(
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
             'tournament_id',       t.id,
             'created_by',          t.created_by,
             'display_name',        t.display_name,
             'format',              t.format,
             'status',              t.status,
             'started_at',          t.started_at,
             'completed_at',        t.completed_at,
             'participant_count',   (
               SELECT count(*)::int FROM public.tournament_participants pc
                WHERE pc.tournament_id = t.id
                  AND pc.registration_status = 'confirmed'
             ),
             'participant_id',      p.id,
             'registration_status', p.registration_status
           )
      FROM public.tournament_participants p
      JOIN public.tournaments t ON t.id = p.tournament_id
     WHERE p.user_id = v_caller
       AND p.registration_status IN ('pending', 'confirmed', 'waitlist')
     ORDER BY t.started_at DESC NULLS FIRST, t.created_at DESC
     LIMIT v_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_list_my_registrations(int)
  TO authenticated;
