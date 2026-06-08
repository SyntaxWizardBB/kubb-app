-- Tournament stage-graph routing — ADR-0030 (§Runner-Semantik steps 2+3).
--
-- Adds one additive child table `tournament_stage_inputs` (the accumulated,
-- routed participants per TARGET stage) plus the SECURITY-DEFINER routing
-- function `tournament_route_completed_stage`, which is the DB implementation
-- of ADR-0030 §Runner-Semantik step 2 ("apply the edge selectors to the local
-- ordering") + step 3 ("materialize/seed into the target stages").
--
-- Parity reference: the pure Dart routing core `routeStageOutputs`
-- (packages/kubb_domain/lib/src/tournament/stage_graph/stage_routing.dart) and
-- the selector wire strings in edge_selector.dart. Selector predicates, the
-- two-phase non_qualifiers semantics, and the ranking-order tie-break here are a
-- 1:1 mirror of that core. Source ordering comes from
-- public.tournament_stage_ranking (it is NOT re-implemented here).

-- ---- 1. tournament_stage_inputs (routed participants per target) -----

CREATE TABLE IF NOT EXISTS public.tournament_stage_inputs (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id  uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  target_node_id text NOT NULL,  -- StageEdge.to_node_id: the stage this row seeds
  participant_id uuid NOT NULL REFERENCES public.tournament_participants(id) ON DELETE CASCADE,
  ordinal        int  NOT NULL,  -- 1-based seed order within the routed set per target (by source rank)
  source_node_id text NOT NULL,  -- the stage that routed this participant (StageEdge.from_node_id)
  created_at     timestamptz NOT NULL DEFAULT now(),
  -- Idempotency anchor: a participant is routed into a given target at most
  -- once (the ON CONFLICT target of the routing function).
  CONSTRAINT tournament_stage_inputs_unique UNIQUE (tournament_id, target_node_id, participant_id),
  -- Composite FK to the target stage, mirroring tournament_matches_stage_node_fk.
  -- tournament_stages exposes the unique key tournament_stages_unique_node
  -- (tournament_id, node_id), so this MATCH SIMPLE composite FK resolves.
  CONSTRAINT tournament_stage_inputs_target_fk
    FOREIGN KEY (tournament_id, target_node_id)
    REFERENCES public.tournament_stages (tournament_id, node_id)
    MATCH SIMPLE ON DELETE CASCADE
);

-- Serves the per-target read and the ordinal computation.
CREATE INDEX IF NOT EXISTS tournament_stage_inputs_target_idx
  ON public.tournament_stage_inputs (tournament_id, target_node_id);

-- ---- 2. RLS ----------------------------------------------------------

ALTER TABLE public.tournament_stage_inputs ENABLE ROW LEVEL SECURITY;

-- Exact structural copy of tournament_stages_read: visible to anyone who may
-- read the parent tournament (non-draft = public/spectator, draft = creator).
DROP POLICY IF EXISTS tournament_stage_inputs_read ON public.tournament_stage_inputs;
CREATE POLICY tournament_stage_inputs_read
  ON public.tournament_stage_inputs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.tournaments t
      WHERE t.id = tournament_stage_inputs.tournament_id
        AND (t.status <> 'draft' OR t.created_by = auth.uid())
    )
  );

-- No INSERT/UPDATE/DELETE policy: writes happen ONLY via the SECURITY-DEFINER
-- routing function below (same no-client-write pattern as tournament_stages /
-- tournament_matches).

-- ---- 3. Routing function ---------------------------------------------

CREATE OR REPLACE FUNCTION public.tournament_route_completed_stage(
  p_tournament_id uuid,
  p_node_id       text
) RETURNS int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_qualified  uuid[] := array[]::uuid[];  -- union of ids selected by all non-NQ edges (phase 1)
  v_inserted   int    := 0;                -- count of newly inserted rows (return value)
  v_rows       int;
  v_edge       record;
begin
  -- ============================================================
  -- Source ordering: read the completed stage's local ranking once into a temp
  -- table. tournament_stage_ranking yields (participant_id, rank,
  -- ko_elimination_round). Unknown/missing/shootout_quali source stage or an
  -- empty stage -> 0 rows here, so every selection below is empty and the
  -- function returns 0 cleanly (no exception).
  --
  -- Dropped explicitly first so REPEATED calls within the SAME transaction
  -- (e.g. an idempotency re-run) do not collide; `on commit drop` alone would
  -- only release the table at transaction end, not between two calls.
  -- ============================================================
  drop table if exists _routing_ranking;
  create temporary table _routing_ranking on commit drop as
    select r.participant_id, r.rank, r.ko_elimination_round
    from public.tournament_stage_ranking(p_tournament_id, p_node_id) r;

  -- ============================================================
  -- Phase 1: resolve every NON-non_qualifiers edge and accumulate the union of
  -- all concretely-selected participant_ids (the "qualifiers"). Overlapping
  -- non-NQ selectors collapse into one set (union of actual ids). Parity:
  -- routeStageOutputs phase 1 (stage_routing.dart L120-135).
  -- ============================================================
  for v_edge in
    select e.to_node_id, e.selector
    from public.tournament_stage_edges e
    where e.tournament_id = p_tournament_id
      and e.from_node_id = p_node_id
      and (e.selector->>'kind') <> 'non_qualifiers'
  loop
    v_qualified := v_qualified || (
      select coalesce(array_agg(rr.participant_id), array[]::uuid[])
      from _routing_ranking rr
      where case v_edge.selector->>'kind'
              -- top_k: ranks are >= 1, so rank <= k matches rank in 1..k
              -- (identical to the Dart _selectFor TopK branch).
              when 'top_k' then rr.rank <= (v_edge.selector->>'k')::int
              -- ranks: inclusive band from..to.
              when 'ranks' then rr.rank >= (v_edge.selector->>'from')::int
                            and rr.rank <= (v_edge.selector->>'to')::int
              -- losers_of_rounds: ko_elimination_round in rounds; a NULL round
              -- (champion / non-KO) is NEVER matched (Dart L184-190).
              when 'losers_of_rounds' then rr.ko_elimination_round is not null
                and rr.ko_elimination_round in (
                  -- jsonb_array_elements_text unwraps each scalar round to its
                  -- text form; self-explanatory and array-shape-correct.
                  select v.val::int
                  from jsonb_array_elements_text(v_edge.selector->'rounds') as v(val)
                )
              -- winners: rank == 1 (may select several).
              when 'winners' then rr.rank = 1
              else false
            end
    );
  end loop;

  -- ============================================================
  -- Phase 2: apply selectors per edge and insert. non_qualifiers edges are
  -- evaluated AFTER the explicit selectors (Dart phase 2, L137-152): each NQ
  -- edge yields the SAME leftover = {all ranking ids} \ {qualifiers union}, in
  -- ranking order. Multiple NQ edges are allowed and all get the identical set.
  --
  -- Ordinal: a 1-based running position PER TARGET stage, aggregated across all
  -- edges pointing to the same to_node_id, deterministic via a row_number() over
  -- the union of that target's selected participants in (rank, participant_id)
  -- order. Ranking order = rank ASC, tie-break participant_id ASC (Dart L112-118
  -- tie-breaks lexicographically; here participant_id is uuid, so we order on
  -- participant_id::text to match the Dart string order bit-for-bit).
  --
  -- ON CONFLICT (tournament_id, target_node_id, participant_id) DO NOTHING makes
  -- a re-run insert nothing; v_inserted counts only the newly inserted rows.
  -- ============================================================
  with selected as (
    -- One row per (target, participant) actually selected by an edge.
    select e.to_node_id as target_node_id,
           rr.participant_id,
           rr.rank,
           rr.ko_elimination_round
    from public.tournament_stage_edges e
    join _routing_ranking rr on true
    where e.tournament_id = p_tournament_id
      and e.from_node_id = p_node_id
      and case e.selector->>'kind'
            when 'top_k' then rr.rank <= (e.selector->>'k')::int
            when 'ranks' then rr.rank >= (e.selector->>'from')::int
                          and rr.rank <= (e.selector->>'to')::int
            when 'losers_of_rounds' then rr.ko_elimination_round is not null
              and rr.ko_elimination_round in (
                select v.val::int
                from jsonb_array_elements_text(e.selector->'rounds') as v(val)
              )
            when 'winners' then rr.rank = 1
            -- non_qualifiers: leftover = ranking minus the phase-1 qualifiers.
            when 'non_qualifiers' then not (rr.participant_id = any(v_qualified))
            else false
          end
  ),
  -- Collapse duplicate (target, participant) pairs that multiple edges to the
  -- same target may produce, then assign the per-target ordinal.
  deduped as (
    select target_node_id,
           participant_id,
           min(rank) as rank
    from selected
    group by target_node_id, participant_id
  ),
  ordered as (
    select target_node_id,
           participant_id,
           row_number() over (
             partition by target_node_id
             order by rank asc, participant_id::text asc
           )::int as ordinal
    from deduped
  ),
  ins as (
    insert into public.tournament_stage_inputs
      (tournament_id, target_node_id, participant_id, ordinal, source_node_id)
    select p_tournament_id, o.target_node_id, o.participant_id, o.ordinal, p_node_id
    from ordered o
    on conflict (tournament_id, target_node_id, participant_id) do nothing
    returning 1
  )
  select count(*) into v_rows from ins;

  v_inserted := coalesce(v_rows, 0);
  return v_inserted;
end;
$$;

comment on function public.tournament_route_completed_stage(uuid, text) is
  'Routes a COMPLETED stage''s participants into its target stages (ADR-0030 '
  '§Runner-Semantik steps 2+3). DB parity to the pure Dart routeStageOutputs: '
  'source ordering = public.tournament_stage_ranking (rank asc, tie-break '
  'participant_id); selector predicates top_k(rank<=k)/ranks(from..to)/'
  'losers_of_rounds(ko_elimination_round in rounds, NULL never matched)/'
  'winners(rank=1) mirror _selectFor; non_qualifiers is evaluated AFTER the '
  'explicit selectors as the leftover = ranking minus the UNION of ids selected '
  'by all non-NQ edges (two-phase, multiple NQ edges yield the same leftover). '
  'ordinal = 1-based running position per TARGET stage in (rank, participant_id) '
  'order, aggregated across all edges to that target. Inserts into '
  'tournament_stage_inputs with ON CONFLICT (tournament_id, target_node_id, '
  'participant_id) DO NOTHING and returns the count of NEWLY inserted rows, so a '
  're-run on the same state returns 0 (idempotent). SECURITY DEFINER because it '
  'writes tournament_stage_inputs, which has no client-write RLS policy '
  '(server-authoritative materialization). Empty ranking / no outgoing edges / '
  'no matching ranks -> 0 (no exception).';
