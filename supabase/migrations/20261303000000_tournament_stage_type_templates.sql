-- Stufen-Typ-Vorlagen (Ebene 2) — spec §6 + §9.6, ADR-0037/ADR-0039.
--
-- A StageTypeTemplate is a PARTICIPANT-AGNOSTIC, reusable Ebene-2 type graph:
-- one stage modelled as rounds / fields / field-edges (StageTypeGraph.toJson,
-- the wire form {"category","rounds":[...],"edges":[...]}). It stores only the
-- structure (never concrete participants). Unlike the Ebene-1 stage-GRAPH
-- template (migration 20261230000000), the type template is NOT materialized
-- server-side into tournament_stages: it feeds a single stage's
-- config['type_graph']. So `apply` just returns the stored type_graph jsonb and
-- the client loads it into the stage-type-graph builder (loadFromGraph) before
-- the stage config is written.
--
-- Visibility mirrors the Ebene-1 organizer-team pattern (§6, §9.6): 'public' is
-- everyone-readable, 'private' is owner-only, 'club' is readable by active
-- members of the owning organizer team. The 'club' wire value is kept (the
-- 20261283000000 rename of Verein -> Veranstalterteam was behaviour-neutral and
-- left the visibility value 'club' untouched). The club arm reuses the
-- SECURITY-DEFINER-STABLE helper
-- public.is_active_organizer_team_member(organizer_team_id, user_id) — NOT a raw
-- team_members subselect — so there is no RLS recursion (same idiom as the
-- Ebene-1 template policy after the rename).
--
-- System presets are rows with owner_user_id IS NULL and visibility='public':
-- readable by everyone, mutable by no client (no client write policy is
-- declared; all writes go through the SECURITY-DEFINER save RPC, which always
-- stamps owner_user_id = auth.uid(), so it can never produce or alter an
-- owner-NULL row).
--
-- Error idiom (mirrors the Ebene-1 template RPCs): ERRCODE 42501 for auth
-- failures; ERRCODE 22023 for domain/graph failures with a stable CODE token in
-- the MESSAGE (INVALID_VISIBILITY / CLUB_REQUIRED / INVALID_TYPE_GRAPH /
-- TEMPLATE_NOT_FOUND).
--
-- Scope: purely additive. The only persistent data mutation is the single
-- idempotent system-preset INSERT at the end.

-- ---- 1. Table -------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.tournament_stage_type_templates (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name               text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
  description        text NULL,
  owner_user_id      uuid NULL REFERENCES auth.users(id) ON DELETE CASCADE,  -- NULL = system preset
  organizer_team_id  uuid NULL REFERENCES public.organizer_teams(id) ON DELETE CASCADE,
  visibility         text NOT NULL DEFAULT 'private'
                       CHECK (visibility IN ('private','club','public')),
  category           text NOT NULL DEFAULT 'ko'
                       CHECK (category IN ('ko','vorrunde')),
  type_graph         jsonb NOT NULL,  -- StageTypeGraph.toJson (participant-agnostic)
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  -- A 'club' template must name its organizer team; the system preset
  -- (visibility='public') is unaffected by this CHECK.
  CONSTRAINT tournament_stage_type_templates_club_visibility_chk
    CHECK (visibility <> 'club' OR organizer_team_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS tournament_stage_type_templates_owner_idx
  ON public.tournament_stage_type_templates(owner_user_id);
CREATE INDEX IF NOT EXISTS tournament_stage_type_templates_visibility_idx
  ON public.tournament_stage_type_templates(visibility);

-- ---- 2. RLS ---------------------------------------------------------------

ALTER TABLE public.tournament_stage_type_templates ENABLE ROW LEVEL SECURITY;

-- Base table read grant for the authenticated role (RLS still gates WHICH rows
-- are returned). No write grants: all writes go through the SECURITY-DEFINER
-- save RPC.
GRANT SELECT ON public.tournament_stage_type_templates TO authenticated;

-- A row is readable if it is public, owned by the caller, or a club template
-- whose organizer team the caller is an active member of. The club arm uses the
-- is_active_organizer_team_member helper (no direct team_members subselect ->
-- no RLS recursion). No INSERT/UPDATE/DELETE policy is declared: all writes go
-- through the SECURITY-DEFINER save RPC, so system presets (owner NULL) are
-- read-only for every client.
DROP POLICY IF EXISTS tournament_stage_type_templates_read
  ON public.tournament_stage_type_templates;
CREATE POLICY tournament_stage_type_templates_read
  ON public.tournament_stage_type_templates FOR SELECT
  USING (
    visibility = 'public'
    OR owner_user_id = auth.uid()
    OR (
      visibility = 'club'
      AND organizer_team_id IS NOT NULL
      AND public.is_active_organizer_team_member(organizer_team_id, auth.uid())
    )
  );

-- ---- 3. Helper: type_graph shape validation -------------------------------

-- A well-formed StageTypeGraph carries a 'category' string and array keys
-- 'rounds' and 'edges'. Raised as a stable domain error from both the save and
-- the (owner-overwrite) update path so a malformed body never lands.
CREATE OR REPLACE FUNCTION public._stage_type_graph_is_valid(p_graph jsonb)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_graph ? 'category'
     AND jsonb_typeof(p_graph -> 'category') = 'string'
     AND p_graph ? 'rounds'
     AND jsonb_typeof(p_graph -> 'rounds') = 'array'
     AND p_graph ? 'edges'
     AND jsonb_typeof(p_graph -> 'edges') = 'array'
     AND (p_graph ->> 'category') IN ('ko','vorrunde');
$$;

-- ---- 4. RPC: save_stage_type_template -------------------------------------

-- Upsert semantics: passing p_template_id overwrites an EXISTING template, but
-- only when the caller owns it (else TEMPLATE_NOT_FOUND — no existence oracle).
-- A NULL p_template_id inserts a fresh owner-stamped row. The category column is
-- derived from the type_graph body so it can never disagree with it.
CREATE OR REPLACE FUNCTION public.save_stage_type_template(
  p_name              text,
  p_description       text,
  p_visibility        text,
  p_type_graph        jsonb,
  p_organizer_team_id uuid DEFAULT NULL,
  p_template_id       uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid      uuid;
  v_id       uuid;
  v_category text;
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

  -- 3. A 'club' template must carry an organizer-team id.
  IF p_visibility = 'club' AND p_organizer_team_id IS NULL THEN
    RAISE EXCEPTION 'CLUB_REQUIRED: club visibility needs an organizer_team_id'
      USING ERRCODE = '22023';
  END IF;

  -- 4. Type-graph shape validation.
  IF NOT public._stage_type_graph_is_valid(p_type_graph) THEN
    RAISE EXCEPTION 'INVALID_TYPE_GRAPH: type_graph must carry a category and '
      'array keys rounds and edges'
      USING ERRCODE = '22023';
  END IF;

  v_category := p_type_graph ->> 'category';

  -- 5a. Overwrite path: only the owner may overwrite. SECURITY DEFINER bypasses
  --     RLS, so the ownership check is explicit. A non-owned / missing id ->
  --     TEMPLATE_NOT_FOUND (no existence oracle).
  IF p_template_id IS NOT NULL THEN
    UPDATE public.tournament_stage_type_templates
       SET name              = p_name,
           description       = p_description,
           visibility        = p_visibility,
           organizer_team_id = p_organizer_team_id,
           category          = v_category,
           type_graph        = p_type_graph,
           updated_at        = now()
     WHERE id = p_template_id
       AND owner_user_id = v_uid
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'TEMPLATE_NOT_FOUND: template not found or not owned'
        USING ERRCODE = '22023';
    END IF;

    RETURN v_id;
  END IF;

  -- 5b. Insert path (owner is always the caller — never owner-NULL).
  INSERT INTO public.tournament_stage_type_templates
    (name, description, owner_user_id, organizer_team_id, visibility, category,
     type_graph)
  VALUES
    (p_name, p_description, v_uid, p_organizer_team_id, p_visibility, v_category,
     p_type_graph)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION
  public.save_stage_type_template(text, text, text, jsonb, uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION
  public.save_stage_type_template(text, text, text, jsonb, uuid, uuid) TO authenticated;

COMMENT ON FUNCTION
  public.save_stage_type_template(text, text, text, jsonb, uuid, uuid) IS
  'spec §6/§9.6: persist a participant-agnostic Ebene-2 stage-TYPE template '
  '(StageTypeGraph) owned by the caller. Auth gate (42501). Validates visibility '
  'domain, club_id presence for club visibility, and the type_graph shape '
  '(category + array rounds/edges, else 22023 INVALID_TYPE_GRAPH). Passing '
  'p_template_id overwrites only when the caller owns the row (else 22023 '
  'TEMPLATE_NOT_FOUND); NULL inserts a fresh owner-stamped row. category is '
  'derived from the body. organizer_team_id scopes a club-visible template. '
  'Returns the template id.';

-- ---- 5. RPC: apply_stage_type_template ------------------------------------

-- Returns the stored type_graph jsonb for the client to load into the
-- stage-type-graph builder (loadFromGraph) and materialize into a single
-- stage's config['type_graph']. SECURITY DEFINER bypasses RLS, so the B2 read
-- predicate is re-applied explicitly. Not readable / not existent ->
-- TEMPLATE_NOT_FOUND.
CREATE OR REPLACE FUNCTION public.apply_stage_type_template(
  p_template_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid        uuid;
  v_type_graph jsonb;
BEGIN
  -- 1. Auth gate.
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- 2. Re-apply the read predicate (SECURITY DEFINER bypasses RLS).
  SELECT t.type_graph INTO v_type_graph
    FROM public.tournament_stage_type_templates t
    WHERE t.id = p_template_id
      AND (
        t.visibility = 'public'
        OR t.owner_user_id = v_uid
        OR (
          t.visibility = 'club'
          AND t.organizer_team_id IS NOT NULL
          AND public.is_active_organizer_team_member(t.organizer_team_id, v_uid)
        )
      );

  IF v_type_graph IS NULL THEN
    RAISE EXCEPTION 'TEMPLATE_NOT_FOUND: template not found or not readable'
      USING ERRCODE = '22023';
  END IF;

  RETURN v_type_graph;
END;
$$;

REVOKE ALL ON FUNCTION
  public.apply_stage_type_template(uuid) FROM public;
GRANT EXECUTE ON FUNCTION
  public.apply_stage_type_template(uuid) TO authenticated;

COMMENT ON FUNCTION public.apply_stage_type_template(uuid) IS
  'spec §6/§9.6: fetch a stage-TYPE template''s stored type_graph for the client '
  'to load into the stage-type-graph builder and materialize into a single '
  'stage''s config[type_graph]. Auth gate (42501). Re-applies the template read '
  'predicate (SECURITY DEFINER bypasses RLS) -> 22023 TEMPLATE_NOT_FOUND if not '
  'readable. Returns the type_graph jsonb (round-trips through '
  'StageTypeGraph.fromJson).';

-- ---- 6. System preset (idempotent) ----------------------------------------

-- A single public, owner-less preset: a KO type for 8 participants (round 1 =
-- F1..F4, round 2 = F1..F2, final = F1) wired winner -> winner -> final, in
-- exact StageTypeGraph.toJson form. `name` is not UNIQUE, so the insert is
-- guarded by WHERE NOT EXISTS to stay idempotent. This is the only persistent
-- data mutation of the migration.
INSERT INTO public.tournament_stage_type_templates
  (name, description, owner_user_id, organizer_team_id, visibility, category,
   type_graph)
SELECT
  'KO 8 (Standard)',
  'Knockout-Typ für 8 Teilnehmer: Viertelfinal, Halbfinal, Final.',
  NULL,
  NULL,
  'public',
  'ko',
  '{
     "category": "ko",
     "rounds": [
       {
         "round_number": 1,
         "fields": [
           {"id": "R1F1", "round_number": 1, "slot": 1},
           {"id": "R1F2", "round_number": 1, "slot": 2},
           {"id": "R1F3", "round_number": 1, "slot": 3},
           {"id": "R1F4", "round_number": 1, "slot": 4}
         ],
         "match_format": {"sets_to_win": 2, "max_sets": 3, "time_limit_seconds": 1800, "tiebreak_enabled": false},
         "ko_matchup": "seed_high_vs_low",
         "ko_tiebreak_method": "classic_kingtoss_removal"
       },
       {
         "round_number": 2,
         "fields": [
           {"id": "R2F1", "round_number": 2, "slot": 1},
           {"id": "R2F2", "round_number": 2, "slot": 2}
         ],
         "match_format": {"sets_to_win": 2, "max_sets": 3, "time_limit_seconds": 1800, "tiebreak_enabled": false},
         "ko_matchup": "seed_high_vs_low",
         "ko_tiebreak_method": "classic_kingtoss_removal"
       },
       {
         "round_number": 3,
         "fields": [
           {"id": "R3F1", "round_number": 3, "slot": 1}
         ],
         "match_format": {"sets_to_win": 2, "max_sets": 3, "time_limit_seconds": 1800, "tiebreak_enabled": false},
         "ko_matchup": "seed_high_vs_low",
         "ko_tiebreak_method": "classic_kingtoss_removal"
       }
     ],
     "edges": [
       {"kind": "winner", "from_field_id": "R1F1", "to_field_id": "R2F1"},
       {"kind": "winner", "from_field_id": "R1F2", "to_field_id": "R2F1"},
       {"kind": "winner", "from_field_id": "R1F3", "to_field_id": "R2F2"},
       {"kind": "winner", "from_field_id": "R1F4", "to_field_id": "R2F2"},
       {"kind": "winner", "from_field_id": "R2F1", "to_field_id": "R3F1"},
       {"kind": "winner", "from_field_id": "R2F2", "to_field_id": "R3F1"}
     ]
   }'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM public.tournament_stage_type_templates
   WHERE name = 'KO 8 (Standard)'
     AND owner_user_id IS NULL
);
