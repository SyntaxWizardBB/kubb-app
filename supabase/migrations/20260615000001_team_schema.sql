-- Team feature — M3 schema.
--
-- Five tables describe a team and its membership lifecycle: the team
-- header, the registered pool memberships (soft-delete via removed_at),
-- the guest players (no auth account), the pending invitations, and an
-- append-only audit log. All mutations flow through SECURITY DEFINER
-- RPCs in subsequent migrations; this file declares tables, indices,
-- the updated_at trigger on the header, and RLS SELECT policies.
--
-- See ADR-0018 and docs/plans/m3-teams-pools-roster/architecture.md §3.2.
-- home_club_id is a nullable FK stub — the clubs table arrives in M5+.


-- ---- 1. Tables --------------------------------------------------------

CREATE TABLE public.teams (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name        text NOT NULL CHECK (length(display_name) BETWEEN 1 AND 60),
  logo_url            text NULL,
  home_club_id        uuid NULL,
  country             text NULL CHECK (country IS NULL OR length(country) = 2),
  league_membership   text NOT NULL DEFAULT 'B'
                        CHECK (league_membership IN ('A','B','C')),
  created_by          uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  dissolved_at        timestamptz NULL,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX teams_created_by_idx ON public.teams(created_by);
CREATE INDEX teams_dissolved_idx ON public.teams(dissolved_at) WHERE dissolved_at IS NULL;


CREATE TABLE public.team_memberships (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id     uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at   timestamptz NOT NULL DEFAULT now(),
  removed_at  timestamptz NULL,
  removed_by  uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE UNIQUE INDEX team_memberships_unique_active_idx
  ON public.team_memberships(team_id, user_id)
  WHERE removed_at IS NULL;
CREATE INDEX team_memberships_user_active_idx
  ON public.team_memberships(user_id)
  WHERE removed_at IS NULL;


CREATE TABLE public.team_guest_players (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id             uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  display_name        text NOT NULL CHECK (length(display_name) BETWEEN 1 AND 40),
  claimed_by_user_id  uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  added_by            uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  added_at            timestamptz NOT NULL DEFAULT now(),
  removed_at          timestamptz NULL
);
CREATE INDEX team_guest_players_team_idx
  ON public.team_guest_players(team_id)
  WHERE removed_at IS NULL;


CREATE TABLE public.team_invitations (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id          uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  invitee_user_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invited_by       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  state            text NOT NULL DEFAULT 'pending'
                     CHECK (state IN ('pending','accepted','declined','revoked')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  responded_at     timestamptz NULL
);
CREATE INDEX team_invitations_invitee_state_idx
  ON public.team_invitations(invitee_user_id, state);
CREATE INDEX team_invitations_team_idx
  ON public.team_invitations(team_id, state);


CREATE TABLE public.team_audit_events (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  team_id        uuid NOT NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  kind           text NOT NULL,
  actor_user_id  uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  payload        jsonb NOT NULL DEFAULT '{}'::jsonb,
  at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX team_audit_events_team_at_idx
  ON public.team_audit_events(team_id, at DESC);


-- ---- 2. updated_at trigger on teams ----------------------------------

CREATE OR REPLACE FUNCTION public.teams_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, auth
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER teams_set_updated_at
  BEFORE UPDATE ON public.teams
  FOR EACH ROW EXECUTE FUNCTION public.teams_set_updated_at();


-- ---- 3. RLS policies --------------------------------------------------
--
-- All writes flow through SECURITY DEFINER RPCs (subsequent migrations).
-- The policies below only declare SELECT visibility:
--
--   * teams: public read (team search per FR-PUB-9).
--   * team_memberships, team_guest_players: visible to any pool member
--     of the team. Anonymous aggregate views are out of scope for M3.
--   * team_invitations: visible to the invitee and pool members.
--   * team_audit_events: visible to pool members only.

ALTER TABLE public.teams ENABLE ROW LEVEL SECURITY;

CREATE POLICY teams_public_read
  ON public.teams FOR SELECT
  USING (true);


ALTER TABLE public.team_memberships ENABLE ROW LEVEL SECURITY;

CREATE POLICY team_memberships_pool_read
  ON public.team_memberships FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.team_memberships m
      WHERE m.team_id = team_memberships.team_id
        AND m.user_id = auth.uid()
        AND m.removed_at IS NULL
    )
  );


ALTER TABLE public.team_guest_players ENABLE ROW LEVEL SECURITY;

CREATE POLICY team_guest_players_pool_read
  ON public.team_guest_players FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.team_memberships m
      WHERE m.team_id = team_guest_players.team_id
        AND m.user_id = auth.uid()
        AND m.removed_at IS NULL
    )
  );


ALTER TABLE public.team_invitations ENABLE ROW LEVEL SECURITY;

CREATE POLICY team_invitations_invitee_or_pool_read
  ON public.team_invitations FOR SELECT
  USING (
    invitee_user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.team_memberships m
      WHERE m.team_id = team_invitations.team_id
        AND m.user_id = auth.uid()
        AND m.removed_at IS NULL
    )
  );


ALTER TABLE public.team_audit_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY team_audit_events_pool_read
  ON public.team_audit_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.team_memberships m
      WHERE m.team_id = team_audit_events.team_id
        AND m.user_id = auth.uid()
        AND m.removed_at IS NULL
    )
  );
