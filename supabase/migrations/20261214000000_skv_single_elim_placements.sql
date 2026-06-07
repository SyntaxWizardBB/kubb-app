-- SKV single-elimination final placements, additive.
--
-- Pure plpgsql function (no table read) that mirrors the Dart reference
--   packages/kubb_domain/lib/src/tournament/bracket_placement.dart
--     (singleElimFinalTiers)
-- and packages/kubb_domain/lib/src/tournament/final_ranking.dart
--     (computeFinalRanking, standard competition ranking)
-- bit-for-bit for SINGLE-ELIMINATION. Points come exclusively from
-- public.skv_points (migration 20261213000000).
--
-- Input p_ko_matches is a jsonb array of objects, each:
--   {"round": int, "phase": "winners"|"finals"|"third_place",
--    "a": text|null, "b": text|null, "winner": text|null, "bye": bool}
-- p_prelim_ranking is ALL participants best->worst (computeStandings order).
--
-- search_path = '' => every reference is schema-qualified (public.skv_points).
--
-- The function is IMMUTABLE, so it must not create temp tables: tier state is
-- held in plpgsql variables (a jsonb array of tiers, each tier a jsonb array of
-- member ids already sorted by prelim position). Final ranking + point lookup
-- is one set-based query over that accumulated structure.
--
-- Loser rule (single source of truth, applied via a single CASE expression):
-- a match yields a loser exactly when bye is false/absent AND a, b, winner are
-- all set AND winner is one of {a, b}; the loser is the non-winner. Otherwise
-- no loser.

create or replace function public.skv_single_elim_placements(
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
  v_finals         jsonb;          -- the single finals match object
  v_finals_winner  text;
  v_finals_loser   text;
  v_third          jsonb;          -- the third_place match object (or null)
  v_third_winner   text;
  v_third_loser    text;
  v_max_round      int;            -- highest winners round number
  v_dup            text;           -- duplicate detection helper
  v_missing        text;           -- missing-participant detection helper
  -- Accumulated tiers, best first: a jsonb array, each element a jsonb array of
  -- member ids already ordered by prelim position. Built incrementally.
  v_tiers          jsonb := '[]'::jsonb;
  v_tier           jsonb;          -- one tier (jsonb array of ids), scratch
  r                record;
begin
  -- ============================================================
  -- Validation (runs FULLY before any tier is built; 22023 on error).
  -- ============================================================

  -- 6.1: p_ko_matches must be a non-empty jsonb array.
  if p_ko_matches is null
     or jsonb_typeof(p_ko_matches) <> 'array'
     or jsonb_array_length(p_ko_matches) = 0 then
    raise exception 'p_ko_matches must be a non-empty jsonb array'
      using errcode = '22023';
  end if;

  v_n := coalesce(array_length(p_prelim_ranking, 1), 0);

  -- 6.6: p_prelim_ranking must not contain duplicates.
  select id into v_dup
  from unnest(p_prelim_ranking) as t(id)
  group by id
  having count(*) > 1
  limit 1;
  if v_dup is not null then
    raise exception 'p_prelim_ranking contains duplicate participantId (%)', v_dup
      using errcode = '22023';
  end if;

  -- Distinct real KO participants (non-null a/b across all matches). BYE/null
  -- slots do not count.
  select array_agg(distinct p) into v_ko_part
  from jsonb_array_elements(p_ko_matches) as m(obj)
  cross join lateral (values (m.obj->>'a'), (m.obj->>'b')) as v(p)
  where p is not null;
  v_ko_part := coalesce(v_ko_part, array[]::text[]);
  v_ko_rank_count := coalesce(array_length(v_ko_part, 1), 0);

  -- 6.5: every real KO participant must appear in p_prelim_ranking.
  select x into v_missing
  from unnest(v_ko_part) as x
  where not (x = any(p_prelim_ranking))
  limit 1;
  if v_missing is not null then
    raise exception 'KO participant is missing from p_prelim_ranking (%)', v_missing
      using errcode = '22023';
  end if;

  -- 6.2: a finals match must be present.
  select m.obj into v_finals
  from jsonb_array_elements(p_ko_matches) as m(obj)
  where m.obj->>'phase' = 'finals'
  limit 1;
  if v_finals is null then
    raise exception 'no finals match found (expected a completed single-elim)'
      using errcode = '22023';
  end if;

  -- 6.3: finals must yield a loser (complete).
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

  -- third_place: present? validate completeness (6.4).
  select m.obj into v_third
  from jsonb_array_elements(p_ko_matches) as m(obj)
  where m.obj->>'phase' = 'third_place'
  limit 1;
  if v_third is not null then
    v_third_winner := v_third->>'winner';
    v_third_loser  := case
      when coalesce((v_third->>'bye')::boolean, false) then null
      when v_third->>'a' is null or v_third->>'b' is null
        or v_third->>'winner' is null then null
      when v_third->>'winner' = v_third->>'a' then v_third->>'b'
      when v_third->>'winner' = v_third->>'b' then v_third->>'a'
      else null
    end;
    if v_third_winner is null or v_third_loser is null then
      raise exception 'third-place match is not completed'
        using errcode = '22023';
    end if;
  end if;

  -- ============================================================
  -- Tier building (best first). Each tier is appended to v_tiers as a jsonb
  -- array of ids, already ordered by prelim position. Empty tiers are skipped.
  -- ============================================================

  -- Highest winners round (semifinal handling).
  select max((m.obj->>'round')::int) into v_max_round
  from jsonb_array_elements(p_ko_matches) as m(obj)
  where m.obj->>'phase' = 'winners';

  -- Step 1: finals -> tier [winner] (rank 1), tier [loser] (rank 2).
  v_tiers := v_tiers
    || jsonb_build_array(jsonb_build_array(v_finals_winner))
    || jsonb_build_array(jsonb_build_array(v_finals_loser));

  if v_third is not null then
    -- Step 2a: third_place -> [winner] (rank 3), [loser] (rank 4).
    v_tiers := v_tiers
      || jsonb_build_array(jsonb_build_array(v_third_winner))
      || jsonb_build_array(jsonb_build_array(v_third_loser));
  elsif v_max_round is not null then
    -- Step 2b: no third_place -> the two losers of the highest winners round
    -- (semifinal) form ONE shared tier, ordered by prelim position.
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
      where m.obj->>'phase' = 'winners'
        and (m.obj->>'round')::int = v_max_round
    ) s
    where loser is not null;
    if v_tier is not null then
      v_tiers := v_tiers || jsonb_build_array(v_tier);
    end if;
  end if;

  -- Step 3: remaining winners rounds, descending by round (excluding the
  -- highest); losers of each round form one tier each. Only emit non-empty.
  if v_max_round is not null then
    for r in
      select distinct (m.obj->>'round')::int as round
      from jsonb_array_elements(p_ko_matches) as m(obj)
      where m.obj->>'phase' = 'winners'
        and (m.obj->>'round')::int < v_max_round
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
        where m.obj->>'phase' = 'winners'
          and (m.obj->>'round')::int = r.round
      ) s
      where loser is not null;
      if v_tier is not null then
        v_tiers := v_tiers || jsonb_build_array(v_tier);
      end if;
    end loop;
  end if;

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
  -- Competition ranking + points.
  -- Rank of tier i = 1 + sum of sizes of tiers 0..i-1. Members of one tier share
  -- the rank; the next tier jumps by the FULL predecessor size. Output order is
  -- tier order (best first), then prelim order within each tier (already baked
  -- into each tier's element order).
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

comment on function public.skv_single_elim_placements(jsonb, text[], text, boolean) is
  'SKV single-elimination final placements. Pure plpgsql; mirrors the Dart '
  'reference singleElimFinalTiers (bracket_placement.dart) + computeFinalRanking '
  '(final_ranking.dart). Points via public.skv_points. Standard competition '
  'ranking with deterministic prelim-ordered tie-breaking.';
