-- M7-Fix-HIGH-2 — Account-Deletion ohne Service-Role-Key.
--
-- Vorher rief der Mobile-Client `_client.auth.admin.deleteUser(userId)`
-- direkt. Das setzt den Service-Role-Key im Bundle voraus — und der
-- darf dort nie liegen, sonst ist RLS effektiv deaktiviert. Liegt er
-- nicht im Bundle, scheitert die Deletion zur Laufzeit silent.
--
-- Stattdessen eine RPC mit SECURITY DEFINER, die ausschliesslich den
-- aktuell authentifizierten User löscht. auth.uid() löst aus dem
-- Request-JWT auf, also kann der Aufrufer keinen fremden Account
-- treffen. Die FK-Cascades auf user_credentials, user_keypair_backups
-- und user_profiles räumen die abhängigen Daten transaktional mit auf
-- (siehe 20260504000001_auth_tables.sql — alle Referenzen auf
-- auth.users(id) sind ON DELETE CASCADE).

CREATE OR REPLACE FUNCTION auth.fn_delete_current_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'fn_delete_current_account requires an authenticated session'
      USING ERRCODE = '42501';
  END IF;
  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

COMMENT ON FUNCTION auth.fn_delete_current_account IS
  'Hard-delete the currently authenticated user. FK cascades clean up '
  'user_credentials, user_keypair_backups and user_profiles. Replaces '
  'the client-side admin.deleteUser call which would have required the '
  'service-role key in the app bundle.';

REVOKE ALL ON FUNCTION auth.fn_delete_current_account() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION auth.fn_delete_current_account() TO authenticated;


-- Public-Wrapper, damit PostgREST den Aufruf findet (siehe
-- 20260504000007_public_rpc_wrappers.sql für das gleiche Pattern bei
-- den anderen Auth-RPCs).

CREATE OR REPLACE FUNCTION public.fn_delete_current_account()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = auth, public
AS $$
  SELECT auth.fn_delete_current_account();
$$;

GRANT EXECUTE ON FUNCTION public.fn_delete_current_account()
  TO authenticated;
