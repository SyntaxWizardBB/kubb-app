-- SKV tour-points function (System 1), additive.
--
-- Bit-for-bit integer parity with the Dart engine
-- packages/kubb_domain/lib/src/tournament/skv_tour_points.dart
-- (skvWinnerPoints / skvPointsForPlacement) and docs/SKV_TOUR_POINTS.md.
--
-- Rounding parity is critical: PostgreSQL round(double precision) uses
-- half-to-even (banker's rounding), whereas Dart num.round() rounds
-- half-away-from-zero. We therefore round on numeric throughout, which
-- matches Dart (e.g. round(2.5) = 3, round(141.25) = 141).

create or replace function public.skv_points(
  p_field_size    int,
  p_league        text,
  p_is_masters    boolean,
  p_placement     int,
  p_ko_rank_count int,
  p_p_min         int default 3
) returns int
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_league text := lower(p_league);
  v_b      int;          -- reference field size B per league
  v_mult   int;          -- masters multiplier per league
  v_w      int;          -- winner points W
  v_t      int;          -- KO tier index
  v_p_last int;          -- KO-tier value at the last KO rank
  v_m      int;          -- number of non-KO (tail) ranks
begin
  -- Validation, in the same order as the Dart engine: field size, then
  -- placement range, then ko_rank_count range. No silent clamping.
  if p_field_size < 1 then
    raise exception 'fieldSize must be >= 1 (got %)', p_field_size
      using errcode = '22023';
  end if;
  if p_placement < 1 or p_placement > p_field_size then
    raise exception 'placement must be in 1..% (got %)', p_field_size, p_placement
      using errcode = '22023';
  end if;
  if p_ko_rank_count < 4 or p_ko_rank_count > p_field_size then
    raise exception 'koRankCount must be in 4..% (got %)', p_field_size, p_ko_rank_count
      using errcode = '22023';
  end if;

  -- Reference size B (spec §2): a/b -> 10, c -> 20, einzel -> 40.
  v_b := case v_league
           when 'a' then 10
           when 'b' then 10
           when 'c' then 20
           when 'einzel' then 40
           else 10
         end;

  -- Winner points W (spec §2, §5).
  if p_is_masters then
    -- Masters multiplier (spec §5): a/c -> 2, b -> 1, einzel -> 1.
    v_mult := case v_league
                when 'a' then 2
                when 'c' then 2
                when 'b' then 1
                when 'einzel' then 1
                else 1
              end;
    v_w := 100 * v_mult;
  else
    -- W must be bit-for-bit identical to Dart, which evaluates
    --   (100 * (1.0 + (N - B) / (2 * B))).round()
    -- in IEEE-754 double precision. The half (e.g. einzel N=42) is itself a
    -- product of lossy double arithmetic: Dart gets 102.4999999999999857...,
    -- not an exact 102.5, so round() yields 102, not 103. Evaluating this in
    -- exact numeric would instead produce 102.5 -> 103 and break parity.
    -- We therefore reproduce Dart's double computation and emulate Dart
    -- round() (half-away-from-zero; W is always positive here) via
    -- floor(x + 0.5) directly on the double, avoiding any numeric cast that
    -- would re-normalize the double to its shortest round-trip string.
    v_w := floor(
             100::double precision
             * (1 + (p_field_size - v_b)::double precision / (2 * v_b))
             + 0.5
           )::int;
  end if;

  -- Ranks 1-4: fixed factors [1.0, 0.8, 0.65, 0.5] (spec §3.1).
  if p_placement <= 4 then
    return round(
             (v_w * (array[1.0, 0.8, 0.65, 0.5])[p_placement])::numeric
           )::int;
  end if;

  -- Ranks 5..koRankCount: halving KO tiers (spec §3.2).
  -- t = greatest(1, floor(log2(placement - 1)) - 1); P = round(W * 0.5^(t+1)).
  if p_placement <= p_ko_rank_count then
    v_t := greatest(1, floor(ln((p_placement - 1)::numeric) / ln(2::numeric))::int - 1);
    return round((v_w * power(0.5::numeric, v_t + 1))::numeric)::int;
  end if;

  -- Ranks > koRankCount: linear preliminary-round tail down to p_min (spec §3.3).
  -- p_last is the KO-tier value at the last KO rank, via the same tier formula.
  v_t := greatest(1, floor(ln((p_ko_rank_count - 1)::numeric) / ln(2::numeric))::int - 1);
  v_p_last := round((v_w * power(0.5::numeric, v_t + 1))::numeric)::int;
  v_m := p_field_size - p_ko_rank_count;
  return round(
           (v_p_last - (v_p_last - p_p_min) * (p_placement - p_ko_rank_count)::numeric / v_m)::numeric
         )::int;
end;
$$;

comment on function public.skv_points(int, text, boolean, int, int, int) is
  'SKV tour-points (System 1). Bit-for-bit integer parity with the Dart engine '
  'packages/kubb_domain/lib/src/tournament/skv_tour_points.dart '
  '(skvWinnerPoints / skvPointsForPlacement). Uses numeric half-away-from-zero '
  'rounding to match Dart num.round().';
