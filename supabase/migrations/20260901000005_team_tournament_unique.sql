-- P2 follow-up: unique names for teams and tournaments, plus an automatic
-- year suffix on tournaments.
--
-- - Team names are globally unique (case- and whitespace-insensitive).
-- - Tournament names are stored WITH the current year appended on create
--   ("KUCA" -> "KUCA 2026") and are unique that way, so the same event can
--   be created again next year as "KUCA 2027".
--
-- Both tables are currently empty (0 rows), so the unique indexes build
-- without a backfill conflict.


-- ---- 1. Unique team names ------------------------------------------

CREATE UNIQUE INDEX IF NOT EXISTS teams_display_name_unique_idx
  ON public.teams (lower(btrim(display_name)));

COMMENT ON INDEX public.teams_display_name_unique_idx IS
  'Team display names are globally unique, case- and whitespace-insensitive.';


-- ---- 2. Unique tournament names (year included) --------------------

CREATE UNIQUE INDEX IF NOT EXISTS tournaments_display_name_unique_idx
  ON public.tournaments (lower(btrim(display_name)));

COMMENT ON INDEX public.tournaments_display_name_unique_idx IS
  'Tournament display names (which include the year suffix, e.g. '
  '"KUCA 2026") are unique, case- and whitespace-insensitive.';


-- ---- 3. tournament_create: year suffix + duplicate guard -----------
--
-- Re-declares tournament_create (last: 20260901000003) so the stored name
-- gets the current year appended and duplicates are rejected with a clear
-- message before the insert. The organizer gate and all other validations
-- are unchanged.

CREATE OR REPLACE FUNCTION public.tournament_create(
  p_display_name        text,
  p_team_size           int,
  p_min_participants    int,
  p_max_participants    int,
  p_format              text,
  p_match_format_config jsonb,
  p_tiebreaker_order    text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_tournament_id uuid;
  v_display_name  text;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Organizer-role gate (P1). Blocks only an explicit non-organizer.
  IF EXISTS (
    SELECT 1 FROM public.user_profiles up
     WHERE up.user_id = v_caller AND up.is_organizer = false
  ) THEN
    RAISE EXCEPTION 'organizer role required to create tournaments'
      USING ERRCODE = '42501';
  END IF;

  IF p_display_name IS NULL OR length(btrim(p_display_name)) < 1
     OR length(btrim(p_display_name)) > 55 THEN
    RAISE EXCEPTION 'display_name length must be 1..55 (year suffix is added)'
      USING ERRCODE = '22023';
  END IF;
  IF p_team_size IS NULL OR p_team_size < 1 OR p_team_size > 6 THEN
    RAISE EXCEPTION 'team_size must be 1..6' USING ERRCODE = '22023';
  END IF;
  IF p_min_participants IS NULL OR p_min_participants < 2 THEN
    RAISE EXCEPTION 'min_participants must be >= 2' USING ERRCODE = '22023';
  END IF;
  IF p_max_participants IS NULL
     OR p_max_participants < p_min_participants
     OR p_max_participants > 200 THEN
    RAISE EXCEPTION 'max_participants must be in [min_participants, 200]'
      USING ERRCODE = '22023';
  END IF;
  IF p_format IS NULL OR p_format NOT IN (
       'round_robin','single_elimination','round_robin_then_ko',
       'schoch','swiss','schoch_then_ko','swiss_then_ko') THEN
    RAISE EXCEPTION 'invalid format' USING ERRCODE = '22023';
  END IF;
  IF p_match_format_config IS NULL OR jsonb_typeof(p_match_format_config) <> 'object' THEN
    RAISE EXCEPTION 'match_format_config must be a JSON object' USING ERRCODE = '22023';
  END IF;
  IF p_tiebreaker_order IS NULL OR array_length(p_tiebreaker_order, 1) IS NULL THEN
    RAISE EXCEPTION 'tiebreaker_order must be a non-empty array' USING ERRCODE = '22023';
  END IF;

  -- Year suffix: "KUCA" -> "KUCA 2026". Unique per year, so next year's
  -- edition ("KUCA 2027") is a distinct, allowed name.
  v_display_name := btrim(p_display_name) || ' ' || to_char(now(), 'YYYY');

  IF EXISTS (
    SELECT 1 FROM public.tournaments t
     WHERE lower(btrim(t.display_name)) = lower(v_display_name)
  ) THEN
    RAISE EXCEPTION 'a tournament named "%" already exists', v_display_name
      USING ERRCODE = '23505';
  END IF;

  INSERT INTO public.tournaments(
      created_by, display_name, team_size, min_participants, max_participants,
      format, scoring, match_format, tiebreaker_order, status)
    VALUES (
      v_caller, v_display_name, p_team_size::smallint,
      p_min_participants::smallint, p_max_participants::smallint,
      p_format, 'ekc', p_match_format_config, p_tiebreaker_order, 'draft')
    RETURNING id INTO v_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'created',
      v_caller,
      jsonb_build_object(
        'display_name',     v_display_name,
        'team_size',        p_team_size,
        'min_participants', p_min_participants,
        'max_participants', p_max_participants,
        'format',           p_format
      )
    );

  RETURN jsonb_build_object('tournament_id', v_tournament_id);
END;
$$;
