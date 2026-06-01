-- P6 "TournierStart" — Stage C (1/2): ELO WRITER.
--
-- Closes the Phase 5 loop: 20261201000001_player_ratings.sql created the
-- public.player_ratings store but explicitly left it EMPTY ("the match->ELO
-- writer is a Phase 6 task"). This migration adds that writer as an
-- AFTER-UPDATE trigger on public.tournament_matches: whenever a match flips
-- into a terminal, decided state (status finalized/overridden with a
-- winner_participant), the standard-ELO ratings of the two sides are updated
-- in place and their games counter is incremented.
--
-- ============================ WHY A TRIGGER ============================
-- Both finalize paths converge on the SAME UPDATE of tournament_matches:
--   * consensus agreement  -> tournament_propose_set_scores sets
--       status='finalized', winner_participant=...  (20260525000004 §2,
--       l.309-315).
--   * organizer override   -> tournament_organizer_override sets
--       status='overridden', winner_participant=...  (20260525000004 §3,
--       l.451-457).
-- An AFTER-UPDATE trigger on tournament_matches is therefore the single,
-- complete hook for "a match just produced a final winner" — it cannot be
-- bypassed by adding a third finalize RPC later, and it runs in the SAME
-- transaction as the finalizing UPDATE (atomic with the result).
--
-- This MIRRORS the gating of the existing KO-advance trigger
-- (20260601000016_trigger_advance_ko_winner.sql / its double-elim successor
-- 20261101000002 §5): same WHEN clause shape
--   OLD.status NOT IN ('finalized','overridden')
--   AND NEW.status     IN ('finalized','overridden')
-- so it fires exactly once per match, on the transition INTO terminal, and
-- never re-fires for an already-finalized row (re-finalize is impossible
-- anyway — the finalize RPCs only act on scheduled/awaiting_results/disputed).
--
-- The two triggers are INDEPENDENT (no ordering dependency): ELO touches
-- only public.player_ratings, KO-advance touches only OTHER tournament_matches
-- rows. Postgres fires AFTER-ROW triggers in name order; ours sorts after
-- `tournament_advance_*` — irrelevant here since they share no rows.
--
-- ======================= TEAM HANDLING (documented) ====================
-- A tournament_match is a single A-vs-B contest regardless of team_size.
-- We compute ONE ELO delta from the team-vs-team result (team A rating vs
-- team B rating), then apply that SAME per-pair delta to EVERY active
-- roster member of the winning/losing side. Rationale:
--   * It keeps a member's per-game swing on the standard-ELO scale (a 2-vs-2
--     win moves each of the two winners by the normal K-bounded amount,
--     not by half or double), which is what players intuitively expect and
--     what makes the rating comparable to a solo player's.
--   * The "team rating" used for the EXPECTED-score term is the SUM of the
--     active members' ELO — the SAME aggregation §I/auto-seed already uses
--     (tournament_autoseed_from_elo, 20261201000002, l.135-146: SUM of
--     active member ELO, default 1200). This keeps the rating that DRIVES
--     seeding and the rating that RESULTS from a match on one definition.
--     (Note: the expected-score formula is scale-invariant in the rating
--     DIFFERENCE, so summing both sides is equivalent to averaging both
--     sides for the purpose of the expectation — the team SIZE only matters
--     if the two sides differ in size, in which case SUM correctly favours
--     the larger roster, consistent with §I.)
--   * Solo participant = a "team" whose roster is the single user_id; it
--     takes the exact same code path with one member per side.
--
-- "Active roster member" = public.tournament_roster_slots row with
-- member_user_id IS NOT NULL AND replaced_at IS NULL (the open-slot filter
-- used by autoseed l.121-122 and the public roster view). GUEST players
-- (guest_player_id, no member_user_id, no auth.users row) carry NO ELO and
-- are simply not updated — there is nowhere to store a guest rating. A
-- side made up entirely of guests contributes/receives nothing; its rating
-- for the expectation term defaults to the neutral baseline (see code).
--
-- ============================ ELO FORMULA ==============================
-- Standard ELO, integer ratings:
--   expected_a = 1 / (1 + 10^((rating_b - rating_a)/400))
--   score_a    = 1 win / 0 loss        (no draws: a finalized match always
--                                        has a winner_participant)
--   new_a      = rating_a + K * (score_a - expected_a)   [rounded]
-- with K = kEloK (24, see constant below) and the neutral default 1200
-- (kEloDefault) for any member with no existing player_ratings row. The
-- delta applied to side B is the exact negative of side A's (zero-sum per
-- pair). games is incremented by 1 for every updated member.
--
-- ============================ DEPENDENCIES =============================
-- Tables READ:
--   * public.tournament_matches(NEW.*): tournament_id, participant_a,
--       participant_b, winner_participant, status, phase.
--       — 20260525000001_tournament_schema.sql; phase 20260601000010.
--   * public.tournament_participants(id, team_id, user_id)
--       — base 20260525000001 (l.44-55); team_id 20260615000005 (l.14).
--   * public.tournament_roster_slots(participant_id, member_user_id,
--       replaced_at) active-row filter — 20260615000005 (l.34-50);
--       same filter as autoseed 20261201000002 (l.117-122).
--   * public.player_ratings(user_id, discipline, elo, games)
--       — 20261201000001 (l.32-40). discipline 'overall' (the single bucket
--         autoseed reads, 20261201000002 l.133).
-- Tables WRITTEN:
--   * public.player_ratings — UPSERT (insert-or-update) per member. This is
--       the SECURITY DEFINER write the store was designed for: 20261201000001
--       declares NO write RLS policy and notes "writes via SECURITY DEFINER
--       RPC only" (l.50-55, l.65-68). A SECURITY DEFINER trigger function
--       owned by the migration role satisfies that contract; client-side
--       INSERT/UPDATE still fail closed (no policy).
-- Functions: NEW — public.tournament_write_match_elo() (trigger fn).
-- =====================================================================

-- ---- 0. Tunable constant ----------------------------------------------
-- K-factor and default rating as IMMUTABLE SQL constants so the value lives
-- in one place. (kept as functions rather than a settings row to avoid a
-- new table; trivial to bump later via CREATE OR REPLACE.)
CREATE OR REPLACE FUNCTION public._elo_k() RETURNS int
  LANGUAGE sql IMMUTABLE AS $$ SELECT 24 $$;
CREATE OR REPLACE FUNCTION public._elo_default() RETURNS int
  LANGUAGE sql IMMUTABLE AS $$ SELECT 1200 $$;

REVOKE EXECUTE ON FUNCTION public._elo_k() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._elo_default() FROM PUBLIC;


-- ---- 1. tournament_write_match_elo (trigger function) -----------------

CREATE OR REPLACE FUNCTION public.tournament_write_match_elo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_winner_part   uuid;
  v_loser_part    uuid;
  v_default       int := public._elo_default();
  v_k             int := public._elo_k();
  -- Per-side aggregate ratings (SUM of active member ELO; default-filled).
  v_rating_win    int;
  v_rating_lose   int;
  v_expected_win  double precision;
  v_delta         int;
BEGIN
  -- Guard (defensive; the WHEN clause already enforces winner + status).
  IF NEW.winner_participant IS NULL THEN
    RETURN NEW;
  END IF;
  IF NEW.participant_a IS NULL OR NEW.participant_b IS NULL THEN
    -- BYE/walkover-only rows have no two-sided contest; nothing to rate.
    RETURN NEW;
  END IF;

  v_winner_part := NEW.winner_participant;
  v_loser_part  := CASE
    WHEN NEW.winner_participant = NEW.participant_a THEN NEW.participant_b
    WHEN NEW.winner_participant = NEW.participant_b THEN NEW.participant_a
    ELSE NULL
  END;
  IF v_loser_part IS NULL THEN
    -- Inconsistent data: winner not one of the two participants. Skip.
    RETURN NEW;
  END IF;

  -- Resolve each side's active member user_ids into a temp set. Solo
  -- participants (team_id IS NULL) contribute their own user_id; team
  -- participants contribute every active roster member. Guests are
  -- excluded (member_user_id IS NULL) — they cannot be rated.
  --
  -- IF NOT EXISTS + TRUNCATE (pattern from tournament_start_ko_phase's
  -- _tmp_pool_cuts) so the trigger is re-entrant within one transaction:
  -- if several matches finalize in the same txn the temp table is reused,
  -- never re-created (which would raise "relation already exists").
  CREATE TEMP TABLE IF NOT EXISTS _elo_members (
    side    text NOT NULL,          -- 'W' winner, 'L' loser
    user_id uuid NOT NULL
  ) ON COMMIT DROP;
  TRUNCATE _elo_members;

  INSERT INTO _elo_members(side, user_id)
  SELECT s.side, mu.user_id
    FROM (VALUES ('W'::text, v_winner_part), ('L'::text, v_loser_part)) AS s(side, pid)
    JOIN LATERAL (
      -- solo: own user_id
      SELECT p.user_id
        FROM public.tournament_participants p
       WHERE p.id = s.pid
         AND p.team_id IS NULL
         AND p.user_id IS NOT NULL
      UNION ALL
      -- team: active roster members
      SELECT rs.member_user_id
        FROM public.tournament_participants p
        JOIN public.tournament_roster_slots rs
          ON rs.participant_id = p.id
       WHERE p.id = s.pid
         AND p.team_id IS NOT NULL
         AND rs.replaced_at IS NULL
         AND rs.member_user_id IS NOT NULL
    ) AS mu(user_id) ON true;

  -- Per-side aggregate rating = SUM of member ELO (matching §I/autoseed),
  -- with the neutral default for members that have no rating row yet. A
  -- side with zero rateable members (e.g. all-guest team) falls back to the
  -- single-default baseline so the expectation term stays well-defined.
  SELECT COALESCE(SUM(COALESCE(r.elo, v_default)), v_default)
    INTO v_rating_win
    FROM _elo_members m
    LEFT JOIN public.player_ratings r
      ON r.user_id = m.user_id AND r.discipline = 'overall'
   WHERE m.side = 'W';

  SELECT COALESCE(SUM(COALESCE(r.elo, v_default)), v_default)
    INTO v_rating_lose
    FROM _elo_members m
    LEFT JOIN public.player_ratings r
      ON r.user_id = m.user_id AND r.discipline = 'overall'
   WHERE m.side = 'L';

  -- Standard ELO: winner scored 1, expected from the rating difference.
  v_expected_win := 1.0 / (1.0 + power(10.0, (v_rating_lose - v_rating_win) / 400.0));
  -- Same per-pair delta applied to each member of each side (see header).
  v_delta := round(v_k * (1.0 - v_expected_win));
  -- Guard against a zero-delta no-op write churn when ratings are extreme.
  -- (round() can yield 0 only for pathological inputs; we still write to
  -- bump games, which is intentional — a played game always counts.)

  -- Winners: +delta. Losers: -delta. UPSERT so first-ever rating rows are
  -- created at default+delta. games +1 for every updated member.
  INSERT INTO public.player_ratings(user_id, discipline, elo, games, updated_at)
  SELECT m.user_id,
         'overall',
         greatest(0, v_default + v_delta),   -- new-row baseline = default ± delta
         1,
         now()
    FROM _elo_members m
   WHERE m.side = 'W'
  ON CONFLICT (user_id, discipline) DO UPDATE
    SET elo        = greatest(0, public.player_ratings.elo + v_delta),
        games      = public.player_ratings.games + 1,
        updated_at = now();

  INSERT INTO public.player_ratings(user_id, discipline, elo, games, updated_at)
  SELECT m.user_id,
         'overall',
         greatest(0, v_default - v_delta),
         1,
         now()
    FROM _elo_members m
   WHERE m.side = 'L'
  ON CONFLICT (user_id, discipline) DO UPDATE
    SET elo        = greatest(0, public.player_ratings.elo - v_delta),
        games      = public.player_ratings.games + 1,
        updated_at = now();

  -- No explicit DROP: ON COMMIT DROP cleans up at txn end, and keeping the
  -- table lets a subsequent same-txn invocation reuse it (TRUNCATE above).
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.tournament_write_match_elo() IS
  'AFTER-UPDATE trigger fn: writes standard-ELO (K=_elo_k, default '
  '_elo_default) into public.player_ratings when a match flips to '
  'finalized/overridden with a winner. Team handling: one team-vs-team '
  'delta (SUM of active member ELO per side, matching auto-seed §I) applied '
  'to every active roster member; solo = single-member team. Guests are not '
  'rated. Zero-sum per pair; games incremented.';


-- ---- 2. Trigger -------------------------------------------------------
-- Same WHEN-gating as tournament_advance_ko_winner (fires once on the
-- transition INTO finalized/overridden). NOTE: NO phase filter — ELO must
-- accrue for EVERY format (round_robin, swiss/schoch group rounds, pools,
-- ko/final/wb/lb/grand_final[_reset]), unlike the KO-advance trigger which
-- only cares about bracket phases. 'voided' is intentionally excluded: a
-- voided match has no sporting result and must not move ratings.

DROP TRIGGER IF EXISTS tournament_write_match_elo ON public.tournament_matches;
CREATE TRIGGER tournament_write_match_elo
  AFTER UPDATE ON public.tournament_matches
  FOR EACH ROW
  WHEN (
    OLD.status NOT IN ('finalized','overridden')
    AND NEW.status     IN ('finalized','overridden')
    AND NEW.winner_participant IS NOT NULL
  )
  EXECUTE FUNCTION public.tournament_write_match_elo();
