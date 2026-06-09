-- Phase A / Block A3b (ADR-0031 §Uhr): server-authoritative clock source.
--
-- The timed tournament runner derives a skew offset on the client
-- (offset = server_now - local_now) and renders `now = DateTime.now() + offset`
-- with a pure 1s UI ticker (no per-second push, no polling — ADR-0029).
-- This RPC is the rare offset-sync source called at app start / reconnect.
--
-- NEW function (not previously defined in the repo): no stale-body re-base
-- applies. STABLE so it can be inlined per statement; returns server now()
-- as `timestamptz` (UTC), which the client compares against
-- DateTime.now().toUtc(). EXECUTE granted to authenticated AND anon so the
-- public live spectator view can correct its clock too.

CREATE OR REPLACE FUNCTION public.app_server_now()
RETURNS timestamptz
LANGUAGE sql
STABLE
AS $$ SELECT now(); $$;

GRANT EXECUTE ON FUNCTION public.app_server_now() TO authenticated, anon;
