-- Stage-graph TEMPLATES — carry the pitch plan (#11). Additive on top of
-- 20261230000000_tournament_stage_graph_templates.sql.
--
-- A StageGraphTemplate stores the participant-agnostic structure (`graph`).
-- The wizard's full setup also carries a PitchPlan (the available pitches /
-- fields + their assignment), which lived ONLY on the tournament's `p_setup`,
-- never on the template — so "save everything as a template" lost the pitches.
-- This migration adds an OPTIONAL `pitch_plan jsonb` column and extends the
-- save RPC with a matching nullable parameter. Old templates (pitch_plan NULL)
-- and old callers (no p_pitch_plan arg, DEFAULT NULL) keep working unchanged.
--
-- The apply RPC is intentionally NOT changed: it materializes stages/edges
-- from `graph` only. The pitch plan is restored CLIENT-SIDE in the wizard
-- (loaded into the config draft before the tournament is created), so there is
-- no server-side pitch restoration to do here.

-- ---- 1. Column (additive, nullable) ---------------------------------------

ALTER TABLE public.tournament_stage_graph_templates
  ADD COLUMN IF NOT EXISTS pitch_plan jsonb NULL;

-- ---- 2. RPC: save_stage_graph_template (+ p_pitch_plan) --------------------

CREATE OR REPLACE FUNCTION public.save_stage_graph_template(
  p_name        text,
  p_description text,
  p_visibility  text,
  p_graph       jsonb,
  p_club_id     uuid DEFAULT NULL,
  p_pitch_plan  jsonb DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid uuid;
  v_id  uuid;
BEGIN
  -- 1. Auth gate.
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- 2. Visibility domain.
  IF p_visibility NOT IN ('private','club','public') THEN
    RAISE EXCEPTION 'INVALID_VISIBILITY: % is not a valid visibility', p_visibility
      USING ERRCODE = '22023';
  END IF;

  -- 3. A 'club' template must carry a club id (mirrors the table CHECK, but
  --    raised here as a stable domain error rather than a raw constraint).
  IF p_visibility = 'club' AND p_club_id IS NULL THEN
    RAISE EXCEPTION 'CLUB_REQUIRED: club visibility needs a club_id'
      USING ERRCODE = '22023';
  END IF;

  -- 4. Graph validation: both top-level keys present and array-typed.
  IF NOT (p_graph ? 'nodes')
     OR NOT (p_graph ? 'edges')
     OR jsonb_typeof(p_graph -> 'nodes') <> 'array'
     OR jsonb_typeof(p_graph -> 'edges') <> 'array' THEN
    RAISE EXCEPTION 'INVALID_GRAPH: graph must have array keys nodes and edges'
      USING ERRCODE = '22023';
  END IF;

  -- 5. Pitch plan validation is tolerant: NULL is allowed (older / pitch-less
  --    setups), a non-NULL value must be a json object — never an array/scalar.
  IF p_pitch_plan IS NOT NULL AND jsonb_typeof(p_pitch_plan) <> 'object' THEN
    RAISE EXCEPTION 'INVALID_PITCH_PLAN: pitch_plan must be a json object'
      USING ERRCODE = '22023';
  END IF;

  -- 6. Insert (owner is always the caller — never owner-NULL).
  INSERT INTO public.tournament_stage_graph_templates
    (name, description, owner_user_id, club_id, visibility, graph, pitch_plan)
  VALUES
    (p_name, p_description, v_uid, p_club_id, p_visibility, p_graph, p_pitch_plan)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION
  public.save_stage_graph_template(text, text, text, jsonb, uuid, jsonb) FROM public;
GRANT EXECUTE ON FUNCTION
  public.save_stage_graph_template(text, text, text, jsonb, uuid, jsonb) TO authenticated;

COMMENT ON FUNCTION
  public.save_stage_graph_template(text, text, text, jsonb, uuid, jsonb) IS
  'ADR-0030 §Templates (#11): persist a stage-graph template owned by the '
  'caller, now carrying an optional pitch_plan jsonb. Auth gate (42501). '
  'Validates visibility domain, club_id presence for club visibility, that '
  'graph carries array keys nodes/edges, and that a non-NULL pitch_plan is a '
  'json object (else 22023). Always stamps owner_user_id = auth.uid() so it '
  'can never create or alter a system preset (owner NULL). Returns the new id.';
