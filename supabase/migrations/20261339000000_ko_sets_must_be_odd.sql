-- A KO match is best-of-N, and N must be odd.
--
-- An even N can end level, which the KO bracket has no answer for — there is no
-- draw to award, a winner has to advance. The solo-match path has enforced this
-- since 20260507000007 (matches.format CHECK ^bo([13579]|[1-9][13579])$); the
-- tournament path never did. The KO wizard derives max_sets as 2*sets_to_win-1
-- and so happens to produce odd values, but that is a UI floor, not a rule: an
-- imported or hand-written setup could carry an even one and nothing objected.
--
-- The prelim is deliberately NOT covered. Draws are a legitimate group/Schoch
-- result there (K14) and ADR-0024 §2 pays them a point, so match_format keeps
-- taking even values.
--
-- Enforced as a table CHECK rather than inside tournament_create, so it holds
-- whichever RPC writes the row. NOT VALID: new and updated rows are checked
-- from now on, existing ones are left alone — the constraint can be validated
-- separately once the hosted data is known clean.

CREATE OR REPLACE FUNCTION public._tournament_ko_sets_all_odd(
  p_ko     jsonb,
  p_rounds jsonb
)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    -- The phase-wide KO format.
    (
      p_ko IS NULL
      OR jsonb_typeof(p_ko) <> 'object'
      OR jsonb_typeof(p_ko -> 'max_sets') <> 'number'
      OR ((p_ko ->> 'max_sets')::int) % 2 = 1
    )
    AND
    -- Every per-KO-round override.
    (
      p_rounds IS NULL
      OR jsonb_typeof(p_rounds) <> 'array'
      OR NOT EXISTS (
        SELECT 1
          FROM jsonb_array_elements(p_rounds) AS r(spec)
         WHERE jsonb_typeof(r.spec -> 'max_sets') = 'number'
           AND ((r.spec ->> 'max_sets')::int) % 2 = 0
      )
    );
$$;

COMMENT ON FUNCTION public._tournament_ko_sets_all_odd IS
  'True when every KO match format carries an odd max_sets. Prelim formats are '
  'out of scope: draws are allowed there (K14 / ADR-0024 §2).';

ALTER TABLE public.tournaments
  ADD CONSTRAINT tournaments_ko_max_sets_odd
  CHECK (public._tournament_ko_sets_all_odd(ko_match_format, ko_round_formats))
  NOT VALID;
