-- Sprint C tail of Sprint B Maengel #2.1 (R19-F-03, R20-F-01):
-- The /social/groups surface was removed in Sprint B; teams replace the
-- groups concept per ADR-0018. The DB-side tables and RPCs from
-- 20260507000001_social_graph.sql and the 20260507000002 jsonb-return
-- fix are now dead weight. Drop them so the schema matches the client.

-- RPCs first (they hold no hard dependency on the tables, so CASCADE on
-- the tables would not remove them).
DROP FUNCTION IF EXISTS public.group_create(text);
DROP FUNCTION IF EXISTS public.group_rename(uuid, text);
DROP FUNCTION IF EXISTS public.group_delete(uuid);
DROP FUNCTION IF EXISTS public.group_invite_member(uuid, uuid);
DROP FUNCTION IF EXISTS public.group_remove_member(uuid, uuid);
DROP FUNCTION IF EXISTS public.group_list_for_caller();
DROP FUNCTION IF EXISTS public.group_members_for(uuid);

-- Tables: group_members first (FK to groups), then groups.
DROP TABLE IF EXISTS public.group_members CASCADE;
DROP TABLE IF EXISTS public.groups CASCADE;
