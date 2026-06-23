-- Match-RLS recursion fix + matches CDC SELECT grant.
--
-- Bug: match_participants_participant_read (20260507000003_match_schema.sql)
-- is self-referential — its USING subquery reads public.match_participants,
-- so evaluating the policy re-evaluates the policy → infinite recursion.
-- The inline EXISTS on matches_participant_read hits the same table during
-- a matches read, so direct SELECTs on matches recurse too.
--
--   SET ROLE authenticated; SELECT count(*) FROM public.match_participants;
--   → 'infinite recursion detected in policy for relation match_participants'
--
-- Fix (PART A): move the membership check into a SECURITY DEFINER helper.
-- The function owner reads its own table without re-evaluating RLS, so the
-- recursion is broken. The user_id = auth.uid() predicate stays inside the
-- helper — without it every authenticated caller could read every match.
--
-- Fix (PART B): the matches SELECT grant alone is inert. matches_participant_read
-- still reads match_participants inline (the EXISTS subquery), and authenticated
-- has no SELECT grant on that table (RPC-only, ADR-0013). RLS evaluates the
-- subquery under the caller's privileges, so every authenticated matches read —
-- creator included — fails with 42501 before the policy predicate even matters.
-- So PART B also reroutes the participant branch through the same DEFINER helper:
-- the membership probe runs under the function owner, match_participants keeps
-- its zero-grant surface, and authenticated can finally read matches.

-- ---- PART A — break the recursion ------------------------------------

CREATE OR REPLACE FUNCTION public._is_match_participant(p_match_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.match_participants mp
                 WHERE mp.match_id = p_match_id AND mp.user_id = auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public._is_match_participant(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public._is_match_participant(uuid) TO authenticated;

DROP POLICY match_participants_participant_read ON public.match_participants;
CREATE POLICY match_participants_participant_read ON public.match_participants
  FOR SELECT TO authenticated USING (public._is_match_participant(match_participants.match_id));

-- ---- PART B — matches CDC SELECT grant + helper-routed policy --------
--
-- Realtime needs a SELECT grant on matches to deliver the matches:id channel.
-- matches_participant_read scopes reads to created_by OR participant, so the
-- grant exposes nothing the policy does not already allow.

GRANT SELECT ON public.matches TO authenticated;

-- The grant is useless while the policy still reads match_participants inline:
-- that subquery is evaluated under the caller, who has no SELECT grant there
-- (RPC-only, ADR-0013), so the whole read 42501s. Route the participant branch
-- through the DEFINER helper instead — same semantics (participant OR creator),
-- same id filter (now passed as the helper argument), but the membership probe
-- runs under the function owner. match_participants keeps its NO-grant surface.
--
-- Role: the original policy had no TO clause, so it applied to PUBLIC (anon
-- included). matches has no anon SELECT grant anywhere, so anon could never
-- read it regardless; scoping to authenticated matches the only reachable role
-- and mirrors the tournaments narrowing in 20261307 — no weakening of the
-- authenticated path, just dropping a role that has no grant.

DROP POLICY matches_participant_read ON public.matches;
CREATE POLICY matches_participant_read ON public.matches
  FOR SELECT TO authenticated
  USING (created_by = auth.uid() OR public._is_match_participant(matches.id));
