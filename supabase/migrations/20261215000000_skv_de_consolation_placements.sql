-- SKV double-elimination + consolation final placements, additive.
--
-- Pure plpgsql functions (no table read) that mirror the Dart reference
--   packages/kubb_domain/lib/src/tournament/bracket_placement.dart
--     (doubleElimFinalTiers, consolationFinalTiers)
-- and packages/kubb_domain/lib/src/tournament/final_ranking.dart
--     (computeFinalRanking, standard competition ranking)
-- bit-for-bit. Points come exclusively from public.skv_points (migration
-- 20261213000000) and are NOT re-implemented here. Form/style follow the
-- single-elim template public.skv_single_elim_placements (20261214000000):
-- same jsonb input shape, same RETURNS TABLE, same competition ranking, same
-- deterministic prelim-ordered tie-breaking.
--
-- Input p_ko_matches is a jsonb array of objects, each:
--   {"round": int, "phase": text, "a": text|null, "b": text|null,
--    "winner": text|null, "bye": bool}
--   Double-elim phases : "wb", "lb", "grand_final", "grand_final_reset".
--   Consolation phases : "winners", "finals", "third_place" (main) +
--                        "consolation", "consolation_third_place" (consolation).
-- p_prelim_ranking is ALL participants best->worst (computeStandings order).
--
-- search_path = '' => every reference is schema-qualified (public.skv_points).
--
-- The functions are IMMUTABLE, so they must not create temp tables: tier state
-- is held in plpgsql variables (a jsonb array of tiers, each tier a jsonb array
-- of member ids already sorted by prelim position). Final ranking + point
-- lookup is one set-based query over that accumulated structure.
--
-- Loser rule (single source of truth, applied via a single CASE expression):
-- a match yields a loser exactly when bye is false/absent AND a, b, winner are
-- all set AND winner is one of {a, b}; the loser is the non-winner. Otherwise
-- no loser.

-- =====================================================================
-- ZIEL 1: public.skv_double_elim_placements -- mirrors doubleElimFinalTiers.
-- =====================================================================
create or replace function public.skv_double_elim_placements(
  p_ko_matches     jsonb,
  p_prelim_ranking text[],
  p_league         text,
  p_is_masters     boolean
) returns table(participant_id text, rank int, points int)
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_n              int;            -- field size N = length of prelim ranking
  v_ko_rank_count  int;            -- distinct real KO participants
  v_ko_part        text[];         -- distinct real KO participants
  v_dup            text;           -- duplicate detection helper
  v_missing        text;           -- missing-participant detection helper
  v_grand_final    jsonb;          -- the grand_final match object (must exist)
  v_reset          jsonb;          -- the grand_final_reset match object (or null)
  v_decider        jsonb;          -- chosen decider: reset if present, else gf
  v_decider_winner text;
  v_decider_loser  text;
  -- Accumulated tiers, best first: a jsonb array, each element a jsonb array of
  -- member ids already ordered by prelim position. Built incrementally.
  v_tiers          jsonb := '[]'::jsonb;
  v_tier           jsonb;          -- one tier (jsonb array of ids), scratch
  r                record;
begin
  -- ============================================================
  -- Validation (runs FULLY before any tier is built; 22023 on error).
  -- ============================================================

  -- 19a: p_ko_matches must be a non-empty jsonb array.
  if p_ko_matches is null
     or jsonb_typeof(p_ko_matches) <> 'array'
     or jsonb_array_length(p_ko_matches) = 0 then
    raise exception 'p_ko_matches must be a non-empty jsonb array'
      using errcode = '22023';
  end if;

  v_n := coalesce(array_length(p_prelim_ranking, 1), 0);

  -- 19b: p_prelim_ranking must not contain duplicates.
  select id into v_dup
  from unnest(p_prelim_ranking) as t(id)
  group by id
  having count(*) > 1
  limit 1;
  if v_dup is not null then
    raise exception 'p_prelim_ranking contains duplicate participantId (%)', v_dup
      using errcode = '22023';
  end if;

  -- Distinct real KO participants (non-null a/b across ALL matches: wb+lb+
  -- grand_final+grand_final_reset). BYE/null slots do not count.
  select array_agg(distinct p) into v_ko_part
  from jsonb_array_elements(p_ko_matches) as m(obj)
  cross join lateral (values (m.obj->>'a'), (m.obj->>'b')) as v(p)
  where p is not null;
  v_ko_part := coalesce(v_ko_part, array[]::text[]);
  v_ko_rank_count := coalesce(array_length(v_ko_part, 1), 0);

  -- 19c: every real KO participant must appear in p_prelim_ranking.
  select x into v_missing
  from unnest(v_ko_part) as x
  where not (x = any(p_prelim_ranking))
  limit 1;
  if v_missing is not null then
    raise exception 'KO participant is missing from p_prelim_ranking (%)', v_missing
      using errcode = '22023';
  end if;

  -- 19d: a grand_final match must be present.
  select m.obj into v_grand_final
  from jsonb_array_elements(p_ko_matches) as m(obj)
  where m.obj->>'phase' = 'grand_final'
  limit 1;
  if v_grand_final is null then
    raise exception 'no grand_final match found (expected a completed double-elim)'
      using errcode = '22023';
  end if;

  -- Decider selection: reset if present, else grand final. A reset, if present,
  -- is the decider -- never a fallback to grand_final. When a complete reset
  -- exists the grand_final match is fully ignored for tier building.
  select m.obj into v_reset
  from jsonb_array_elements(p_ko_matches) as m(obj)
  where m.obj->>'phase' = 'grand_final_reset'
  limit 1;
  v_decider := coalesce(v_reset, v_grand_final);

  -- 19e: decider (reset if present, else grand_final) must be complete.
  v_decider_winner := v_decider->>'winner';
  v_decider_loser  := case
    when coalesce((v_decider->>'bye')::boolean, false) then null
    when v_decider->>'a' is null or v_decider->>'b' is null
      or v_decider->>'winner' is null then null
    when v_decider->>'winner' = v_decider->>'a' then v_decider->>'b'
    when v_decider->>'winner' = v_decider->>'b' then v_decider->>'a'
    else null
  end;
  if v_decider_winner is null or v_decider_loser is null then
    raise exception 'decider match (grand_final_reset if present, else grand_final) is not completed'
      using errcode = '22023';
  end if;

  -- ============================================================
  -- Tier building (best first). Each tier is appended to v_tiers as a jsonb
  -- array of ids, already ordered by prelim position. Empty tiers are skipped.
  -- ============================================================

  -- Step 1: decider -> tier [winner] (rank 1), tier [loser] (rank 2).
  -- When a complete reset exists we only emit the reset's winner/loser, so the
  -- grand_final loser (== reset winner) never gets a separate tier.
  v_tiers := v_tiers
    || jsonb_build_array(jsonb_build_array(v_decider_winner))
    || jsonb_build_array(jsonb_build_array(v_decider_loser));

  -- Step 2: lb-round losers, grouped by round DESCENDING (LB final = highest
  -- lb round -> rank-3 tier, next lower -> below, etc.). WB matches are NEVER
  -- inspected: a WB loss is not an elimination, so it produces no tier.
  -- grand_final / grand_final_reset are phase-local round==1; phase assignment
  -- is SOLELY via phase, so they never collide with lb round 1.
  for r in
    select distinct (m.obj->>'round')::int as round
    from jsonb_array_elements(p_ko_matches) as m(obj)
    where m.obj->>'phase' = 'lb'
    order by (m.obj->>'round')::int desc
  loop
    select jsonb_agg(loser order by array_position(p_prelim_ranking, loser))
      into v_tier
    from (
      select case
        when coalesce((m.obj->>'bye')::boolean, false) then null
        when m.obj->>'a' is null or m.obj->>'b' is null
          or m.obj->>'winner' is null then null
        when m.obj->>'winner' = m.obj->>'a' then m.obj->>'b'
        when m.obj->>'winner' = m.obj->>'b' then m.obj->>'a'
        else null
      end as loser
      from jsonb_array_elements(p_ko_matches) as m(obj)
      where m.obj->>'phase' = 'lb'
        and (m.obj->>'round')::int = r.round
    ) s
    where loser is not null;
    -- An lb round whose matches yield no real loser must NOT inject an empty
    -- tier -- computeFinalRanking rejects empty tiers.
    if v_tier is not null then
      v_tiers := v_tiers || jsonb_build_array(v_tier);
    end if;
  end loop;

  -- Step 3: preliminary tail. prelim entries that appear in NO match as a real
  -- a/b, each as its own singleton tier, in prelim order, AFTER all KO tiers.
  for r in
    select pr.id
    from unnest(p_prelim_ranking) with ordinality as pr(id, ix)
    where not (pr.id = any(v_ko_part))
    order by pr.ix
  loop
    v_tiers := v_tiers || jsonb_build_array(jsonb_build_array(r.id));
  end loop;

  -- ============================================================
  -- Competition ranking + points (identical to the single-elim template).
  -- Rank of tier i = 1 + sum of sizes of tiers 0..i-1. Members of one tier
  -- share the rank; the next tier jumps by the FULL predecessor size.
  -- ============================================================
  return query
  with tiers(ord, members) as (
    select (t.ord)::int - 1, t.members
    from jsonb_array_elements(v_tiers) with ordinality as t(members, ord)
  ),
  tier_ranks as (
    select t.ord,
           t.members,
           (1 + coalesce(
             sum(jsonb_array_length(t.members)) over (
               order by t.ord rows between unbounded preceding and 1 preceding),
             0))::int as tier_rank
    from tiers t
  )
  select e.member::text,
         tr.tier_rank,
         public.skv_points(v_n, p_league, p_is_masters, tr.tier_rank, v_ko_rank_count)
  from tier_ranks tr
  cross join lateral jsonb_array_elements_text(tr.members)
    with ordinality as e(member, mix)
  order by tr.ord asc, e.mix asc;
end;
$$;

comment on function public.skv_double_elim_placements(jsonb, text[], text, boolean) is
  'SKV double-elimination final placements. Pure plpgsql; mirrors the Dart '
  'reference doubleElimFinalTiers (bracket_placement.dart) + computeFinalRanking '
  '(final_ranking.dart). Points via public.skv_points. Standard competition '
  'ranking with deterministic prelim-ordered tie-breaking.';

-- =====================================================================
-- ZIEL 2: public.skv_consolation_placements -- mirrors consolationFinalTiers
-- (ADR-0028). Main bracket (winners/finals/third_place) decides ranks 1-4;
-- consolation bracket (consolation/consolation_third_place) re-ranks from 5.
-- =====================================================================
create or replace function public.skv_consolation_placements(
  p_ko_matches     jsonb,
  p_prelim_ranking text[],
  p_league         text,
  p_is_masters     boolean
) returns table(participant_id text, rank int, points int)
language plpgsql
immutable
security invoker
set search_path = ''
as $$
declare
  v_n              int;            -- field size N = length of prelim ranking
  v_ko_rank_count  int;            -- distinct real KO participants
  v_ko_part        text[];         -- distinct real KO participants
  v_dup            text;           -- duplicate detection helper
  v_missing        text;           -- missing-participant detection helper
  v_finals         jsonb;          -- main finals match object (must exist)
  v_finals_winner  text;
  v_finals_loser   text;
  v_third          jsonb;          -- main third_place match object (must exist)
  v_tp_winner      text;
  v_tp_loser       text;
  v_cons_max       int;            -- highest consolation round (= cons final)
  v_cons_second    int;            -- second-highest consolation round (or null)
  v_cons_final     jsonb;          -- consolation final match object
  v_cf_winner      text;
  v_cf_loser       text;
  v_cons_third     jsonb;          -- consolation_third_place match object (or null)
  v_ct_winner      text;
  v_ct_loser       text;
  v_has_cons_third boolean;
  -- Accumulated tiers, best first.
  v_tiers          jsonb := '[]'::jsonb;
  v_tier           jsonb;          -- one tier (jsonb array of ids), scratch
  r                record;
begin
  -- ============================================================
  -- Validation (runs FULLY before any tier is built; 22023 on error).
  -- ============================================================

  -- 25a: p_ko_matches must be a non-empty jsonb array.
  if p_ko_matches is null
     or jsonb_typeof(p_ko_matches) <> 'array'
     or jsonb_array_length(p_ko_matches) = 0 then
    raise exception 'p_ko_matches must be a non-empty jsonb array'
      using errcode = '22023';
  end if;

  v_n := coalesce(array_length(p_prelim_ranking, 1), 0);

  -- 25b: p_prelim_ranking must not contain duplicates.
  select id into v_dup
  from unnest(p_prelim_ranking) as t(id)
  group by id
  having count(*) > 1
  limit 1;
  if v_dup is not null then
    raise exception 'p_prelim_ranking contains duplicate participantId (%)', v_dup
      using errcode = '22023';
  end if;

  -- Distinct real KO participants (non-null a/b across ALL matches: main
  -- winners/finals/third_place AND consolation/consolation_third_place).
  select array_agg(distinct p) into v_ko_part
  from jsonb_array_elements(p_ko_matches) as m(obj)
  cross join lateral (values (m.obj->>'a'), (m.obj->>'b')) as v(p)
  where p is not null;
  v_ko_part := coalesce(v_ko_part, array[]::text[]);
  v_ko_rank_count := coalesce(array_length(v_ko_part, 1), 0);

  -- 25c: every real KO participant must appear in p_prelim_ranking.
  select x into v_missing
  from unnest(v_ko_part) as x
  where not (x = any(p_prelim_ranking))
  limit 1;
  if v_missing is not null then
    raise exception 'KO participant is missing from p_prelim_ranking (%)', v_missing
      using errcode = '22023';
  end if;

  -- 25d: a finals match must be present.
  select m.obj into v_finals
  from jsonb_array_elements(p_ko_matches) as m(obj)
  where m.obj->>'phase' = 'finals'
  limit 1;
  if v_finals is null then
    raise exception 'no finals match found (expected a completed consolation main bracket)'
      using errcode = '22023';
  end if;

  -- 25e: finals must be complete.
  v_finals_winner := v_finals->>'winner';
  v_finals_loser  := case
    when coalesce((v_finals->>'bye')::boolean, false) then null
    when v_finals->>'a' is null or v_finals->>'b' is null
      or v_finals->>'winner' is null then null
    when v_finals->>'winner' = v_finals->>'a' then v_finals->>'b'
    when v_finals->>'winner' = v_finals->>'b' then v_finals->>'a'
    else null
  end;
  if v_finals_winner is null or v_finals_loser is null then
    raise exception 'finals match is not completed'
      using errcode = '22023';
  end if;

  -- 25f: a third_place match must be present (consolation main always has one;
  -- no "shared rank 3" fallback as in single-elim).
  select m.obj into v_third
  from jsonb_array_elements(p_ko_matches) as m(obj)
  where m.obj->>'phase' = 'third_place'
  limit 1;
  if v_third is null then
    raise exception 'no third_place match found (consolation main bracket always has one)'
      using errcode = '22023';
  end if;

  -- 25g: third_place must be complete.
  v_tp_winner := v_third->>'winner';
  v_tp_loser  := case
    when coalesce((v_third->>'bye')::boolean, false) then null
    when v_third->>'a' is null or v_third->>'b' is null
      or v_third->>'winner' is null then null
    when v_third->>'winner' = v_third->>'a' then v_third->>'b'
    when v_third->>'winner' = v_third->>'b' then v_third->>'a'
    else null
  end;
  if v_tp_winner is null or v_tp_loser is null then
    raise exception 'third-place match is not completed'
      using errcode = '22023';
  end if;

  -- 25h: consolation rows must exist.
  select max((m.obj->>'round')::int) into v_cons_max
  from jsonb_array_elements(p_ko_matches) as m(obj)
  where m.obj->>'phase' = 'consolation';
  if v_cons_max is null then
    raise exception 'no consolation rows found (a consolation tournament needs a consolation bracket)'
      using errcode = '22023';
  end if;

  -- Second-highest consolation round (the consolation semifinal), or null.
  select max((m.obj->>'round')::int) into v_cons_second
  from jsonb_array_elements(p_ko_matches) as m(obj)
  where m.obj->>'phase' = 'consolation'
    and (m.obj->>'round')::int < v_cons_max;

  -- 25i: consolation final (highest consolation round) must be complete.
  -- The consolation final is a single match at the highest round.
  select m.obj into v_cons_final
  from jsonb_array_elements(p_ko_matches) as m(obj)
  where m.obj->>'phase' = 'consolation'
    and (m.obj->>'round')::int = v_cons_max
  limit 1;
  v_cf_winner := v_cons_final->>'winner';
  v_cf_loser  := case
    when coalesce((v_cons_final->>'bye')::boolean, false) then null
    when v_cons_final->>'a' is null or v_cons_final->>'b' is null
      or v_cons_final->>'winner' is null then null
    when v_cons_final->>'winner' = v_cons_final->>'a' then v_cons_final->>'b'
    when v_cons_final->>'winner' = v_cons_final->>'b' then v_cons_final->>'a'
    else null
  end;
  if v_cf_winner is null or v_cf_loser is null then
    raise exception 'consolation final (highest consolation round) is not completed'
      using errcode = '22023';
  end if;

  -- 25j: consolation_third_place, when present, must be complete.
  select m.obj into v_cons_third
  from jsonb_array_elements(p_ko_matches) as m(obj)
  where m.obj->>'phase' = 'consolation_third_place'
  limit 1;
  v_has_cons_third := v_cons_third is not null;
  if v_has_cons_third then
    v_ct_winner := v_cons_third->>'winner';
    v_ct_loser  := case
      when coalesce((v_cons_third->>'bye')::boolean, false) then null
      when v_cons_third->>'a' is null or v_cons_third->>'b' is null
        or v_cons_third->>'winner' is null then null
      when v_cons_third->>'winner' = v_cons_third->>'a' then v_cons_third->>'b'
      when v_cons_third->>'winner' = v_cons_third->>'b' then v_cons_third->>'a'
      else null
    end;
    if v_ct_winner is null or v_ct_loser is null then
      raise exception 'consolation third-place match is not completed'
        using errcode = '22023';
    end if;
  end if;

  -- ============================================================
  -- Tier building (best first). All validation has passed.
  -- ============================================================

  -- Step 1: main bracket -> ranks 1-4. finals winner/loser, third_place
  -- winner/loser. The main `winners` phase is intentionally NEVER inspected.
  -- Step 2: consolation final -> ranks 5/6.
  v_tiers := v_tiers
    || jsonb_build_array(jsonb_build_array(v_finals_winner))
    || jsonb_build_array(jsonb_build_array(v_finals_loser))
    || jsonb_build_array(jsonb_build_array(v_tp_winner))
    || jsonb_build_array(jsonb_build_array(v_tp_loser))
    || jsonb_build_array(jsonb_build_array(v_cf_winner))
    || jsonb_build_array(jsonb_build_array(v_cf_loser));

  -- Step 2b: ranks 7/8. With a consolation third-place playoff: its winner ->
  -- rank 7, loser -> rank 8 (two singletons). Without it: the consolation-
  -- semifinal losers (second-highest consolation round) share ONE tier
  -- (shared rank 7), ordered by prelim position.
  if v_has_cons_third then
    v_tiers := v_tiers
      || jsonb_build_array(jsonb_build_array(v_ct_winner))
      || jsonb_build_array(jsonb_build_array(v_ct_loser));
  elsif v_cons_second is not null then
    select jsonb_agg(loser order by array_position(p_prelim_ranking, loser))
      into v_tier
    from (
      select case
        when coalesce((m.obj->>'bye')::boolean, false) then null
        when m.obj->>'a' is null or m.obj->>'b' is null
          or m.obj->>'winner' is null then null
        when m.obj->>'winner' = m.obj->>'a' then m.obj->>'b'
        when m.obj->>'winner' = m.obj->>'b' then m.obj->>'a'
        else null
      end as loser
      from jsonb_array_elements(p_ko_matches) as m(obj)
      where m.obj->>'phase' = 'consolation'
        and (m.obj->>'round')::int = v_cons_second
    ) s
    where loser is not null;
    if v_tier is not null then
      v_tiers := v_tiers || jsonb_build_array(v_tier);
    end if;
  end if;

  -- Step 3: deeper consolation rounds, descending, below the consolation final.
  -- The highest round (final) is covered by step 2 and the second-highest is
  -- covered by step 2b -- both are excluded here. Each remaining round's losers
  -- form one tier (ranks 9+). Only emit non-empty tiers.
  for r in
    select distinct (m.obj->>'round')::int as round
    from jsonb_array_elements(p_ko_matches) as m(obj)
    where m.obj->>'phase' = 'consolation'
      and (m.obj->>'round')::int < v_cons_max
      and (m.obj->>'round')::int is distinct from v_cons_second
    order by (m.obj->>'round')::int desc
  loop
    select jsonb_agg(loser order by array_position(p_prelim_ranking, loser))
      into v_tier
    from (
      select case
        when coalesce((m.obj->>'bye')::boolean, false) then null
        when m.obj->>'a' is null or m.obj->>'b' is null
          or m.obj->>'winner' is null then null
        when m.obj->>'winner' = m.obj->>'a' then m.obj->>'b'
        when m.obj->>'winner' = m.obj->>'b' then m.obj->>'a'
        else null
      end as loser
      from jsonb_array_elements(p_ko_matches) as m(obj)
      where m.obj->>'phase' = 'consolation'
        and (m.obj->>'round')::int = r.round
    ) s
    where loser is not null;
    if v_tier is not null then
      v_tiers := v_tiers || jsonb_build_array(v_tier);
    end if;
  end loop;

  -- Step 4: preliminary tail. prelim entries that appear in NO match as a real
  -- a/b, each as its own singleton tier, in prelim order, AFTER all KO tiers.
  for r in
    select pr.id
    from unnest(p_prelim_ranking) with ordinality as pr(id, ix)
    where not (pr.id = any(v_ko_part))
    order by pr.ix
  loop
    v_tiers := v_tiers || jsonb_build_array(jsonb_build_array(r.id));
  end loop;

  -- ============================================================
  -- Competition ranking + points (identical to the single-elim template).
  -- ============================================================
  return query
  with tiers(ord, members) as (
    select (t.ord)::int - 1, t.members
    from jsonb_array_elements(v_tiers) with ordinality as t(members, ord)
  ),
  tier_ranks as (
    select t.ord,
           t.members,
           (1 + coalesce(
             sum(jsonb_array_length(t.members)) over (
               order by t.ord rows between unbounded preceding and 1 preceding),
             0))::int as tier_rank
    from tiers t
  )
  select e.member::text,
         tr.tier_rank,
         public.skv_points(v_n, p_league, p_is_masters, tr.tier_rank, v_ko_rank_count)
  from tier_ranks tr
  cross join lateral jsonb_array_elements_text(tr.members)
    with ordinality as e(member, mix)
  order by tr.ord asc, e.mix asc;
end;
$$;

comment on function public.skv_consolation_placements(jsonb, text[], text, boolean) is
  'SKV consolation (Trostturnier, Model B, ADR-0028) final placements. Pure '
  'plpgsql; mirrors the Dart reference consolationFinalTiers '
  '(bracket_placement.dart) + computeFinalRanking (final_ranking.dart). Points '
  'via public.skv_points. Standard competition ranking with deterministic '
  'prelim-ordered tie-breaking.';
