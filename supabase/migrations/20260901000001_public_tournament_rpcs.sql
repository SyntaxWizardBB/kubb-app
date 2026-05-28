-- W3-T3 (Sprint-A): Public spectator RPCs fuer den Anon-Pfad.
--
-- Implementiert ADR-0026 Strategie A: dedizierte, JWT-freie
-- `public_*_get`-RPCs mit `SECURITY DEFINER` und `GRANT EXECUTE TO anon,
-- authenticated`. Pre-Check auf `tournaments.public = true AND status IN
-- ('published','registration_open','registration_closed','live',
-- 'finalized')` ersetzt den RLS-Filter aus den `*_anon_public_read`-
-- Policies (die als Defense-in-Depth bleiben — siehe T2-Migration).
--
-- Projektion bewusst reduziert gegenueber `tournament_get`:
--   * Enthalten:    tournament_id, display_name, format, status,
--                   started_at, completed_at, team_size,
--                   match_format_config, matches[] (ohne Proposals,
--                   ohne submitter_user_id), roster[] aus
--                   public_tournament_roster_view (display_name only),
--                   participant_count.
--   * Nicht enthalten: created_by, participants[*].user_id,
--                      participants[*].nickname (kommt nur via Roster-
--                      View), audit_tail, tiebreaker_order (intern),
--                      bye_points / forfeit_points (intern),
--                      set_score_proposals.
--
-- Realtime fuer den anon-Pfad ist Folge-Task (T6 / Wave 4); diese
-- Migration deckt nur den Read-Pfad ab.
--
-- Sources: ADR-0026, docs/plans/sprint-a-bug-fix/anon-rls-plan.md T1.


-- ---- 1. public_tournament_get ----------------------------------------

CREATE OR REPLACE FUNCTION public.public_tournament_get(p_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_tournament       jsonb;
  v_matches          jsonb;
  v_roster           jsonb;
  v_participant_cnt  int;
BEGIN
  -- Pre-Check: nur public-Turniere in einem nicht-draft, nicht-aborted
  -- Lifecycle sind sichtbar. Kein `auth.uid()`-Guard — diese RPC ist
  -- bewusst fuer den `anon`-Pfad ausgelegt.
  IF NOT EXISTS (
    SELECT 1
      FROM public.tournaments
     WHERE id = p_tournament_id
       AND public = true
       AND status IN (
         'published',
         'registration_open',
         'registration_closed',
         'live',
         'finalized'
       )
  ) THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
           'tournament_id',       t.id,
           'display_name',        t.display_name,
           'team_size',           t.team_size,
           'format',              t.format,
           'status',              t.status,
           'match_format_config', t.match_format,
           'started_at',          t.started_at,
           'completed_at',        t.completed_at
         )
    INTO v_tournament
    FROM public.tournaments t
   WHERE t.id = p_tournament_id;

  -- Matches: vollstaendige Pairing-Info plus finaler Score und Status,
  -- aber ohne Proposals oder Submitter-IDs. participant_a/b bleiben als
  -- IDs erhalten — Namens-Aufloesung passiert clientseitig ueber das
  -- roster[]-Array (siehe unten), das nur display_name enthaelt.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
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
           'phase',                 m.phase,
           'bracket_position',      m.bracket_position
         ) ORDER BY m.round_number, m.match_number_in_round), '[]'::jsonb)
    INTO v_matches
    FROM public.tournament_matches m
   WHERE m.tournament_id = p_tournament_id;

  -- Roster: ausschliesslich display_name + participant_id + slot_index.
  -- Quelle ist die `public_tournament_roster_view`, die genau diese
  -- Privacy-Projektion bereits zentral durchsetzt (kein user_id,
  -- keine E-Mail, keine team-Metadaten).
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'slot_id',        v.slot_id,
           'participant_id', v.participant_id,
           'slot_index',     v.slot_index,
           'display_name',   v.display_name
         ) ORDER BY v.participant_id, v.slot_index), '[]'::jsonb)
    INTO v_roster
    FROM public.public_tournament_roster_view v
    JOIN public.tournament_participants p ON p.id = v.participant_id
   WHERE p.tournament_id = p_tournament_id;

  SELECT count(*)::int
    INTO v_participant_cnt
    FROM public.tournament_participants p
   WHERE p.tournament_id = p_tournament_id
     AND p.registration_status = 'confirmed';

  RETURN jsonb_build_object(
    'tournament',        v_tournament,
    'matches',           v_matches,
    'roster',            v_roster,
    'participant_count', v_participant_cnt
  );
END;
$$;

REVOKE ALL ON FUNCTION public.public_tournament_get(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.public_tournament_get(uuid)
  TO anon, authenticated;

COMMENT ON FUNCTION public.public_tournament_get(uuid) IS
  'Anon-friendly read of a public tournament: header, matches, roster '
  '(display_name only). Returns NULL for non-public or draft tournaments. '
  'No user_id / created_by / email / set_score_proposals leakage. '
  'Driven by ADR-0026 Strategie A; primary spectator-read path.';


-- ---- 2. public_tournament_match_get ----------------------------------

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
           'phase',                 m.phase,
           'bracket_position',      m.bracket_position
         )
    INTO v_match
    FROM public.tournament_matches m
   WHERE m.id = p_match_id;

  RETURN v_match;
END;
$$;

REVOKE ALL ON FUNCTION public.public_tournament_match_get(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.public_tournament_match_get(uuid)
  TO anon, authenticated;

COMMENT ON FUNCTION public.public_tournament_match_get(uuid) IS
  'Anon-friendly read of a single public tournament match: header, '
  'score, status. Returns NULL for matches of non-public or draft '
  'tournaments. No set_score_proposals / submitter_user_id leakage. '
  'Driven by ADR-0026 Strategie A.';
