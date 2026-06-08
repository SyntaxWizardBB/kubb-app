-- Associate matches with stage-graph stages (System 3, runner integration).
--
-- ADR-0030 §Runner-Semantik: the runner generates a stage's matches and must
-- know which match belongs to which graph node. The existing tournament_matches
-- only carries tournament_id + phase/round. This adds an OPTIONAL stage_node_id:
--   * legacy / non-stage-graph tournaments leave it NULL (unaffected),
--   * stage-graph tournaments set it to the owning StageNode.id.
--
-- A composite FK (tournament_id, stage_node_id) -> tournament_stages
-- (tournament_id, node_id) keeps stage matches referentially consistent. With
-- the default MATCH SIMPLE semantics a NULL stage_node_id skips the check, so
-- legacy matches (NULL) are never constrained. ON DELETE CASCADE: dropping a
-- stage removes its materialized matches.

ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS stage_node_id text;

-- Composite FK to the owning stage (only enforced when stage_node_id is set).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'tournament_matches_stage_node_fk'
      AND conrelid = 'public.tournament_matches'::regclass
  ) THEN
    ALTER TABLE public.tournament_matches
      ADD CONSTRAINT tournament_matches_stage_node_fk
      FOREIGN KEY (tournament_id, stage_node_id)
      REFERENCES public.tournament_stages(tournament_id, node_id)
      ON DELETE CASCADE;
  END IF;
END $$;

-- Runner query: "all matches of a given stage".
CREATE INDEX IF NOT EXISTS tournament_matches_stage_node_idx
  ON public.tournament_matches(tournament_id, stage_node_id);

COMMENT ON COLUMN public.tournament_matches.stage_node_id IS
  'Owning stage-graph node (StageNode.id) for stage-graph tournaments; NULL for '
  'legacy/non-stage-graph matches. ADR-0030 runner integration.';
