-- A bye must not occupy a pitch.
--
-- With an odd field every schoch round produces one bye row: participant_b
-- NULL, status finalized, winner already set. It is never played, yet it was
-- taking a slot in the pitch distribution — on "Demo Schoch 33" the bye sat on
-- pitch 32 while sixteen real matches shared the remaining sixteen. On a venue
-- with exactly as many pitches as matches that pushes two real matches onto one
-- pitch.
--
-- Verbatim re-base of the body from 20261201000003_tournament_assign_pitches.sql
-- with byes cleared up front and excluded from the ranking. The UI already
-- renders a pitch only when one is set, so a bye now simply shows none.

CREATE OR REPLACE FUNCTION public._tournament_assign_pitches(
  p_tournament_id uuid,
  p_round         smallint
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_plan        jsonb;
  v_all         int[];
  v_has_groups  boolean;
  v_strategy    text;
BEGIN
  -- A bye is finalised the moment it is created and never played, so it must
  -- not hold a pitch. Clear whatever the insert defaulted to; this runs before
  -- the plan checks below because it holds with or without a pitch plan.
  UPDATE public.tournament_matches
     SET pitch_number = NULL
   WHERE tournament_id = p_tournament_id
     AND round_number  = p_round
     AND (participant_a IS NULL OR participant_b IS NULL);

  SELECT pitch_plan INTO v_plan
    FROM public.tournaments
    WHERE id = p_tournament_id;

  -- No plan -> leave the inserted default (pitch_number = 1) untouched.
  IF v_plan IS NULL OR jsonb_typeof(v_plan) <> 'object' THEN
    RETURN;
  END IF;

  v_all := public._tournament_pitch_available(v_plan);
  IF array_length(v_all, 1) IS NULL THEN
    RETURN;   -- empty plan -> no assignment (Dart: result smaller/empty)
  END IF;

  v_has_groups := (jsonb_typeof(v_plan -> 'group_assignment') = 'object')
              AND ((SELECT count(*) FROM jsonb_object_keys(v_plan -> 'group_assignment')) > 0);
  v_strategy   := coalesce(v_plan ->> 'sort_strategy', 'top_seeds_low_numbers');

  -- Per-partition (pool key, phase) assignment. The pool key is the
  -- group_label only when the plan has a group_assignment AND the match
  -- carries a group_label; otherwise the synthetic plan-wide pool (Dart's
  -- `null` poolKey). For each partition we build the ordered pitch list,
  -- order the matches, then assign pitch[(i-1) % len] round-robin.
  WITH src AS (
    SELECT
      m.id,
      m.phase,
      -- pool key: NULL = plan-wide pool.
      CASE WHEN v_has_groups AND m.group_label IS NOT NULL
           THEN m.group_label END                                  AS pool_key,
      -- Dart RoundMatch.order: bracket_position when present, else
      -- match_number_in_round.
      coalesce(m.bracket_position, m.match_number_in_round)         AS ord,
      -- stable tiebreaker for equal `ord` (mirror Dart "ties keep input
      -- order"): input order here is the row's natural numbering.
      m.match_number_in_round                                       AS in_order
    FROM public.tournament_matches m
    WHERE m.tournament_id = p_tournament_id
      AND m.round_number  = p_round
      AND m.participant_a IS NOT NULL
      AND m.participant_b IS NOT NULL
  ),
  -- Ordered pitch list per pool: plan-wide list for pool_key IS NULL;
  -- for a group pool, the group's assigned pitches intersected with the
  -- plan-wide list (Dart _pitchesForPool), preserving the group list's
  -- own order. A group with no/invalid assigned pitches -> empty -> no
  -- assignment for that partition.
  pool_pitch AS (
    SELECT DISTINCT s.pool_key
      FROM src s
  ),
  pitches AS (
    SELECT
      pp.pool_key,
      CASE
        WHEN pp.pool_key IS NULL THEN v_all
        ELSE (
          -- group's list, in the group's own order, kept only if also in
          -- the plan-wide available set.
          SELECT coalesce(
                   array_agg((g.val #>> '{}')::int ORDER BY g.ord)
                     FILTER (WHERE (g.val #>> '{}')::int = ANY (v_all)),
                   ARRAY[]::int[])
            FROM jsonb_array_elements(
                   v_plan -> 'group_assignment' -> pp.pool_key)
                 WITH ORDINALITY AS g(val, ord)
        )
      END AS list
      FROM pool_pitch pp
  ),
  -- Rank matches within each (pool_key, phase) partition. top_seeds_low_
  -- numbers -> order by ord asc (ties by in_order). manual -> caller list
  -- order == the row's natural (match_number_in_round / bracket_position)
  -- order, which is in_order asc.
  ranked AS (
    SELECT
      s.id,
      s.pool_key,
      s.phase,
      row_number() OVER (
        PARTITION BY s.pool_key, s.phase
        ORDER BY
          CASE WHEN v_strategy = 'top_seeds_low_numbers'
               THEN s.ord ELSE s.in_order END,
          s.in_order
      ) AS rn
    FROM src s
  )
  UPDATE public.tournament_matches t
     SET pitch_number = p.list[ ((r.rn - 1) % array_length(p.list, 1)) + 1 ]
    FROM ranked r
    JOIN pitches p ON p.pool_key IS NOT DISTINCT FROM r.pool_key
   WHERE t.id = r.id
     AND array_length(p.list, 1) IS NOT NULL;  -- empty pool -> skip (Dart: no entry)
END;
$$;
