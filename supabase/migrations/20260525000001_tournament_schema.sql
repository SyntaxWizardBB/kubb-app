-- Tournament feature — M1 schema.
--
-- Five tables describe a tournament: the tournament header, the
-- registered participants, the scheduled matches, the per-user
-- per-set score proposals (with consensus-retry semantics, max 3
-- attempts), and an append-only audit trail. All mutations flow
-- through SECURITY DEFINER RPCs in subsequent migrations; this file
-- only declares tables, indices, RLS SELECT policies, and the
-- updated_at trigger on the header table.

-- ---- 1. Tables --------------------------------------------------------

CREATE TABLE public.tournaments (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by               uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  display_name             text NOT NULL CHECK (length(display_name) BETWEEN 1 AND 60),
  team_size                smallint NOT NULL CHECK (team_size BETWEEN 1 AND 6),
  min_participants         smallint NOT NULL DEFAULT 2 CHECK (min_participants >= 2),
  max_participants         smallint NOT NULL CHECK (max_participants BETWEEN min_participants AND 200),
  format                   text NOT NULL CHECK (format IN (
                             'round_robin','single_elimination','round_robin_then_ko',
                             'schoch','swiss','schoch_then_ko','swiss_then_ko')),
  scoring                  text NOT NULL CHECK (scoring IN ('ekc','classic')),
  match_format             jsonb NOT NULL,
  tiebreaker_order         text[] NOT NULL DEFAULT ARRAY[
                             'total_points','buchholz_minus_h2h','direct_comparison','wins'],
  bye_points               int NOT NULL DEFAULT 0,
  forfeit_points           int NOT NULL DEFAULT 18,
  status                   text NOT NULL DEFAULT 'draft' CHECK (status IN (
                             'draft','published','registration_open','registration_closed',
                             'live','finalized','aborted')),
  registration_opens_at    timestamptz NULL,
  registration_closes_at   timestamptz NULL,
  started_at               timestamptz NULL,
  completed_at             timestamptz NULL,
  published_at             timestamptz NULL,
  created_at               timestamptz NOT NULL DEFAULT now(),
  updated_at               timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX tournaments_status_created_idx ON public.tournaments(status, created_at DESC);
CREATE INDEX tournaments_created_by_idx ON public.tournaments(created_by);


CREATE TABLE public.tournament_participants (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id       uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  user_id             uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  registration_status text NOT NULL DEFAULT 'pending' CHECK (registration_status IN (
                        'pending','confirmed','rejected','withdrawn','waitlist')),
  seed                int NULL,
  registered_at       timestamptz NOT NULL DEFAULT now(),
  responded_at        timestamptz NULL,
  withdrew_at         timestamptz NULL,
  CONSTRAINT tournament_participants_unique_user UNIQUE (tournament_id, user_id)
);
CREATE INDEX tournament_participants_status_idx
  ON public.tournament_participants(tournament_id, registration_status);


CREATE TABLE public.tournament_matches (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id           uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  round_number            smallint NOT NULL CHECK (round_number BETWEEN 1 AND 99),
  match_number_in_round   smallint NOT NULL CHECK (match_number_in_round >= 1),
  participant_a           uuid NULL REFERENCES public.tournament_participants(id) ON DELETE CASCADE,
  participant_b           uuid NULL REFERENCES public.tournament_participants(id) ON DELETE CASCADE,
  pitch_number            smallint NULL,
  status                  text NOT NULL DEFAULT 'scheduled' CHECK (status IN (
                            'scheduled','awaiting_results','disputed','finalized',
                            'overridden','voided')),
  consensus_round         smallint NOT NULL DEFAULT 1 CHECK (consensus_round BETWEEN 1 AND 3),
  winner_participant      uuid NULL REFERENCES public.tournament_participants(id),
  final_score_a           int NULL,
  final_score_b           int NULL,
  started_at              timestamptz NULL,
  finalized_at            timestamptz NULL,
  created_at              timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX tournament_matches_round_idx
  ON public.tournament_matches(tournament_id, round_number, match_number_in_round);
CREATE INDEX tournament_matches_status_idx
  ON public.tournament_matches(tournament_id, status);
CREATE INDEX tournament_matches_participant_a_idx
  ON public.tournament_matches(participant_a);
CREATE INDEX tournament_matches_participant_b_idx
  ON public.tournament_matches(participant_b);


CREATE TABLE public.tournament_set_score_proposals (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  match_id                 uuid NOT NULL REFERENCES public.tournament_matches(id) ON DELETE CASCADE,
  consensus_round          smallint NOT NULL CHECK (consensus_round BETWEEN 1 AND 3),
  set_number               smallint NOT NULL CHECK (set_number BETWEEN 1 AND 9),
  submitter_user_id        uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  basekubbs_knocked_by_a   smallint NOT NULL CHECK (basekubbs_knocked_by_a BETWEEN 0 AND 6),
  basekubbs_knocked_by_b   smallint NOT NULL CHECK (basekubbs_knocked_by_b BETWEEN 0 AND 6),
  set_winner               text NOT NULL CHECK (set_winner IN ('A','B','none')),
  proposed_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tournament_set_score_proposals_unique_slot
    UNIQUE (match_id, consensus_round, set_number, submitter_user_id)
);
CREATE INDEX tournament_set_score_proposals_round_idx
  ON public.tournament_set_score_proposals(match_id, consensus_round);


CREATE TABLE public.tournament_audit_events (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id  uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  match_id       uuid NULL REFERENCES public.tournament_matches(id) ON DELETE CASCADE,
  kind           text NOT NULL,
  actor_user_id  uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  payload        jsonb NULL,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX tournament_audit_events_tournament_idx
  ON public.tournament_audit_events(tournament_id, created_at DESC);


-- ---- 2. updated_at trigger on tournaments ----------------------------

CREATE OR REPLACE FUNCTION public.tournaments_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, auth
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER tournaments_set_updated_at
  BEFORE UPDATE ON public.tournaments
  FOR EACH ROW EXECUTE FUNCTION public.tournaments_set_updated_at();


-- ---- 3. RLS policies --------------------------------------------------
--
-- All writes flow through SECURITY DEFINER RPCs (subsequent migrations).
-- The policies below only declare SELECT visibility plus the narrow
-- direct-write paths the spec demands:
--
--   * tournaments: creator inserts, creator updates own header (RPCs
--     handle status-transition rules), creator deletes own draft.
--   * tournament_participants: a user may self-register (INSERT their
--     own row, registration_status='pending') and self-withdraw
--     (UPDATE to 'withdrawn'); the organizer manages everything else
--     via RPC.
--
-- All other mutations on tournament_matches, tournament_set_score_-
-- proposals and tournament_audit_events go through RPCs only — no
-- INSERT/UPDATE/DELETE policy declared, so direct client writes fail.

ALTER TABLE public.tournaments ENABLE ROW LEVEL SECURITY;

CREATE POLICY tournaments_public_read
  ON public.tournaments FOR SELECT
  USING (status <> 'draft' OR created_by = auth.uid());

CREATE POLICY tournaments_creator_insert
  ON public.tournaments FOR INSERT
  WITH CHECK (created_by = auth.uid());

CREATE POLICY tournaments_creator_update
  ON public.tournaments FOR UPDATE
  USING (created_by = auth.uid())
  WITH CHECK (created_by = auth.uid());

CREATE POLICY tournaments_creator_delete_draft
  ON public.tournaments FOR DELETE
  USING (created_by = auth.uid() AND status = 'draft');


ALTER TABLE public.tournament_participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY tournament_participants_read
  ON public.tournament_participants FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tournaments t
      WHERE t.id = tournament_participants.tournament_id
        AND (t.status <> 'draft' OR t.created_by = auth.uid())
    )
  );

CREATE POLICY tournament_participants_self_register
  ON public.tournament_participants FOR INSERT
  WITH CHECK (
    user_id = auth.uid()
    AND registration_status = 'pending'
    AND EXISTS (
      SELECT 1 FROM public.tournaments t
      WHERE t.id = tournament_participants.tournament_id
        AND t.status = 'registration_open'
    )
  );

CREATE POLICY tournament_participants_self_withdraw
  ON public.tournament_participants FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid() AND registration_status = 'withdrawn');


ALTER TABLE public.tournament_matches ENABLE ROW LEVEL SECURITY;

CREATE POLICY tournament_matches_read
  ON public.tournament_matches FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tournaments t
      WHERE t.id = tournament_matches.tournament_id
        AND (t.status <> 'draft' OR t.created_by = auth.uid())
    )
  );


ALTER TABLE public.tournament_set_score_proposals ENABLE ROW LEVEL SECURITY;

CREATE POLICY tournament_set_score_proposals_read
  ON public.tournament_set_score_proposals FOR SELECT
  USING (
    submitter_user_id = auth.uid()
    OR EXISTS (
      SELECT 1
        FROM public.tournament_matches m
        JOIN public.tournaments t ON t.id = m.tournament_id
       WHERE m.id = tournament_set_score_proposals.match_id
         AND (
           t.created_by = auth.uid()
           OR EXISTS (
             SELECT 1 FROM public.tournament_participants p
              WHERE p.tournament_id = t.id
                AND p.user_id = auth.uid()
                AND p.id IN (m.participant_a, m.participant_b)
           )
         )
    )
  );


ALTER TABLE public.tournament_audit_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY tournament_audit_events_read
  ON public.tournament_audit_events FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tournaments t
      WHERE t.id = tournament_audit_events.tournament_id
        AND (
          t.created_by = auth.uid()
          OR EXISTS (
            SELECT 1 FROM public.tournament_participants p
             WHERE p.tournament_id = t.id AND p.user_id = auth.uid()
          )
        )
    )
  );
