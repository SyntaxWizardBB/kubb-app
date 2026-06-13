-- Spaßturnier „auf Einladung" — S2: tournament_invitations + inbox kind.
--
-- Shape mirrors public.club_invitations (20260901000012): state machine
-- pending/accepted/declined/revoked, invited_by, responded_at. One invitation
-- per (tournament, invitee). RLS: invitee OR tournament creator may SELECT;
-- the write path is SECURITY DEFINER only (no INSERT/UPDATE/DELETE policy).

CREATE TABLE IF NOT EXISTS public.tournament_invitations (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id    uuid NOT NULL
                     REFERENCES public.tournaments(id) ON DELETE CASCADE,
  invitee_user_id  uuid NOT NULL
                     REFERENCES auth.users(id) ON DELETE CASCADE,
  invited_by       uuid NOT NULL
                     REFERENCES auth.users(id) ON DELETE CASCADE,
  state            text NOT NULL DEFAULT 'pending'
                     CHECK (state IN ('pending','accepted','declined','revoked')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  responded_at     timestamptz NULL,
  UNIQUE (tournament_id, invitee_user_id)
);

-- Index for the visibility sub-query (list_for_caller / RLS lookups by invitee).
CREATE INDEX IF NOT EXISTS tournament_invitations_invitee_idx
  ON public.tournament_invitations(invitee_user_id);

ALTER TABLE public.tournament_invitations ENABLE ROW LEVEL SECURITY;

-- SECURITY DEFINER helper: is auth.uid() the creator of this tournament?
-- Used in the SELECT policy below. It MUST bypass RLS (definer) to avoid a
-- mutual-recursion loop: tournaments_public_read (S4) selects from
-- tournament_invitations, whose policy would otherwise select from tournaments
-- (re-triggering tournaments_public_read), and so on. Routing the creator
-- check through this definer function breaks that cycle.
CREATE OR REPLACE FUNCTION public.tournament_is_created_by_caller(
  p_tournament_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tournaments t
     WHERE t.id = p_tournament_id
       AND t.created_by = auth.uid()
  );
$$;
GRANT EXECUTE ON FUNCTION public.tournament_is_created_by_caller(uuid)
  TO authenticated;

-- SELECT: the invitee, or the tournament's creator. No I/U/D policy — the
-- write path runs exclusively through SECURITY DEFINER RPCs.
DROP POLICY IF EXISTS tournament_invitations_invitee_or_creator_read
  ON public.tournament_invitations;
CREATE POLICY tournament_invitations_invitee_or_creator_read
  ON public.tournament_invitations FOR SELECT
  USING (
    invitee_user_id = auth.uid()
    OR public.tournament_is_created_by_caller(tournament_invitations.tournament_id)
  );

-- Inbox notification spine: register the new kind 'tournament_invitation'.
-- DROP + ADD preserving every existing value (16 current + 1 new).
ALTER TABLE public.user_inbox_messages
  DROP CONSTRAINT IF EXISTS user_inbox_messages_kind_check;
ALTER TABLE public.user_inbox_messages
  ADD CONSTRAINT user_inbox_messages_kind_check CHECK (kind = ANY (ARRAY[
    'notice', 'verification_request', 'system', 'team_invitation',
    'team_member_removed', 'team_dissolved', 'club_invitation',
    'club_member_removed', 'club_join_request', 'tournament_started',
    'tournament_round', 'tournament_team_registered',
    'tournament_registration_confirmed', 'tournament_waitlisted',
    'tournament_promoted', 'tournament_finished',
    'tournament_invitation'
  ]::text[]));
