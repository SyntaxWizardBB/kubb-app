-- SRV-03 (ADR-0029, messaging-framework-plan §(d) + §(h) + Phase P7): team membership
-- changes drive both the per-team roster CDC channel
-- (team_memberships:team_id=<id>) and the "my teams" list discovery
-- (team_memberships:user_id=<uid>). Add the table to the (NOT "FOR ALL TABLES")
-- supabase_realtime publication so Postgres emits row-level change events.
--
-- REPLICA IDENTITY stays DEFAULT ('d'); the consumer refreshes on the new row and
-- never inspects the OLD row, so REPLICA IDENTITY FULL is not set.
ALTER PUBLICATION supabase_realtime ADD TABLE public.team_memberships;

-- §(h) RLS filter-column risk: a CDC subscription can only filter on ONE indexed
-- column, and Realtime evaluates the SELECT policy against that filter column. The
-- existing team_memberships_pool_read authorises the team_id scope
-- (is_active_team_member(team_id, auth.uid())) but does NOT authorise a row scoped
-- only by user_id, so the "my teams" user_id=<uid> filter would be denied.
--
-- Additive fix: a self-read policy authorising a user's own membership rows. This
-- is purely additive (RLS policies are OR-combined), so team_memberships_pool_read
-- and is_active_team_member are left completely untouched.
CREATE POLICY team_memberships_self_read
  ON public.team_memberships FOR SELECT
  USING (user_id = auth.uid());
