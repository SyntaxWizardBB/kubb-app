-- P1 (Tournament-Hub V1) — live set score for the public single-match RPC.
--
-- CONTEXT: public_tournament_match_get already returns running matches
-- (scheduled / awaiting_results / disputed) of a public+live tournament —
-- the pre-check only gates the PARENT tournament (public = true AND status
-- IN published/registration_open/registration_closed/live/finalized), NOT
-- the match status. So readability of running matches is NOT the gap.
--
-- THE GAP: the single-match RPC (defined ONCE in
-- 20260901000001_public_tournament_rpcs.sql, never re-stated since — see
-- `grep -rn 'FUNCTION public.public_tournament_match_get'`) projects
-- final_score_a/b (only populated at finalize) but NO per-side set wins.
-- The tournament-level public_tournament_get (FF2, 20261212000000) added
-- sets_won_a/_b, but its `agreed_sets` CTE is filtered to
-- status IN ('finalized','overridden') — so even there a RUNNING match
-- reports sets_won = 0. Result: the public match screen has zero live
-- score data for an in-flight match and can only ever show '–:–'.
--
-- THIS MIGRATION (additive only): CREATE OR REPLACE
-- public_tournament_match_get, re-stated VERBATIM from the CURRENT
-- definition in 20260901000001 (verified byte-for-byte against
-- pg_get_functiondef on the live DB — no stale body), EXCEPT it ADDS two
-- projected fields `sets_won_a` / `sets_won_b`, aggregated EXACTLY like
-- FF2 / tournament_pool_standings (DISTINCT ON (match_id, set_number) on
-- the consensus row, then count(*) FILTER on set_winner) but WITHOUT the
-- finalized/overridden status filter — so the agreed sets of a RUNNING
-- match (current consensus_round) are visible live. No DROP / DELETE /
-- TRUNCATE / schema removal. The REVOKE/GRANT/COMMENT are re-stated
-- unchanged.
--
-- PRIVACY (ADR-0023 spectator-RLS): the added projection exposes only the
-- aggregated set counts (integers). No created_by / submitter_user_id /
-- user_id / email / nickname. The aggregation reads
-- tournament_set_score_proposals.set_winner only, never the submitter.
--
-- Sources: ADR-0026 Strategie A, ADR-0023, FF2 (20261212000000).

CREATE OR REPLACE FUNCTION public.public_tournament_match_get(p_match_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_match jsonb;
BEGIN
  -- Pre-Check via Join: das Eltern-Turnier muss public und in einem
  -- sichtbaren Status sein. Sonst NULL — keine Existenz-Bestaetigung.
  IF NOT EXISTS (
    SELECT 1
      FROM public.tournament_matches m
      JOIN public.tournaments t ON t.id = m.tournament_id
     WHERE m.id = p_match_id
       AND t.public = true
       AND t.status IN (
         'published',
         'registration_open',
         'registration_closed',
         'live',
         'finalized'
       )
  ) THEN
    RETURN NULL;
  END IF;

  -- P1 / live set wins: agreed sets of the match at its CURRENT
  -- consensus_round, aggregated like FF2 but WITHOUT the
  -- finalized/overridden gate so a running match shows its live set tally.
  WITH agreed_sets AS (
    SELECT DISTINCT ON (sp.set_number)
           sp.set_number,
           sp.set_winner
      FROM public.tournament_set_score_proposals sp
      JOIN public.tournament_matches m
        ON m.id = sp.match_id
       AND sp.consensus_round = m.consensus_round
     WHERE sp.match_id = p_match_id
     ORDER BY sp.set_number, sp.submitter_user_id
  ),
  match_set_wins AS (
    SELECT coalesce(count(*) FILTER (WHERE s.set_winner = 'A'), 0) AS sets_a,
           coalesce(count(*) FILTER (WHERE s.set_winner = 'B'), 0) AS sets_b
      FROM agreed_sets s
  )
  SELECT jsonb_build_object(
           'match_id',              m.id,
           'tournament_id',         m.tournament_id,
           'round_number',          m.round_number,
           'match_number_in_round', m.match_number_in_round,
           'participant_a_id',      m.participant_a,
           'participant_b_id',      m.participant_b,
           'status',                m.status,
           'consensus_round',       m.consensus_round,
           'started_at',            m.started_at,
           'completed_at',          m.finalized_at,
           'winner_participant_id', m.winner_participant,
           'final_score_a',         m.final_score_a,
           'final_score_b',         m.final_score_b,
           -- P1: real per-side set wins (null-safe -> 0), live for
           -- running matches.
           'sets_won_a',            coalesce(sw.sets_a, 0),
           'sets_won_b',            coalesce(sw.sets_b, 0),
           'phase',                 m.phase,
           'bracket_position',      m.bracket_position
         )
    INTO v_match
    FROM public.tournament_matches m
    CROSS JOIN match_set_wins sw
   WHERE m.id = p_match_id;

  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.public_tournament_match_get(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.public_tournament_match_get(uuid)
  TO anon, authenticated;

COMMENT ON FUNCTION public.public_tournament_match_get(uuid) IS
  'Anon-friendly read of a single public tournament match: header, '
  'score, live per-side set wins (sets_won_a/_b), status. Returns NULL '
  'for matches of non-public or draft tournaments. No set_score_proposals '
  '/ submitter_user_id leakage. Driven by ADR-0026 Strategie A.';
