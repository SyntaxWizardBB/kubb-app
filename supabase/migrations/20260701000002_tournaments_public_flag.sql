-- M4.2 — Spectator-View: public flag plus anon read RLS.
--
-- Adds the per-tournament `public` toggle and declares anonymous
-- SELECT policies on the four tables that drive the public read
-- surface: tournaments, tournament_matches, tournament_participants,
-- tournament_set_score_proposals. Visibility is gated on both
-- `tournaments.public = true` and a non-draft, non-aborted status so
-- that draft tournaments never leak to anonymous clients.
--
-- Writes for the anon role remain forbidden everywhere: no
-- FOR INSERT/UPDATE/DELETE policy is declared, and RLS is
-- deny-by-default, so the absence of a policy is a hard block.
--
-- A privacy-projecting view `public_tournament_roster_view` exposes
-- only display names; no auth.users IDs, no email, no team membership
-- metadata. Roster anonymisation (Team X / N Spieler) is M5+.
--
-- Sources: ADR-0023, plan tasks.md M4.2-T1.

-- ---- 1. Public flag column on tournaments ----------------------------

ALTER TABLE public.tournaments
  ADD COLUMN public boolean NOT NULL DEFAULT true;


-- ---- 2. Anon-only SELECT policies ------------------------------------
--
-- The names are suffixed with `_anon_` to avoid a collision with the
-- existing authenticated `tournaments_public_read` policy from
-- 20260525000001_tournament_schema.sql (PostgreSQL requires policy
-- names to be unique per table).

CREATE POLICY tournaments_anon_public_read
  ON public.tournaments
  FOR SELECT
  TO anon
  USING (
    public = true
    AND status IN (
      'published',
      'registration_open',
      'registration_closed',
      'live',
      'finalized'
    )
  );

CREATE POLICY tournament_matches_anon_public_read
  ON public.tournament_matches
  FOR SELECT
  TO anon
  USING (
    EXISTS (
      SELECT 1
        FROM public.tournaments t
       WHERE t.id = tournament_matches.tournament_id
         AND t.public = true
         AND t.status IN (
           'published',
           'registration_open',
           'registration_closed',
           'live',
           'finalized'
         )
    )
  );

CREATE POLICY tournament_participants_anon_public_read
  ON public.tournament_participants
  FOR SELECT
  TO anon
  USING (
    EXISTS (
      SELECT 1
        FROM public.tournaments t
       WHERE t.id = tournament_participants.tournament_id
         AND t.public = true
         AND t.status IN (
           'published',
           'registration_open',
           'registration_closed',
           'live',
           'finalized'
         )
    )
  );

CREATE POLICY tournament_set_score_proposals_anon_public_read
  ON public.tournament_set_score_proposals
  FOR SELECT
  TO anon
  USING (
    EXISTS (
      SELECT 1
        FROM public.tournament_matches m
        JOIN public.tournaments t ON t.id = m.tournament_id
       WHERE m.id = tournament_set_score_proposals.match_id
         AND t.public = true
         AND t.status IN (
           'published',
           'registration_open',
           'registration_closed',
           'live',
           'finalized'
         )
    )
  );


-- ---- 3. Privacy-projecting roster view -------------------------------
--
-- Lists every active roster slot of a public tournament with only the
-- player's display name. The display name resolves to (in order):
--   1. `user_profiles.nickname` for member slots,
--   2. `team_guest_players.display_name` for guest slots,
--   3. literal 'Unbekannt' as a defensive fallback.
--
-- No user_id, email, team_id or auth metadata is projected. The view
-- runs as the invoker (SECURITY INVOKER is the default), so anon
-- clients can only see roster rows whose underlying tournament passes
-- the anon RLS policies above.

CREATE VIEW public.public_tournament_roster_view AS
SELECT
  trs.id                                                        AS slot_id,
  trs.participant_id,
  trs.slot_index,
  COALESCE(up.nickname::text, gp.display_name, 'Unbekannt')     AS display_name,
  trs.assigned_at
FROM public.tournament_roster_slots trs
LEFT JOIN public.user_profiles    up ON up.user_id = trs.member_user_id
LEFT JOIN public.team_guest_players gp ON gp.id    = trs.guest_player_id
WHERE trs.replaced_at IS NULL;

GRANT SELECT ON public.public_tournament_roster_view TO anon, authenticated;

COMMENT ON VIEW public.public_tournament_roster_view IS
  'Public spectator roster: display_name only, no user_id / email / team_id. '
  'Driven by ADR-0023 (Spectator-View — Public-Read-RLS).';

COMMENT ON COLUMN public.tournaments.public IS
  'When true, the tournament is visible to the anon role through '
  'the *_anon_public_read RLS policies. Default true per ADR-0023; '
  'organisers may opt internal tournaments out via the wizard.';
