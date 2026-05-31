-- Hard-delete the caller's archived inbox messages.
--
-- user_inbox_messages has no DELETE RLS policy (see
-- 20260504000011_mnemonic_admin_inbox.sql) — deletes were never expected to
-- happen client-side. The archive "endgültig löschen" action (P7) needs a
-- destructive purge, so it goes through a SECURITY DEFINER function scoped to
-- the caller and to already-archived rows only.
--
-- Scope guarantees:
--   * user_id = auth.uid()        → never touches another user's inbox.
--   * archived_at IS NOT NULL     → only messages the user has actively
--                                   archived (= past / dismissed events).
-- Still-needed records such as tournament registrations live in their own
-- tables (tournament_registrations, ...) and are never affected by this.

CREATE OR REPLACE FUNCTION public.inbox_purge_archived()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller  uuid;
  v_deleted integer;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.user_inbox_messages
  WHERE user_id = v_caller
    AND archived_at IS NOT NULL;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.inbox_purge_archived() FROM public;
GRANT EXECUTE ON FUNCTION public.inbox_purge_archived() TO authenticated;

COMMENT ON FUNCTION public.inbox_purge_archived() IS
  'Hard-delete the caller''s archived inbox messages (archived_at not null). '
  'Returns the number of rows removed. Still-needed records (e.g. tournament '
  'registrations) live in other tables and are unaffected.';
