-- ELO System 2 — Stage: 1v1 match writer (personal discipline only).
--
-- Source of truth: docs/ELO_RATINGS.md §2 (a 1v1 public.matches game feeds
-- ONLY discipline='personal' — never 'tournament'), §3 (standard-ELO formula
-- + games-dependent provisional K on the PRE-increment games counter), §4
-- (rateable 1v1 members = match_participants with kind='in_app', user_id NOT
-- NULL, invitation_status='accepted'; walk-ins / non-accepted contribute no
-- row, a side with no rateable members falls back to the neutral default for
-- the expectation term only).
--
-- Mathematics, UPSERT and greatest(0,..) semantics are deliberately IDENTICAL
-- to the provisional-K template public.tournament_write_match_elo()
-- (migration 20261219000000) — only the discipline set differs: this writer
-- touches ONLY 'personal' and contains no 'tournament' literal.
--
-- Additive only: one new function (CREATE OR REPLACE for idempotent re-apply)
-- + one trigger (DROP IF EXISTS / CREATE) + one COMMENT. No DDL on tables.
--
-- NOTE on live-schema drift (verified against the running container): the
-- match_participants CHECKs already force kind='in_app' AND user_id IS NOT
-- NULL (the walk_in/walkin_name shape no longer exists). The function still
-- carries the FULL §4 predicate (kind='in_app' AND user_id IS NOT NULL AND
-- invitation_status='accepted') so it stays correct regardless of schema; the
-- invitation_status='accepted' clause is the part still doing live filtering.

CREATE OR REPLACE FUNCTION public.match_write_personal_elo()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_winner_side   text;
  v_loser_side    text;
  v_default       int := public._elo_default();
  -- Provisional-K anchors (games-dependent K; see ELO_RATINGS.md §3).
  v_k_prov        int := public._elo_k_provisional();
  v_prov_games    int := public._elo_provisional_games();
  -- Per-side aggregate ratings (SUM of rateable member ELO; default-filled).
  v_rating_win    int;
  v_rating_lose   int;
  v_expected_win  double precision;
BEGIN
  -- Guard (defensive; the WHEN clause already enforces winner + status flip).
  IF NEW.winner_team_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Winner side is the recorded winner; loser side is the other of 'A'/'B'.
  v_winner_side := NEW.winner_team_id;
  v_loser_side  := CASE NEW.winner_team_id WHEN 'A' THEN 'B' ELSE 'A' END;

  -- A 1v1 match feeds ONLY discipline='personal' (ELO_RATINGS.md §2). The
  -- per-side aggregate = SUM of rateable member ELO with the neutral default
  -- for members lacking a 'personal' row yet; a side with zero rateable
  -- members falls back to the single-default baseline so the expectation term
  -- stays well-defined (matching the tournament writer's COALESCE(SUM,..)).
  --
  -- Rateable membership (§4): kind='in_app' AND user_id IS NOT NULL AND
  -- invitation_status='accepted'. Walk-ins / non-accepted contribute nothing
  -- and get no row.
  SELECT COALESCE(SUM(COALESCE(r.elo, v_default)), v_default)
    INTO v_rating_win
    FROM public.match_participants p
    LEFT JOIN public.player_ratings r
      ON r.user_id = p.user_id AND r.discipline = 'personal'
   WHERE p.match_id = NEW.id
     AND p.team_id  = v_winner_side
     AND p.kind     = 'in_app'
     AND p.user_id IS NOT NULL
     AND p.invitation_status = 'accepted';

  SELECT COALESCE(SUM(COALESCE(r.elo, v_default)), v_default)
    INTO v_rating_lose
    FROM public.match_participants p
    LEFT JOIN public.player_ratings r
      ON r.user_id = p.user_id AND r.discipline = 'personal'
   WHERE p.match_id = NEW.id
     AND p.team_id  = v_loser_side
     AND p.kind     = 'in_app'
     AND p.user_id IS NOT NULL
     AND p.invitation_status = 'accepted';

  -- Standard ELO: winner scored 1, expected from the rating difference.
  v_expected_win := 1.0 / (1.0 + power(10.0, (v_rating_lose - v_rating_win) / 400.0));

  -- Winners: +delta. Losers: -delta. UPSERT so first-ever rating rows are
  -- created at default ± delta. games +1 for every updated member. Provisional
  -- K is PER MEMBER on the PRE-increment games value:
  --   * new row (INSERT branch): games is 0 -> K = _elo_k_provisional() (40).
  --   * existing row (DO UPDATE branch): stored games read BEFORE the +1;
  --     K = 40 if games < threshold, else _elo_k() (24).
  -- Only rateable members are selected, so non-accepted / walk-in rows get no
  -- player_ratings row.
  INSERT INTO public.player_ratings(user_id, discipline, elo, games, updated_at)
  SELECT p.user_id,
         'personal',
         -- new-row baseline = default + delta; new row has games 0 -> K=40.
         greatest(0, v_default + round(v_k_prov * (1.0 - v_expected_win))),
         1,
         now()
    FROM public.match_participants p
   WHERE p.match_id = NEW.id
     AND p.team_id  = v_winner_side
     AND p.kind     = 'in_app'
     AND p.user_id IS NOT NULL
     AND p.invitation_status = 'accepted'
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
  SELECT p.user_id,
         'personal',
         greatest(0, v_default - round(v_k_prov * (1.0 - v_expected_win))),
         1,
         now()
    FROM public.match_participants p
   WHERE p.match_id = NEW.id
     AND p.team_id  = v_loser_side
     AND p.kind     = 'in_app'
     AND p.user_id IS NOT NULL
     AND p.invitation_status = 'accepted'
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

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.match_write_personal_elo() IS
  'AFTER-UPDATE trigger fn on public.matches: writes standard-ELO ONLY into '
  'discipline=''personal'' when a 1v1 match flips to finalized with a winner '
  '(ELO_RATINGS.md §2 — never tournament). Rateable members per side = '
  'match_participants kind=''in_app'' AND user_id NOT NULL AND '
  'invitation_status=''accepted'' (§4); walk-ins & non-accepted are ignored '
  'and get no row. Per-side aggregate = SUM of member personal-ELO (neutral '
  'default fill). Per-member games-dependent provisional K (40 while games<10 '
  'else 24, pre-increment games; §3); games incremented; elo=greatest(0,..).';


DROP TRIGGER IF EXISTS match_write_personal_elo ON public.matches;
CREATE TRIGGER match_write_personal_elo AFTER UPDATE ON public.matches FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM 'finalized' AND NEW.status = 'finalized'
        AND NEW.winner_team_id IS NOT NULL)
  EXECUTE FUNCTION public.match_write_personal_elo();
