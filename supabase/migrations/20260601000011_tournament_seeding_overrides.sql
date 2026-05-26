-- Tournament feature — M2 KO seeding overrides.
--
-- Per-participant manual seed override for the KO phase. Populated by
-- the organizer via the `tournament_set_seeding` RPC (next migration);
-- consumed when the KO bracket is generated. One row per
-- (tournament, participant). Audit-Trail bleibt in
-- `tournament_audit_events` (kind='seeding_set'), nicht hier.

CREATE TABLE public.tournament_seeding_overrides (
  tournament_id  uuid        NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  participant_id uuid        NOT NULL REFERENCES public.tournament_participants(id) ON DELETE CASCADE,
  seed_override  int         NOT NULL CHECK (seed_override >= 1),
  set_by         uuid        NOT NULL REFERENCES auth.users(id),
  set_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tournament_seeding_overrides_pkey
    PRIMARY KEY (tournament_id, participant_id)
);

CREATE INDEX tournament_seeding_overrides_tournament_idx
  ON public.tournament_seeding_overrides(tournament_id);


-- ---- RLS ---------------------------------------------------------------
--
-- Mutations laufen via `tournament_set_seeding` (SECURITY DEFINER, next
-- migration). Direkte Client-Mutationen (INSERT/UPDATE/DELETE) sind
-- ausschliesslich dem Veranstalter (`tournaments.created_by =
-- auth.uid()`) erlaubt; damit bleibt die Tabelle gegen versehentliche
-- Anon-Writes geschützt, auch wenn das RPC einmal umgangen würde.
--
-- Read-Pattern folgt `tournament_matches_read` aus
-- `20260525000001_tournament_schema.sql`: sichtbar für alle, die das
-- Turnier ohnehin lesen dürfen (Nicht-Draft oder eigener Draft).

ALTER TABLE public.tournament_seeding_overrides ENABLE ROW LEVEL SECURITY;

CREATE POLICY tournament_seeding_overrides_read
  ON public.tournament_seeding_overrides FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tournaments t
      WHERE t.id = tournament_seeding_overrides.tournament_id
        AND (t.status <> 'draft' OR t.created_by = auth.uid())
    )
  );

CREATE POLICY tournament_seeding_overrides_organizer_write
  ON public.tournament_seeding_overrides FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.tournaments t
      WHERE t.id = tournament_seeding_overrides.tournament_id
        AND t.created_by = auth.uid()
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tournaments t
      WHERE t.id = tournament_seeding_overrides.tournament_id
        AND t.created_by = auth.uid()
    )
  );
