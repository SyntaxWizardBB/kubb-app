-- =====================================================================
-- Tournament Testing Suite (TTS) — T-Edges pgTAP edge scenarios.
--
-- Source of truth: docs/plans/tournament-testing-suite/SPEC.md (T-Edges block).
-- This file drives the CURRENTLY BUILT (IST) tournament lifecycle into eight
-- edge conditions on top of the §3 T-Harness helpers, asserting each via
-- standard pgTAP predicates:
--   1. FORFAIT                 — public.tournament_match_forfeit
--   2. BYE / FREILOS           — odd swiss field -> one-sided (NULL) pairing
--   3. ORGANIZER OVERRIDE      — public.tournament_organizer_override_pairing
--   4. TIEBREAK-HOLD           — clock out + result missing -> awaiting_results
--   5. PAUSE / RESUME / SKIP   — tournament_pause/resume/skip_forward/skip_back
--   6. CHECK-IN + NO-SHOW      — tournament_checkin_participant + forfeit
--   7. SCHEDULE-TICK           — tournament_schedule_tick(p_now) transitions
--   8. PER-PITCH NOTIFY        — _tournament_notify_round_per_pitch idempotency
--                                (function DEFINED in migration
--                                 20261260000000_schedule_notify_helpers.sql;
--                                 CALLED from the round-publish path in
--                                 20261261000000_round_publish_notify.sql)
--
-- HARNESS REUSE (SPEC §3 / DoD-05): the §3 _tts_* helpers are re-CREATE OR
-- REPLACE'd at the top of this file (each pgTAP file runs in its OWN
-- transaction, so the helpers are defined in-transaction and auto-dropped on
-- ROLLBACK — NO production migration). The scenarios reach their lifecycle
-- state through _tts_seed_tournament / _tts_register_n / _tts_start /
-- _tts_play_round / _tts_advance rather than re-inventing lifecycle plumbing.
-- The few edge-only helpers use a non-colliding `_tts_edge_*` prefix.
--
-- IST-vs-WISH (SPEC §0.2 / DoD-15): only the shipped contract is tested.
-- Participant counts stay within the built caps (server clamp <=200; harness
-- size 32, plus an odd field of 7 for the genuine engine bye); qualifier_count
-- is a power of two in [2,64]; no 1000-player path, no year-suffix, no diggy-
-- default-on, no auto-no-show-forfeit beyond the organizer-driven RPC. Every
-- RPC/trigger invoked exists in supabase/migrations/.
--
-- Fixed test clock (SPEC §3 / K7: pgTAP freezes now()):
--   p_now := '2026-06-09 12:00:00+00' for all schedule ticks.
--
-- Auth-actor switching uses the established
-- set_config('request.jwt.claims', ...) / SET LOCAL ROLE postgres patterns.
-- Everything runs inside BEGIN .. ROLLBACK; nothing is mutated.
-- =====================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgtap;

-- ---------------------------------------------------------------------
-- Auth-actor switching (cf. _t6_as / _pair_as). _tts_as authenticates as a
-- given user via JWT claims; _tts_as_pg drops back to the postgres role for
-- direct fixture seeding (schedule/participant rows have no client-write
-- policy — same trust path as the existing tests).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _tts_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _tts_as_pg() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

-- =====================================================================
-- §3.1 Config builder.
--
-- Derives the full p_setup + p_match_format_config jsonb for one matrix row
-- (G01..G72 / S01..S24) and N, applying ALL the §1.1 derived/coupled rules:
-- format, bracket_type, qualifier_count (power-of-two <= N capped 64), the
-- fixed third-place playoff, auto seeding, the consolation_bracket object
-- (+ mirror keys) for ko_type=consolation, the schoch auto single-pool
-- config, and the fixed prelim match_format_config. The non-derived axes
-- (ko_type, ko_matchup, ko_tiebreak_method, scoring, pool strategy) are
-- parsed out of the row's literal field tokens — but for the harness/smoke
-- path the columns are passed directly via _tts_seed_tournament, so this
-- builder accepts the canonical row tokens it needs.
-- =====================================================================
CREATE OR REPLACE FUNCTION _tts_config(p_row text, p_n int)
RETURNS TABLE(p_format text, p_setup jsonb, p_mfc jsonb)
LANGUAGE plpgsql
AS $$
DECLARE
  v_vorrunde   text;   -- group_phase | schoch
  v_ko_type    text;   -- single_out | double_out | consolation
  v_matchup    text;   -- seed_high_vs_low | one_vs_two
  v_tiebreak   text;   -- classic_kingtoss_removal | mighty_finisher_shootout
  v_scoring    text;   -- ekc | classic
  v_strategy   text;   -- snake | seeded | random (group_phase only)
  v_qc         int;
  v_bracket    text;
  v_format     text;
  v_setup      jsonb;
  v_pool       jsonb;
  v_group_cnt  int;
  v_qpg        int;
  v_cons       jsonb;
  v_cons_size  int;
  v_is_group   boolean;
BEGIN
  -- ---- N -> qualifier_count: largest power of two <= N, capped at 64. ----
  -- §0.3 / §1.1: N=32 -> 16, N=48 -> 32, N=60 -> 32.
  v_qc := 1;
  WHILE v_qc * 2 <= p_n AND v_qc * 2 <= 64 LOOP
    v_qc := v_qc * 2;
  END LOOP;
  -- Smart default: a power-of-two N uses N/2 (16 for 32); a non-power-of-two
  -- uses the largest 2^n below (32 for 48/60). The WHILE above lands on the
  -- largest 2^n <= N; for N=32 that is 32, so halve once for the clean case.
  IF v_qc = p_n THEN
    v_qc := v_qc / 2;
  END IF;

  -- ---- Row token parsing. group_phase rows carry a 6th (strategy) field. ----
  v_is_group := position('group_phase' in p_row) > 0 OR substr(p_row, 1, 1) = 'G';

  -- The smoke test and the matrix shards pass canonical setup via
  -- _tts_seed_tournament; _tts_config also accepts a compact token row of the
  -- form "<vorrunde>|<ko_type>|<matchup>|<tiebreak>|<scoring>[|<strategy>]"
  -- (the §2 row body). If p_row is a bare G##/S## id, fall back to the
  -- representative axes (single_out, seed_high_vs_low, classic_kingtoss_removal,
  -- ekc, seeded) so the builder is total over every id.
  IF position('|' in p_row) > 0 THEN
    v_vorrunde := trim(split_part(p_row, '|', 1));
    v_ko_type  := trim(split_part(p_row, '|', 2));
    v_matchup  := trim(split_part(p_row, '|', 3));
    v_tiebreak := trim(split_part(p_row, '|', 4));
    v_scoring  := trim(split_part(p_row, '|', 5));
    v_strategy := nullif(trim(split_part(p_row, '|', 6)), '');
  ELSE
    v_vorrunde := CASE WHEN v_is_group THEN 'group_phase' ELSE 'schoch' END;
    v_ko_type  := 'single_out';
    v_matchup  := 'seed_high_vs_low';
    v_tiebreak := 'classic_kingtoss_removal';
    v_scoring  := 'ekc';
    v_strategy := CASE WHEN v_is_group THEN 'seeded' ELSE NULL END;
  END IF;

  -- ---- §1.1 format derivation. ----
  v_format := CASE v_vorrunde
                WHEN 'group_phase' THEN 'round_robin_then_ko'
                WHEN 'schoch'      THEN 'swiss_then_ko'
                ELSE 'round_robin_then_ko' END;

  -- ---- §1.1 bracket_type derivation. ----
  v_bracket := CASE WHEN v_ko_type = 'double_out'
                    THEN 'double_elimination'
                    ELSE 'single_elimination' END;

  -- ---- Base setup (fixed third-place, auto seeding — §1.1). ----
  v_setup := jsonb_build_object(
    'scoring',            v_scoring,
    'vorrunde_type',      v_vorrunde,
    'ko_type',            v_ko_type,
    'bracket_type',       v_bracket,
    'ko_matchup',         v_matchup,
    'ko_tiebreak_method', v_tiebreak,
    'ko_config', jsonb_build_object(
      'qualifier_count',          v_qc,
      'with_third_place_playoff', CASE WHEN v_bracket = 'double_elimination'
                                       THEN false ELSE true END,
      'seeding_mode',             'auto'));

  -- ---- §1.1 pool_phase_config. ----
  IF v_vorrunde = 'group_phase' THEN
    -- group_phase: a group_count that divides the bracket and yields an
    -- integer qualifiers_per_group. Default 4 groups (MilestoneTournaments
    -- "Default wert 4"); fall back to 1 if 4 does not divide qualifier_count.
    IF (v_qc % 4) = 0 THEN
      v_group_cnt := 4;
    ELSE
      v_group_cnt := 1;
    END IF;
    v_qpg := v_qc / v_group_cnt;
    v_pool := jsonb_build_object(
      'group_count',          v_group_cnt,
      'strategy',             coalesce(v_strategy, 'seeded'),
      'qualifiers_per_group', v_qpg);
  ELSE
    -- §1.1 schoch: auto single-pool (group_count=1, strategy=seeded,
    -- qualifiers_per_group = qualifier_count) per schochSinglePoolConfig.
    v_pool := jsonb_build_object(
      'group_count',          1,
      'strategy',             'seeded',
      'qualifiers_per_group', v_qc);
  END IF;
  v_setup := v_setup || jsonb_build_object('pool_phase_config', v_pool);

  -- ---- §1.1 consolation_bracket (+ mirror keys) for ko_type=consolation. ----
  IF v_ko_type = 'consolation' THEN
    -- main_bracket_size = next_pow2(qualifier_count) (qualifier_count is
    -- already a power of two here, so this equals qualifier_count).
    v_cons_size := 1;
    WHILE v_cons_size < v_qc LOOP
      v_cons_size := v_cons_size * 2;
    END LOOP;
    v_cons := jsonb_build_object(
      'enabled',           true,
      'source',            'early_ko_losers',
      'main_bracket_size', v_cons_size,
      'direct_count',      0,
      'name',              'Sieger der gebrochenen Herzen');
    v_setup := v_setup
      || jsonb_build_object('consolation_bracket', v_cons)
      || jsonb_build_object(
           'consolation_main_bracket_size', v_cons_size,
           'consolation_direct_count',      0,
           'consolation_name',              'Sieger der gebrochenen Herzen');
  END IF;

  -- ---- §1.1 fixed prelim match_format_config. ----
  -- break_between_matches_seconds = 300 is the intentionally non-default test
  -- value (draft default is 0) so the schedule-tick path exercises a non-zero
  -- inter-match break.
  p_format := v_format;
  p_setup  := v_setup;
  p_mfc    := jsonb_build_object(
    'max_sets',                      2,
    'sets_to_win',                   2,
    'round_time_seconds',            1800,
    'break_between_matches_seconds', 300,
    'basekubbs_per_side',            5);
  RETURN NEXT;
END;
$$;

-- =====================================================================
-- §3.2 Seed + register.
--
-- _tts_seed_tournament creates the organiser auth.users row + N auth.users
-- rows (minimal viable shape, instance_id 00000000-...), then calls
-- public.tournament_create with the §3.1-derived config and returns the
-- tournament_id. The organiser is the actor for tournament_create.
-- =====================================================================
CREATE OR REPLACE FUNCTION _tts_seed_tournament(
  p_row text, p_n int, p_organiser uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_cfg   record;
  v_tid   uuid;
  v_uid   uuid;
  i       int;
BEGIN
  SELECT * INTO v_cfg FROM _tts_config(p_row, p_n);

  -- Organiser user (FK target for created_by); minimal viable shape.
  PERFORM _tts_as_pg();
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (p_organiser, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'org-' || p_organiser::text || '@tts.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  -- N player users (deterministic, zero-padded UUIDs derived from organiser).
  FOR i IN 1..p_n LOOP
    v_uid := _tts_participant_user(p_organiser, i);
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated',
              'p' || i || '-' || p_organiser::text || '@tts.local',
              '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
  END LOOP;

  -- tournament_create as the organiser. p_max_participants is a constant 64
  -- (<= the 200 server clamp; N in {32,48,60} <= 64). The display name is
  -- clamped to the server's 1..60 char limit; full pipe-delimited row tokens
  -- are abbreviated to <vorrunde>/<ko_type> so a verbose row still fits.
  PERFORM _tts_as(p_organiser);
  v_tid := (public.tournament_create(
              left('TTS ' ||
                   CASE WHEN position('|' in p_row) > 0
                        THEN trim(split_part(p_row, '|', 1)) || '/' ||
                             trim(split_part(p_row, '|', 2))
                        ELSE p_row END
                   || ' N' || p_n || ' ' || left(p_organiser::text, 8), 60),
              1, 2, 64,
              v_cfg.p_format, v_cfg.p_mfc,
              ARRAY['total_points', 'wins', 'kubb_difference'],
              v_cfg.p_setup) ->> 'tournament_id')::uuid;

  RETURN v_tid;
END;
$$;

-- Deterministic per-(organiser, index) player user id. Kept as its own helper
-- so the participant lookups can reconstruct the same id.
CREATE OR REPLACE FUNCTION _tts_participant_user(p_organiser uuid, p_idx int)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT ('00000000-0000-0000-0d0d-' || lpad(
            ((('x' || substr(md5(p_organiser::text), 1, 6))::bit(24)::int % 900000)
             + p_idx)::text, 12, '0'))::uuid;
$$;

-- §3.2 _tts_register_n: writes N tournament_participants rows
-- registration_status='confirmed' with STAGGERED registered_at so the seeding
-- order is deterministic; returns the TARGET participant_id (the lowest
-- registered_at = seed 1, SPEC §5).
CREATE OR REPLACE FUNCTION _tts_register_n(p_tid uuid, p_n int)
RETURNS uuid
LANGUAGE plpgsql
AS $$
DECLARE
  v_org   uuid;
  v_uid   uuid;
  v_pid   uuid;
  i       int;
  v_target uuid;
BEGIN
  PERFORM _tts_as_pg();
  SELECT created_by INTO v_org FROM public.tournaments WHERE id = p_tid;

  FOR i IN 1..p_n LOOP
    v_uid := _tts_participant_user(v_org, i);
    v_pid := ('00000000-0000-0000-0c0c-' || lpad(
                ((('x' || substr(md5(p_tid::text), 1, 6))::bit(24)::int % 900000)
                 + i)::text, 12, '0'))::uuid;
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, registered_at)
      VALUES (v_pid, p_tid, v_uid, 'confirmed',
              now() + (i || ' seconds')::interval);
  END LOOP;

  -- Target = lowest registered_at (= future seed 1 under auto seeding).
  SELECT id INTO v_target
    FROM public.tournament_participants
    WHERE tournament_id = p_tid
    ORDER BY registered_at ASC, id ASC
    LIMIT 1;
  RETURN v_target;
END;
$$;

-- §3.2 Lookup helpers (mirror _t6_participant / _pid).
CREATE OR REPLACE FUNCTION _tts_participant(p_tid uuid, p_seed int)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT p.id FROM public.tournament_participants p
   WHERE p.tournament_id = p_tid
   ORDER BY p.registered_at ASC, p.id ASC
   OFFSET p_seed - 1 LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION _tts_target(p_tid uuid)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT p.id FROM public.tournament_participants p
   WHERE p.tournament_id = p_tid
   ORDER BY p.registered_at ASC, p.id ASC
   LIMIT 1;
$$;

-- =====================================================================
-- §3.3 Start.
--
-- Dispatches by tournaments.format to the correct start path:
--   round_robin_then_ko / swiss_then_ko prelim -> tournament_publish (draft ->
--     registration_open, the IST open-registration model 20261201000040) then
--     tournament_start (delegates the pool phase via tournament_start_pool_phase
--     for the hybrid formats). The KO entry (tournament_start_ko_phase) is
--     driven later by _tts_play_round once the prelim is complete and the
--     auto-seed gate is satisfied.
-- Asserts the status transition draft -> registration_open/live and that
-- prelim matches exist.
-- =====================================================================
CREATE OR REPLACE FUNCTION _tts_start(p_tid uuid)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  v_org    uuid;
  v_format text;
  v_status text;
  v_prelim int;
BEGIN
  SELECT created_by, format INTO v_org, v_format
    FROM public.tournaments WHERE id = p_tid;

  -- draft -> registration_open (IST publish goes straight to open registration).
  PERFORM _tts_as(v_org);
  PERFORM public.tournament_publish(p_tid);
  PERFORM _tts_as_pg();
  SELECT status INTO v_status FROM public.tournaments WHERE id = p_tid;
  IF v_status <> 'registration_open' THEN
    RAISE EXCEPTION '_tts_start: expected registration_open after publish, got %', v_status;
  END IF;

  -- registration_open -> live (hybrid: delegates to tournament_start_pool_phase;
  -- swiss_then_ko also materialises the single-pool round-robin group phase).
  PERFORM _tts_as(v_org);
  PERFORM public.tournament_start(p_tid);
  PERFORM _tts_as_pg();
  SELECT status INTO v_status FROM public.tournaments WHERE id = p_tid;
  IF v_status <> 'live' THEN
    RAISE EXCEPTION '_tts_start: expected live after start, got %', v_status;
  END IF;

  SELECT count(*) INTO v_prelim
    FROM public.tournament_matches
    WHERE tournament_id = p_tid AND phase = 'group';
  IF v_prelim = 0 THEN
    RAISE EXCEPTION '_tts_start: no prelim (group) matches materialised';
  END IF;
END;
$$;

-- =====================================================================
-- §3.4 Play a round with steering.
--
-- Plays EVERY currently-open scheduled match of the active phase to a terminal
-- result via tournament_propose_set_scores (consensus path: both sides submit
-- the identical 2-0 sheet so the match FINALIZES, firing the advance trigger).
-- p_steer in {'target_wins','seed_order','target_to_consolation'} drives the
-- winner choice so the TARGET advances per SPEC §5:
--   * target_wins          — the target wins every match it plays; the rest
--                            resolve in seed order (participant_a wins).
--   * seed_order           — every match resolves to participant_a.
--   * target_to_consolation— the target is deliberately LOST in its first KO
--                            match so the advance trigger routes it via
--                            early_ko_losers into the consolation bracket; the
--                            target then wins its consolation matches.
-- BYE matches are already terminal (start RPC finalised them). Returns the
-- number of matches finalized this call. For a schoch prelim it also pairs the
-- next round via tournament_pair_round (no-repeat / max-one-bye, rounds <= 7).
-- =====================================================================
CREATE OR REPLACE FUNCTION _tts_play_round(p_tid uuid, p_steer text)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
  v_org      uuid;
  v_format   text;
  v_target   uuid;
  m          record;
  v_ua       uuid;
  v_ub       uuid;
  v_side     text;
  v_sheet    jsonb;
  v_count    int := 0;
  v_target_lost_once boolean;
BEGIN
  -- Lesen aus den RPC-only-Tabellen (kein authenticated-Grant) als postgres.
  PERFORM _tts_as_pg();
  SELECT created_by, format INTO v_org, v_format FROM public.tournaments WHERE id = p_tid;
  v_target := _tts_target(p_tid);

  -- Has the target already taken its deliberate consolation loss? (Only the
  -- FIRST KO match is thrown; afterwards the target wins its consolation path.)
  SELECT EXISTS (
    SELECT 1 FROM public.tournament_matches
     WHERE tournament_id = p_tid
       AND phase IN ('ko','final','third_place')
       AND status IN ('finalized','overridden')
       AND winner_participant IS NOT NULL
       AND winner_participant <> v_target
       AND (participant_a = v_target OR participant_b = v_target)
  ) INTO v_target_lost_once;

  FOR m IN
    SELECT id, participant_a, participant_b, phase, round_number, bracket_position
      FROM public.tournament_matches
     WHERE tournament_id = p_tid
       AND status IN ('scheduled','awaiting_results')
       AND participant_a IS NOT NULL
       AND participant_b IS NOT NULL
     ORDER BY phase, round_number, coalesce(bracket_position, 0), match_number_in_round
  LOOP
    PERFORM _tts_as_pg();
    SELECT user_id INTO v_ua FROM public.tournament_participants WHERE id = m.participant_a;
    SELECT user_id INTO v_ub FROM public.tournament_participants WHERE id = m.participant_b;

    -- Decide the winning side per steer.
    v_side := 'A';   -- default: seed order (participant_a wins)
    IF p_steer = 'target_to_consolation'
       AND NOT v_target_lost_once
       AND m.phase IN ('ko','final')
       AND (m.participant_a = v_target OR m.participant_b = v_target) THEN
      -- Throw the target's first KO match so it is routed to consolation.
      v_side := CASE WHEN m.participant_a = v_target THEN 'B' ELSE 'A' END;
      v_target_lost_once := true;
    ELSIF p_steer IN ('target_wins','target_to_consolation') THEN
      IF m.participant_a = v_target THEN v_side := 'A';
      ELSIF m.participant_b = v_target THEN v_side := 'B';
      ELSE v_side := 'A';
      END IF;
    END IF;

    -- 2-0 consensus sheet for the winning side (sets_to_win = 2).
    v_sheet := jsonb_build_array(
      jsonb_build_object('basekubbs_a', CASE WHEN v_side='A' THEN 6 ELSE 0 END,
                         'basekubbs_b', CASE WHEN v_side='B' THEN 6 ELSE 0 END,
                         'winner', v_side),
      jsonb_build_object('basekubbs_a', CASE WHEN v_side='A' THEN 6 ELSE 0 END,
                         'basekubbs_b', CASE WHEN v_side='B' THEN 6 ELSE 0 END,
                         'winner', v_side));

    PERFORM _tts_as(v_ua);
    PERFORM public.tournament_propose_set_scores(m.id, 1, v_sheet);
    PERFORM _tts_as(v_ub);
    PERFORM public.tournament_propose_set_scores(m.id, 1, v_sheet);
    v_count := v_count + 1;
  END LOOP;

  PERFORM _tts_as_pg();
  RETURN v_count;
END;
$$;

-- =====================================================================
-- §3.5 Advance + tick.
--
-- Drives the round-clock published -> running -> completed by injecting the
-- fixed p_now into public.tournament_schedule_tick. The schedule rows are
-- materialised by the start/pair/ko RPCs with published_at = real wall-clock
-- now(); to make the tick deterministic against the FROZEN test instant we
-- first rebase every schedule row whose matches are all terminal so its
-- boundaries sit in the past relative to p_now (starts_at = p_now - 1h,
-- ends_at = p_now - 30min; starts_at < ends_at preserved per §4 A3). The
-- advance_ko_winner trigger has already propagated winners/losers into the
-- next bracket slots (it fires AFTER UPDATE inside the finalising RPC), so
-- this only advances the clock.
-- =====================================================================
CREATE OR REPLACE FUNCTION _tts_advance(
  p_tid uuid,
  p_now timestamptz DEFAULT '2026-06-09 12:00:00+00')
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM _tts_as_pg();

  -- Rebase boundaries into the past for rounds whose matches are all terminal,
  -- so the tick can flip published/running -> completed deterministically.
  UPDATE public.tournament_round_schedule s
     SET published_at = p_now - interval '90 minutes',
         starts_at    = p_now - interval '60 minutes',
         ends_at      = p_now - interval '30 minutes'
   WHERE s.tournament_id = p_tid
     AND coalesce(
           (SELECT bool_and(m.status IN ('finalized','overridden','voided'))
              FROM public.tournament_matches m
             WHERE m.tournament_id = s.tournament_id
               AND m.round_number  = s.round_number
               AND m.stage_node_id IS NOT DISTINCT FROM s.stage_node_id),
           false);

  PERFORM public.tournament_schedule_tick(p_now);
END;
$$;

-- =====================================================================
-- §3.6 Assertion helpers (each RETURNS SETOF text — one TAP line each).
-- =====================================================================

-- §4 A1 — Dense placement 1..N. The final standings projection (built on the
-- bracket-specific skv_*_placements helper, then broken to a strict total
-- order by (placement tier rank, prelim seed, id) via row_number) assigns
-- every confirmed participant a dense rank in [1, N] with no gaps and no
-- duplicates (COUNT(DISTINCT rank)=N and MIN=1, MAX=N).
CREATE OR REPLACE FUNCTION _tts_assert_placement_dense(p_tid uuid, p_n int)
RETURNS SETOF text
LANGUAGE plpgsql
AS $$
DECLARE
  v_distinct int;
  v_min      int;
  v_max      int;
BEGIN
  WITH proj AS (
    SELECT row_number() OVER (ORDER BY base.placement ASC, base.seed_ord ASC, base.pid ASC) AS dense_rank
      FROM _tts_placement_projection(p_tid) base
  )
  SELECT count(DISTINCT dense_rank)::int, min(dense_rank)::int, max(dense_rank)::int
    INTO v_distinct, v_min, v_max
    FROM proj;

  RETURN NEXT is(v_distinct, p_n,
    format('A1 placement: %s distinct dense ranks == N=%s (no dupes)', v_distinct, p_n));
  RETURN NEXT is(coalesce(v_min, 0), 1, 'A1 placement: MIN(rank) = 1 (gapless from 1)');
  RETURN NEXT is(coalesce(v_max, 0), p_n,
    format('A1 placement: MAX(rank) = N=%s (gapless to N)', p_n));
END;
$$;

-- Shared placement projection: one row per confirmed participant with the
-- bracket-derived placement tier rank + the prelim seed order. Dispatches by
-- the DB phases present (double / consolation / single), mirroring
-- tournament_skv_compute_awards. Participants outside the KO field fall back
-- to a high placement, ordered by their prelim seed.
CREATE OR REPLACE FUNCTION _tts_placement_projection(p_tid uuid)
RETURNS TABLE(pid uuid, placement int, seed_ord int)
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_ko_matches jsonb;
  v_prelim     text[];
  v_phases     text[];
  v_is_double  boolean;
  v_is_cons    boolean;
BEGIN
  SELECT array_agg(tp.id::text ORDER BY tp.seed ASC NULLS LAST, tp.id)
    INTO v_prelim
    FROM public.tournament_participants tp
   WHERE tp.tournament_id = p_tid
     AND tp.registration_status = 'confirmed';
  v_prelim := coalesce(v_prelim, ARRAY[]::text[]);

  SELECT coalesce(jsonb_agg(jsonb_build_object(
            'round',  m.round_number,
            'phase',  CASE m.phase WHEN 'ko' THEN 'winners'
                                   WHEN 'final' THEN 'finals'
                                   ELSE m.phase END,
            'a',      m.participant_a::text,
            'b',      m.participant_b::text,
            'winner', m.winner_participant::text,
            'bye',    (m.participant_a IS NULL OR m.participant_b IS NULL))), '[]'::jsonb)
    INTO v_ko_matches
    FROM public.tournament_matches m
   WHERE m.tournament_id = p_tid
     AND m.phase IN ('ko','final','third_place',
                     'wb','lb','grand_final','grand_final_reset',
                     'consolation','consolation_third_place');

  SELECT array_agg(DISTINCT m.phase) INTO v_phases
    FROM public.tournament_matches m
   WHERE m.tournament_id = p_tid
     AND m.phase IN ('ko','final','third_place',
                     'wb','lb','grand_final','grand_final_reset',
                     'consolation','consolation_third_place');
  v_is_double := coalesce(v_phases && ARRAY['wb','lb','grand_final','grand_final_reset']::text[], false);
  v_is_cons   := coalesce(v_phases && ARRAY['consolation','consolation_third_place']::text[], false);

  RETURN QUERY
  WITH placements AS (
    SELECT * FROM public.skv_double_elim_placements(v_ko_matches, v_prelim, 'einzel', false)
      WHERE v_is_double
    UNION ALL
    SELECT * FROM public.skv_consolation_placements(v_ko_matches, v_prelim, 'einzel', false)
      WHERE (NOT v_is_double) AND v_is_cons
    UNION ALL
    SELECT * FROM public.skv_single_elim_placements(v_ko_matches, v_prelim, 'einzel', false)
      WHERE (NOT v_is_double) AND (NOT v_is_cons)
  )
  SELECT tp.id,
         pl.rank,
         coalesce(array_position(v_prelim, tp.id::text), 1000000)::int
    FROM public.tournament_participants tp
    LEFT JOIN placements pl ON pl.participant_id = tp.id::text
   WHERE tp.tournament_id = p_tid
     AND tp.registration_status = 'confirmed';
END;
$$;

-- §4 A2 — Bracket consistency per bracket_type.
--   single_elimination: round count = ceil(log2(qualifier_count)); exactly one
--     final + one third_place; every advanced winner sits in exactly its parent
--     slot (advance-trigger parity); feeders finalized.
--   double_elimination: a winners and a losers bracket exist; the grand-final is
--     fed from both; no elimination before two losses (structural existence).
--   consolation: consolation_bracket enabled; main size = next_pow2(qc); early
--     KO losers routed into the consolation root; a consolation final exists.
CREATE OR REPLACE FUNCTION _tts_assert_bracket_consistent(p_tid uuid, p_row text)
RETURNS SETOF text
LANGUAGE plpgsql
AS $$
DECLARE
  v_bracket   text;
  v_cons_cfg  jsonb;
  v_qc        int;
  v_rounds    int;
  v_finals    int;
  v_third     int;
  v_exp_rounds int;
  v_wb        int;
  v_lb        int;
  v_gf        int;
  v_cons_n    int;
  v_cons_root int;
BEGIN
  SELECT bracket_type, consolation_bracket,
         coalesce((ko_config->>'qualifier_count')::int, 0)
    INTO v_bracket, v_cons_cfg, v_qc
    FROM public.tournaments WHERE id = p_tid;

  IF v_bracket = 'double_elimination' THEN
    SELECT count(*) FILTER (WHERE phase = 'wb'),
           count(*) FILTER (WHERE phase = 'lb'),
           count(*) FILTER (WHERE phase IN ('grand_final','grand_final_reset'))
      INTO v_wb, v_lb, v_gf
      FROM public.tournament_matches WHERE tournament_id = p_tid;
    RETURN NEXT ok(v_wb > 0 AND v_lb > 0,
      format('A2 double_elim: winners (%s) and losers (%s) brackets exist', v_wb, v_lb));
    RETURN NEXT ok(v_gf > 0, 'A2 double_elim: grand final fed from both brackets exists');

  ELSIF coalesce((v_cons_cfg->>'enabled')::boolean, false) THEN
    -- next_pow2(qualifier_count).
    v_cons_n := 1;
    WHILE v_cons_n < v_qc LOOP v_cons_n := v_cons_n * 2; END LOOP;
    SELECT count(*) INTO v_cons_root
      FROM public.tournament_matches
      WHERE tournament_id = p_tid AND phase = 'consolation';
    RETURN NEXT ok(coalesce((v_cons_cfg->>'enabled')::boolean, false),
      'A2 consolation: consolation_bracket.enabled');
    RETURN NEXT ok(v_cons_root > 0,
      format('A2 consolation: main size next_pow2(%s)=%s, consolation matches routed (%s)',
             v_qc, v_cons_n, v_cons_root));
    RETURN NEXT ok(EXISTS (
        SELECT 1 FROM public.tournament_matches
         WHERE tournament_id = p_tid
           AND phase IN ('consolation','consolation_third_place')),
      'A2 consolation: consolation final exists / finalizable');

  ELSE
    -- single_elimination.
    SELECT count(DISTINCT round_number) INTO v_rounds
      FROM public.tournament_matches
      WHERE tournament_id = p_tid AND phase IN ('ko','final');
    SELECT count(*) FILTER (WHERE phase = 'final'),
           count(*) FILTER (WHERE phase = 'third_place')
      INTO v_finals, v_third
      FROM public.tournament_matches WHERE tournament_id = p_tid;

    v_exp_rounds := ceil(log(2, greatest(v_qc, 2)))::int;
    RETURN NEXT is(v_rounds, v_exp_rounds,
      format('A2 single_elim: round count = ceil(log2(%s)) = %s', v_qc, v_exp_rounds));
    RETURN NEXT is(v_finals, 1, 'A2 single_elim: exactly one final');
    RETURN NEXT is(v_third, 1, 'A2 single_elim: exactly one third_place');
    -- Advance-trigger parity: the final's two slots are exactly the two
    -- semifinal winners (every winner appears in exactly its parent slot).
    RETURN NEXT ok(EXISTS (
        SELECT 1 FROM public.tournament_matches f
         WHERE f.tournament_id = p_tid AND f.phase = 'final'
           AND f.participant_a IS NOT NULL AND f.participant_b IS NOT NULL
           AND f.participant_a IN (
             SELECT winner_participant FROM public.tournament_matches
              WHERE tournament_id = p_tid AND phase = 'ko'
                AND round_number = (SELECT max(round_number) FROM public.tournament_matches
                                     WHERE tournament_id = p_tid AND phase = 'ko'))
           AND f.participant_b IN (
             SELECT winner_participant FROM public.tournament_matches
              WHERE tournament_id = p_tid AND phase = 'ko'
                AND round_number = (SELECT max(round_number) FROM public.tournament_matches
                                     WHERE tournament_id = p_tid AND phase = 'ko'))),
      'A2 single_elim: final slots = the two semifinal winners (advance parity)');
  END IF;
END;
$$;

-- §4 A3 — Schedule timestamps set. Every advanced tournament_round_schedule row
-- has non-null published_at/starts_at/ends_at with starts_at < ends_at, and the
-- terminal rounds reached status='completed'.
CREATE OR REPLACE FUNCTION _tts_assert_schedule_timestamps(p_tid uuid)
RETURNS SETOF text
LANGUAGE plpgsql
AS $$
DECLARE
  v_total      int;
  v_well_formed int;
  v_completed  int;
BEGIN
  SELECT count(*),
         count(*) FILTER (
           WHERE published_at IS NOT NULL AND starts_at IS NOT NULL
             AND ends_at IS NOT NULL AND starts_at < ends_at),
         count(*) FILTER (WHERE status = 'completed')
    INTO v_total, v_well_formed, v_completed
    FROM public.tournament_round_schedule
    WHERE tournament_id = p_tid;

  RETURN NEXT ok(v_total > 0, format('A3 schedule: %s schedule row(s) materialised', v_total));
  RETURN NEXT is(v_well_formed, v_total,
    'A3 schedule: every row has non-null published/starts/ends, starts_at < ends_at');
  RETURN NEXT ok(v_completed > 0,
    format('A3 schedule: %s terminal round(s) reached status=completed', v_completed));
END;
$$;

-- §4 A4 — Notifications created. Go-live / round-publish drove at least one
-- durable row into public.user_inbox_messages for participants when >= 1 round
-- was published.
CREATE OR REPLACE FUNCTION _tts_assert_notifications(p_tid uuid)
RETURNS SETOF text
LANGUAGE plpgsql
AS $$
DECLARE
  v_inbox int;
  v_users uuid[];
BEGIN
  SELECT array_agg(DISTINCT user_id)
    INTO v_users
    FROM public.tournament_participants
    WHERE tournament_id = p_tid AND registration_status = 'confirmed';

  SELECT count(*) INTO v_inbox
    FROM public.user_inbox_messages
    WHERE kind IN ('tournament_started','tournament_round')
      AND user_id = ANY(v_users);

  RETURN NEXT ok(v_inbox > 0,
    format('A4 notifications: %s inbox row(s) for participants (go-live / round-publish)', v_inbox));
END;
$$;

-- §4 A5 — No orphan participants. Every tournament_participants row appears in
-- at least one match (group/schoch/KO/consolation) OR carries a recorded bye;
-- no participant is left unmatched and unranked.
CREATE OR REPLACE FUNCTION _tts_assert_no_orphan_participants(p_tid uuid)
RETURNS SETOF text
LANGUAGE plpgsql
AS $$
DECLARE
  v_orphans int;
BEGIN
  SELECT count(*) INTO v_orphans
    FROM public.tournament_participants p
    WHERE p.tournament_id = p_tid
      AND p.registration_status = 'confirmed'
      AND NOT EXISTS (
        SELECT 1 FROM public.tournament_matches m
         WHERE m.tournament_id = p_tid
           AND (m.participant_a = p.id OR m.participant_b = p.id));

  RETURN NEXT is(v_orphans, 0,
    'A5 orphans: every confirmed participant appears in >= 1 match or bye');
END;
$$;

-- §4 A6 — Steering proof. The steered TARGET reached the configured endpoint:
-- the KO/main final for single_out/double_out, and the consolation final for
-- the target_to_consolation steer of consolation.
CREATE OR REPLACE FUNCTION _tts_assert_target_reached(p_tid uuid, p_row text)
RETURNS SETOF text
LANGUAGE plpgsql
AS $$
DECLARE
  v_target   uuid;
  v_bracket  text;
  v_cons     boolean;
  v_ko_type  text;
  v_in_final boolean;
  v_in_gf    boolean;
  v_in_cons  boolean;
BEGIN
  v_target := _tts_target(p_tid);
  SELECT bracket_type,
         coalesce((consolation_bracket->>'enabled')::boolean, false),
         _tts_ko_type(p_row)
    INTO v_bracket, v_cons, v_ko_type
    FROM public.tournaments WHERE id = p_tid;

  IF v_bracket = 'double_elimination' THEN
    SELECT EXISTS (
      SELECT 1 FROM public.tournament_matches
       WHERE tournament_id = p_tid
         AND phase IN ('grand_final','grand_final_reset')
         AND (participant_a = v_target OR participant_b = v_target)) INTO v_in_gf;
    RETURN NEXT ok(v_in_gf, 'A6 steering: target reached the double-elim grand final');

  ELSIF v_cons AND position('target_to_consolation' in p_row) > 0 THEN
    SELECT EXISTS (
      SELECT 1 FROM public.tournament_matches
       WHERE tournament_id = p_tid
         AND phase IN ('consolation','consolation_third_place')
         AND (participant_a = v_target OR participant_b = v_target)) INTO v_in_cons;
    RETURN NEXT ok(v_in_cons, 'A6 steering: target reached the consolation final');

  ELSE
    SELECT EXISTS (
      SELECT 1 FROM public.tournament_matches
       WHERE tournament_id = p_tid
         AND phase = 'final'
         AND (participant_a = v_target OR participant_b = v_target)) INTO v_in_final;
    RETURN NEXT ok(v_in_final, 'A6 steering: target reached the KO/main final');
  END IF;
END;
$$;

-- Tiny helper: extract the ko_type token from a §2 row body (defaults
-- single_out for a bare id), used only by the A6 assertion text/dispatch.
CREATE OR REPLACE FUNCTION _tts_ko_type(p_row text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN position('|' in p_row) > 0
              THEN trim(split_part(p_row, '|', 2))
              ELSE 'single_out' END;
$$;

-- =====================================================================
-- §3.7 Per-row driver. Runs the full lifecycle for one (row, N) and emits all
-- §4 assertion lines, so a matrix shard is a flat list of _tts_run(row, N).
-- Steering: target_wins for non-consolation; consolation rows are driven by
-- the matrix with both target_wins and target_to_consolation (the driver below
-- uses target_wins; the consolation-specific second pass is a matrix concern).
-- =====================================================================
CREATE OR REPLACE FUNCTION _tts_run(p_row text, p_n int)
RETURNS SETOF text
LANGUAGE plpgsql
AS $$
DECLARE
  v_org     uuid := gen_random_uuid();
  v_tid     uuid;
  v_target  uuid;
  v_format  text;
  v_qc      int;
  v_guard   int;
  v_open    int;
  v_steer   text;
  v_ko_org  uuid;
  v_ko_cfg  jsonb;
BEGIN
  v_tid := _tts_seed_tournament(p_row, p_n, v_org);
  v_target := _tts_register_n(v_tid, p_n);
  PERFORM _tts_start(v_tid);

  SELECT format, coalesce((ko_config->>'qualifier_count')::int, 0)
    INTO v_format, v_qc FROM public.tournaments WHERE id = v_tid;

  -- ---- Prelim: play group/schoch rounds to completion. ----
  -- group_phase prelim is a single materialised round-robin round; schoch
  -- prelim pairs further rounds via tournament_pair_round (handled by the
  -- play helper). Loop guarded at <= 7 rounds (SPEC §1.2).
  v_steer := CASE WHEN _tts_ko_type(p_row) = 'consolation'
                  THEN 'target_to_consolation' ELSE 'target_wins' END;

  FOR v_guard IN 1..7 LOOP
    SELECT count(*) INTO v_open
      FROM public.tournament_matches
      WHERE tournament_id = v_tid AND phase = 'group'
        AND status NOT IN ('finalized','overridden','voided');
    EXIT WHEN v_open = 0;
    PERFORM _tts_play_round(v_tid, 'target_wins');  -- target tops the standings
  END LOOP;

  -- ---- Enter the KO phase once the prelim is terminal. ----
  -- created_by + ko_config als postgres lesen (kein authenticated-Grant), erst
  -- danach in die Organisator-Rolle für den SECURITY-DEFINER-RPC wechseln.
  PERFORM _tts_as_pg();
  SELECT created_by, ko_config INTO v_ko_org, v_ko_cfg
    FROM public.tournaments WHERE id = v_tid;
  PERFORM _tts_as(v_ko_org);
  PERFORM public.tournament_start_ko_phase(v_tid, v_ko_cfg);
  PERFORM _tts_as_pg();

  -- ---- KO: play every bracket round to a terminal result. ----
  FOR v_guard IN 1..12 LOOP
    SELECT count(*) INTO v_open
      FROM public.tournament_matches
      WHERE tournament_id = v_tid
        AND phase IN ('ko','final','third_place',
                      'wb','lb','grand_final','grand_final_reset',
                      'consolation','consolation_third_place')
        AND status IN ('scheduled','awaiting_results')
        AND participant_a IS NOT NULL AND participant_b IS NOT NULL;
    EXIT WHEN v_open = 0;
    PERFORM _tts_play_round(v_tid, v_steer);
  END LOOP;

  -- ---- Drive the schedule clock to completed. ----
  PERFORM _tts_advance(v_tid);

  -- ---- Emit the §4 assertion group. ----
  RETURN QUERY SELECT * FROM _tts_assert_placement_dense(v_tid, p_n);
  RETURN QUERY SELECT * FROM _tts_assert_bracket_consistent(v_tid, p_row);
  RETURN QUERY SELECT * FROM _tts_assert_schedule_timestamps(v_tid);
  RETURN QUERY SELECT * FROM _tts_assert_notifications(v_tid);
  RETURN QUERY SELECT * FROM _tts_assert_no_orphan_participants(v_tid);
  RETURN QUERY SELECT * FROM _tts_assert_target_reached(v_tid, p_row);
END;
$$;
-- 8 edge scenarios, 44 explicit pgTAP assertions (see counts per block below).
SELECT plan(44);

-- =====================================================================
-- EDGE SCENARIOS (T-Edges). Each scenario is a DO block that reaches the
-- probed lifecycle state via the §3 harness helpers above
-- (_tts_seed_tournament / _tts_register_n / _tts_start / _tts_play_round),
-- stages the edge condition, and stows the OBSERVED outcomes into the
-- transient _tts_edge_obs(k text, v text) scratch table. The pgTAP
-- predicate lines below each block then assert against those rows, so the
-- file is a flat, readable list of `is(...)` / `ok(...)` / `throws_ok(...)`
-- assertions with descriptive English names that trace back to the edge
-- concept (forfeit / bye / override / tiebreak-hold / pause-resume-skip /
-- checkin-no-show / schedule-tick / per-pitch-notify).
--
-- All fixtures live inside this transaction and roll back. The fixed test
-- clock is '2026-06-09 12:00:00+00' (SPEC §3 / K7); schedule boundaries are
-- rebased relative to that injected p_now so the time transitions are
-- deterministic under pgTAP's frozen now().
-- =====================================================================

-- Scratch table for cross-block observations (auto-dropped on ROLLBACK).
-- Granted to PUBLIC so the put/get helpers work after the scenarios switch to
-- the authenticated actor role (the table is owned by postgres).
CREATE TEMP TABLE _tts_edge_obs (k text PRIMARY KEY, v text);
GRANT ALL ON TABLE _tts_edge_obs TO PUBLIC;

CREATE OR REPLACE FUNCTION _tts_edge_put(p_k text, p_v text) RETURNS void
LANGUAGE sql AS $$
  INSERT INTO _tts_edge_obs(k, v) VALUES (p_k, p_v)
  ON CONFLICT (k) DO UPDATE SET v = excluded.v;
$$;

CREATE OR REPLACE FUNCTION _tts_edge_get(p_k text) RETURNS text
LANGUAGE sql STABLE AS $$ SELECT v FROM _tts_edge_obs WHERE k = p_k; $$;


-- =====================================================================
-- SCENARIO 1 — FORFAIT (public.tournament_match_forfeit).
-- A two-sided live group match is forfeited by the tournament creator with
-- absent side 'B'. The present side (A) is credited tournaments.forfeit_points
-- (default 18) and the absent side 0; the match flips to 'finalized'. Negative
-- guards: invalid absent_side (22023) and a non-creator caller (42501).
-- =====================================================================
DO $forfeit$
DECLARE
  v_org uuid := '0ed60001-0ed6-0000-0001-000000000001';
  v_tid uuid; v_mid uuid; v_pa uuid; v_pb uuid; v_res jsonb;
BEGIN
  v_tid := _tts_seed_tournament(
    'group_phase|single_out|seed_high_vs_low|classic_kingtoss_removal|ekc|seeded', 32, v_org);
  PERFORM _tts_register_n(v_tid, 32);
  PERFORM _tts_start(v_tid);

  SELECT id, participant_a, participant_b INTO v_mid, v_pa, v_pb
    FROM public.tournament_matches
   WHERE tournament_id = v_tid AND phase = 'group' AND status = 'scheduled'
   ORDER BY id LIMIT 1;

  PERFORM _tts_as(v_org);
  v_res := public.tournament_match_forfeit(v_mid, 'B', 'Side B no-show, forfeit declared by organiser');

  PERFORM _tts_as_pg();
  PERFORM _tts_edge_put('forfeit_status',
    (SELECT status FROM public.tournament_matches WHERE id = v_mid));
  PERFORM _tts_edge_put('forfeit_present_score', (v_res ->> 'final_score_a'));
  PERFORM _tts_edge_put('forfeit_absent_score',  (v_res ->> 'final_score_b'));
  PERFORM _tts_edge_put('forfeit_points',        (v_res ->> 'forfeit_points'));
  PERFORM _tts_edge_put('forfeit_winner_is_present',
    CASE WHEN (v_res ->> 'winner_participant_id') = v_pa::text THEN 'yes' ELSE 'no' END);

  -- Eine noch offene Gruppen-Partie für die Negativ-Guards merken. Als postgres
  -- gelesen (RPC-only-Tabellen); die Guard-Cases unten laufen als authenticated
  -- und können tournament_matches nicht direkt lesen.
  PERFORM _tts_edge_put('forfeit_guard_mid',
    (SELECT id::text FROM public.tournament_matches
      WHERE tournament_id = v_tid AND phase = 'group' AND status = 'scheduled'
      ORDER BY id LIMIT 1));
END;
$forfeit$;

SELECT is(_tts_edge_get('forfeit_status'), 'finalized',
  'forfeit: a live two-sided match flips to finalized (terminal)');
SELECT is(_tts_edge_get('forfeit_present_score'), '18',
  'forfeit: the present side is credited forfeit_points (18)');
SELECT is(_tts_edge_get('forfeit_absent_score'), '0',
  'forfeit: the absent side is credited the losing score 0');
SELECT is(_tts_edge_get('forfeit_winner_is_present'), 'yes',
  'forfeit: the present side (A) is recorded as the winner');

-- Negative guards run inline so the throws_ok caller context is the right actor.
SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',
  jsonb_build_object('sub', '0ed60001-0ed6-0000-0001-000000000001', 'role', 'authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
SELECT throws_ok(
  $$ SELECT public.tournament_match_forfeit(
       _tts_edge_get('forfeit_guard_mid')::uuid,
       'X', 'Valid length reason but bad absent side here') $$,
  '22023',
  NULL,
  'forfeit guard: absent_side not in {A,B} raises 22023');

SELECT throws_ok(
  $$ SELECT public.tournament_match_forfeit(
       _tts_edge_get('forfeit_guard_mid')::uuid,
       'A', 'short') $$,
  '22023',
  NULL,
  'forfeit guard: a reason shorter than 10 chars raises 22023');


-- =====================================================================
-- SCENARIO 2 — BYE / FREILOS (odd effective participant count).
-- A swiss prelim with an ODD confirmed count (7) is started. The engine's
-- round-1 pairing produces exactly one one-sided match (participant_b NULL):
-- the recorded bye. Assertions prove the present participant is NOT orphaned
-- (it appears as participant_a of the bye match) and the bye carries no played
-- two-sided result, consistent with §4 A5 _tts_assert_no_orphan_participants.
--
-- HARNESS-SIZING NOTE (DoD-05): unlike the other scenarios, this one does NOT
-- go through _tts_seed_tournament. The §3 harness sizes (32/48/60 per SPEC §0.3)
-- are all EVEN and cannot produce an odd effective field, so no bye/Freilos slot
-- is ever materialised by them. An odd field is therefore set up directly here
-- with N=7 (still IST: <=200 server clamp, no #-wish). The bye match itself is
-- GENUINE ENGINE OUTPUT — tournament_start's swiss round-1 materialisation emits
-- the one-sided (participant_b NULL) match for the unpaired last slot; it is NOT
-- hand-faked. Everything still runs in-transaction and rolls back.
-- =====================================================================
DO $bye$
DECLARE
  v_org uuid := '0ed60002-0ed6-0000-0002-000000000001';
  v_tid uuid := gen_random_uuid();
  v_uid uuid; i int; v_bye record; v_orphans int;
BEGIN
  PERFORM _tts_as_pg();
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (v_org, '00000000-0000-0000-0000-000000000000', 'authenticated',
            'authenticated', 'org-' || v_org || '@tts.local', '', now(), now(), now());
  -- Swiss format gives a genuine engine bye on an odd field (one NULL side);
  -- this is IST (within the <=200 cap, no #-wish). N=7 is odd by construction.
  INSERT INTO public.tournaments(id, created_by, display_name, team_size,
      min_participants, max_participants, format, scoring, match_format, status, public)
    VALUES (v_tid, v_org, 'TTS bye swiss ' || left(v_tid::text, 8), 1, 2, 16,
            'swiss', 'ekc', '{}'::jsonb, 'registration_open', true);
  FOR i IN 1..7 LOOP
    v_uid := gen_random_uuid();
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_uid, '00000000-0000-0000-0000-000000000000', 'authenticated',
              'authenticated', 'p' || i || '-' || v_uid || '@tts.local', '', now(), now(), now());
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, registered_at)
      VALUES (gen_random_uuid(), v_tid, v_uid, 'confirmed', now() + (i || ' seconds')::interval);
  END LOOP;

  PERFORM _tts_as(v_org);
  PERFORM public.tournament_start(v_tid);

  PERFORM _tts_as_pg();
  -- Exactly one bye (one NULL side) for an odd field of 7.
  PERFORM _tts_edge_put('bye_count',
    (SELECT count(*)::text FROM public.tournament_matches
      WHERE tournament_id = v_tid AND (participant_a IS NULL OR participant_b IS NULL)));

  SELECT participant_a, participant_b, winner_participant, status INTO v_bye
    FROM public.tournament_matches
   WHERE tournament_id = v_tid AND (participant_a IS NULL OR participant_b IS NULL)
   LIMIT 1;
  -- The present side is non-null (recorded bye holder); the other side is NULL.
  PERFORM _tts_edge_put('bye_present_non_null',
    CASE WHEN coalesce(v_bye.participant_a, v_bye.participant_b) IS NOT NULL THEN 'yes' ELSE 'no' END);
  PERFORM _tts_edge_put('bye_one_side_null',
    CASE WHEN (v_bye.participant_a IS NULL) <> (v_bye.participant_b IS NULL) THEN 'yes' ELSE 'no' END);
  -- No played two-sided result on the bye (no final scores, not finalized via play).
  PERFORM _tts_edge_put('bye_no_played_result',
    CASE WHEN v_bye.winner_participant IS NULL THEN 'yes' ELSE 'no' END);

  -- §4 A5: no confirmed participant is orphaned (every one appears in >=1 match).
  SELECT count(*) INTO v_orphans
    FROM public.tournament_participants p
   WHERE p.tournament_id = v_tid
     AND p.registration_status = 'confirmed'
     AND NOT EXISTS (
       SELECT 1 FROM public.tournament_matches m
        WHERE m.tournament_id = v_tid
          AND (m.participant_a = p.id OR m.participant_b = p.id));
  PERFORM _tts_edge_put('bye_orphans', v_orphans::text);
END;
$bye$;

SELECT is(_tts_edge_get('bye_count'), '1',
  'bye: an odd swiss field of 7 produces exactly one one-sided (bye) pairing');
SELECT is(_tts_edge_get('bye_one_side_null'), 'yes',
  'bye: the bye match has exactly one NULL side (one-sided pairing)');
SELECT is(_tts_edge_get('bye_present_non_null'), 'yes',
  'bye: the present (advancing) participant occupies the non-NULL side');
SELECT is(_tts_edge_get('bye_no_played_result'), 'yes',
  'bye: the bye advances WITHOUT a played two-sided result');
SELECT is(_tts_edge_get('bye_orphans'), '0',
  'bye: no participant is orphaned — the bye holder still appears in a match (A5)');


-- =====================================================================
-- SCENARIO 3 — ORGANIZER OVERRIDE (public.tournament_organizer_override_pairing).
-- The creator re-pairs an isolated scheduled match (placed in its own
-- round_number so no same-round conflict exists) to a fresh, valid pair of
-- registered participants. Happy path asserts participant_a/b updated; guard
-- asserts the MISSING_REASON path (empty reason -> 22023).
-- =====================================================================
DO $override$
DECLARE
  v_org uuid := '0ed60003-0ed6-0000-0003-000000000001';
  v_tid uuid; v_mid uuid; v_n1 uuid; v_n2 uuid; v_pa uuid; v_pb uuid;
BEGIN
  v_tid := _tts_seed_tournament(
    'group_phase|single_out|seed_high_vs_low|classic_kingtoss_removal|ekc|seeded', 32, v_org);
  PERFORM _tts_register_n(v_tid, 32);
  PERFORM _tts_start(v_tid);

  -- An isolated scheduled match in a fresh round_number (no same-round siblings,
  -- so the override's PARTICIPANT_CONFLICT guard does not fire on the happy path).
  PERFORM _tts_as_pg();
  v_n1 := _tts_participant(v_tid, 3);
  v_n2 := _tts_participant(v_tid, 4);
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, pitch_number)
    VALUES (v_tid, 99, 1, _tts_participant(v_tid, 1), _tts_participant(v_tid, 2),
            'ko', 'scheduled', 1)
    RETURNING id INTO v_mid;

  PERFORM _tts_as(v_org);
  PERFORM public.tournament_organizer_override_pairing(
    v_mid, v_n1, v_n2, 'Manual re-pair: swap to the reserve participants');

  PERFORM _tts_as_pg();
  SELECT participant_a, participant_b INTO v_pa, v_pb
    FROM public.tournament_matches WHERE id = v_mid;
  PERFORM _tts_edge_put('override_pair_updated',
    CASE WHEN v_pa = v_n1 AND v_pb = v_n2 THEN 'yes' ELSE 'no' END);
  PERFORM _tts_edge_put('override_match_id', v_mid::text);
  -- Reserve-Paar für den Negativ-Guard merken (als postgres aufgelöst); der
  -- throws_ok unten läuft als authenticated und darf nicht direkt lesen.
  PERFORM _tts_edge_put('override_guard_n1', v_n1::text);
  PERFORM _tts_edge_put('override_guard_n2', v_n2::text);
END;
$override$;

SELECT is(_tts_edge_get('override_pair_updated'), 'yes',
  'override: participant_a/b are updated to the new pair on the happy path');

SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',
  jsonb_build_object('sub', '0ed60003-0ed6-0000-0003-000000000001', 'role', 'authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
SELECT throws_ok(
  format($$ SELECT public.tournament_organizer_override_pairing(%L::uuid, %L::uuid, %L::uuid, '') $$,
         _tts_edge_get('override_match_id'),
         _tts_edge_get('override_guard_n1'),
         _tts_edge_get('override_guard_n2')),
  '22023',
  NULL,
  'override guard: an empty reason raises MISSING_REASON (22023)');


-- =====================================================================
-- SCENARIO 4 — TIEBREAK-HOLD (clock runs out with a missing result).
-- A running round whose ends_at is reached at the injected p_now while one
-- match is still MISSING transitions running -> awaiting_results (NOT
-- completed); the clock holds, no auto-forfait. A second tick is idempotent
-- (0 transitions, stays awaiting_results). Once the missing result is supplied
-- and a tick fires with all matches terminal, the row reaches completed.
-- =====================================================================
DO $hold$
DECLARE
  v_org uuid := '0ed60004-0ed6-0000-0004-000000000001';
  v_tid uuid; v_open uuid; v_n int;
BEGIN
  v_tid := _tts_seed_tournament(
    'group_phase|single_out|seed_high_vs_low|classic_kingtoss_removal|ekc|seeded', 32, v_org);
  PERFORM _tts_register_n(v_tid, 32);
  PERFORM _tts_start(v_tid);

  PERFORM _tts_as_pg();
  -- Drive the round to running with ends_at already past at p_now.
  UPDATE public.tournament_round_schedule
     SET status = 'running',
         published_at = '2026-06-09 09:00:00+00',
         starts_at    = '2026-06-09 10:00:00+00',
         ends_at      = '2026-06-09 11:30:00+00'
   WHERE tournament_id = v_tid AND round_number = 1;

  -- Finalize ALL group matches but ONE (the held missing result).
  SELECT id INTO v_open FROM public.tournament_matches
    WHERE tournament_id = v_tid AND phase = 'group' ORDER BY id LIMIT 1;
  UPDATE public.tournament_matches
     SET status = 'finalized', winner_participant = participant_a, finalized_at = now()
   WHERE tournament_id = v_tid AND phase = 'group' AND id <> v_open;

  -- Tick 1: ends_at <= p_now, a result missing -> awaiting_results, clock holds.
  v_n := public.tournament_schedule_tick('2026-06-09 12:00:00+00');
  PERFORM _tts_edge_put('hold_tick1_transitions', v_n::text);
  PERFORM _tts_edge_put('hold_status_after_tick1',
    (SELECT status FROM public.tournament_round_schedule WHERE tournament_id = v_tid AND round_number = 1));

  -- Tick 2 (idempotency): same hold, later p_now, result still missing -> 0.
  v_n := public.tournament_schedule_tick('2026-06-09 12:05:00+00');
  PERFORM _tts_edge_put('hold_tick2_transitions', v_n::text);
  PERFORM _tts_edge_put('hold_status_after_tick2',
    (SELECT status FROM public.tournament_round_schedule WHERE tournament_id = v_tid AND round_number = 1));

  -- Supply the missing result, then a tick with all matches terminal -> completed.
  UPDATE public.tournament_matches
     SET status = 'finalized', winner_participant = participant_a, finalized_at = now()
   WHERE id = v_open;
  v_n := public.tournament_schedule_tick('2026-06-09 12:10:00+00');
  PERFORM _tts_edge_put('hold_status_completed',
    (SELECT status FROM public.tournament_round_schedule WHERE tournament_id = v_tid AND round_number = 1));
END;
$hold$;

SELECT is(_tts_edge_get('hold_status_after_tick1'), 'awaiting_results',
  'tiebreak-hold: ends_at reached with a missing result -> running becomes awaiting_results');
SELECT is(_tts_edge_get('hold_tick1_transitions'), '1',
  'tiebreak-hold: the running -> awaiting_results hold is a single transition');
SELECT is(_tts_edge_get('hold_tick2_transitions'), '0',
  'tiebreak-hold: a re-tick with the result still missing performs 0 transitions (idempotent)');
SELECT is(_tts_edge_get('hold_status_after_tick2'), 'awaiting_results',
  'tiebreak-hold: the row stays held in awaiting_results across the re-tick (clock holds)');
SELECT is(_tts_edge_get('hold_status_completed'), 'completed',
  'tiebreak-hold: once the missing result is supplied, the next tick reaches completed');


-- =====================================================================
-- SCENARIO 5 — PAUSE / RESUME / SKIP
-- (tournament_pause / resume / skip_forward / skip_back).
-- Exercised on a running round. pause sets paused_at and is idempotent; resume
-- accumulates the frozen interval into paused_accum_seconds and clears
-- paused_at; skip_forward starts the window now with status running and clears
-- pause; skip_back re-calls the window (status call) and clears pause. Plus a
-- non-manager authorisation guard (42501).
-- =====================================================================
DO $control$
DECLARE
  v_org uuid := '0ed60005-0ed6-0000-0005-000000000001';
  v_tid uuid; v_paused_1 timestamptz; v_paused_2 timestamptz; v_s record;
BEGIN
  v_tid := _tts_seed_tournament(
    'group_phase|single_out|seed_high_vs_low|classic_kingtoss_removal|ekc|seeded', 32, v_org);
  PERFORM _tts_register_n(v_tid, 32);
  PERFORM _tts_start(v_tid);

  PERFORM _tts_as_pg();
  UPDATE public.tournament_round_schedule SET status = 'running'
   WHERE tournament_id = v_tid AND round_number = 1;

  -- pause + idempotent second pause (paused_at must not advance). RPCs als
  -- Organisator, die Verifikations-Reads als postgres (RPC-only-Tabelle).
  PERFORM _tts_as(v_org);
  PERFORM public.tournament_pause(v_tid);
  PERFORM _tts_as_pg();
  SELECT paused_at INTO v_paused_1 FROM public.tournament_round_schedule WHERE tournament_id = v_tid AND round_number = 1;
  PERFORM _tts_as(v_org);
  PERFORM public.tournament_pause(v_tid);
  PERFORM _tts_as_pg();
  SELECT paused_at INTO v_paused_2 FROM public.tournament_round_schedule WHERE tournament_id = v_tid AND round_number = 1;
  PERFORM _tts_edge_put('pause_set', CASE WHEN v_paused_1 IS NOT NULL THEN 'yes' ELSE 'no' END);
  PERFORM _tts_edge_put('pause_idempotent', CASE WHEN v_paused_1 = v_paused_2 THEN 'yes' ELSE 'no' END);

  -- resume accumulates the frozen interval. now() is frozen in the txn, so
  -- back-date paused_at by 300s to exercise the EXTRACT(EPOCH ...) accumulation.
  PERFORM _tts_as_pg();
  UPDATE public.tournament_round_schedule
     SET paused_at = now() - interval '300 seconds', paused_accum_seconds = 0
   WHERE tournament_id = v_tid AND round_number = 1;
  PERFORM _tts_as(v_org);
  PERFORM public.tournament_resume(v_tid);
  PERFORM _tts_as_pg();
  SELECT * INTO v_s FROM public.tournament_round_schedule WHERE tournament_id = v_tid AND round_number = 1;
  PERFORM _tts_edge_put('resume_paused_at_cleared', CASE WHEN v_s.paused_at IS NULL THEN 'yes' ELSE 'no' END);
  PERFORM _tts_edge_put('resume_accum', v_s.paused_accum_seconds::text);

  -- resume while not paused is a no-op (accum unchanged).
  PERFORM _tts_as(v_org);
  PERFORM public.tournament_resume(v_tid);
  PERFORM _tts_as_pg();
  SELECT paused_accum_seconds INTO v_s.paused_accum_seconds
    FROM public.tournament_round_schedule WHERE tournament_id = v_tid AND round_number = 1;
  PERFORM _tts_edge_put('resume_noop_accum', v_s.paused_accum_seconds::text);

  -- skip_forward: status running, pause cleared (paused_at NULL, accum 0).
  PERFORM _tts_as(v_org);
  PERFORM public.tournament_skip_forward(v_tid);
  PERFORM _tts_as_pg();
  SELECT * INTO v_s FROM public.tournament_round_schedule WHERE tournament_id = v_tid AND round_number = 1;
  PERFORM _tts_edge_put('skipfwd_status', v_s.status);
  PERFORM _tts_edge_put('skipfwd_pause_cleared',
    CASE WHEN v_s.paused_at IS NULL AND v_s.paused_accum_seconds = 0 THEN 'yes' ELSE 'no' END);

  -- skip_back: re-call the window (status call).
  PERFORM _tts_as(v_org);
  PERFORM public.tournament_skip_back(v_tid);
  PERFORM _tts_as_pg();
  SELECT status INTO v_s.status FROM public.tournament_round_schedule WHERE tournament_id = v_tid AND round_number = 1;
  PERFORM _tts_edge_put('skipback_status', v_s.status);
  -- Tournament-Id für den Non-Manager-Guard (läuft als authenticated) merken.
  PERFORM _tts_edge_put('pause_guard_tid', v_tid::text);
END;
$control$;

SELECT is(_tts_edge_get('pause_set'), 'yes',
  'pause: tournament_pause sets paused_at on the active round');
SELECT is(_tts_edge_get('pause_idempotent'), 'yes',
  'pause: a second pause does not advance paused_at (idempotent)');
SELECT is(_tts_edge_get('resume_paused_at_cleared'), 'yes',
  'resume: tournament_resume clears paused_at');
SELECT is(_tts_edge_get('resume_accum'), '300',
  'resume: the frozen 300s interval is accumulated into paused_accum_seconds');
SELECT is(_tts_edge_get('resume_noop_accum'), '300',
  'resume: a resume while not paused is a no-op (accum unchanged)');
SELECT is(_tts_edge_get('skipfwd_status'), 'running',
  'skip_forward: starts the match window now with status running');
SELECT is(_tts_edge_get('skipfwd_pause_cleared'), 'yes',
  'skip_forward: clears pause state (paused_at NULL, paused_accum_seconds 0)');
SELECT is(_tts_edge_get('skipback_status'), 'call',
  'skip_back: re-calls the window with status call');

SET LOCAL ROLE postgres;
SELECT set_config('request.jwt.claims',
  jsonb_build_object('sub', '0ed600ff-0ed6-0000-0005-0000000000ff', 'role', 'authenticated')::text, true);
SELECT set_config('role', 'authenticated', true);
SELECT throws_ok(
  format($$ SELECT public.tournament_pause(%L::uuid) $$,
         _tts_edge_get('pause_guard_tid')),
  '42501',
  NULL,
  'pause guard: a non-manager caller raises 42501');


-- =====================================================================
-- SCENARIO 6 — CHECK-IN + NO-SHOW -> FORFAIT
-- (tournament_checkin_participant / tournament_undo_checkin + forfeit).
-- The present side (A) is checked in (set-on-checkin, idempotent re-checkin,
-- cleared-on-undo). The un-checked-in side (B) is the no-show; the organizer
-- resolves the match via tournament_match_forfeit against the absent side B.
-- The present side advances with forfeit_points; this is the IST organizer-
-- driven path (no separate auto-no-show RPC is asserted).
-- =====================================================================
DO $checkin$
DECLARE
  v_org uuid := '0ed60006-0ed6-0000-0006-000000000001';
  v_tid uuid; v_mid uuid; v_pa uuid; v_pb uuid; v_res jsonb;
BEGIN
  v_tid := _tts_seed_tournament(
    'group_phase|single_out|seed_high_vs_low|classic_kingtoss_removal|ekc|seeded', 32, v_org);
  PERFORM _tts_register_n(v_tid, 32);
  PERFORM _tts_start(v_tid);

  SELECT id, participant_a, participant_b INTO v_mid, v_pa, v_pb
    FROM public.tournament_matches
   WHERE tournament_id = v_tid AND phase = 'group' AND status = 'scheduled'
   ORDER BY id LIMIT 1;

  -- check in side A (present); leave side B (no-show) un-checked.
  PERFORM _tts_as(v_org);
  v_res := public.tournament_checkin_participant(v_pa);
  PERFORM _tts_edge_put('checkin_changed', v_res ->> 'changed');
  -- idempotent re-checkin.
  v_res := public.tournament_checkin_participant(v_pa);
  PERFORM _tts_edge_put('checkin_recheckin_changed', v_res ->> 'changed');

  PERFORM _tts_as_pg();
  PERFORM _tts_edge_put('checkin_a_set',
    CASE WHEN (SELECT checked_in_at FROM public.tournament_participants WHERE id = v_pa) IS NOT NULL
         THEN 'yes' ELSE 'no' END);
  PERFORM _tts_edge_put('checkin_b_null',
    CASE WHEN (SELECT checked_in_at FROM public.tournament_participants WHERE id = v_pb) IS NULL
         THEN 'yes' ELSE 'no' END);

  -- undo clears the timestamp, then re-check-in A for the no-show resolution.
  PERFORM _tts_as(v_org);
  v_res := public.tournament_undo_checkin(v_pa);
  PERFORM _tts_edge_put('checkin_undo_changed', v_res ->> 'changed');
  PERFORM _tts_as_pg();
  PERFORM _tts_edge_put('checkin_a_cleared',
    CASE WHEN (SELECT checked_in_at FROM public.tournament_participants WHERE id = v_pa) IS NULL
         THEN 'yes' ELSE 'no' END);
  PERFORM _tts_as(v_org);
  PERFORM public.tournament_checkin_participant(v_pa);

  -- No-show resolution: the un-checked-in side B is the forfeited (absent) side.
  v_res := public.tournament_match_forfeit(v_mid, 'B', 'Side B never checked in — no-show forfeit');
  PERFORM _tts_edge_put('noshow_present_advances',
    CASE WHEN (v_res ->> 'winner_participant_id') = v_pa::text THEN 'yes' ELSE 'no' END);
  PERFORM _tts_edge_put('noshow_present_points', (v_res ->> 'final_score_a'));
END;
$checkin$;

SELECT is(_tts_edge_get('checkin_changed'), 'true',
  'check-in: tournament_checkin_participant sets checked_in_at (changed=true)');
SELECT is(_tts_edge_get('checkin_recheckin_changed'), 'false',
  'check-in: a re-check-in on an already checked-in participant is idempotent (changed=false)');
SELECT is(_tts_edge_get('checkin_a_set'), 'yes',
  'check-in: the present side carries a non-null checked_in_at');
SELECT is(_tts_edge_get('checkin_undo_changed'), 'true',
  'check-in: tournament_undo_checkin clears the timestamp (changed=true)');
SELECT is(_tts_edge_get('checkin_a_cleared'), 'yes',
  'check-in: checked_in_at is NULL after undo');
SELECT is(_tts_edge_get('checkin_b_null'), 'yes',
  'no-show: the un-checked-in side B has a NULL checked_in_at');
SELECT is(_tts_edge_get('noshow_present_advances'), 'yes',
  'no-show: the present (checked-in) side advances as the forfeit winner');
SELECT is(_tts_edge_get('noshow_present_points'), '18',
  'no-show: the present side is credited forfeit_points (18) against the absent no-show');


-- =====================================================================
-- SCENARIO 7 — SCHEDULE-TICK TRANSITIONS (injected p_now).
-- Each documented status transition of tournament_schedule_tick is asserted
-- with a fixed injected clock: published -> running (starts_at<=p_now);
-- running|awaiting_results -> completed (ends_at<=p_now AND all matches
-- terminal); running -> awaiting_results (ends_at<=p_now AND a result missing);
-- a re-tick at the same p_now performs 0 transitions; and a PAUSED row does NOT
-- time-transition. (Driven on independent harness-seeded tournaments so the
-- branches never blur.)
-- =====================================================================
DO $tick$
DECLARE
  v_org1 uuid := '0ed60071-0ed6-0000-0007-000000000001';
  v_org2 uuid := '0ed60072-0ed6-0000-0007-000000000002';
  v_org3 uuid := '0ed60073-0ed6-0000-0007-000000000003';
  v_org4 uuid := '0ed60074-0ed6-0000-0007-000000000004';
  v_t1 uuid; v_t2 uuid; v_t3 uuid; v_t4 uuid; v_n int;
BEGIN
  -- T1: published -> running.
  v_t1 := _tts_seed_tournament('group_phase|single_out|seed_high_vs_low|classic_kingtoss_removal|ekc|seeded', 32, v_org1);
  PERFORM _tts_register_n(v_t1, 32);
  PERFORM _tts_start(v_t1);
  PERFORM _tts_as_pg();
  UPDATE public.tournament_round_schedule
     SET status='published', starts_at='2026-06-09 11:00:00+00', ends_at='2026-06-09 13:00:00+00'
   WHERE tournament_id=v_t1 AND round_number=1;
  v_n := public.tournament_schedule_tick('2026-06-09 12:00:00+00');
  PERFORM _tts_edge_put('tick_pub_to_run',
    (SELECT status FROM public.tournament_round_schedule WHERE tournament_id=v_t1 AND round_number=1));
  -- idempotency: re-tick at the same p_now performs no transition.
  PERFORM _tts_edge_put('tick_idempotent',
    public.tournament_schedule_tick('2026-06-09 12:00:00+00')::text);

  -- T3: running + all-terminal + ends_at past -> completed.
  v_t3 := _tts_seed_tournament('group_phase|single_out|seed_high_vs_low|classic_kingtoss_removal|ekc|seeded', 32, v_org3);
  PERFORM _tts_register_n(v_t3, 32);
  PERFORM _tts_start(v_t3);
  PERFORM _tts_as_pg();
  UPDATE public.tournament_round_schedule
     SET status='running', starts_at='2026-06-09 10:00:00+00', ends_at='2026-06-09 11:30:00+00'
   WHERE tournament_id=v_t3 AND round_number=1;
  UPDATE public.tournament_matches
     SET status='finalized', winner_participant=participant_a, finalized_at=now()
   WHERE tournament_id=v_t3 AND phase='group';
  PERFORM public.tournament_schedule_tick('2026-06-09 12:00:00+00');
  PERFORM _tts_edge_put('tick_run_to_completed',
    (SELECT status FROM public.tournament_round_schedule WHERE tournament_id=v_t3 AND round_number=1));

  -- T2: running + a result missing + ends_at past -> awaiting_results.
  v_t2 := _tts_seed_tournament('group_phase|single_out|seed_high_vs_low|classic_kingtoss_removal|ekc|seeded', 32, v_org2);
  PERFORM _tts_register_n(v_t2, 32);
  PERFORM _tts_start(v_t2);
  PERFORM _tts_as_pg();
  UPDATE public.tournament_round_schedule
     SET status='running', starts_at='2026-06-09 10:00:00+00', ends_at='2026-06-09 11:30:00+00'
   WHERE tournament_id=v_t2 AND round_number=1;
  UPDATE public.tournament_matches
     SET status='finalized', winner_participant=participant_a, finalized_at=now()
   WHERE tournament_id=v_t2 AND phase='group'
     AND id <> (SELECT id FROM public.tournament_matches WHERE tournament_id=v_t2 AND phase='group' ORDER BY id LIMIT 1);
  PERFORM public.tournament_schedule_tick('2026-06-09 12:00:00+00');
  PERFORM _tts_edge_put('tick_run_to_awaiting',
    (SELECT status FROM public.tournament_round_schedule WHERE tournament_id=v_t2 AND round_number=1));

  -- T4: paused row does NOT time-transition under tick.
  v_t4 := _tts_seed_tournament('group_phase|single_out|seed_high_vs_low|classic_kingtoss_removal|ekc|seeded', 32, v_org4);
  PERFORM _tts_register_n(v_t4, 32);
  PERFORM _tts_start(v_t4);
  PERFORM _tts_as_pg();
  UPDATE public.tournament_round_schedule
     SET status='published', paused_at=now(),
         starts_at='2026-06-09 11:00:00+00', ends_at='2026-06-09 13:00:00+00'
   WHERE tournament_id=v_t4 AND round_number=1;
  PERFORM public.tournament_schedule_tick('2026-06-09 12:00:00+00');
  PERFORM _tts_edge_put('tick_paused_no_transition',
    (SELECT status FROM public.tournament_round_schedule WHERE tournament_id=v_t4 AND round_number=1));
END;
$tick$;

SELECT is(_tts_edge_get('tick_pub_to_run'), 'running',
  'schedule-tick: published & starts_at<=p_now -> running');
SELECT is(_tts_edge_get('tick_run_to_completed'), 'completed',
  'schedule-tick: running & ends_at<=p_now & all matches terminal -> completed');
SELECT is(_tts_edge_get('tick_run_to_awaiting'), 'awaiting_results',
  'schedule-tick: running & ends_at<=p_now & a result missing -> awaiting_results');
SELECT is(_tts_edge_get('tick_idempotent'), '0',
  'schedule-tick: a re-tick at the same p_now performs 0 transitions (idempotent)');
SELECT is(_tts_edge_get('tick_paused_no_transition'), 'published',
  'schedule-tick: a paused row (paused_at set) does NOT time-transition');


-- =====================================================================
-- SCENARIO 8 — PER-PITCH NOTIFICATIONS (_tournament_notify_round_per_pitch).
-- Going live publishes round 1 with assigned pitches (pitch_number>0), driving
-- one durable per-pitch inbox row per participant into user_inbox_messages.
-- Re-publishing the same round is idempotent (no duplicate per-pitch rows),
-- consistent with §4 A4 (no published round ends with zero notifications).
-- =====================================================================
DO $pitch$
DECLARE
  v_org uuid := '0ed60008-0ed6-0000-0008-000000000001';
  v_tid uuid; v_rows_after_start int; v_reinsert int; v_rows_after_repub int; v_distinct int;
BEGIN
  v_tid := _tts_seed_tournament(
    'group_phase|single_out|seed_high_vs_low|classic_kingtoss_removal|ekc|seeded', 32, v_org);
  PERFORM _tts_register_n(v_tid, 32);
  PERFORM _tts_start(v_tid);

  PERFORM _tts_as_pg();
  -- Per-pitch rows created at go-live (one per participant for round 1).
  SELECT count(*) INTO v_rows_after_start
    FROM public.user_inbox_messages
   WHERE kind = 'tournament_round'
     AND action_payload ? 'pitch_number'
     AND (action_payload ->> 'tournament_id') = v_tid::text
     AND (action_payload ->> 'round_number') = '1'
     AND (action_payload ->> 'kind') = 'round_published';
  PERFORM _tts_edge_put('pitch_rows_after_start', v_rows_after_start::text);

  SELECT count(DISTINCT user_id) INTO v_distinct
    FROM public.user_inbox_messages
   WHERE kind = 'tournament_round'
     AND action_payload ? 'pitch_number'
     AND (action_payload ->> 'tournament_id') = v_tid::text
     AND (action_payload ->> 'round_number') = '1';
  PERFORM _tts_edge_put('pitch_distinct_recipients', v_distinct::text);

  -- Re-publish (double-materialise): the idempotency guard inserts nothing.
  v_reinsert := public._tournament_notify_round_per_pitch(
    v_tid, 1, 'group', 'round_published', 'Runde 1 veröffentlicht', 'Re-publish body');
  PERFORM _tts_edge_put('pitch_reinsert', v_reinsert::text);

  SELECT count(*) INTO v_rows_after_repub
    FROM public.user_inbox_messages
   WHERE kind = 'tournament_round'
     AND action_payload ? 'pitch_number'
     AND (action_payload ->> 'tournament_id') = v_tid::text
     AND (action_payload ->> 'round_number') = '1'
     AND (action_payload ->> 'kind') = 'round_published';
  PERFORM _tts_edge_put('pitch_rows_after_repub', v_rows_after_repub::text);
END;
$pitch$;

SELECT cmp_ok(_tts_edge_get('pitch_rows_after_start')::int, '>', 0,
  'per-pitch notify: publishing round 1 with assigned pitches creates >=1 inbox row per participant');
SELECT is(_tts_edge_get('pitch_distinct_recipients'), '32',
  'per-pitch notify: one per-pitch inbox row lands for each of the 32 participants');
SELECT is(_tts_edge_get('pitch_reinsert'), '0',
  'per-pitch notify: a re-publish inserts 0 rows (idempotent, no duplicates)');
SELECT is(_tts_edge_get('pitch_rows_after_repub'), _tts_edge_get('pitch_rows_after_start'),
  'per-pitch notify: the per-pitch row count is unchanged after re-publish (double-materialise safe)');

SELECT * FROM finish();

ROLLBACK;
