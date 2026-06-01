-- P6 "TournierStart" — ELO-based auto-seeding RPC.
--
-- `tournament_autoseed_from_elo(p_tournament_id)` lets the organizer derive
-- a full seed order from each confirmed participant's ELO and persist it
-- through the SAME store the manual `tournament_set_seeding` writes:
-- `tournament_seeding_overrides` (seed_override = 1..N). The KO bracket
-- generator already consumes that table (start_ko_phase override CTE), so
-- auto-seeding needs no new read path.
--
-- Rating aggregation mirrors the pure-Dart `seedFromElo` logic
-- (packages/kubb_domain/.../elo_seeding.dart) per P6_RULES_DECISIONS §I:
--   * Team rating = SUM of the active roster members' ELO (default mode).
--   * Missing ratings default to 1200 (elo_default).
--   * Participants with NO rating history at all sort to the bottom.
--   * Higher rating = lower (better) seed number.
-- See the "Parity with Dart" note below for the tie-break divergence.
--
-- IMPORTANT — out of scope (Phase 6): the ELO values read here are only as
-- real as the (currently empty) player_ratings table. Until the match->ELO
-- writer lands in Phase 6, every participant resolves to 1200 and the order
-- is decided entirely by the deterministic tie-break.
--
-- ---- Dependencies (verified by reading) -------------------------------
--  * public.tournaments(id, created_by)
--      — 20260525000001_tournament_schema.sql (l.13-39).
--  * public.tournament_participants(id, tournament_id, user_id, team_id,
--    registration_status)  with status 'confirmed' as the canonical
--    "in tournament" filter (precedent: start_ko_phase l.125,
--    pair_round_swiss l.69, tournament_lifecycle_rpcs l.270).
--      — base: 20260525000001_tournament_schema.sql (l.44-55);
--        team_id added 20260615000005_tournament_team_roster.sql (l.14).
--  * public.tournament_roster_slots(participant_id, member_user_id,
--    replaced_at)  — active member rows have replaced_at IS NULL and a
--    non-null member_user_id (guests carry guest_player_id and have no ELO,
--    so they default to 1200, matching the Dart "null member -> default").
--      — 20260615000005_tournament_team_roster.sql (l.34-50);
--        active-row filter precedent: public_tournament_roster_view,
--        20260701000002_tournaments_public_flag.sql (l.126-136).
--  * public.player_ratings(user_id, discipline, elo)  — read-only here;
--    default discipline 'overall'.
--      — 20261201000001_player_ratings.sql (this batch).
--  * public.tournament_seeding_overrides(tournament_id, participant_id,
--    seed_override, set_by, set_at)  PK(tournament_id, participant_id).
--      — 20260601000011_tournament_seeding_overrides.sql (l.9-17). Written
--        via the SAME upsert shape as tournament_set_seeding
--        (20260601000012_..., l.121-127).
--  * public.tournament_audit_events(tournament_id, kind, actor_user_id,
--    payload)  — append-only audit (kind is free text).
--      — 20260525000001_tournament_schema.sql (l.106-114). New kind
--        'autoseed_from_elo' (siblings: 'seeding_set','pairing_overridden').
--
-- ---- Parity with Dart -------------------------------------------------
-- The RATING aggregation (sum / default 1200 / no-history-last / higher =
-- better) matches `EloParticipant.seedRating(sum)` and the primary sort of
-- `seedFromElo`. The TIE-BREAK does NOT bit-match Dart: `elo_seeding.dart`
-- breaks ties with `dart:math Random` seeded by `String.hashCode`, neither
-- of which is reproducible in plpgsql. We instead use a deterministic SQL
-- draw `md5(p_tournament_id || participant_id)` then participant_id. Both
-- sides are TOTAL and DETERMINISTIC; only the specific order WITHIN a tie
-- group can differ between the Dart preview and the server result. Because
-- ELO is uniformly 1200 until Phase 6, this divergence is currently the
-- common case for the whole field — see parity risks in the handover.

CREATE OR REPLACE FUNCTION public.tournament_autoseed_from_elo(
  p_tournament_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller   uuid;
  v_creator  uuid;
  v_count    int := 0;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Defense-in-depth: SECURITY DEFINER bypasses RLS, so organizer-only is
  -- enforced explicitly (mirrors tournament_set_seeding l.54-68).
  SELECT created_by INTO v_creator
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;
  IF v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'only the tournament creator may auto-seed'
      USING ERRCODE = '42501';
  END IF;

  -- Build the seed order and upsert it into the same store manual seeding
  -- uses. One statement: rate -> rank -> upsert, returning the row count.
  WITH confirmed AS (
    SELECT p.id AS participant_id, p.team_id, p.user_id
      FROM public.tournament_participants p
     WHERE p.tournament_id = p_tournament_id
       AND p.registration_status = 'confirmed'
  ),
  -- Every user_id that contributes ELO to a participant:
  --   * solo  -> the participant's own user_id
  --   * team  -> each ACTIVE roster member's member_user_id
  -- Guests (guest_player_id, no member_user_id) contribute no row and thus
  -- default to 1200, matching the Dart "null member ELO -> kEloDefault".
  member_users AS (
    SELECT c.participant_id, c.user_id AS member_user_id
      FROM confirmed c
     WHERE c.team_id IS NULL AND c.user_id IS NOT NULL
    UNION ALL
    SELECT s.participant_id, s.member_user_id
      FROM confirmed c
      JOIN public.tournament_roster_slots s
        ON s.participant_id = c.participant_id
     WHERE c.team_id IS NOT NULL
       AND s.replaced_at IS NULL
       AND s.member_user_id IS NOT NULL
  ),
  -- Resolve each contributing member to an ELO (default 1200 when missing)
  -- and remember whether ANY member had a real rating row.
  member_elo AS (
    SELECT mu.participant_id,
           COALESCE(r.elo, 1200) AS elo,
           (r.user_id IS NOT NULL) AS has_rating
      FROM member_users mu
      LEFT JOIN public.player_ratings r
        ON r.user_id = mu.member_user_id
       AND r.discipline = 'overall'
  ),
  -- Aggregate to the participant: SUM of member ELO (§I default mode) and
  -- a no-history flag (TRUE iff no contributing member had a rating row).
  -- A confirmed participant with zero contributing members (e.g. a team of
  -- only guests) gets seed_rating 0 here but is flagged no_history, so it
  -- still sorts to the bottom alongside other historyless entries.
  rated AS (
    SELECT c.participant_id,
           COALESCE(SUM(me.elo), 0)                       AS seed_rating,
           bool_or(COALESCE(me.has_rating, false)) IS NOT TRUE AS no_history
      FROM confirmed c
      LEFT JOIN member_elo me ON me.participant_id = c.participant_id
     GROUP BY c.participant_id
  ),
  ranked AS (
    SELECT participant_id,
           row_number() OVER (
             ORDER BY
               -- no-history participants last (§I)
               no_history ASC,
               -- higher rating = better (lower) seed
               seed_rating DESC,
               -- deterministic SQL tie-break (see "Parity with Dart")
               md5(p_tournament_id::text || participant_id::text) ASC,
               participant_id ASC
           ) AS seed_no
      FROM rated
  ),
  upserted AS (
    INSERT INTO public.tournament_seeding_overrides(
        tournament_id, participant_id, seed_override, set_by)
      SELECT p_tournament_id, participant_id, seed_no, v_caller
        FROM ranked
      ON CONFLICT (tournament_id, participant_id) DO UPDATE
        SET seed_override = EXCLUDED.seed_override,
            set_by        = EXCLUDED.set_by,
            set_at        = now()
      RETURNING 1
  )
  SELECT count(*)::int INTO v_count FROM upserted;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'autoseed_from_elo',
      v_caller,
      jsonb_build_object(
        'seed_count',  v_count,
        'seed_source', 'elo',
        'team_rating_mode', 'sum',
        'elo_default', 1200));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'seed_count',    v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_autoseed_from_elo(uuid)
  TO authenticated;
