-- Local development seed. Runs on `supabase db reset`; never applied to a
-- hosted project.
--
-- Gives you something to sign in to and something to run, because an empty
-- database is not testable: can_found_clubs defaults to false, so a freshly
-- created account cannot even open the "+ Neues Turnier" FAB.
--
-- Accounts — nickname plus password kubb1234 for all of them:
--   * veranstalter  — organizer + admin
--   * spieler01..33 — players
--
-- Sign in with the nickname; the client resolves it to the synthetic GoTrue
-- address itself (20261335000000).
--
-- Tournaments, all left at registration_closed so you press Start yourself:
--
--   1. Demo Schoch 16        sixteen players, one pool, four Monrad rounds,
--                            pitches 1..8, EKC scoring, king-toss tiebreak.
--                            The clean even case.
--
--   2. Demo Schoch 33        thirty-three players on a shared venue: pitches
--                            16..32. Odd count, so every round leaves one
--                            player with a BYE. Five rounds, 20-minute clock so
--                            the timer is quick to watch, Buchholz as second
--                            tiebreak, no third-place playoff.
--
--   3. Demo Gruppenphase 24  four groups of six by snake seeding, then a KO
--                            with a consolation bracket. Manual pitch choice —
--                            a hand-picked, non-contiguous set in a hand-set
--                            order, each group pinned to its own pair — instead
--                            of the range/top-seed default. One-vs-two matchup,
--                            shoot-out tiebreak, classic scoring, 40-minute
--                            rounds.

do $seed$
declare
  v_password constant text := 'kubb1234';
  v_org      constant uuid := '00000000-0000-4000-8000-000000000001';
  v_players  constant int  := 33;

  v_tids   uuid[] := '{}';
  v_sizes  int[]  := '{16, 33, 24}';
  v_player uuid;
  v_tid    uuid;
  i        int;
  k        int;
begin
  -- ---- accounts ---------------------------------------------------------
  -- GoTrue authenticates against auth.users; the identities row is what makes
  -- the email provider resolvable. Both are seeded directly because there is
  -- no server-side signup RPC to call from here.
  for i in 0..v_players loop
    v_player := case when i = 0 then v_org
                     else ('00000000-0000-4000-8000-0000000001' ||
                           lpad(i::text, 2, '0'))::uuid end;

    insert into auth.users(
        id, instance_id, aud, role, email, encrypted_password,
        email_confirmed_at, created_at, updated_at,
        raw_app_meta_data, raw_user_meta_data,
        -- GoTrue scans these into non-nullable Go strings; NULL makes every
        -- sign-in fail with "Database error querying schema".
        confirmation_token, recovery_token, email_change, email_change_token_new)
      values (
        v_player, '00000000-0000-0000-0000-000000000000',
        'authenticated', 'authenticated',
        v_player::text || '@login.kubbclub.ch',
        extensions.crypt(v_password, extensions.gen_salt('bf')),
        now(), now(), now(),
        jsonb_build_object('provider', 'email', 'providers',
                           jsonb_build_array('email')),
        '{}'::jsonb,
        '', '', '', '')
      on conflict (id) do nothing;

    insert into auth.identities(
        id, provider_id, user_id, identity_data, provider,
        created_at, updated_at, last_sign_in_at)
      values (
        gen_random_uuid(), v_player::text, v_player,
        jsonb_build_object('sub', v_player::text, 'email',
                           v_player::text || '@login.kubbclub.ch'),
        'email', now(), now(), now())
      on conflict do nothing;

    insert into public.user_profiles(
        user_id, nickname, onboarding_completed, can_found_clubs, is_admin)
      values (
        v_player,
        case when i = 0 then 'veranstalter'
             else 'spieler' || lpad(i::text, 2, '0') end,
        true, i = 0, i = 0)
      on conflict (user_id) do nothing;

    insert into public.user_credentials(id, user_id, kind, created_at)
      values (gen_random_uuid(), v_player, 'password', now())
      on conflict do nothing;
  end loop;

  -- ---- the three tournaments --------------------------------------------
  -- Everything goes through the real RPCs so the seeded state satisfies the
  -- same invariants a hand-driven run would. The setup blocks follow what the
  -- test matrices generate for these format combinations; the pitch plans, the
  -- round counts and the clock are hand-set per tournament.
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_org::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  v_tids := array_append(v_tids, (public.tournament_create(
      'Demo Schoch 16', 1, 2, 16, 'swiss_then_ko',
      jsonb_build_object(
        'max_sets', 2, 'sets_to_win', 2, 'basekubbs_per_side', 5,
        'round_time_seconds', 1800, 'break_between_matches_seconds', 300),
      array['total_points', 'wins', 'kubb_difference'],
      jsonb_build_object(
        'ko_type', 'single_out',
        'scoring', 'ekc',
        'ko_config', jsonb_build_object(
          'seeding_mode', 'auto', 'qualifier_count', 8,
          'with_third_place_playoff', true),
        'ko_matchup', 'seed_high_vs_low',
        'bracket_type', 'single_elimination',
        'vorrunde_type', 'schoch',
        'pool_phase_config', jsonb_build_object(
          'strategy', 'seeded', 'group_count', 1,
          'schoch_rounds', 4, 'qualifiers_per_group', 8),
        'ko_tiebreak_method', 'classic_kingtoss_removal',
        'pitch_plan', jsonb_build_object(
          'mode', 'range', 'range_from', 1, 'range_to', 8,
          'sort_strategy', 'top_seeds_low_numbers'))
    ) ->> 'tournament_id')::uuid);

  -- Seventeen pitches carry sixteen simultaneous matches; the odd player out
  -- sits the round.
  v_tids := array_append(v_tids, (public.tournament_create(
      'Demo Schoch 33 · Plätze 16-32', 1, 2, 33, 'swiss_then_ko',
      jsonb_build_object(
        'max_sets', 2, 'sets_to_win', 2, 'basekubbs_per_side', 5,
        'round_time_seconds', 1200, 'break_between_matches_seconds', 180),
      array['total_points', 'wins', 'buchholz'],
      jsonb_build_object(
        'ko_type', 'single_out',
        'scoring', 'ekc',
        'ko_config', jsonb_build_object(
          'seeding_mode', 'auto', 'qualifier_count', 16,
          'with_third_place_playoff', false),
        'ko_matchup', 'seed_high_vs_low',
        'bracket_type', 'single_elimination',
        'vorrunde_type', 'schoch',
        'pool_phase_config', jsonb_build_object(
          'strategy', 'seeded', 'group_count', 1,
          'schoch_rounds', 5, 'qualifiers_per_group', 16),
        'ko_tiebreak_method', 'classic_kingtoss_removal',
        'pitch_plan', jsonb_build_object(
          'mode', 'range', 'range_from', 16, 'range_to', 32,
          'sort_strategy', 'top_seeds_low_numbers'))
    ) ->> 'tournament_id')::uuid);

  v_tids := array_append(v_tids, (public.tournament_create(
      'Demo Gruppenphase 24', 1, 2, 24, 'round_robin_then_ko',
      jsonb_build_object(
        'max_sets', 2, 'sets_to_win', 2, 'basekubbs_per_side', 6,
        'round_time_seconds', 2400, 'break_between_matches_seconds', 600),
      array['wins', 'total_points', 'kubb_difference'],
      jsonb_build_object(
        'ko_type', 'consolation',
        'scoring', 'classic',
        'ko_config', jsonb_build_object(
          'seeding_mode', 'auto', 'qualifier_count', 16,
          'with_third_place_playoff', true),
        'ko_matchup', 'one_vs_two',
        'bracket_type', 'single_elimination',
        'vorrunde_type', 'group_phase',
        'consolation_name', 'Sieger der gebrochenen Herzen',
        'pool_phase_config', jsonb_build_object(
          'strategy', 'snake', 'group_count', 4, 'qualifiers_per_group', 4),
        'ko_tiebreak_method', 'mighty_finisher_shootout',
        'consolation_bracket', jsonb_build_object(
          'name', 'Sieger der gebrochenen Herzen', 'source', 'early_ko_losers',
          'enabled', true, 'direct_count', 0, 'main_bracket_size', 16),
        'consolation_direct_count', 0,
        'consolation_main_bracket_size', 16,
        'pitch_plan', jsonb_build_object(
          'mode', 'manual',
          'numbers', jsonb_build_array(3, 4, 7, 8, 11, 12, 15, 16),
          'order', jsonb_build_array(15, 16, 3, 4, 11, 12, 7, 8),
          'sort_strategy', 'manual',
          'group_assignment', jsonb_build_object(
            'A', jsonb_build_array(15, 16),
            'B', jsonb_build_array(3, 4),
            'C', jsonb_build_array(11, 12),
            'D', jsonb_build_array(7, 8))))
    ) ->> 'tournament_id')::uuid);

  -- ---- fill them up -----------------------------------------------------
  for k in 1..array_length(v_tids, 1) loop
    v_tid := v_tids[k];
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', v_org::text, 'role', 'authenticated')::text,
      true);
    -- publish already lands on registration_open; there is no separate step.
    perform public.tournament_publish(v_tid);

    for i in 1..v_sizes[k] loop
      v_player := ('00000000-0000-4000-8000-0000000001' ||
                   lpad(i::text, 2, '0'))::uuid;
      perform set_config('request.jwt.claims',
        jsonb_build_object('sub', v_player::text,
                           'role', 'authenticated')::text, true);
      perform public.tournament_register_single(v_tid);
    end loop;

    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', v_org::text, 'role', 'authenticated')::text,
      true);
    perform public.tournament_close_registration(v_tid);
  end loop;

  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);
end
$seed$;
