-- Tournament stage-graph persistence — ADR-0030 (§Modell + §Persistenz).
--
-- Adds two additive child tables that materialize the stage-graph of a
-- tournament: `tournament_stages` (graph nodes) and
-- `tournament_stage_edges` (routing edges). The columns mirror the Dart
-- domain model in its WIRE form (Lage 1a, `packages/kubb_domain/.../
-- stage_graph/`): snake_case enum strings plus jsonb for the free-form
-- `config` / `selector` payloads.
--
--   * type / seeding / status   <- StageNodeType / StageSeedingSource +
--                                   runner runtime state
--   * from_node_id / to_node_id / selector / seeding_in
--                                <- StageEdge.toJson keys + StageSeedingIn
--   * node_id                    <- StageNode.toJson key `id`
--
-- The three CHECK lists are character-for-character identical to the Dart
-- enums' `wire` strings (stage_node.dart / stage_edge.dart). `ruleset`,
-- `groupCount` etc. live INSIDE `config` (jsonb), per the Dart model — they
-- are NOT separate columns. `status` (pending->active->completed) is pure
-- runner runtime state and is server-authoritative; it is not part of the
-- Dart wire form (ADR-0030 §Runner-Semantik).
--
-- RLS — mirrors the existing tournament child-table pattern
-- (`public.tournament_matches`, migration 20260525000001):
--
--   * SELECT policy = exact copy of `tournament_matches_read`: a row is
--     visible to anyone who may read its tournament, i.e. the graph of a
--     non-draft tournament is publicly/spectator-readable, a draft only to
--     its creator.
--
--   * Write strategy = NO-CLIENT-WRITE (deliberate choice, documented here).
--     `tournament_matches` declares NO INSERT/UPDATE/DELETE policy (schema
--     header 20260525000001 §150-152: "All other mutations ... go through
--     RPCs only — no INSERT/UPDATE/DELETE policy declared, so direct client
--     writes fail."). Stages/edges are the same concept (server-materialized
--     tournament child rows), so the same pattern is adopted. Per ADR-0030
--     §Runner-Semantik + §Offene Punkte 3, materialization is
--     server-authoritative (trigger/RPC, SECURITY DEFINER); the client never
--     writes these rows directly. The existing helper
--     `public.tournament_caller_can_manage` is an RPC-INTERNAL gate (used as
--     an `IF NOT ... THEN raise` check in 20261201000032), NOT a table write
--     policy — exposing it as a write policy would permit direct client
--     writes and bypass the server-authority path, which is unwanted.
--     Consequence: NO INSERT/UPDATE/DELETE policy is declared on either
--     table; writes happen later exclusively via a SECURITY-DEFINER
--     runner/RPC (separate migration, out of this scope).

-- ---- 1. tournament_stages (graph nodes) ------------------------------

CREATE TABLE IF NOT EXISTS public.tournament_stages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  node_id       text NOT NULL,  -- stable StageNode.id within the graph (wire key `id`)
  type          text NOT NULL CHECK (type IN (
                  'pool','round_robin','swiss','single_elim','double_elim',
                  'consolation','shootout_quali')),  -- StageNodeType.wire
  config        jsonb NOT NULL DEFAULT '{}'::jsonb,  -- StageNode.config (ruleset/groupCount/... live here)
  seeding       text NOT NULL DEFAULT 'as_routed' CHECK (seeding IN (
                  'from_elo','from_prev_ranking','manual','as_routed')),  -- StageSeedingSource.wire
  status        text NOT NULL DEFAULT 'pending' CHECK (status IN (
                  'pending','active','completed')),  -- runner runtime state (server-side, not wire)
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT tournament_stages_unique_node UNIQUE (tournament_id, node_id)
);
CREATE INDEX IF NOT EXISTS tournament_stages_tournament_idx
  ON public.tournament_stages(tournament_id);

-- ---- 2. tournament_stage_edges (routing edges) -----------------------

CREATE TABLE IF NOT EXISTS public.tournament_stage_edges (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  from_node_id  text NOT NULL,  -- StageEdge.from_node_id
  to_node_id    text NOT NULL,  -- StageEdge.to_node_id
  selector      jsonb NOT NULL,  -- EdgeSelector.toJson ({'kind':...})
  seeding_in    text NOT NULL DEFAULT 'order_preserving' CHECK (seeding_in IN (
                  'order_preserving','reseed_by_source_rank','manual')),  -- StageSeedingIn.wire
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS tournament_stage_edges_tournament_idx
  ON public.tournament_stage_edges(tournament_id);
-- Serves the runner query "outgoing edges of a stage" (ADR-0030
-- §Runner-Semantik step 2).
CREATE INDEX IF NOT EXISTS tournament_stage_edges_from_idx
  ON public.tournament_stage_edges(tournament_id, from_node_id);

-- ---- 3. RLS ----------------------------------------------------------

ALTER TABLE public.tournament_stages ENABLE ROW LEVEL SECURITY;

-- Exact mirror of tournament_matches_read: visible to anyone who may read
-- the parent tournament (non-draft = public/spectator, draft = creator).
DROP POLICY IF EXISTS tournament_stages_read ON public.tournament_stages;
CREATE POLICY tournament_stages_read
  ON public.tournament_stages FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tournaments t
      WHERE t.id = tournament_stages.tournament_id
        AND (t.status <> 'draft' OR t.created_by = auth.uid())
    )
  );

-- No INSERT/UPDATE/DELETE policy: writes go through a SECURITY-DEFINER
-- runner/RPC only (mirrors tournament_matches).

ALTER TABLE public.tournament_stage_edges ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS tournament_stage_edges_read ON public.tournament_stage_edges;
CREATE POLICY tournament_stage_edges_read
  ON public.tournament_stage_edges FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tournaments t
      WHERE t.id = tournament_stage_edges.tournament_id
        AND (t.status <> 'draft' OR t.created_by = auth.uid())
    )
  );

-- No INSERT/UPDATE/DELETE policy: writes go through a SECURITY-DEFINER
-- runner/RPC only (mirrors tournament_matches).
