-- OAuth-an-Keypair-Konto serverseitig reconcilen (ADR-0042).
--
-- Schema-Delta für den Reconcile-Flow aus
-- docs/plans/oauth-account-link/architecture.md §Migration. Kein neues
-- Column: oauth_subject, der (kind, oauth_subject)-Unique-Index und der
-- Shape-CHECK existieren bereits in 20260504000001_auth_tables.sql.
--
-- (A) Partieller Unique-Index, damit ein User höchstens je eine
--     oauth_google- und oauth_apple-Zeile hält. keypair bleibt
--     ausgenommen, da es nie kollidieren soll. Macht die Idempotenz des
--     Reconcile zur DB-Invariante statt App-Logik.
-- (B) reconcile_link_oauth — SECURITY DEFINER, nur über Service-Role
--     erreichbar. Bindet die bewiesene OAuth-Identität an die bewiesene
--     Keypair-user_id und löscht den geforkten auth.users-Eintrag in
--     derselben Transaktion.

CREATE UNIQUE INDEX IF NOT EXISTS user_credentials_user_kind_idx
  ON user_credentials (user_id, kind)
  WHERE kind <> 'keypair';


CREATE OR REPLACE FUNCTION public.reconcile_link_oauth(
  p_keypair_user_id uuid,
  p_kind            text,
  p_oauth_subject   text,
  p_forked_user_id  uuid
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_deleted  boolean := false;
  v_bound_to uuid;
BEGIN
  IF p_kind NOT IN ('oauth_google', 'oauth_apple') THEN
    RAISE EXCEPTION 'invalid kind %', p_kind USING ERRCODE = '22023';
  END IF;

  -- Defence-in-depth: the edge function already runs the collision guard,
  -- but a subject bound to a different user must never be re-pointed here.
  -- No insert, no delete on this path — the takeover block.
  SELECT user_id INTO v_bound_to
  FROM user_credentials
  WHERE kind = p_kind
    AND oauth_subject = p_oauth_subject;

  IF v_bound_to IS NOT NULL AND v_bound_to <> p_keypair_user_id THEN
    RAISE EXCEPTION 'OAUTH_SUBJECT_IN_USE' USING ERRCODE = '23505';
  END IF;

  INSERT INTO user_credentials (user_id, kind, oauth_subject)
  VALUES (p_keypair_user_id, p_kind, p_oauth_subject)
  ON CONFLICT (kind, oauth_subject) WHERE oauth_subject IS NOT NULL
  DO NOTHING;

  IF p_forked_user_id <> p_keypair_user_id THEN
    DELETE FROM auth.users WHERE id = p_forked_user_id;
    v_deleted := true;
  END IF;

  RETURN jsonb_build_object(
    'user_id', p_keypair_user_id,
    'kind', p_kind,
    'oauth_subject', p_oauth_subject,
    'forked_user_deleted', v_deleted
  );
END;
$$;


REVOKE ALL ON FUNCTION public.reconcile_link_oauth(uuid, text, text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reconcile_link_oauth(uuid, text, text, uuid) TO service_role;
