-- Sprint-C W2-T2: Profile-Visibility-Field + visibility-aware RLS
-- read policy fuer `user_profiles`.
--
-- Refs:
--   - R20-F-02 (Profile-Visibility-Settings fehlen komplett, FR-AUTH-5,
--     DSGVO Art. 25 Privacy-by-Default)
--   - R20-F-10 (Friends-only-Privacy nirgends umgesetzt, FR-SOCIAL-4)
--   - Spec/Tests: supabase/tests/profile_visibility_rls_test.sql
--
-- Visibility-Modell:
--   'public'       => jeder authenticated User darf die Row lesen
--   'friends_only' => Owner + accepted-friends duerfen lesen
--   'private'      => nur der Owner darf lesen
--
-- Privacy-Floor (DSGVO Art. 25): Default ist 'friends_only', d.h. neue
-- Accounts sind nicht standardmaessig fuer Fremde sichtbar. Der User
-- muss aktiv auf 'public' opt-in-en.
--
-- Anon-Caller bekommen IMMER deny — der oeffentliche Lesepfad laeuft
-- ausschliesslich ueber die `public_*`-RPCs (ADR-0026 Strategie A).
-- Diese Migration ersetzt die `user_profiles_owner_read`-Policy aus
-- `20260504000003_auth_rls.sql`; die neue Policy ist der einzige Read-
-- Pfad fuer `authenticated` und subsumiert den Owner-Read-Case.


-- ---- 1. Column + CHECK constraint -----------------------------------

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS profile_visibility text NOT NULL
    DEFAULT 'friends_only'
    CHECK (profile_visibility IN ('public', 'friends_only', 'private'));

COMMENT ON COLUMN public.user_profiles.profile_visibility IS
  'Visibility tier for the profile row: public (every authenticated '
  'user), friends_only (owner + accepted friends; default for privacy-'
  'by-default per DSGVO Art. 25), private (owner only). Anon callers '
  'never see this table directly — public spectator paths go through '
  'public_* RPCs (ADR-0026 Strategie A).';


-- ---- 2. RLS read policy ---------------------------------------------
--
-- Replace the legacy owner-only read policy with a single
-- visibility-aware policy. The new policy fully subsumes the owner case
-- (auth.uid() = user_id) and adds the friends-only / public branches.
-- All other CRUD policies (owner_insert / owner_update) stay untouched
-- because writes are always owner-bounded.

DROP POLICY IF EXISTS user_profiles_owner_read ON public.user_profiles;

CREATE POLICY user_profiles_visibility_aware_read
  ON public.user_profiles
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id
    OR profile_visibility = 'public'
    OR (
      profile_visibility = 'friends_only'
      AND EXISTS (
        SELECT 1
          FROM public.friendships f
         WHERE f.status = 'accepted'
           AND (
             (f.low_user_id  = auth.uid() AND f.high_user_id = user_profiles.user_id)
             OR
             (f.low_user_id  = user_profiles.user_id AND f.high_user_id = auth.uid())
           )
      )
    )
  );

COMMENT ON POLICY user_profiles_visibility_aware_read
  ON public.user_profiles IS
  'Single read path for authenticated callers; honours '
  'profile_visibility (public / friends_only / private). Owner always '
  'sees their own row. Anon never sees this table — spectator data '
  'goes through public_* RPCs (ADR-0026 Strategie A).';
