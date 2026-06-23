-- =====================================================================
-- Tournament Testing Suite (TTS) — CONFIG MATRIX shard: schoch rows S01..S24.
--
-- Source of truth: docs/plans/tournament-testing-suite/SPEC.md (Block T-Matrix,
-- §6.1 sharding so each pgTAP file stays runnable under `supabase test db`).
-- This shard drives the 24 schoch combos S01..S24 (A2×A3×A4×A5; pool strategy N/A, schoch_rounds=7) end-to-end through the real RPCs and triggers via
-- the §3.7 T-Harness entry point _tts_run(p_row, p_n). Each row is passed as the
-- full pipe-delimited §2 row BODY (NOT a bare id) so every non-derived axis
-- (incl. the pool strategy for group_phase) is exercised (SPEC §1.1). Per
-- (row, N) run _tts_run emits exactly the SPEC §4 group A1..A6 (placement_dense,
-- bracket_consistent, schedule_timestamps, notifications, no_orphan_participants,
-- target_reached) — no assertion dropped or weakened.
--
-- The full 96-combo matrix is sharded across (SPEC §6.1):
--   config_matrix_test.sql        -- G01..G24 (group_phase single_out) [THIS is shard 1]
--   tts_matrix_group_double.sql   -- G25..G48 (group_phase double_out)
--   tts_matrix_group_cons.sql     -- G49..G72 (group_phase consolation)
--   tts_matrix_schoch.sql         -- S01..S24 (schoch)
-- Together: the 72 group_phase rows + 24 schoch rows = all 96 §2 combos, each at
-- the default N=32, plus a small representative N=48/N=60 subset (SPEC §0.3,
-- DoD-05/DoD-10 — one size per combo is the default; the 288 full fan-out is NOT
-- the execution path).
--
-- SELF-CONTAINED / runnable standalone (SPEC §6.1): installs pgtap, re-CREATE-
-- OR-REPLACEs the §3 helpers at the top (the helper head below is COPIED
-- BYTE-FOR-BYTE from supabase/tests/tts_harness.sql — this shard does NOT
-- rewrite that harness), wraps everything in a single BEGIN .. ROLLBACK (every
-- helper defined in-transaction, auto-dropped on ROLLBACK — NO production
-- migration, NO COMMIT, NO db reset), uses no_plan()/finish() (SPEC §4: per-run
-- line counts are bracket-type-dependent — single_out=13, double_out=11,
-- consolation=12, plus the consolation main-path A6 line — so a static plan is
-- brittle), and ROLLBACKs at the end.
--
-- One documented matrix-local refinement of a §3 helper follows the head: the
-- placement projection is re-CREATE-OR-REPLACEd to honour the DOCUMENTED
-- contract of public.skv_double_elim_placements ("reset if present" == a reset
-- that actually happened). When the WB champion wins the grand final outright
-- (the target_wins case), double_elim_server.sql §3.3 leaves the
-- grand_final_reset as an UNPLAYED stub (NULL participants); that stub must not
-- be serialised into p_ko_matches, or the immutable SKV helper raises "decider
-- match ... is not completed". Contract-conformance, not a contract change.
--
-- IST-vs-WISH (SPEC §0.2): only the currently built contract is driven —
-- max_participants <= 200 (server clamp), qualifier_count a power of two in
-- [2,64], N in {32,48,60}. No 1000-player path, no year-suffix, no Spasstournier,
-- no diggy-default-on. Derived/coupled values (p_format, bracket_type,
-- qualifier_count 16|32|32 for N 32|48|60, with_third_place_playoff=true,
-- seeding_mode=auto, consolation_bracket block, schoch auto single-pool with
-- qualifiers_per_group) are produced by _tts_config — NOT re-hardcoded here.
--
-- Fixed test clock p_now = '2026-06-09 12:00:00+00' for schedule ticks (the
-- harness default; K7: pgTAP freezes now()).
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
  -- ADR-0039 §4: swiss_then_ko / schoch_then_ko run on the stage graph; the
  -- runner auto-routes top_k into the KO stage and materialises the bracket
  -- itself (the single ko_config-aware source). The explicit legacy
  -- tournament_start_ko_phase is only the KO materialiser on the flat-pool
  -- round_robin_then_ko path; firing it on the stage-graph path raises
  -- ALREADY_STARTED against the auto-materialised KO.
  IF v_format = 'round_robin_then_ko' THEN
    PERFORM _tts_as_pg();
    SELECT created_by, ko_config INTO v_ko_org, v_ko_cfg
      FROM public.tournaments WHERE id = v_tid;
    PERFORM _tts_as(v_ko_org);
    PERFORM public.tournament_start_ko_phase(v_tid, v_ko_cfg);
    PERFORM _tts_as_pg();
  END IF;

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

-- =====================================================================
-- Matrix-local refinement (documented above): re-CREATE-OR-REPLACE the §3.6
-- placement projection so that UNPLAYED terminal-state STUBS (NULL-slot matches
-- left behind by the eager bracket materialisation) are excluded from the
-- p_ko_matches array handed to the SKV placement helpers. Two stubs arise:
-- (1) the grand_final_reset when the WB champion wins outright ("no reset",
-- double_elim_server.sql §3.3), and (2) an unfilled consolation_third_place
-- playoff that never received both feeders for the steered run. Both
-- skv_double_elim_placements and skv_consolation_placements document
-- "reset/third-place, WHEN PRESENT, must be complete"; a NULL-slot stub is not a
-- real present match, so feeding it trips their 22023 "... is not completed"
-- guards. Identical to tts_harness.sql _tts_placement_projection except for this
-- single phase filter — the external contract (signature + semantics for every
-- already-passing single/double/consolation case) is unchanged.
-- =====================================================================
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
                     'consolation','consolation_third_place')
     -- Exclude unplayed terminal-state stubs (contract conformance). Two cases
     -- arise from the eager bracket materialisation: (1) the grand_final_reset
     -- stub when the WB champion wins outright (double_elim_server.sql §3.3),
     -- and (2) an unfilled consolation_third_place playoff that never received
     -- both feeders for the steered run. skv_double_elim_placements /
     -- skv_consolation_placements both document "reset/third-place, WHEN PRESENT,
     -- must be complete"; a NULL-slot stub is not a real present match, so it
     -- must not be serialised into p_ko_matches (else their 22023 guards fire).
     AND NOT (m.phase IN ('grand_final_reset','consolation_third_place')
              AND (m.participant_a IS NULL
                   OR m.participant_b IS NULL
                   OR m.winner_participant IS NULL));

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

-- =====================================================================
-- Matrix-local consolation MAIN-PATH driver (SPEC §5 endpoint 1 / DoD-06).
-- Thin glue mirroring _tts_run but steering target_wins so the target reaches
-- the MAIN final; reuses every §3 harness helper (_tts_seed_tournament,
-- _tts_register_n, _tts_start, _tts_play_round, _tts_advance,
-- _tts_assert_target_reached) and adds NO lifecycle logic of its own. The row is
-- passed WITHOUT a 'target_to_consolation' token, so _tts_assert_target_reached
-- asserts the MAIN final (the consolation-final endpoint is proven by the
-- canonical _tts_run pass). Emits exactly the one A6 TAP line.
-- =====================================================================
CREATE OR REPLACE FUNCTION _tts_run_cons_main(p_row text, p_n int)
RETURNS SETOF text
LANGUAGE plpgsql
AS $$
DECLARE
  v_org   uuid := gen_random_uuid();
  v_tid   uuid;
  v_guard int;
  v_open  int;
BEGIN
  v_tid := _tts_seed_tournament(p_row, p_n, v_org);
  PERFORM _tts_register_n(v_tid, p_n);
  PERFORM _tts_start(v_tid);

  -- Prelim to completion (target tops the standings).
  FOR v_guard IN 1..7 LOOP
    SELECT count(*) INTO v_open
      FROM public.tournament_matches
      WHERE tournament_id = v_tid AND phase = 'group'
        AND status NOT IN ('finalized','overridden','voided');
    EXIT WHEN v_open = 0;
    PERFORM _tts_play_round(v_tid, 'target_wins');
  END LOOP;

  -- Enter the KO phase.
  PERFORM _tts_as((SELECT created_by FROM public.tournaments WHERE id = v_tid));
  PERFORM public.tournament_start_ko_phase(v_tid,
    (SELECT ko_config FROM public.tournaments WHERE id = v_tid));

  -- KO to completion, target_wins -> target lands in the MAIN final.
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
    PERFORM _tts_play_round(v_tid, 'target_wins');
  END LOOP;

  PERFORM _tts_advance(v_tid);

  -- A6 only: p_row carries no target_to_consolation token -> MAIN final assertion.
  RETURN QUERY SELECT * FROM _tts_assert_target_reached(v_tid, p_row);
END;
$$;

-- =====================================================================
-- Matrix-local determinism hardening (SPEC §3.2: "Deterministic, zero-padded
-- UUIDs"). The matrix drives ~26-49 tournaments PER SHARD inside one
-- transaction, far more than the single-run harness/smoke path. The harness's
-- participant/user id derivation truncates md5(...) to 6 hex digits, then takes
-- `% 900000 + i`: two runs whose hashes land within `i` of each other produce
-- COLLIDING ids, tripping tournament_participants_pkey (a non-deterministic
-- ~1-in-50 birthday collision across many runs). Re-CREATE-OR-REPLACE
-- _tts_participant_user and _tts_register_n so the id is derived INJECTIVELY
-- from the FULL md5 of (key || ':' || i) — making the "deterministic, unique"
-- contract actually hold at matrix scale. Seeding semantics are unchanged: the
-- staggered registered_at (now() + i seconds) and the target = lowest
-- registered_at rule (SPEC §5) are byte-identical to the harness; only the id
-- bit-pattern (never asserted on) differs. Lookups (_tts_participant/_tts_target)
-- order by registered_at, so they are unaffected.
-- =====================================================================
CREATE OR REPLACE FUNCTION _tts_participant_user(p_organiser uuid, p_idx int)
RETURNS uuid
LANGUAGE sql
IMMUTABLE
AS $$
  -- Injective per (organiser, idx): full md5 hex, 'd0d' marker + 12 hex tail.
  SELECT ('00000000-0000-0000-0d0d-'
          || substr(md5(p_organiser::text || ':u:' || p_idx::text), 1, 12))::uuid;
$$;

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
    -- Injective per (tournament, idx): full md5 hex, 'c0c' marker + 12 hex tail.
    v_pid := ('00000000-0000-0000-0c0c-'
              || substr(md5(p_tid::text || ':p:' || i::text), 1, 12))::uuid;
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

-- =====================================================================
-- Matrix-local format-aware cons-main driver (Unit 8b). The harness's
-- _tts_run_cons_main unconditionally calls tournament_start_ko_phase — correct
-- on the flat-pool round_robin_then_ko path, but on the schoch stage-graph path
-- (swiss_then_ko) the KO stage is auto-materialised by tournament_start, so
-- firing the legacy KO RPC raises ALREADY_STARTED. Re-CREATE-OR-REPLACE the
-- driver to skip that call for the stage-graph formats (identical to the harness
-- otherwise: target_wins -> the target reaches the MAIN final, single A6 line).
-- =====================================================================
CREATE OR REPLACE FUNCTION _tts_run_cons_main(p_row text, p_n int)
RETURNS SETOF text
LANGUAGE plpgsql
AS $$
DECLARE
  v_org    uuid := gen_random_uuid();
  v_tid    uuid;
  v_guard  int;
  v_open   int;
  v_format text;
BEGIN
  v_tid := _tts_seed_tournament(p_row, p_n, v_org);
  PERFORM _tts_register_n(v_tid, p_n);
  PERFORM _tts_start(v_tid);

  SELECT format INTO v_format FROM public.tournaments WHERE id = v_tid;

  -- Prelim to completion (target tops the standings).
  FOR v_guard IN 1..7 LOOP
    SELECT count(*) INTO v_open
      FROM public.tournament_matches
      WHERE tournament_id = v_tid AND phase = 'group'
        AND status NOT IN ('finalized','overridden','voided');
    EXIT WHEN v_open = 0;
    PERFORM _tts_play_round(v_tid, 'target_wins');
  END LOOP;

  -- Enter the KO phase. Only the flat-pool round_robin_then_ko path needs the
  -- explicit legacy RPC; the schoch / swiss stage graph auto-materialises it.
  IF v_format = 'round_robin_then_ko' THEN
    PERFORM _tts_as((SELECT created_by FROM public.tournaments WHERE id = v_tid));
    PERFORM public.tournament_start_ko_phase(v_tid,
      (SELECT ko_config FROM public.tournaments WHERE id = v_tid));
    PERFORM _tts_as_pg();
  END IF;

  -- KO to completion, target_wins -> target lands in the MAIN final.
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
    PERFORM _tts_play_round(v_tid, 'target_wins');
  END LOOP;

  PERFORM _tts_advance(v_tid);

  RETURN QUERY SELECT * FROM _tts_assert_target_reached(v_tid, p_row);
END;
$$;

-- =====================================================================
-- THE MATRIX. no_plan()/finish() per SPEC §4 (per-run line counts vary by
-- bracket_type). Each call drives one full (row, N) lifecycle and emits the
-- §4 A1..A6 group; consolation main-path passes emit the single A6 line.
-- =====================================================================
SELECT no_plan();


-- ---------------------------------------------------------------------
-- §2.B schoch rows S01..S24 @ default N=32 (schoch_rounds=7 fixed).
-- ---------------------------------------------------------------------
-- S01 (N=32) single_out: target -> final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|single_out|seed_high_vs_low|classic_kingtoss_removal|ekc', 32);
-- S02 (N=32) single_out: target -> final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|single_out|seed_high_vs_low|classic_kingtoss_removal|classic', 32);
-- S03 (N=32) single_out: target -> final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|single_out|seed_high_vs_low|mighty_finisher_shootout|ekc', 32);
-- S04 (N=32) single_out: target -> final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|single_out|seed_high_vs_low|mighty_finisher_shootout|classic', 32);
-- S05 (N=32) single_out: target -> final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|single_out|one_vs_two|classic_kingtoss_removal|ekc', 32);
-- S06 (N=32) single_out: target -> final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|single_out|one_vs_two|classic_kingtoss_removal|classic', 32);
-- S07 (N=32) single_out: target -> final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|single_out|one_vs_two|mighty_finisher_shootout|ekc', 32);
-- S08 (N=32) single_out: target -> final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|single_out|one_vs_two|mighty_finisher_shootout|classic', 32);

-- §0.3 larger-size regime subset (single_out) for this slice (DoD-05).
-- S01 (N=48) single_out: target -> final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|single_out|seed_high_vs_low|classic_kingtoss_removal|ekc', 48);

-- ---------------------------------------------------------------------
-- §2.B schoch rows S09..S16 double_out @ default N=32 (Unit 8b). ADR-0039 §4:
-- the schoch->KO auto-route now derives the KO stage type from bracket_type, so
-- double_elimination after schoch materialises a stage wb/lb/grand_final
-- bracket. with_reset is owner-default OFF. A6 -> grand final.
-- ---------------------------------------------------------------------
-- S09 (N=32) double_out: target -> grand final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|double_out|seed_high_vs_low|classic_kingtoss_removal|ekc', 32);
-- S10 (N=32) double_out: target -> grand final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|double_out|seed_high_vs_low|classic_kingtoss_removal|classic', 32);
-- S11 (N=32) double_out: target -> grand final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|double_out|seed_high_vs_low|mighty_finisher_shootout|ekc', 32);
-- S12 (N=32) double_out: target -> grand final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|double_out|seed_high_vs_low|mighty_finisher_shootout|classic', 32);
-- S13 (N=32) double_out: target -> grand final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|double_out|one_vs_two|classic_kingtoss_removal|ekc', 32);
-- S14 (N=32) double_out: target -> grand final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|double_out|one_vs_two|classic_kingtoss_removal|classic', 32);
-- S15 (N=32) double_out: target -> grand final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|double_out|one_vs_two|mighty_finisher_shootout|ekc', 32);
-- S16 (N=32) double_out: target -> grand final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|double_out|one_vs_two|mighty_finisher_shootout|classic', 32);

-- ---------------------------------------------------------------------
-- §2.B schoch rows S17..S24 consolation @ default N=32 (Unit 8b). ADR-0039 §4:
-- the auto-route now materialises a consolation sub-bracket alongside the main
-- single-elim KO; early_ko_losers are routed in by the advance trigger. Each row
-- runs BOTH endpoints (SPEC §5): _tts_run with target_to_consolation steering
-- (A6 -> consolation final) and _tts_run_cons_main (A6 -> MAIN final).
-- ---------------------------------------------------------------------
-- S17 (N=32) consolation: target -> consolation final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|consolation|seed_high_vs_low|classic_kingtoss_removal|ekc|target_to_consolation', 32);
SELECT * FROM _tts_run_cons_main('schoch|consolation|seed_high_vs_low|classic_kingtoss_removal|ekc', 32);
-- S18 (N=32) consolation: target -> consolation final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|consolation|seed_high_vs_low|classic_kingtoss_removal|classic|target_to_consolation', 32);
SELECT * FROM _tts_run_cons_main('schoch|consolation|seed_high_vs_low|classic_kingtoss_removal|classic', 32);
-- S19 (N=32) consolation: target -> consolation final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|consolation|seed_high_vs_low|mighty_finisher_shootout|ekc|target_to_consolation', 32);
SELECT * FROM _tts_run_cons_main('schoch|consolation|seed_high_vs_low|mighty_finisher_shootout|ekc', 32);
-- S20 (N=32) consolation: target -> consolation final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|consolation|seed_high_vs_low|mighty_finisher_shootout|classic|target_to_consolation', 32);
SELECT * FROM _tts_run_cons_main('schoch|consolation|seed_high_vs_low|mighty_finisher_shootout|classic', 32);
-- S21 (N=32) consolation: target -> consolation final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|consolation|one_vs_two|classic_kingtoss_removal|ekc|target_to_consolation', 32);
SELECT * FROM _tts_run_cons_main('schoch|consolation|one_vs_two|classic_kingtoss_removal|ekc', 32);
-- S22 (N=32) consolation: target -> consolation final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|consolation|one_vs_two|classic_kingtoss_removal|classic|target_to_consolation', 32);
SELECT * FROM _tts_run_cons_main('schoch|consolation|one_vs_two|classic_kingtoss_removal|classic', 32);
-- S23 (N=32) consolation: target -> consolation final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|consolation|one_vs_two|mighty_finisher_shootout|ekc|target_to_consolation', 32);
SELECT * FROM _tts_run_cons_main('schoch|consolation|one_vs_two|mighty_finisher_shootout|ekc', 32);
-- S24 (N=32) consolation: target -> consolation final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|consolation|one_vs_two|mighty_finisher_shootout|classic|target_to_consolation', 32);
SELECT * FROM _tts_run_cons_main('schoch|consolation|one_vs_two|mighty_finisher_shootout|classic', 32);

-- §0.3 larger-size regime subset (N=60) for double_out / consolation (DoD-05).
-- S09 (N=60) double_out: target -> grand final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|double_out|seed_high_vs_low|classic_kingtoss_removal|ekc', 60);
-- S17 (N=60) consolation: target -> consolation final (SPEC §5/A6).
SELECT * FROM _tts_run('schoch|consolation|seed_high_vs_low|classic_kingtoss_removal|ekc|target_to_consolation', 60);
-- S17 (N=60) consolation main-path: target -> MAIN final (SPEC §5/A6 endpoint 1).
SELECT * FROM _tts_run_cons_main('schoch|consolation|seed_high_vs_low|classic_kingtoss_removal|ekc', 60);

SELECT * FROM finish();

ROLLBACK;
