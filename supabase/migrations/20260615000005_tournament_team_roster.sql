-- M3.2-T1: Tournament team-roster schema + BR-5 trigger.
--
-- Extends `tournament_participants` with team registration support and
-- introduces `tournament_roster_slots` as the append-only slot log. The
-- BR-5 trigger blocks a player from holding two open slots within the
-- same tournament; cross-tournament participation stays allowed.
--
-- Spec: docs/plans/m3-teams-pools-roster/architecture.md §3.3.


-- ---- 1. tournament_participants extension ----------------------------

ALTER TABLE public.tournament_participants
  ADD COLUMN team_id           uuid NULL REFERENCES public.teams(id) ON DELETE CASCADE,
  ADD COLUMN roster_locked_at  timestamptz NULL;

ALTER TABLE public.tournament_participants
  ALTER COLUMN user_id DROP NOT NULL;

ALTER TABLE public.tournament_participants
  ADD CONSTRAINT tournament_participants_user_or_team_chk
    CHECK (
      (team_id IS NULL AND user_id IS NOT NULL)
      OR (team_id IS NOT NULL)
    );

CREATE INDEX tournament_participants_team_idx
  ON public.tournament_participants(team_id)
  WHERE team_id IS NOT NULL;


-- ---- 2. tournament_roster_slots -------------------------------------

CREATE TABLE public.tournament_roster_slots (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  participant_id    uuid NOT NULL REFERENCES public.tournament_participants(id) ON DELETE CASCADE,
  slot_index        smallint NOT NULL CHECK (slot_index BETWEEN 1 AND 6),
  member_user_id    uuid NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  guest_player_id   uuid NULL REFERENCES public.team_guest_players(id) ON DELETE RESTRICT,
  assigned_at       timestamptz NOT NULL DEFAULT now(),
  assigned_by       uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  replaced_at       timestamptz NULL,
  replaced_by       uuid NULL REFERENCES auth.users(id) ON DELETE SET NULL,
  reason            text NULL,
  CONSTRAINT tournament_roster_slots_member_xor_guest_chk
    CHECK (
      (member_user_id IS NOT NULL AND guest_player_id IS NULL)
      OR (member_user_id IS NULL AND guest_player_id IS NOT NULL)
    )
);

CREATE UNIQUE INDEX tournament_roster_slots_unique_open_slot_idx
  ON public.tournament_roster_slots(participant_id, slot_index)
  WHERE replaced_at IS NULL;

CREATE INDEX tournament_roster_slots_member_open_idx
  ON public.tournament_roster_slots(member_user_id, replaced_at);

CREATE INDEX tournament_roster_slots_participant_idx
  ON public.tournament_roster_slots(participant_id);


-- ---- 3. BR-5 trigger --------------------------------------------------
--
-- A player (member_user_id) must not occupy an open slot in more than
-- one participant of the same tournament. Cross-tournament participation
-- remains permitted. Guest players are tournament-scoped via their
-- team and are not subject to this check (guests are pre-claimed in
-- M3.1; if a guest is claimed by a user, the resulting member-slot
-- triggers the check at that point).

CREATE OR REPLACE FUNCTION public.tournament_roster_slots_br5_check()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, auth
AS $$
DECLARE
  v_tournament_id uuid;
BEGIN
  IF NEW.member_user_id IS NULL OR NEW.replaced_at IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT p.tournament_id INTO v_tournament_id
    FROM public.tournament_participants p
   WHERE p.id = NEW.participant_id;

  IF EXISTS (
    SELECT 1
      FROM public.tournament_roster_slots s
      JOIN public.tournament_participants p ON p.id = s.participant_id
     WHERE s.member_user_id = NEW.member_user_id
       AND s.replaced_at IS NULL
       AND s.id IS DISTINCT FROM NEW.id
       AND p.tournament_id = v_tournament_id
       AND p.id <> NEW.participant_id
  ) THEN
    RAISE EXCEPTION
      'player % already holds an open roster slot in tournament %',
      NEW.member_user_id, v_tournament_id
      USING ERRCODE = '23P01', HINT = 'BR_5_VIOLATION';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER tournament_roster_slots_br5_check
  BEFORE INSERT OR UPDATE ON public.tournament_roster_slots
  FOR EACH ROW EXECUTE FUNCTION public.tournament_roster_slots_br5_check();
