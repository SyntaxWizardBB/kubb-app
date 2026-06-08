-- H1 (Tournament-Hub V1): expose `event_starts_at` on the discovery list.
--
-- The hub's "Kuenftige Turniere" tile filters the discovery list by the
-- scheduled kickoff date (>= today 00:00 OR undated). The list RPC only
-- projected `started_at` so far; this migration adds the existing
-- `tournaments.event_starts_at` column to the jsonb projection.
--
-- ADDITIVE ONLY: CREATE OR REPLACE based on the CURRENT live definition
-- (last touched by 20260525000003, verified via pg_get_functiondef). The
-- only change vs. that body is the extra `'event_starts_at'` json key —
-- signature, security, ordering and every existing key stay identical, so
-- older clients keep decoding cleanly.

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
     ORDER BY t.started_at DESC NULLS FIRST, t.created_at DESC
     LIMIT v_limit;
END;
$function$;
