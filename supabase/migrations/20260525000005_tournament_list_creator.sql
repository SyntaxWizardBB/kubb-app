-- Extends `tournament_list_for_caller` so each row also carries the
-- `created_by` column. The list screen needs this to filter the
-- "Meine Turniere" tab by ownership rather than guessing from the
-- lifecycle status (which produced false positives once drafts were
-- published).
--
-- Nothing else about the function changes — same params, same RLS
-- guard, same ORDER BY, same authenticated grant. The added key is
-- nullable on the Dart side, so old clients keep working.

CREATE OR REPLACE FUNCTION public.tournament_list_for_caller(
  p_status_filter text DEFAULT NULL,
  p_limit         int  DEFAULT 50
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
             'tournament_id',     t.id,
             'created_by',        t.created_by,
             'display_name',      t.display_name,
             'format',            t.format,
             'status',            t.status,
             'started_at',        t.started_at,
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
$$;

GRANT EXECUTE ON FUNCTION public.tournament_list_for_caller(text, int)
  TO authenticated;
