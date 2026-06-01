-- Tournament feature — per-tournament organizing club + manage helper.
--
-- USER DECISION (supersedes 20261201000030's GLOBAL organizer capability):
-- a tournament has an OPTIONAL organizing club (tournaments.club_id). Who
-- may manage/edit/start a tournament =
--   the CREATOR (tournaments.created_by)
--   OR an active owner/admin/organizer of THAT tournament's club_id.
-- A tournament with NO club_id is manageable by the creator ONLY.
--
-- This migration adds the link column + a per-tournament SECURITY DEFINER
-- helper `tournament_caller_can_manage(p_tournament_id)`. The companion
-- migration 20261201000032 re-gates every lifecycle/update RPC onto this
-- helper, replacing the over-broad `tournament_caller_is_organizer()`
-- (20261201000030) which returned true for ~everyone because
-- user_profiles.is_organizer DEFAULTs true.
--
-- ============================ DEPENDENCIES ============================
-- Requires (must already exist, all earlier on disk):
--   * public.tournaments (20260525000001_tournament_schema.sql) — target of
--     the new club_id column; PK is `id uuid`.
--   * public.clubs (20260901000012_club_schema.sql) — FK target; PK `id uuid`.
--   * public.club_memberships(club_id, user_id, roles text[], removed_at)
--     (20260901000012_club_schema.sql) — the role source. `roles` is a
--     text[] set including {owner,admin,organizer,...}; an active row has
--     removed_at IS NULL (unique active row per (club_id,user_id)).
-- Mirrors the role predicate of public.club_caller_can_publish()
--   (20260901000016 §9) but scoped to ONE club_id instead of "any club".
-- =====================================================================


-- ---- 1. tournaments.club_id ------------------------------------------
-- Optional organizing club. ON DELETE SET NULL: dissolving/deleting the
-- club row must not delete the tournament — it simply loses its club link
-- (and thereby its club-based manage authority, leaving the creator).

ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS club_id uuid NULL
    REFERENCES public.clubs(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS tournaments_club_idx
  ON public.tournaments(club_id)
  WHERE club_id IS NOT NULL;

COMMENT ON COLUMN public.tournaments.club_id IS
  'Optional organizing club. NULL = no club (creator-only authority). '
  'Owner/admin/organizer of this club may manage the tournament alongside '
  'the creator — see public.tournament_caller_can_manage().';


-- ---- 2. tournament_caller_can_manage ---------------------------------
-- Per-tournament authority. True when the caller is the tournament's
-- creator, OR the tournament has a club_id and the caller is an active
-- owner/admin/organizer of THAT club. SECURITY DEFINER + STABLE so it can
-- read created_by / club_memberships without re-triggering RLS; reads only.
--
-- Returns false (never raises) when the tournament does not exist or the
-- caller is anon — call sites layer their own not-found / not-authorised
-- 42501, exactly as they did with created_by.

CREATE OR REPLACE FUNCTION public.tournament_caller_can_manage(
  p_tournament_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM public.tournaments t
     WHERE t.id = p_tournament_id
       AND (
         -- Creator: unchanged behaviour.
         t.created_by = auth.uid()
         OR
         -- Club owner/admin/organizer of THIS tournament's club.
         (t.club_id IS NOT NULL AND EXISTS (
            SELECT 1
              FROM public.club_memberships cm
             WHERE cm.club_id = t.club_id
               AND cm.user_id = auth.uid()
               AND cm.removed_at IS NULL
               AND (cm.roles && ARRAY['owner','admin','organizer']::text[])
         ))
       )
  );
$$;

REVOKE ALL ON FUNCTION public.tournament_caller_can_manage(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.tournament_caller_can_manage(uuid)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_caller_can_manage(uuid) IS
  'Per-tournament manage authority: caller is created_by OR an active '
  'owner/admin/organizer of the tournament''s club_id. NULL club_id => '
  'creator only. Replaces the global tournament_caller_is_organizer(). '
  'See 20261201000031_tournament_club_link.sql.';
