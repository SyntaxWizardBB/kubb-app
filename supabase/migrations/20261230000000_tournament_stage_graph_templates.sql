-- Tournament stage-graph TEMPLATES — ADR-0030 (§Templates).
--
-- A StageGraphTemplate is a PARTICIPANT-AGNOSTIC, reusable stage-graph
-- blueprint. It stores only the structure (`graph` = StageGraph.toJson, the
-- Lage-1a wire form: {"nodes":[{"id","type","config","seeding"}],
-- "edges":[{"from_node_id","to_node_id","selector","seeding_in"}]}) and never
-- references concrete participants. Templates can be saved by a user (private /
-- club / public) and APPLIED to a pre-start tournament, which materializes the
-- graph into `tournament_stages` / `tournament_stage_edges` (copy semantics —
-- no live link, only a `source_template_id` provenance hint).
--
-- Visibility mirrors the club pattern: 'public' is everyone-readable, 'private'
-- is owner-only, 'club' is readable by active members of the owning club. The
-- club predicate reuses the SECURITY-DEFINER-STABLE helper
-- `public.is_active_club_member(club_id, user_id)` (which reads
-- `public.club_memberships` with soft-delete `removed_at IS NULL`) — NOT a raw
-- `club_memberships` subselect, to avoid RLS recursion (same idiom as the club
-- membership/invitation/audit policies, migration 20260901000012).
--
-- System presets are rows with `owner_user_id IS NULL` and `visibility='public'`:
-- readable by everyone, mutable by no client (no client write policy is
-- declared; all writes go through the SECURITY-DEFINER save RPC, and that RPC
-- always stamps `owner_user_id = auth.uid()`, so it can never produce or alter
-- an owner-NULL row).
--
-- Error idiom (mirrors tournament_start_stage_graph): ERRCODE 42501 for
-- auth/manage failures; ERRCODE 22023 for domain/status/graph failures, with a
-- stable CODE token in the MESSAGE (INVALID_GRAPH / TEMPLATE_NOT_FOUND /
-- ALREADY_HAS_STAGES / TOURNAMENT_NOT_PRE_START).
--
-- Scope: purely additive. The only persistent data mutation is the single
-- idempotent system-preset INSERT at the end.

-- ---- 1. Table -------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.tournament_stage_graph_templates (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name               text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
  description        text NULL,
  owner_user_id      uuid NULL REFERENCES auth.users(id) ON DELETE CASCADE,  -- NULL = system preset
  club_id            uuid NULL REFERENCES public.clubs(id) ON DELETE CASCADE,
  visibility         text NOT NULL DEFAULT 'private'
                       CHECK (visibility IN ('private','club','public')),
  graph              jsonb NOT NULL,  -- StageGraph.toJson (participant-agnostic)
  source_template_id uuid NULL,       -- provenance hint (copy semantics, no live FK)
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  -- A 'club' template must name its club; the system preset (visibility='public')
  -- is unaffected by this CHECK.
  CONSTRAINT tournament_stage_graph_templates_club_visibility_chk
    CHECK (visibility <> 'club' OR club_id IS NOT NULL)
);

CREATE INDEX IF NOT EXISTS tournament_stage_graph_templates_owner_idx
  ON public.tournament_stage_graph_templates(owner_user_id);
CREATE INDEX IF NOT EXISTS tournament_stage_graph_templates_visibility_idx
  ON public.tournament_stage_graph_templates(visibility);

-- ---- 2. RLS ---------------------------------------------------------------

ALTER TABLE public.tournament_stage_graph_templates ENABLE ROW LEVEL SECURITY;

-- A row is readable if it is public, owned by the caller, or a club template
-- whose club the caller is an active member of. The club arm uses the
-- is_active_club_member helper (no direct club_memberships subselect ->
-- no RLS recursion). No INSERT/UPDATE/DELETE policy is declared: all writes go
-- through the SECURITY-DEFINER save RPC, so system presets (owner NULL) are
-- read-only for every client.
DROP POLICY IF EXISTS tournament_stage_graph_templates_read
  ON public.tournament_stage_graph_templates;
CREATE POLICY tournament_stage_graph_templates_read
  ON public.tournament_stage_graph_templates FOR SELECT
  USING (
    visibility = 'public'
    OR owner_user_id = auth.uid()
    OR (
      visibility = 'club'
      AND club_id IS NOT NULL
      AND public.is_active_club_member(club_id, auth.uid())
    )
  );

-- ---- 3. RPC: save_stage_graph_template ------------------------------------

CREATE OR REPLACE FUNCTION public.save_stage_graph_template(
  p_name        text,
  p_description text,
  p_visibility  text,
  p_graph       jsonb,
  p_club_id     uuid DEFAULT NULL
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

  -- 5. Insert (owner is always the caller — never owner-NULL).
  INSERT INTO public.tournament_stage_graph_templates
    (name, description, owner_user_id, club_id, visibility, graph)
  VALUES
    (p_name, p_description, v_uid, p_club_id, p_visibility, p_graph)
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION
  public.save_stage_graph_template(text, text, text, jsonb, uuid) FROM public;
GRANT EXECUTE ON FUNCTION
  public.save_stage_graph_template(text, text, text, jsonb, uuid) TO authenticated;

COMMENT ON FUNCTION
  public.save_stage_graph_template(text, text, text, jsonb, uuid) IS
  'ADR-0030 §Templates: persist a participant-agnostic stage-graph template '
  'owned by the caller. Auth gate (42501). Validates visibility domain, club_id '
  'presence for club visibility, and that graph carries array keys nodes/edges '
  '(else 22023 INVALID_GRAPH). Always stamps owner_user_id = auth.uid() so it '
  'can never create or alter a system preset (owner NULL). Returns the new id.';

-- ---- 4. RPC: apply_stage_graph_template -----------------------------------

CREATE OR REPLACE FUNCTION public.apply_stage_graph_template(
  p_tournament_id uuid,
  p_template_id   uuid
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid          uuid;
  v_status       text;
  v_created_by   uuid;
  v_graph        jsonb;
  v_node_count   int;
  v_edge_count   int;
BEGIN
  -- 1. Auth gate.
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- 2. Load + lock the tournament. Not-found OR not-authorised collapse into
  --    one 42501 (no existence oracle) — same idiom as tournament_start_stage_graph.
  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_created_by IS NULL
     OR NOT public.tournament_caller_can_manage(p_tournament_id) THEN
    RAISE EXCEPTION 'tournament not found or not authorised' USING ERRCODE = '42501';
  END IF;

  -- 3. Status gate: only a pre-start tournament may receive a stage graph.
  --    Formulated as the same ALLOWLIST as the sister RPC
  --    tournament_start_stage_graph (non-terminal pre-live stati of
  --    tournaments_status_check) so the two RPCs stay in lock-step: a future
  --    pre-start status added to the CHECK would NOT be silently admitted here
  --    by a stale denylist. Equivalent to the prior denylist over today's
  --    7-value CHECK {draft, published, registration_open, registration_closed,
  --    live, finalized, aborted}.
  IF v_status NOT IN ('published', 'registration_open', 'registration_closed', 'draft') THEN
    RAISE EXCEPTION 'TOURNAMENT_NOT_PRE_START: tournament is not in a pre-start status'
      USING ERRCODE = '22023';
  END IF;

  -- 4. Template visibility check. SECURITY DEFINER bypasses RLS, so we re-apply
  --    the B5 read predicate explicitly. Not readable / not existent ->
  --    TEMPLATE_NOT_FOUND.
  SELECT t.graph INTO v_graph
    FROM public.tournament_stage_graph_templates t
    WHERE t.id = p_template_id
      AND (
        t.visibility = 'public'
        OR t.owner_user_id = v_uid
        OR (
          t.visibility = 'club'
          AND t.club_id IS NOT NULL
          AND public.is_active_club_member(t.club_id, v_uid)
        )
      );

  IF v_graph IS NULL THEN
    RAISE EXCEPTION 'TEMPLATE_NOT_FOUND: template not found or not readable'
      USING ERRCODE = '22023';
  END IF;

  -- 5. Conflict gate (copy semantics, no merge): the tournament must have no
  --    stages yet.
  IF EXISTS (
    SELECT 1 FROM public.tournament_stages
     WHERE tournament_id = p_tournament_id
  ) THEN
    RAISE EXCEPTION 'ALREADY_HAS_STAGES: tournament already has stages'
      USING ERRCODE = '22023';
  END IF;

  -- 6. Materialize nodes. Wire keys map 1:1 onto the L1b columns; config
  --    defaults to {} and seeding to 'as_routed' when the node omits them.
  INSERT INTO public.tournament_stages (tournament_id, node_id, type, config, seeding)
  SELECT
    p_tournament_id,
    node ->> 'id',
    node ->> 'type',
    coalesce(node -> 'config', '{}'::jsonb),
    coalesce(node ->> 'seeding', 'as_routed')
  FROM jsonb_array_elements(v_graph -> 'nodes') AS node;
  GET DIAGNOSTICS v_node_count = ROW_COUNT;

  -- 7. Materialize edges. `selector` is jsonb NOT NULL — a well-formed template
  --    carries a selector object; a missing one would fail the NOT NULL cleanly.
  INSERT INTO public.tournament_stage_edges
    (tournament_id, from_node_id, to_node_id, selector, seeding_in)
  SELECT
    p_tournament_id,
    edge ->> 'from_node_id',
    edge ->> 'to_node_id',
    edge -> 'selector',
    coalesce(edge ->> 'seeding_in', 'order_preserving')
  FROM jsonb_array_elements(v_graph -> 'edges') AS edge;
  GET DIAGNOSTICS v_edge_count = ROW_COUNT;

  -- 8. Return total rows materialized (#nodes + #edges).
  RETURN v_node_count + v_edge_count;
END;
$$;

REVOKE ALL ON FUNCTION
  public.apply_stage_graph_template(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION
  public.apply_stage_graph_template(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.apply_stage_graph_template(uuid, uuid) IS
  'ADR-0030 §Templates: materialize a stage-graph template into a pre-start '
  'tournament (copy semantics). Manage gate (creator/club role, 42501) + '
  'pre-start status gate (else 22023 TOURNAMENT_NOT_PRE_START). Re-applies the '
  'template read predicate (SECURITY DEFINER bypasses RLS) -> 22023 '
  'TEMPLATE_NOT_FOUND if not readable. Refuses if the tournament already has '
  'stages (22023 ALREADY_HAS_STAGES). Instantiates tournament_stages / '
  'tournament_stage_edges from graph nodes/edges and returns #nodes + #edges.';

-- ---- 5. System preset (idempotent) ----------------------------------------

-- A single public, owner-less preset: a two-stage "pool -> single-elim (top 2)"
-- graph in exact StageGraph.toJson form. `name` is not UNIQUE, so the insert is
-- guarded by WHERE NOT EXISTS to stay idempotent across re-runs. This is the
-- only persistent data mutation of the migration.
INSERT INTO public.tournament_stage_graph_templates
  (name, description, owner_user_id, club_id, visibility, graph)
SELECT
  'Pool -> KO (Top 2)',
  'Two-stage preset: a pool stage feeding its top 2 into a single-elimination bracket.',
  NULL,
  NULL,
  'public',
  '{
     "nodes": [
       {"id": "grp", "type": "pool", "config": {}, "seeding": "as_routed"},
       {"id": "ko", "type": "single_elim", "config": {}, "seeding": "as_routed"}
     ],
     "edges": [
       {"from_node_id": "grp", "selector": {"kind": "top_k", "k": 2}, "to_node_id": "ko", "seeding_in": "order_preserving"}
     ]
   }'::jsonb
WHERE NOT EXISTS (
  SELECT 1 FROM public.tournament_stage_graph_templates
   WHERE name = 'Pool -> KO (Top 2)'
     AND owner_user_id IS NULL
);
