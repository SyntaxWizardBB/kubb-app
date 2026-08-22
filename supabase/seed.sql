-- Local development seed. Runs on `supabase db reset`; never applied to a
-- hosted project.
--
-- Gives you something to sign in to and something to run, because an empty
-- database is not testable: can_found_clubs defaults to false, so a freshly
-- created account cannot even open the "+ Neues Turnier" FAB.
--
-- What you get:
--   * veranstalter  — organizer + admin, password kubb1234
--   * spieler01..16 — sixteen players, same password
--   * one schoch_then_ko tournament, registration closed, sixteen confirmed
--     participants, waiting to be started
--
-- Sign in with the nickname and the password; the client resolves the nickname
-- to the synthetic GoTrue address itself (20261335000000).

do $seed$
declare
  v_password constant text := 'kubb1234';
  v_org      constant uuid := '00000000-0000-4000-8000-000000000001';
  v_tid      uuid;
  v_player   uuid;
  i          int;

begin
  -- ---- accounts ---------------------------------------------------------
  -- GoTrue authenticates against auth.users; the identities row is what makes
  -- the email provider resolvable. Both are seeded directly because there is
  -- no server-side signup RPC to call from here.
  for i in 0..16 loop
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

  -- ---- a tournament that is ready to start ------------------------------
  -- Everything below goes through the real RPCs so the seeded state satisfies
  -- the same invariants a hand-driven run would. The setup block is the one
  -- the schoch matrix generates for a single-out KO with EKC scoring;
  -- schoch_rounds is added so the runner plans four Monrad rounds for sixteen
  -- players rather than falling back to its conservative one.
  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_org::text, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  v_tid := (public.tournament_create(
      'Demo Schoch 16',
      1, 2, 16,
      'swiss_then_ko',
      jsonb_build_object(
        'max_sets', 2,
        'sets_to_win', 2,
        'basekubbs_per_side', 5,
        'round_time_seconds', 1800,
        'break_between_matches_seconds', 300),
      array['total_points', 'wins', 'kubb_difference'],
      jsonb_build_object(
        'ko_type', 'single_out',
        'scoring', 'ekc',
        'ko_config', jsonb_build_object(
          'seeding_mode', 'auto',
          'qualifier_count', 8,
          'with_third_place_playoff', true),
        'ko_matchup', 'seed_high_vs_low',
        'bracket_type', 'single_elimination',
        'vorrunde_type', 'schoch',
        'pool_phase_config', jsonb_build_object(
          'strategy', 'seeded',
          'group_count', 1,
          'schoch_rounds', 4,
          'qualifiers_per_group', 8),
        'ko_tiebreak_method', 'classic_kingtoss_removal')
    ) ->> 'tournament_id')::uuid;

  -- publish already lands on registration_open; there is no separate step.
  perform public.tournament_publish(v_tid);

  for i in 1..16 loop
    v_player := ('00000000-0000-4000-8000-0000000001' ||
                 lpad(i::text, 2, '0'))::uuid;
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub', v_player::text, 'role', 'authenticated')::text,
      true);
    perform public.tournament_register_single(v_tid);
  end loop;

  perform set_config('request.jwt.claims',
    jsonb_build_object('sub', v_org::text, 'role', 'authenticated')::text, true);
  perform public.tournament_close_registration(v_tid);

  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'postgres', true);

  raise notice 'seed: tournament % ready to start', v_tid;
end
$seed$;
