-- Reactivate an aborted tournament.
--
-- Aborting a tournament currently overwrites status with 'aborted' and loses
-- the status it had before. To "Fortsetzen" (continue where it was) we need to
-- remember that prior status, so this migration:
--   1. adds tournaments.pre_abort_status (nullable, additive — old rows stay
--      NULL and fall back to 'draft' on reactivate)
--   2. re-defines tournament_abort to snapshot the current status into
--      pre_abort_status before flipping to 'aborted' (behaviour otherwise
--      unchanged: same gate, same allowed source states, same audit event)
--   3. adds tournament_reactivate(uuid): only an aborted tournament, only a
--      setup-capable caller (creator OR club owner/admin), restores
--      coalesce(pre_abort_status,'draft'), clears completed_at and the
--      snapshot, and writes a 'reactivated' audit event.
--
-- Authorisation mirrors tournament_abort: public.tournament_caller_can_setup
-- (the gate-split SETUP authority — creator OR an active organizer-team role in
-- {owner, admin}). The deprecated tournament_caller_can_manage alias now maps
-- to ADMINISTER (which also lets referees through); reactivating is a
-- structural lifecycle move, so SETUP is the correct gate and keeps it 1:1 with
-- who could abort in the first place.
--
-- Base body for tournament_abort: 20261283000000_rename_organizer_teams.sql
-- (the latest on-disk definition). The only change is the pre_abort_status
-- snapshot in the UPDATE.

ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS pre_abort_status text;

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

  -- PER-TOURNAMENT: creator OR owner/admin/organizer of the organizer_team_id.
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
    SET pre_abort_status = v_status,
        status = 'aborted',
        completed_at = now()
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (p_tournament_id, 'aborted', v_caller, '{}'::jsonb);
END;
$function$;

CREATE OR REPLACE FUNCTION public.tournament_reactivate(p_tournament_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_created_by uuid;
  v_restored   text;
  v_pre        text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by, pre_abort_status
    INTO v_status, v_created_by, v_pre
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_setup(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;
  IF v_status <> 'aborted' THEN
    RAISE EXCEPTION 'only an aborted tournament can be reactivated'
      USING ERRCODE = '22023';
  END IF;

  v_restored := coalesce(v_pre, 'draft');

  UPDATE public.tournaments
    SET status = v_restored,
        completed_at = NULL,
        pre_abort_status = NULL
    WHERE id = p_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'reactivated',
      v_caller,
      jsonb_build_object('restored_status', v_restored));
END;
$function$;

REVOKE ALL ON FUNCTION public.tournament_reactivate(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_reactivate(uuid) TO authenticated;
