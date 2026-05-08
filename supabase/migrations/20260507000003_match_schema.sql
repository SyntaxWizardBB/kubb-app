-- Kubb Match feature — Phase 1 schema.
--
-- Five tables describe a multi-round Kubb match: the match header, the
-- two teams, the participants (in-app friends + walk-ins), the per-user
-- result proposals, and an append-only audit trail. All mutations go
-- through SECURITY DEFINER RPCs (next migration), so this file only
-- enables RLS for SELECT-side visibility.

-- ---- 1. Tables --------------------------------------------------------

CREATE TABLE public.matches (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by    uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  format        text NOT NULL CHECK (format IN ('bo1','bo3','bo5')),
  scoring       text NOT NULL CHECK (scoring IN ('wins','points')),
  status        text NOT NULL CHECK (status IN ('pending_invites','active','awaiting_results','finalized','voided')),
  current_round smallint NOT NULL DEFAULT 0 CHECK (current_round BETWEEN 0 AND 3),
  winner_team_id text NULL CHECK (winner_team_id IS NULL OR winner_team_id IN ('A','B')),
  final_score_a int NULL,
  final_score_b int NULL,
  settings      jsonb NOT NULL DEFAULT '{}'::jsonb,
  started_at    timestamptz NOT NULL DEFAULT now(),
  completed_at  timestamptz NULL,
  voided_at     timestamptz NULL
);
CREATE INDEX matches_created_by_idx ON public.matches(created_by, started_at DESC);
CREATE INDEX matches_active_idx ON public.matches(status) WHERE status IN ('pending_invites','active','awaiting_results');


CREATE TABLE public.match_teams (
  match_id     uuid NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  team_id      text NOT NULL CHECK (team_id IN ('A','B')),
  display_name text NULL,
  PRIMARY KEY (match_id, team_id)
);


CREATE TABLE public.match_participants (
  participant_id    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id          uuid NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  team_id           text NOT NULL CHECK (team_id IN ('A','B')),
  kind              text NOT NULL CHECK (kind IN ('in_app','walk_in')),
  user_id           uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  walkin_name       text NULL CHECK (walkin_name IS NULL OR length(walkin_name) BETWEEN 1 AND 40),
  invitation_status text NOT NULL CHECK (invitation_status IN ('pending','accepted','declined','left')),
  joined_at         timestamptz NOT NULL DEFAULT now(),
  responded_at      timestamptz NULL,
  CONSTRAINT match_participants_kind_shape CHECK (
    (kind='in_app'  AND user_id IS NOT NULL AND walkin_name IS NULL) OR
    (kind='walk_in' AND user_id IS NULL     AND walkin_name IS NOT NULL AND invitation_status='accepted')
  )
);
CREATE INDEX match_participants_match_idx ON public.match_participants(match_id, team_id);
CREATE INDEX match_participants_user_idx  ON public.match_participants(user_id, match_id) WHERE user_id IS NOT NULL;
CREATE UNIQUE INDEX match_participants_unique_user_per_match
  ON public.match_participants(match_id, user_id) WHERE user_id IS NOT NULL;


CREATE TABLE public.match_result_proposals (
  match_id        uuid NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  round           smallint NOT NULL CHECK (round BETWEEN 1 AND 3),
  user_id         uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  winner_team_id  text NULL CHECK (winner_team_id IS NULL OR winner_team_id IN ('A','B')),
  score_a         int NOT NULL CHECK (score_a >= 0),
  score_b         int NOT NULL CHECK (score_b >= 0),
  proposed_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (match_id, round, user_id)
);
CREATE INDEX match_result_proposals_round_idx ON public.match_result_proposals(match_id, round);


CREATE TABLE public.match_audit_events (
  id            bigserial PRIMARY KEY,
  match_id      uuid NOT NULL REFERENCES public.matches(id) ON DELETE CASCADE,
  kind          text NOT NULL,
  actor_user_id uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  payload       jsonb NOT NULL DEFAULT '{}'::jsonb,
  at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX match_audit_events_match_idx ON public.match_audit_events(match_id, at DESC);


-- ---- 2. RLS policies --------------------------------------------------
--
-- All writes flow through SECURITY DEFINER RPCs. The policies below
-- only constrain direct SELECT from the client. We deliberately do NOT
-- declare INSERT/UPDATE/DELETE policies — anything that needs to mutate
-- these tables must go through the RPC layer.

ALTER TABLE public.matches ENABLE ROW LEVEL SECURITY;
CREATE POLICY matches_participant_read
  ON public.matches FOR SELECT
  USING (
    created_by = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.match_participants mp
      WHERE mp.match_id = matches.id AND mp.user_id = auth.uid()
    )
  );

ALTER TABLE public.match_teams ENABLE ROW LEVEL SECURITY;
CREATE POLICY match_teams_participant_read
  ON public.match_teams FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.match_participants mp
      WHERE mp.match_id = match_teams.match_id AND mp.user_id = auth.uid()
    )
  );

ALTER TABLE public.match_participants ENABLE ROW LEVEL SECURITY;
CREATE POLICY match_participants_participant_read
  ON public.match_participants FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.match_participants mp2
      WHERE mp2.match_id = match_participants.match_id
        AND mp2.user_id = auth.uid()
    )
  );

ALTER TABLE public.match_result_proposals ENABLE ROW LEVEL SECURITY;
CREATE POLICY match_result_proposals_read
  ON public.match_result_proposals FOR SELECT
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.matches m
      WHERE m.id = match_result_proposals.match_id
        AND m.status IN ('finalized','voided')
        AND EXISTS (
          SELECT 1 FROM public.match_participants mp
          WHERE mp.match_id = m.id AND mp.user_id = auth.uid()
        )
    )
  );

ALTER TABLE public.match_audit_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY match_audit_events_participant_read
  ON public.match_audit_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.match_participants mp
      WHERE mp.match_id = match_audit_events.match_id
        AND mp.user_id = auth.uid()
    )
  );
