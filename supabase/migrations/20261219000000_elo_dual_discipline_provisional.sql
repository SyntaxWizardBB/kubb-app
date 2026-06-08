-- ELO System 2 — Stage: dual-discipline tournament writer + provisional K.
--
-- Source of truth: docs/ELO_RATINGS.md (§2 source matrix, §3 formula +
-- provisional K, §6 launch/rename, §9 seeding). Additive only: one data
-- rename UPDATE + CREATE OR REPLACE of exactly two existing functions.
-- The tournament_write_match_elo TRIGGER binding on tournament_matches is
-- left untouched (only the function body is replaced).
--
-- Changes (exactly):
--  1. DATA RENAME (idempotent): existing discipline='overall' rows (produced
--     by the original writer) become discipline='tournament' — no replay,
--     just keep what was already triggered (ELO_RATINGS.md §6).
--  2. public.tournament_write_match_elo() — member-resolution + guards kept
--     VERBATIM from 20261201000004; ONLY: (a) compute+upsert for BOTH
--     disciplines 'tournament' AND 'personal' (a tournament match feeds both,
--     §2), (b) discipline literal parametrised, (c) games-dependent
--     provisional K (40 while games<10, else 24) using the PRE-increment
--     games value, instead of the fixed _elo_k() (24).
--  3. public.tournament_autoseed_from_elo(uuid) — body VERBATIM from
--     20261201000002; ONLY the read literal discipline='overall' becomes
--     'tournament' (§9; post-rename this is the same bucket).

-- ---- 0. Provisional-K constants (additive) ----------------------------
-- _elo_default (1200) and _elo_k (24, "established" value) from
-- 20261201000004 are left as-is. We add the provisional-anchor K (40) and
-- the games threshold (10) as IMMUTABLE SQL constants so the values live in
-- one place (ELO_RATINGS.md §3).
CREATE OR REPLACE FUNCTION public._elo_k_provisional() RETURNS int
  LANGUAGE sql IMMUTABLE AS $$ SELECT 40 $$;
CREATE OR REPLACE FUNCTION public._elo_provisional_games() RETURNS int
  LANGUAGE sql IMMUTABLE AS $$ SELECT 10 $$;

REVOKE EXECUTE ON FUNCTION public._elo_k_provisional() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._elo_provisional_games() FROM PUBLIC;


-- ---- 1. Data rename (idempotent) --------------------------------------
-- One-off launch rename (ELO_RATINGS.md §6): the original writer wrote the
-- single bucket 'overall'; System 2 renames that public bucket to
-- 'tournament'. WHERE discipline='overall' makes a second run a no-op (0
-- rows) and never touches existing 'tournament'/'personal' rows.
UPDATE public.player_ratings
   SET discipline = 'tournament'
 WHERE discipline = 'overall';


-- ---- 2. tournament_write_match_elo (trigger function) -----------------
-- Member-resolution and all guards are kept EXACTLY as in 20261201000004.
-- The ONLY behavioural changes are the three listed in the header: dual
-- discipline, parametrised literal, games-dependent provisional K.

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
  -- Provisional-K anchors (games-dependent K replaces the former fixed
  -- _elo_k(); see ELO_RATINGS.md §3).
  v_k_prov        int := public._elo_k_provisional();
  v_prov_games    int := public._elo_provisional_games();
  -- Per-side aggregate ratings (SUM of active member ELO; default-filled),
  -- recomputed per discipline (each discipline reads its OWN values).
  v_rating_win    int;
  v_rating_lose   int;
  v_expected_win  double precision;
  -- Discipline loop variable: a tournament match feeds both ELO buckets.
  v_discipline    text;
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

  -- A tournament match feeds BOTH disciplines (ELO_RATINGS.md §2). Each
  -- discipline is computed INDEPENDENTLY: its own per-side aggregate, its
  -- own expected score, and its own per-member provisional K from its own
  -- games counter. No cross-discipline reads.
  FOREACH v_discipline IN ARRAY ARRAY['tournament','personal'] LOOP
    -- Per-side aggregate rating = SUM of member ELO (matching §I/autoseed),
    -- with the neutral default for members that have no rating row yet in
    -- THIS discipline. A side with zero rateable members (e.g. all-guest
    -- team) falls back to the single-default baseline so the expectation
    -- term stays well-defined.
    SELECT COALESCE(SUM(COALESCE(r.elo, v_default)), v_default)
      INTO v_rating_win
      FROM _elo_members m
      LEFT JOIN public.player_ratings r
        ON r.user_id = m.user_id AND r.discipline = v_discipline
     WHERE m.side = 'W';

    SELECT COALESCE(SUM(COALESCE(r.elo, v_default)), v_default)
      INTO v_rating_lose
      FROM _elo_members m
      LEFT JOIN public.player_ratings r
        ON r.user_id = m.user_id AND r.discipline = v_discipline
     WHERE m.side = 'L';

    -- Standard ELO: winner scored 1, expected from the rating difference.
    v_expected_win := 1.0 / (1.0 + power(10.0, (v_rating_lose - v_rating_win) / 400.0));

    -- Winners: +delta. Losers: -delta. UPSERT so first-ever rating rows are
    -- created at default ± delta. games +1 for every updated member.
    --
    -- Provisional K is PER MEMBER and uses the PRE-increment games value:
    --   * new row (INSERT branch): games is 0 -> K = _elo_k_provisional().
    --   * existing row (DO UPDATE branch): the stored player_ratings.games
    --     is read BEFORE the +1; K = 40 if games < threshold, else 24.
    -- Delta is therefore evaluated per member, so a match is NOT strictly
    -- zero-sum when members straddle the threshold (intended, §3).
    INSERT INTO public.player_ratings(user_id, discipline, elo, games, updated_at)
    SELECT m.user_id,
           v_discipline,
           -- new-row baseline = default ± delta; new row has games 0 -> K=40.
           greatest(0, v_default + round(v_k_prov * (1.0 - v_expected_win))),
           1,
           now()
      FROM _elo_members m
     WHERE m.side = 'W'
    ON CONFLICT (user_id, discipline) DO UPDATE
      SET elo        = greatest(
                         0,
                         public.player_ratings.elo
                         + round(
                             (CASE WHEN public.player_ratings.games < v_prov_games
                                   THEN v_k_prov ELSE public._elo_k() END)
                             * (1.0 - v_expected_win))),
          games      = public.player_ratings.games + 1,
          updated_at = now();

    INSERT INTO public.player_ratings(user_id, discipline, elo, games, updated_at)
    SELECT m.user_id,
           v_discipline,
           greatest(0, v_default - round(v_k_prov * (1.0 - v_expected_win))),
           1,
           now()
      FROM _elo_members m
     WHERE m.side = 'L'
    ON CONFLICT (user_id, discipline) DO UPDATE
      SET elo        = greatest(
                         0,
                         public.player_ratings.elo
                         - round(
                             (CASE WHEN public.player_ratings.games < v_prov_games
                                   THEN v_k_prov ELSE public._elo_k() END)
                             * (1.0 - v_expected_win))),
          games      = public.player_ratings.games + 1,
          updated_at = now();
  END LOOP;

  -- No explicit DROP: ON COMMIT DROP cleans up at txn end, and keeping the
  -- table lets a subsequent same-txn invocation reuse it (TRUNCATE above).
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.tournament_write_match_elo() IS
  'AFTER-UPDATE trigger fn: writes standard-ELO into public.player_ratings '
  'for BOTH disciplines tournament + personal when a match flips to '
  'finalized/overridden with a winner (ELO_RATINGS.md §2). Team handling: '
  'one team-vs-team delta per discipline (SUM of active member ELO per side, '
  'matching auto-seed §I) applied to every active roster member; solo = '
  'single-member team. Guests are not rated. Per-member games-dependent K '
  '(40 while games<10 else 24, pre-increment games); games incremented.';


-- ---- 3. tournament_autoseed_from_elo (minimal diff) -------------------
-- Body VERBATIM from 20261201000002; the ONLY change is the read literal
-- discipline = 'overall' -> 'tournament' in the member_elo CTE LEFT JOIN
-- (ELO_RATINGS.md §9; post-rename this is the same bucket). Signature,
-- SECURITY DEFINER, search_path, audit event, GRANT, tie-break and
-- aggregation are unchanged.

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
       AND r.discipline = 'tournament'
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
