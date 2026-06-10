-- Spaßturnier „auf Einladung" — S1: tournaments.invite_only.
--
-- Additive, idempotent flag. When true, only invited players (and the
-- creator) may see/register for the tournament. Generic column; the UI only
-- exposes the toggle for fun tournaments (club_id IS NULL).

ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS invite_only boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.tournaments.invite_only IS
  'nur eingeladene Spieler sehen/registrieren; relevant v.a. für '
  'Spaßturniere (club_id IS NULL)';
