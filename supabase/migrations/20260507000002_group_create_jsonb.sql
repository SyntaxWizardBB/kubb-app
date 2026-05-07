-- Bug-fix follow-up to ADR-0012: group_create previously returned a raw
-- `uuid`, which forced the Dart client into a scalar-cast pattern
-- (`_client.rpc<String>(...)`) that no other RPC in this codebase
-- uses — every other write RPC returns `jsonb`. The mismatch
-- surfaces as a "Failed" error on the GroupsScreen after a successful
-- server-side insert.
--
-- Aligning the return type with the rest of the auth/social RPCs
-- removes one possible failure mode and keeps the surface uniform.

-- DROP first because Postgres refuses to change the return type of an
-- existing function via CREATE OR REPLACE.
DROP FUNCTION IF EXISTS public.group_create(text);

CREATE FUNCTION public.group_create(p_name text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller uuid;
  v_id     uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;
  IF length(coalesce(p_name, '')) NOT BETWEEN 1 AND 50 THEN
    RAISE EXCEPTION 'group name length must be 1..50 chars'
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.groups(owner_user_id, name)
    VALUES (v_caller, p_name)
    RETURNING id INTO v_id;

  INSERT INTO public.group_members(group_id, user_id, role)
    VALUES (v_id, v_caller, 'owner');

  RETURN jsonb_build_object('group_id', v_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.group_create(text) TO authenticated;
