-- P1 (Tournament-Hub): coarse "organizer" role on user_profiles.
--
-- Product decision 2026-05-31: the flag defaults to TRUE, so every
-- existing and new account may create/publish tournaments for now. A later
-- verification flow (Roadmap B10) can flip the default to FALSE and this
-- gate then enforces verified-organizer-only without further code changes.
--
-- Read by the client (the tournament hub gates the "create" tile on it)
-- and enforced server-side in tournament_create below as defense-in-depth.


-- ---- 1. Column ------------------------------------------------------

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS is_organizer boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.user_profiles.is_organizer IS
  'Whether the user may create/publish tournaments. Defaults to true so '
  'every account is an organizer for now; a later verification flow '
  '(Roadmap B10) can tighten the default. Read by the client tournament '
  'hub and enforced in tournament_create.';


-- ---- 2. Enforce the role in tournament_create -----------------------
--
-- Re-declares tournament_create (originally 20260525000002) with one extra
-- guard right after the auth check; the rest is identical. The guard only
-- blocks callers whose profile EXPLICITLY has is_organizer = false, so
-- accounts without a profile row (or with the default true) are unaffected
-- — nothing that works today breaks while the default stays true.

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
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Organizer-role gate (P1). Blocks only an explicit non-organizer; the
  -- default-true column keeps every current account allowed.
  IF EXISTS (
    SELECT 1 FROM public.user_profiles up
     WHERE up.user_id = v_caller AND up.is_organizer = false
  ) THEN
    RAISE EXCEPTION 'organizer role required to create tournaments'
      USING ERRCODE = '42501';
  END IF;

  IF p_display_name IS NULL OR length(p_display_name) < 1 OR length(p_display_name) > 60 THEN
    RAISE EXCEPTION 'display_name length must be 1..60' USING ERRCODE = '22023';
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

  INSERT INTO public.tournaments(
      created_by, display_name, team_size, min_participants, max_participants,
      format, scoring, match_format, tiebreaker_order, status)
    VALUES (
      v_caller, p_display_name, p_team_size::smallint,
      p_min_participants::smallint, p_max_participants::smallint,
      p_format, 'ekc', p_match_format_config, p_tiebreaker_order, 'draft')
    RETURNING id INTO v_tournament_id;

  INSERT INTO public.tournament_audit_events(tournament_id, kind, actor_user_id, payload)
    VALUES (
      v_tournament_id,
      'created',
      v_caller,
      jsonb_build_object(
        'display_name',     p_display_name,
        'team_size',        p_team_size,
        'min_participants', p_min_participants,
        'max_participants', p_max_participants,
        'format',           p_format
      )
    );

  RETURN jsonb_build_object('tournament_id', v_tournament_id);
END;
$$;
