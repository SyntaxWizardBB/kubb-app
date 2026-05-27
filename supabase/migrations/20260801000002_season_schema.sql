-- Season feature — M5 schema.
--
-- Three tables plus one read-view describe the Saison-Kontext: a season
-- header (seasons), the n:m link to participating tournaments with
-- factor snapshots (season_tournaments), and an append-only point ledger
-- (season_standings_awards). The view v_season_standings aggregates the
-- ledger into per-participant totals.
--
-- Append-only-Charakter of season_standings_awards is enforced by a
-- BEFORE UPDATE OR DELETE trigger. Reversals must be expressed by
-- inserting new rows with negative final_points (see task notes).
--
-- See docs/plans/m5-swiss-league-season/architecture.md §3.2 and
-- TASK-M5.2-T6. RLS policies and write RPCs land in the follow-up
-- migration 20260801000003_season_rls.sql.


-- ---- 1. Tables --------------------------------------------------------

CREATE TABLE public.seasons (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                    text NOT NULL CHECK (length(name) BETWEEN 1 AND 80),
  league_id               uuid NULL,
  status                  text NOT NULL DEFAULT 'draft'
                            CHECK (status IN ('draft','open','closed')),
  starts_at               date NULL,
  ends_at                 date NULL,
  transfer_window_start   date NULL,
  transfer_window_end     date NULL,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX seasons_league_idx ON public.seasons(league_id);
CREATE INDEX seasons_status_idx ON public.seasons(status);


CREATE TABLE public.season_tournaments (
  season_id          uuid NOT NULL REFERENCES public.seasons(id) ON DELETE CASCADE,
  tournament_id      uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  tournament_factor  numeric NOT NULL DEFAULT 1.0,
  league_factor      numeric NOT NULL DEFAULT 1.0,
  snapshot_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (season_id, tournament_id)
);
CREATE INDEX season_tournaments_season_idx
  ON public.season_tournaments(season_id);


CREATE TABLE public.season_standings_awards (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  season_id       uuid NOT NULL REFERENCES public.seasons(id) ON DELETE CASCADE,
  league_id       uuid NULL,
  tournament_id   uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  participant_id  uuid NOT NULL,
  placement       int NULL CHECK (placement IS NULL OR placement >= 1),
  base_points     numeric NOT NULL DEFAULT 0,
  final_points    numeric NOT NULL DEFAULT 0,
  breakdown       text NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX season_standings_awards_lookup_idx
  ON public.season_standings_awards(season_id, league_id, participant_id);


-- ---- 2. updated_at trigger on seasons --------------------------------

CREATE OR REPLACE FUNCTION public.seasons_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER seasons_set_updated_at
  BEFORE UPDATE ON public.seasons
  FOR EACH ROW EXECUTE FUNCTION public.seasons_set_updated_at();


-- ---- 3. Append-only ledger trigger -----------------------------------
--
-- season_standings_awards is an append-only ledger: any UPDATE or
-- DELETE must be rejected. Corrections are expressed by inserting a
-- compensating row with negative final_points.

CREATE OR REPLACE FUNCTION public.season_standings_awards_block_mutation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION 'append_only_ledger';
END;
$$;

CREATE TRIGGER season_standings_awards_block_update
  BEFORE UPDATE ON public.season_standings_awards
  FOR EACH ROW EXECUTE FUNCTION public.season_standings_awards_block_mutation();

CREATE TRIGGER season_standings_awards_block_delete
  BEFORE DELETE ON public.season_standings_awards
  FOR EACH ROW EXECUTE FUNCTION public.season_standings_awards_block_mutation();


-- ---- 4. Aggregation view ---------------------------------------------

CREATE VIEW public.v_season_standings AS
SELECT
  season_id,
  league_id,
  participant_id,
  SUM(final_points)              AS total_points,
  COUNT(DISTINCT tournament_id)  AS tournament_count
FROM public.season_standings_awards
GROUP BY 1, 2, 3;
