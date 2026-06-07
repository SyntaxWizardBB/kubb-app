-- SKV tour-points award PERSISTENCE (System 1, B2c2), additive.
--
-- Closes the SKV loop opened by 20261216000000_tournament_skv_compute_awards.sql:
-- that migration added the read-only public.tournament_skv_compute_awards(uuid)
-- function (placement points projected onto every season_tournaments assignment,
-- with tournament_factor * league_factor) but explicitly LEFT the persistence
-- into public.season_standings_awards AND the rated / club_id eligibility gate
-- to "a LATER finalize step (B2c2)". This migration adds exactly that step as an
-- AFTER-UPDATE trigger on public.tournaments.
--
-- ============================ WHY A TRIGGER ============================
-- public.tournament_finalize only flips tournaments.status -> 'finalized'
-- (the terminal status, see tournaments_status_check). An AFTER-UPDATE trigger
-- on that status transition is the single, complete hook for "a tournament was
-- just finalized": it runs in the SAME transaction as the finalizing UPDATE,
-- cannot be bypassed by a future alternative finalize path, and needs no change
-- to tournament_finalize itself (which stays untouched -- this migration is
-- purely additive: CREATE OR REPLACE FUNCTION + DROP/CREATE TRIGGER).
--
-- This MIRRORS the gating of the ELO writer
-- (20261201000004_player_ratings_elo_writer.sql): an AFTER-UPDATE trigger whose
-- WHEN clause keys on the status transition INTO the terminal state, so it fires
-- exactly once on the transition and never re-fires for an already-finalized row
-- (DISTINCT-FROM gate). A re-entry via live->finalized is additionally caught by
-- the idempotency gate below.
--
-- ============================ ELIGIBILITY ==============================
-- RATED gate (CF1): only club-backed tournaments earn season awards. The read-
-- only compute function deliberately does NOT apply this gate; we apply it here:
--   NEW.club_id IS NULL  ->  no awards (return early).
--
-- ============================ IDEMPOTENCY ==============================
-- season_standings_awards is append-only (a BEFORE UPDATE/DELETE trigger blocks
-- mutations) and has NO client-side INSERT policy beyond league_admin, so rows
-- are written ONLY through this SECURITY DEFINER trigger. That makes an EXISTS
-- check a sufficient idempotency guard (no UNIQUE constraint needed): if any
-- award row already exists for the tournament, the trigger is a no-op. This
-- protects against a live->finalized re-entry and any future double-finalize.
--
-- ============================ DEPENDENCIES =============================
-- Reads:  public.tournaments(NEW.id, NEW.club_id, NEW.status),
--         public.tournament_skv_compute_awards(uuid) (read-only compute),
--         public.season_standings_awards (EXISTS idempotency probe).
-- Writes: public.season_standings_awards (INSERT only) -- the SECURITY DEFINER
--         write the append-only table was designed for.
--
-- season_standings_awards NOT-NULL columns (verified via \d): season_id,
-- tournament_id, participant_id, base_points (default 0), final_points
-- (default 0). league_id, placement and breakdown are NULLABLE; breakdown still
-- gets a deterministic trace text for auditability.
--
-- search_path = '' => every reference is schema-qualified.

-- ---- 1. tournament_write_skv_awards (trigger function) ----------------

create or replace function public.tournament_write_skv_awards()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- RATED gate (CF1): unrated (no club) tournaments earn no season awards.
  if new.club_id is null then
    return new;
  end if;

  -- Idempotency: awards are written only here (append-only table, no client
  -- INSERT path), so an existing row for this tournament means we already ran.
  if exists (
    select 1
    from public.season_standings_awards
    where tournament_id = new.id
  ) then
    return new;
  end if;

  -- Persist the read-only computation. The compute function maps DB phases
  -- ko/final -> winners/finals and applies tournament_factor * league_factor.
  insert into public.season_standings_awards (
    season_id, league_id, tournament_id, participant_id,
    placement, base_points, final_points, breakdown
  )
  select a.season_id,
         a.league_id,
         new.id,
         a.participant_id,
         a.placement,
         a.base_points,
         a.final_points,
         'skv:auto placement=' || a.placement
  from public.tournament_skv_compute_awards(new.id) a;

  return new;
end;
$$;

comment on function public.tournament_write_skv_awards() is
  'AFTER-UPDATE trigger fn (SECURITY DEFINER): on a tournament''s transition to '
  'status=finalized, persists SKV tour-points into the append-only '
  'season_standings_awards by inserting the rows produced by the read-only '
  'public.tournament_skv_compute_awards(NEW.id). Gates: RATED (NEW.club_id NOT '
  'NULL) and idempotent (no-op if awards already exist for the tournament). '
  'tournament_finalize stays unchanged; it only flips the status and this trigger '
  'reacts.';


-- ---- 2. Trigger -------------------------------------------------------
-- Same WHEN-gating shape as the ELO writer: fires once on the transition INTO
-- 'finalized'. A re-UPDATE finalized->finalized does not fire (DISTINCT-FROM);
-- a live->finalized re-entry fires but is absorbed by the idempotency gate.

drop trigger if exists tournament_write_skv_awards on public.tournaments;
create trigger tournament_write_skv_awards
  after update on public.tournaments
  for each row
  when (
    old.status is distinct from 'finalized'
    and new.status = 'finalized'
  )
  execute function public.tournament_write_skv_awards();
