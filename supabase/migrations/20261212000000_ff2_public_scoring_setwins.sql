-- FF2 — CF2-Angleichung: public scoring envelope + real set wins.
--
-- WHY ----------------------------------------------------------------
-- Two CF2 follow-up findings, both privacy-safe and additive:
--
-- FINDING A (public scoring). The anon spectator standings path
-- (public_tournament_screen.dart, _StandingsTab) computes standings
-- client-side over the projected matches, but public_tournament_get
-- never projected tournaments.scoring. The spectator path therefore
-- hard-coded TournamentScoring.ekc, so a CLASSIC tournament rendered
-- EKC-style totals on the public screen while authenticated users and
-- the server (tournament_pool_standings, CF2) showed correct classic
-- points. FIX: project tournaments.scoring ('ekc' / 'classic') into the
-- tournament object of the public envelope. Privacy-neutral — only the
-- enum, no PII.
--
-- FINDING B (client/server classic divergence). Both Dart standings
-- callers synthesise a SINGLE SetScore from final_score_a/_b. In classic
-- mode computeStandings then counts setsWon = 1/0 per match (= MATCH
-- wins), whereas the server sums real SET wins from
-- tournament_set_score_proposals. For best-of-3 the two diverge. FIX:
-- project the real per-side set wins (sets_won_a / sets_won_b) onto the
-- match rows the client uses for standings — using EXACTLY the same
-- source/logic as tournament_pool_standings (CF2, 20261207000000):
-- DISTINCT ON (match_id, set_number) on the consensus row, FILTER on
-- set_winner = 'A' / 'B'. The Dart synthesis then reconstructs the
-- correct number of SetScore entries so classic standings match the
-- server. EKC fields (final_score_a/_b) are untouched.
--
-- WHAT ---------------------------------------------------------------
--   1. public_tournament_get   — re-stated BYTE-FOR-BYTE from
--      20261208000000 §4 (the truly current definition; no later
--      migration restates it). ADDS: tournament.scoring (coalesce 'ekc'),
--      and matches[].sets_won_a / sets_won_b (LEFT JOIN on a match-set
--      aggregation CTE). Roster branch, privacy projection and every
--      existing field are unchanged.
--   2. tournament_list_matches — re-stated BYTE-FOR-BYTE from
--      20261208000000 §3 (current definition). ADDS: sets_won_a /
--      sets_won_b per match row from the same aggregation. All existing
--      fields (incl. CF3 display names, final_score_a/_b) unchanged.
--
-- The set-win aggregation is the SAME logic tournament_pool_standings
-- uses: DISTINCT ON (match_id, set_number) on the consensus row
-- (sp.consensus_round = m.consensus_round) for finalized/overridden
-- matches, then count(*) FILTER (set_winner = 'A' / 'B'). Unlike the
-- standings RPC it is NOT restricted to phase = 'group' — the match list
-- carries every phase, and a KO match's set wins are equally valid; the
-- standings RPC only aggregates group matches, but per-match set-win
-- counts are phase-agnostic and the client filters by status anyway.
--
-- DB-SAFE: additive CREATE OR REPLACE only. No table change, no data
-- migration, no in-place edit of an existing migration file, no db reset.
-- Both function signatures are unchanged (uuid -> jsonb / SETOF jsonb).


-- ====================================================================
-- 1. public_tournament_get — re-stated from 20261208000000 §4.
--    ADDS tournament.scoring + matches[].sets_won_a/_b. Roster branch
--    and participant_count unchanged.
-- ====================================================================

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
           -- FF2 / Finding A: project the scoring mode so the anon
           -- spectator standings use the real mode (classic vs ekc)
           -- instead of the hard-coded EKC fallback. Defensive coalesce
           -- (the column is NOT NULL CHECK ('ekc','classic'), but stay
           -- safe). Privacy-neutral — only the enum, no PII.
           'scoring',             coalesce(t.scoring, 'ekc'),
           'status',              t.status,
           'match_format_config', t.match_format,
           'started_at',          t.started_at,
           'completed_at',        t.completed_at
         )
    INTO v_tournament
    FROM public.tournaments t
   WHERE t.id = p_tournament_id;

  -- FF2 / Finding B: per-match set wins, aggregated EXACTLY like
  -- tournament_pool_standings (CF2). DISTINCT ON (match_id, set_number)
  -- on the consensus row, then count(*) FILTER on set_winner. LEFT JOIN
  -- so matches without proposals project sets_won_a/_b = 0.
  WITH agreed_sets AS (
    SELECT DISTINCT ON (sp.match_id, sp.set_number)
           sp.match_id,
           sp.set_number,
           sp.set_winner
      FROM public.tournament_set_score_proposals sp
      JOIN public.tournament_matches m
        ON m.id = sp.match_id
       AND sp.consensus_round = m.consensus_round
     WHERE m.tournament_id = p_tournament_id
       AND m.status        IN ('finalized','overridden')
     ORDER BY sp.match_id, sp.set_number, sp.submitter_user_id
  ),
  match_set_wins AS (
    SELECT s.match_id,
           coalesce(count(*) FILTER (WHERE s.set_winner = 'A'), 0) AS sets_a,
           coalesce(count(*) FILTER (WHERE s.set_winner = 'B'), 0) AS sets_b
      FROM agreed_sets s
     GROUP BY s.match_id
  )
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
           -- FF2 / Finding B: real per-side set wins (null-safe -> 0).
           'sets_won_a',            coalesce(sw.sets_a, 0),
           'sets_won_b',            coalesce(sw.sets_b, 0),
           'phase',                 m.phase,
           'bracket_position',      m.bracket_position
         ) ORDER BY m.round_number, m.match_number_in_round), '[]'::jsonb)
    INTO v_matches
    FROM public.tournament_matches m
    LEFT JOIN match_set_wins sw ON sw.match_id = m.id
   WHERE m.tournament_id = p_tournament_id;

  -- Roster = team-roster slots (display_name only, via the privacy view)
  -- UNION single participants (no slots) projected with slot_index 0 and
  -- the player's nickname. Both branches expose only participant_id,
  -- slot_index and display_name — no user_id / email / team metadata.
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'slot_id',        r.slot_id,
           'participant_id', r.participant_id,
           'slot_index',     r.slot_index,
           'display_name',   r.display_name
         ) ORDER BY r.participant_id, r.slot_index), '[]'::jsonb)
    INTO v_roster
    FROM (
      -- Team participants: existing privacy-projecting roster view.
      SELECT v.slot_id::text       AS slot_id,
             v.participant_id::text AS participant_id,
             v.slot_index          AS slot_index,
             v.display_name        AS display_name
        FROM public.public_tournament_roster_view v
        JOIN public.tournament_participants p ON p.id = v.participant_id
       WHERE p.tournament_id = p_tournament_id
      UNION ALL
      -- Single participants (team_id IS NULL): one synthetic entry with the
      -- player's nickname. These have no roster slots, so without this the
      -- spectator screen rendered 'Unbekannt' (CF3 / K08). slot_id is NULL
      -- (singles have no roster slot — the client treats slot_id as an
      -- opaque, optional identifier). Filtered to registration_status =
      -- 'confirmed' so the single roster matches participant_count and the
      -- 'angemeldete Teilnehmer' semantics (a withdrawn single must not show
      -- up in the spectator roster).
      SELECT NULL::text            AS slot_id,
             p.id::text            AS participant_id,
             0                     AS slot_index,
             COALESCE(up.nickname::text, 'Unbekannt') AS display_name
        FROM public.tournament_participants p
        LEFT JOIN public.user_profiles up ON up.user_id = p.user_id
       WHERE p.tournament_id = p_tournament_id
         AND p.team_id IS NULL
         AND p.registration_status = 'confirmed'
    ) r;

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
  'Anon-friendly read of a public tournament: header (incl. scoring mode '
  'per FF2), matches (incl. real per-side set wins sets_won_a/_b per FF2), '
  'roster (display_name only — team slots via public_tournament_roster_view, '
  'singles synthesised from user_profiles.nickname per CF3). Returns NULL '
  'for non-public or draft tournaments. No user_id / created_by / email / '
  'team metadata / set_score_proposals leakage.';


-- ====================================================================
-- 2. tournament_list_matches — re-stated from 20261208000000 §3.
--    ADDS sets_won_a / sets_won_b per row (same aggregation). Display
--    names and every existing field unchanged.
-- ====================================================================

CREATE OR REPLACE FUNCTION public.tournament_list_matches(
  p_tournament_id uuid
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller     uuid;
  v_status     text;
  v_created_by uuid;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  SELECT status, created_by INTO v_status, v_created_by
    FROM public.tournaments WHERE id = p_tournament_id;
  IF v_status IS NULL THEN
    RETURN;
  END IF;
  IF v_status = 'draft' AND v_created_by IS DISTINCT FROM v_caller THEN
    RETURN;
  END IF;

  RETURN QUERY
    WITH agreed_sets AS (
      -- FF2 / Finding B: same consensus-row pick as tournament_pool_standings.
      SELECT DISTINCT ON (sp.match_id, sp.set_number)
             sp.match_id,
             sp.set_number,
             sp.set_winner
        FROM public.tournament_set_score_proposals sp
        JOIN public.tournament_matches m
          ON m.id = sp.match_id
         AND sp.consensus_round = m.consensus_round
       WHERE m.tournament_id = p_tournament_id
         AND m.status        IN ('finalized','overridden')
       ORDER BY sp.match_id, sp.set_number, sp.submitter_user_id
    ),
    match_set_wins AS (
      SELECT s.match_id,
             coalesce(count(*) FILTER (WHERE s.set_winner = 'A'), 0) AS sets_a,
             coalesce(count(*) FILTER (WHERE s.set_winner = 'B'), 0) AS sets_b
        FROM agreed_sets s
       GROUP BY s.match_id
    )
    SELECT jsonb_build_object(
             'match_id',              m.id,
             'tournament_id',         m.tournament_id,
             'round_number',          m.round_number,
             'match_number_in_round', m.match_number_in_round,
             'participant_a_id',      m.participant_a,
             'participant_b_id',      m.participant_b,
             -- CF3: team_id-driven (single nickname vs team name).
             'participant_a_display_name',
               CASE WHEN pa.team_id IS NULL THEN upa.nickname
                    ELSE tma.display_name END,
             'participant_b_display_name',
               CASE WHEN pb.team_id IS NULL THEN upb.nickname
                    ELSE tmb.display_name END,
             'status',                m.status,
             'consensus_round',       m.consensus_round,
             'started_at',            m.started_at,
             'completed_at',          m.finalized_at,
             'winner_participant_id', m.winner_participant,
             'final_score_a',         m.final_score_a,
             'final_score_b',         m.final_score_b,
             -- FF2 / Finding B: real per-side set wins (null-safe -> 0).
             'sets_won_a',            coalesce(sw.sets_a, 0),
             'sets_won_b',            coalesce(sw.sets_b, 0)
           )
      FROM public.tournament_matches m
      LEFT JOIN public.tournament_participants pa ON pa.id = m.participant_a
      LEFT JOIN public.user_profiles            upa ON upa.user_id = pa.user_id
      LEFT JOIN public.teams                    tma ON tma.id      = pa.team_id
      LEFT JOIN public.tournament_participants pb ON pb.id = m.participant_b
      LEFT JOIN public.user_profiles            upb ON upb.user_id = pb.user_id
      LEFT JOIN public.teams                    tmb ON tmb.id      = pb.team_id
      LEFT JOIN match_set_wins sw ON sw.match_id = m.id
     WHERE m.tournament_id = p_tournament_id
     ORDER BY m.round_number ASC, m.match_number_in_round ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.tournament_list_matches(uuid) TO authenticated;
