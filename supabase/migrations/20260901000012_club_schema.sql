-- Club (Verein) feature — P5 schema.
--
-- Mirrors the team feature (20260615000001_team_schema.sql) but for clubs:
-- a club header, role-carrying memberships (soft-delete via removed_at),
-- pending invitations and an append-only audit log. All mutations flow
-- through SECURITY DEFINER RPCs (companion migration 20260901000013); this
-- file declares tables, indices, the updated_at trigger, the RLS SELECT
-- policies and a non-recursive membership helper.
--
-- Founding is gated by a global code (see club_create in the RPC migration).
-- A player can belong to multiple clubs and hold multiple roles per club —
-- hence `roles text[]` rather than a single role column.


-- ---- 1. Tables --------------------------------------------------------

CREATE TABLE public.clubs (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  display_name  text NOT NULL CHECK (length(display_name) BETWEEN 1 AND 80),
  created_by    uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  dissolved_at  timestamptz NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX clubs_created_by_idx ON public.clubs(created_by);
CREATE INDEX clubs_dissolved_idx ON public.clubs(dissolved_at) WHERE dissolved_at IS NULL;


-- Allowed club roles. 'owner' and 'admin' grant management rights; the
-- remainder are functional hats a member can additionally hold. The array is
-- a set — every element must be one of these and must not be empty.
CREATE TABLE public.club_memberships (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id     uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  roles       text[] NOT NULL DEFAULT ARRAY['member']::text[]
                CHECK (
                  array_length(roles, 1) >= 1
                  AND roles <@ ARRAY[
                    'owner','admin','member','referee','timemaster',
                    'organizer','scorekeeper','treasurer'
                  ]::text[]
                ),
  joined_at   timestamptz NOT NULL DEFAULT now(),
  removed_at  timestamptz NULL,
  removed_by  uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL
);
CREATE UNIQUE INDEX club_memberships_unique_active_idx
  ON public.club_memberships(club_id, user_id)
  WHERE removed_at IS NULL;
CREATE INDEX club_memberships_user_active_idx
  ON public.club_memberships(user_id)
  WHERE removed_at IS NULL;


CREATE TABLE public.club_invitations (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id          uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  invitee_user_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  invited_by       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  state            text NOT NULL DEFAULT 'pending'
                     CHECK (state IN ('pending','accepted','declined','revoked')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  responded_at     timestamptz NULL
);
CREATE INDEX club_invitations_invitee_state_idx
  ON public.club_invitations(invitee_user_id, state);
CREATE INDEX club_invitations_club_idx
  ON public.club_invitations(club_id, state);


CREATE TABLE public.club_audit_events (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  club_id        uuid NOT NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  kind           text NOT NULL,
  actor_user_id  uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  payload        jsonb NOT NULL DEFAULT '{}'::jsonb,
  at             timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX club_audit_events_club_at_idx
  ON public.club_audit_events(club_id, at DESC);


-- ---- 2. updated_at trigger -------------------------------------------

CREATE OR REPLACE FUNCTION public.clubs_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, auth
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER clubs_set_updated_at
  BEFORE UPDATE ON public.clubs
  FOR EACH ROW EXECUTE FUNCTION public.clubs_set_updated_at();


-- ---- 3. Membership helper (non-recursive) ----------------------------
--
-- SECURITY DEFINER so it reads club_memberships without re-triggering RLS.
-- Used by the membership/invitation/audit SELECT policies — this is what
-- the team feature only learned to do in a follow-up fix (recursion bug);
-- clubs start out correct.

CREATE OR REPLACE FUNCTION public.is_active_club_member(
  p_club_id uuid,
  p_user_id uuid
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.club_memberships
     WHERE club_id = p_club_id
       AND user_id = p_user_id
       AND removed_at IS NULL
  );
$$;

REVOKE ALL ON FUNCTION public.is_active_club_member(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.is_active_club_member(uuid, uuid)
  TO authenticated, anon;


-- ---- 4. RLS policies --------------------------------------------------
--
-- All writes flow through SECURITY DEFINER RPCs. Policies below declare
-- SELECT visibility only: clubs are publicly readable; membership / invitation
-- / audit rows are visible to active members (invitee also sees their own
-- invitation).

ALTER TABLE public.clubs ENABLE ROW LEVEL SECURITY;
CREATE POLICY clubs_public_read
  ON public.clubs FOR SELECT
  USING (true);

ALTER TABLE public.club_memberships ENABLE ROW LEVEL SECURITY;
CREATE POLICY club_memberships_member_read
  ON public.club_memberships FOR SELECT
  USING (public.is_active_club_member(club_memberships.club_id, auth.uid()));

ALTER TABLE public.club_invitations ENABLE ROW LEVEL SECURITY;
CREATE POLICY club_invitations_invitee_or_member_read
  ON public.club_invitations FOR SELECT
  USING (
    invitee_user_id = auth.uid()
    OR public.is_active_club_member(club_invitations.club_id, auth.uid())
  );

ALTER TABLE public.club_audit_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY club_audit_events_member_read
  ON public.club_audit_events FOR SELECT
  USING (public.is_active_club_member(club_audit_events.club_id, auth.uid()));
