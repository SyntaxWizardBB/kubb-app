-- M5.2-T7 — Consolidated season read RPC.
--
-- `season_get(p_season_id)` returns the full read payload that the
-- season standings screen needs in a single round-trip:
--   { "season":       {...},      -- meta row from `seasons`
--     "tournaments":  [...],      -- rows from `season_tournaments`
--     "standings":    [...] }     -- rows from `v_season_standings`
--
-- The function runs SECURITY INVOKER so RLS still applies. As a
-- belt-and-braces guard for `draft`-status seasons, the body
-- short-circuits unless the caller is a league admin: a draft
-- season returns an empty payload for everyone else, mirroring
-- the underlying RLS visibility rules.

CREATE OR REPLACE FUNCTION public.season_get(p_season_id uuid)
RETURNS json
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_status        text;
  v_is_admin      boolean := (auth.jwt() ->> 'role' = 'league_admin');
  v_season        jsonb;
  v_tournaments   jsonb;
  v_standings     jsonb;
BEGIN
  SELECT status
    INTO v_status
    FROM public.seasons
   WHERE id = p_season_id;

  IF v_status IS NULL THEN
    -- Unknown season id or hidden by RLS — both surface as empty.
    RETURN json_build_object(
      'season',      NULL,
      'tournaments', '[]'::json,
      'standings',   '[]'::json
    );
  END IF;

  -- Draft seasons are admin-only. Non-admin callers get an empty
  -- payload, never an error, so the UI can render a uniform
  -- "no data" state without leaking existence.
  IF v_status = 'draft' AND NOT v_is_admin THEN
    RETURN json_build_object(
      'season',      NULL,
      'tournaments', '[]'::json,
      'standings',   '[]'::json
    );
  END IF;

  SELECT to_jsonb(s.*)
    INTO v_season
    FROM public.seasons s
   WHERE s.id = p_season_id;

  SELECT coalesce(jsonb_agg(to_jsonb(st.*) ORDER BY st.awarded_at), '[]'::jsonb)
    INTO v_tournaments
    FROM public.season_tournaments st
   WHERE st.season_id = p_season_id;

  SELECT coalesce(jsonb_agg(to_jsonb(v.*)), '[]'::jsonb)
    INTO v_standings
    FROM public.v_season_standings v
   WHERE v.season_id = p_season_id;

  RETURN json_build_object(
    'season',      v_season,
    'tournaments', v_tournaments,
    'standings',   v_standings
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.season_get(uuid) TO anon, authenticated;

COMMENT ON FUNCTION public.season_get(uuid) IS
  'Consolidated read path for the season standings screen. Returns '
  'season meta + season_tournaments + v_season_standings as a single '
  'JSON document. Draft-status seasons are visible to league_admin '
  'only; other callers receive an empty payload.';
