-- SRV-04 (ADR-0029, messaging-framework-plan §(d) + §(h) + Phase P7): tournament
-- participant changes drive the per-tournament roster CDC channel
-- (tournament_participants:tournament_id=<id>) and the "my tournaments" list
-- discovery (tournament_participants:user_id=<uid>). Add the table to the (NOT
-- "FOR ALL TABLES") supabase_realtime publication so Postgres emits change events.
--
-- REPLICA IDENTITY stays DEFAULT ('d'); the consumer refreshes on the new row and
-- never inspects the OLD row, so REPLICA IDENTITY FULL is not set.
ALTER PUBLICATION supabase_realtime ADD TABLE public.tournament_participants;

-- §(h) RLS filter-column risk: the existing SELECT policies all gate on
-- tournament_id —
--   * tournament_participants_read            (non-draft or own draft)
--   * tournament_participants_anon_public_read (public + visible status)
-- (the _self_register INSERT and _self_withdraw UPDATE policies do not grant
-- SELECT). None of them authorise a row scoped only by user_id, so the
-- "my tournaments" user_id=<uid> CDC filter would be denied.
--
-- Additive fix: a self-read policy authorising a user's own participant rows.
-- Purely additive (policies OR-combine); the four existing policies
-- (_read, _anon_public_read, _self_register, _self_withdraw) are left untouched.
CREATE POLICY tournament_participants_self_read
  ON public.tournament_participants FOR SELECT
  USING (user_id = auth.uid());
