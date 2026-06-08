-- Discipline-aware RLS for public.player_ratings
--
-- Source of truth: docs/ELO_RATINGS.md §5 + ProjectPlan.
--   * tournament ELO: publicly readable (leaderboard / seeding / profile).
--   * personal ELO: readable only by the owner AND accepted friends (in profile).
--
-- This replaces the single permissive "read everything" policy with two
-- discipline-scoped SELECT policies. PostgreSQL OR-combines multiple permissive
-- SELECT policies, so a row is visible if it satisfies ANY policy:
--   * a 'tournament' row is matched by player_ratings_tournament_public,
--   * a 'personal' row is matched only by player_ratings_personal_self_or_friends.
-- There is no cross-leak: a 'personal' row never satisfies discipline = 'tournament'
-- (Policy 2), and a 'tournament' row never satisfies discipline = 'personal' (Policy 3).
--
-- Write path is intentionally untouched: there is no INSERT/UPDATE/DELETE policy,
-- so writes remain SECURITY DEFINER-only. RLS stays enabled on the table.

-- 1) Remove the old "everyone reads everything" policy (+ drop the new ones
--    if present, so this migration is idempotent on re-apply).
DROP POLICY IF EXISTS player_ratings_public_read ON public.player_ratings;
DROP POLICY IF EXISTS player_ratings_tournament_public ON public.player_ratings;
DROP POLICY IF EXISTS player_ratings_personal_self_or_friends ON public.player_ratings;

-- 2) Tournament ELO is public (anon + authenticated).
CREATE POLICY player_ratings_tournament_public
  ON public.player_ratings
  FOR SELECT
  TO anon, authenticated
  USING (discipline = 'tournament');

-- 3) Personal ELO is visible to the owner and to accepted friends only.
--    friendships stores a canonical pair (low_user_id < high_user_id), so the
--    current user (auth.uid()) may be on either side of the pair; both
--    orientations are checked. Friendship counts only when status = 'accepted'.
CREATE POLICY player_ratings_personal_self_or_friends
  ON public.player_ratings
  FOR SELECT
  TO authenticated
  USING (
    discipline = 'personal'
    AND (
      user_id = auth.uid()
      OR EXISTS (
        SELECT 1
        FROM public.friendships f
        WHERE f.status = 'accepted'
          AND (
            (f.low_user_id = auth.uid() AND f.high_user_id = player_ratings.user_id)
            OR (f.low_user_id = player_ratings.user_id AND f.high_user_id = auth.uid())
          )
      )
    )
  );
