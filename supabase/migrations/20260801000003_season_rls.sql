-- M5.2-T7 — Row-level-security policies for the season context.
--
-- Establishes the public read surface for season data plus
-- league-admin-only write paths, in line with FR-POINTS-11 and the
-- M5 architecture decision that `seasons` and `v_season_standings`
-- behave like the M4 spectator surface (public-readable for
-- non-draft statuses, deny-by-default otherwise).
--
-- Status visibility:
--   * `open`, `closed` → public-readable (anon + authenticated)
--   * `draft`          → league-admin only (covered by the same
--                        admin write policies that grant SELECT)
--
-- Writes for the anon role remain forbidden everywhere — RLS is
-- deny-by-default and no anon write policy is declared.
--
-- `season_standings_awards` is append-only at the policy level too:
-- an INSERT policy exists, but UPDATE/DELETE policies are omitted on
-- purpose. The T6 trigger blocks UPDATE/DELETE even for league-admin;
-- the missing policy is the second line of defence.

-- ---- seasons ---------------------------------------------------------

ALTER TABLE public.seasons ENABLE ROW LEVEL SECURITY;

CREATE POLICY seasons_public_read
  ON public.seasons
  FOR SELECT
  TO anon, authenticated
  USING (status IN ('open', 'closed'));

CREATE POLICY seasons_league_admin_insert
  ON public.seasons
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.jwt() ->> 'role' = 'league_admin');

CREATE POLICY seasons_league_admin_update
  ON public.seasons
  FOR UPDATE
  TO authenticated
  USING (auth.jwt() ->> 'role' = 'league_admin')
  WITH CHECK (auth.jwt() ->> 'role' = 'league_admin');


-- ---- season_tournaments ----------------------------------------------

ALTER TABLE public.season_tournaments ENABLE ROW LEVEL SECURITY;

CREATE POLICY season_tournaments_public_read
  ON public.season_tournaments
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1
        FROM public.seasons s
       WHERE s.id = season_tournaments.season_id
         AND s.status IN ('open', 'closed')
    )
  );

CREATE POLICY season_tournaments_league_admin_insert
  ON public.season_tournaments
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.jwt() ->> 'role' = 'league_admin');

CREATE POLICY season_tournaments_league_admin_update
  ON public.season_tournaments
  FOR UPDATE
  TO authenticated
  USING (auth.jwt() ->> 'role' = 'league_admin')
  WITH CHECK (auth.jwt() ->> 'role' = 'league_admin');


-- ---- season_standings_awards -----------------------------------------
--
-- Append-only by design: only SELECT and INSERT policies exist.
-- UPDATE/DELETE are blocked by the T6 trigger AND by the absence of
-- any matching policy (deny-by-default).

ALTER TABLE public.season_standings_awards ENABLE ROW LEVEL SECURITY;

CREATE POLICY season_standings_awards_public_read
  ON public.season_standings_awards
  FOR SELECT
  TO anon, authenticated
  USING (
    EXISTS (
      SELECT 1
        FROM public.season_tournaments st
        JOIN public.seasons s ON s.id = st.season_id
       WHERE st.id = season_standings_awards.season_tournament_id
         AND s.status IN ('open', 'closed')
    )
  );

CREATE POLICY season_standings_awards_league_admin_insert
  ON public.season_standings_awards
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.jwt() ->> 'role' = 'league_admin');


-- ---- v_season_standings (public-readable view) -----------------------
--
-- The view is created by the T6 migration and runs as SECURITY
-- INVOKER (PostgreSQL default), so it inherits the RLS of the
-- underlying `season_standings_awards`. `security_barrier = false`
-- is the implicit default; we set it explicitly so that planner
-- inlining stays enabled for the standings query (<100 ms target
-- per architecture.md §3.2). The SELECT grant lets anon clients
-- query the view without authenticating.

ALTER VIEW public.v_season_standings SET (security_barrier = false);

GRANT SELECT ON public.v_season_standings TO anon, authenticated;

COMMENT ON VIEW public.v_season_standings IS
  'Public-readable season standings aggregate. Visibility is gated '
  'through the underlying season_standings_awards RLS (status IN '
  '(open, closed)).';
