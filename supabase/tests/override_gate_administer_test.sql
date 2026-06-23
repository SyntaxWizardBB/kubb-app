-- Freeze the tournament_organizer_override administer gate (P2-S gate split,
-- migration 20261283000000 / 20261314000000): the live-intervention gate is
-- tournament_caller_can_administer, i.e. creator OR an active owner/admin/
-- referee of the tournament's organizer_team. This pins two ends of that gate
-- so a later change cannot silently narrow it back to creator-only or widen it
-- to any authenticated user:
--   * a club ADMIN who is NOT the tournament creator may override (lives_ok);
--   * a stranger with no membership is rejected with 42501.
--
-- No migration — the gate already exists; this is a regression freeze.
-- pgTAP runs transiently in BEGIN..ROLLBACK; nothing is persisted.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(2);

CREATE OR REPLACE FUNCTION _oga_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _oga_as_pg() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

CREATE OR REPLACE FUNCTION _oga_mk_user(p_uid uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (p_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'u-' || p_uid::text || '@oga.l', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;
  RETURN p_uid;
END;
$$;

-- The admin match (overridden by the non-creator club admin) and a separate
-- stranger match (rejected). Distinct matches so the lives_ok call cannot
-- pollute the stranger's status precondition.
CREATE OR REPLACE FUNCTION _oga_match_admin() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-0000-0d0d-0000000000a1'::uuid $$;
CREATE OR REPLACE FUNCTION _oga_match_stranger() RETURNS uuid
LANGUAGE sql IMMUTABLE AS $$ SELECT '00000000-0000-0000-0d0d-0000000000b1'::uuid $$;

DO $fixture$
DECLARE
  v_tid     uuid := '0a0a0a0a-0000-0000-0000-0000000000e1'::uuid;
  v_team    uuid := '0c1b0c1b-0000-0000-0000-0000000000c1'::uuid;
  v_creator uuid := '0a0a0a0a-0000-0000-0000-0000000000c1'::uuid;
  v_admin   uuid := '0a0a0a0a-0000-0000-0000-0000000000a2'::uuid; -- club admin, NOT creator
  v_pa      uuid := '00000000-0000-0000-0c0c-0000000000a1'::uuid;
  v_pb      uuid := '00000000-0000-0000-0c0c-0000000000b1'::uuid;
  v_ua      uuid := '00000000-0000-0000-0b0b-000000000001'::uuid;
  v_ub      uuid := '00000000-0000-0000-0b0b-000000000002'::uuid;
BEGIN
  PERFORM _oga_mk_user(v_creator);
  PERFORM _oga_mk_user(v_admin);
  PERFORM _oga_mk_user(v_ua);
  PERFORM _oga_mk_user(v_ub);

  INSERT INTO public.organizer_teams(id, display_name, created_by)
    VALUES (v_team, 'Override-Gate-Club', v_creator);

  -- The admin is an active owner/admin/referee member but NOT the creator.
  INSERT INTO public.team_members(organizer_team_id, user_id, roles)
    VALUES (v_team, v_admin, ARRAY['admin']::text[]);

  INSERT INTO public.tournaments(
      id, created_by, organizer_team_id, display_name, team_size,
      min_participants, max_participants, format, scoring, match_format,
      status, public)
    VALUES (v_tid, v_creator, v_team, 'Override Gate Freeze', 1, 2, 32,
            'round_robin', 'ekc',
            jsonb_build_object('round_time_seconds', 1800), 'live', true);

  INSERT INTO public.tournament_stages(
      id, tournament_id, node_id, type, config, seeding, status)
    VALUES (gen_random_uuid(), v_tid, 'gp1', 'group_phase',
            '{}'::jsonb, 'manual', 'active');

  INSERT INTO public.tournament_participants(
      id, tournament_id, user_id, registration_status, seed, group_label)
  VALUES
    (v_pa, v_tid, v_ua, 'confirmed', 1, 'A'),
    (v_pb, v_tid, v_ub, 'confirmed', 2, 'A');

  INSERT INTO public.tournament_matches(
      id, tournament_id, round_number, match_number_in_round,
      participant_a, participant_b, phase, status, group_label, consensus_round)
  VALUES
    (_oga_match_admin(),    v_tid, 1, 1, v_pa, v_pb, 'group',
       'awaiting_results', 'A', 1),
    (_oga_match_stranger(), v_tid, 1, 2, v_pa, v_pb, 'group',
       'awaiting_results', 'A', 1);
END;
$fixture$;

-- ── Club admin (non-creator) may override ────────────────────────────────
SELECT _oga_as('0a0a0a0a-0000-0000-0000-0000000000a2');

SELECT lives_ok(
  $$ SELECT public.tournament_organizer_override(
       _oga_match_admin(),
       '[{"basekubbs_a":6,"basekubbs_b":1,"winner":"A"}]'::jsonb,
       'club admin on-site') $$,
  'club admin (active member, not the creator) may administer the override');

-- ── Stranger with no membership is rejected with 42501 ───────────────────
SELECT _oga_as('00000000-0000-0000-0b0b-000000000001'); -- player ua: not creator, not a member

SELECT throws_ok(
  $$ SELECT public.tournament_organizer_override(
       _oga_match_stranger(),
       '[{"basekubbs_a":6,"basekubbs_b":1,"winner":"A"}]'::jsonb,
       'stranger attempt') $$,
  '42501',
  'caller cannot administer this tournament',
  'a non-creator non-member is rejected with 42501');

SELECT _oga_as_pg();

SELECT * FROM finish();
ROLLBACK;
