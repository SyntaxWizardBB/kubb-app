-- round_robin ring-rotation collision + NULL-bye fix — Migration
-- 20261313000000_round_robin_ring_rotation_fix.sql.
--
-- Two regressions in the round_robin branch of tournament_start:
--   * the bulk circle-rotation UPDATE hit _tstart_ring_pkey (23505) for any
--     slot_count >= 3 because Postgres checks the PK per row, not deferred;
--   * the odd-N bye was inserted as NULL into _tstart_slots.participant_id,
--     which was declared NOT NULL (not_null_violation).
--
-- AK-1 (N=4, even): start succeeds, status live, exactly 3 rounds of 2
--   matches each (= 6), every (a,b) pairing unique across all rounds
--   (a complete single round-robin).
-- AK-2 (N=5, odd): start succeeds (no not_null/pkey error), 5 rounds, per
--   round 2 real matches + 1 bye, and NO row with participant_a IS NULL
--   (the bye is normalised into participant_a, participant_b NULL allowed).
-- AK-3 (N=2): 1 round, 1 match, no error.
--
-- Seeding idiom mirrors the green suites (creator via auth.uid, confirmed
-- participants seeded as postgres). All transient in BEGIN..ROLLBACK.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(15);

CREATE OR REPLACE FUNCTION _rrr_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _rrr_as_pg() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

CREATE OR REPLACE FUNCTION _rrr_p(p_t int, p_idx int) RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$
  SELECT ('00000000-0000-' || lpad(p_t::text, 4, '0') || '-1c1d-'
          || lpad(p_idx::text, 12, '0'))::uuid
$$;

-- Seeds a round_robin tournament with N confirmed participants. The creator
-- (p_org) is reused across all fixtures; participants get distinct auth users.
CREATE OR REPLACE FUNCTION _rrr_seed(p_tid uuid, p_org uuid, p_t int, p_n int)
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_u uuid;
  i   int;
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (p_org, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'org' || p_t || '@rrr.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.tournaments(
      id, created_by, display_name, team_size, min_participants,
      max_participants, format, scoring, match_format, status, public)
    VALUES (p_tid, p_org, 'RR N=' || p_n, 1, 2, 32,
            'round_robin', 'ekc',
            jsonb_build_object('round_time_seconds', 1800),
            'registration_closed', true);

  FOR i IN 1..p_n LOOP
    v_u := _rrr_p(p_t, 100 + i);
    INSERT INTO auth.users(id, instance_id, aud, role, email,
        encrypted_password, email_confirmed_at, created_at, updated_at)
      VALUES (v_u, '00000000-0000-0000-0000-000000000000',
              'authenticated', 'authenticated',
              'p' || p_t || '_' || i || '@rrr.local', '', now(), now(), now())
      ON CONFLICT (id) DO NOTHING;
    INSERT INTO public.tournament_participants(
        id, tournament_id, user_id, registration_status, registered_at)
      VALUES (_rrr_p(p_t, i), p_tid, v_u, 'confirmed',
              '2026-06-01 09:00:00+00'::timestamptz + (i || ' seconds')::interval);
  END LOOP;
END;
$$;

-- =====================================================================
-- AK-1: N=4 (even). No collision, status live, 3x2 = 6 matches, all
-- pairings unique.
-- =====================================================================
SELECT _rrr_as_pg();
SELECT _rrr_seed('1c1d0000-0000-0000-0000-0000000000a1'::uuid,
                 '1c1d0000-0000-0000-0000-0000000000b1'::uuid, 1, 4);

SELECT _rrr_as('1c1d0000-0000-0000-0000-0000000000b1'::uuid);
SELECT lives_ok(
  $$ SELECT public.tournament_start('1c1d0000-0000-0000-0000-0000000000a1'::uuid) $$,
  'AK-1 N=4: round_robin startet ohne Fehler (kein _tstart_ring_pkey 23505)'
);
SELECT _rrr_as_pg();

SELECT is(
  (SELECT status FROM public.tournaments
    WHERE id = '1c1d0000-0000-0000-0000-0000000000a1'::uuid),
  'live', 'AK-1 N=4: Turnier ist live');

SELECT is(
  (SELECT count(DISTINCT round_number)::int FROM public.tournament_matches
    WHERE tournament_id = '1c1d0000-0000-0000-0000-0000000000a1'::uuid),
  3, 'AK-1 N=4: genau 3 Runden (slot_count-1)');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = '1c1d0000-0000-0000-0000-0000000000a1'::uuid),
  6, 'AK-1 N=4: genau 6 Matches (3 Runden x 2)');

SELECT is(
  (SELECT max(c)::int FROM (
     SELECT count(*) AS c FROM public.tournament_matches
      WHERE tournament_id = '1c1d0000-0000-0000-0000-0000000000a1'::uuid
      GROUP BY round_number) r),
  2, 'AK-1 N=4: jede Runde hat 2 Matches');

-- Every unordered pairing appears exactly once: a complete single RR has
-- C(4,2) = 6 distinct pairs, one per match, none repeated, no NULL slot.
SELECT is(
  (SELECT count(DISTINCT (least(participant_a, participant_b),
                          greatest(participant_a, participant_b)))::int
     FROM public.tournament_matches
    WHERE tournament_id = '1c1d0000-0000-0000-0000-0000000000a1'::uuid),
  6, 'AK-1 N=4: 6 eindeutige Begegnungen (vollständiges Single-Round-Robin)');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = '1c1d0000-0000-0000-0000-0000000000a1'::uuid
      AND (participant_a IS NULL OR participant_b IS NULL)),
  0, 'AK-1 N=4: kein Match mit NULL-Teilnehmer (kein Freilos bei geradem N)');

-- =====================================================================
-- AK-2: N=5 (odd). slot_count = 6, 5 rounds, per round 2 real matches + 1
-- bye = 3 rows. The bye is normalised into participant_a (never NULL); only
-- participant_b may be NULL.
-- =====================================================================
SELECT _rrr_as_pg();
SELECT _rrr_seed('1c1d0000-0000-0000-0000-0000000000a2'::uuid,
                 '1c1d0000-0000-0000-0000-0000000000b1'::uuid, 2, 5);

SELECT _rrr_as('1c1d0000-0000-0000-0000-0000000000b1'::uuid);
SELECT lives_ok(
  $$ SELECT public.tournament_start('1c1d0000-0000-0000-0000-0000000000a2'::uuid) $$,
  'AK-2 N=5: startet ohne Fehler (kein not_null/pkey-Fehler beim Freilos)'
);
SELECT _rrr_as_pg();

SELECT is(
  (SELECT count(DISTINCT round_number)::int FROM public.tournament_matches
    WHERE tournament_id = '1c1d0000-0000-0000-0000-0000000000a2'::uuid),
  5, 'AK-2 N=5: genau 5 Runden (slot_count-1 = 6-1)');

-- Per round: 2 real matches (both slots set) + 1 bye (participant_b NULL).
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = '1c1d0000-0000-0000-0000-0000000000a2'::uuid
      AND participant_b IS NULL),
  5, 'AK-2 N=5: genau 5 Freilose (eines pro Runde)');

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = '1c1d0000-0000-0000-0000-0000000000a2'::uuid
      AND participant_a IS NOT NULL AND participant_b IS NOT NULL),
  10, 'AK-2 N=5: 10 reale Matches (2 pro Runde)');

-- The defining assertion: no match has participant_a NULL — the bye is
-- always rotated into participant_a, participant_b carries the NULL.
SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = '1c1d0000-0000-0000-0000-0000000000a2'::uuid
      AND participant_a IS NULL),
  0, 'AK-2 N=5: kein Match mit participant_a IS NULL (Freilos normalisiert)');

SELECT is(
  (SELECT status FROM public.tournaments
    WHERE id = '1c1d0000-0000-0000-0000-0000000000a2'::uuid),
  'live', 'AK-2 N=5: Turnier ist live');

-- =====================================================================
-- AK-3: N=2. 1 round, 1 match, no error.
-- =====================================================================
SELECT _rrr_as_pg();
SELECT _rrr_seed('1c1d0000-0000-0000-0000-0000000000a3'::uuid,
                 '1c1d0000-0000-0000-0000-0000000000b1'::uuid, 3, 2);

SELECT _rrr_as('1c1d0000-0000-0000-0000-0000000000b1'::uuid);
SELECT lives_ok(
  $$ SELECT public.tournament_start('1c1d0000-0000-0000-0000-0000000000a3'::uuid) $$,
  'AK-3 N=2: startet ohne Fehler'
);
SELECT _rrr_as_pg();

SELECT is(
  (SELECT count(*)::int FROM public.tournament_matches
    WHERE tournament_id = '1c1d0000-0000-0000-0000-0000000000a3'::uuid),
  1, 'AK-3 N=2: genau 1 Match in 1 Runde');

SELECT * FROM finish();
ROLLBACK;
