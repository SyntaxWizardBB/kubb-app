-- BR-5 Roster-Cross-Constraint Trigger-Tests (TASK-M3.2-T2).
--
-- Verifiziert den Trigger aus M3.2-T1 gegen die drei Cases aus
-- `tasks.md` §M3.2-T2 (Doppel-Roster blockiert, Cross-Tournament OK,
-- replaced_at schliesst Slot). Schema-Erwartung exakt aus
-- `architecture.md` §3.3 (Spaltennamen + ERRCODE 23P01 sind Contract).
-- Concurrency-Case (Acceptance-Punkt 4) ist Single-Session-pgTAP-untauglich
-- und laut `tasks.md` Notes ausklammerbar.

BEGIN;

SELECT plan(3);

CREATE OR REPLACE FUNCTION _br5_user(p uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email,
      encrypted_password, email_confirmed_at, created_at, updated_at)
    VALUES (p, '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated',
      'br5-' || p::text || '@test.local', '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;
END; $$;

-- Fixture: User U in zwei Teams (A,B); zwei Turniere T1,T2; je ein
-- Team-Participant. Slot fuer U in Team A / T1 wird initial belegt.
DO $$
DECLARE
  v_u uuid := gen_random_uuid(); v_ca uuid := gen_random_uuid();
  v_cb uuid := gen_random_uuid(); v_cr uuid := gen_random_uuid();
  v_a uuid := gen_random_uuid(); v_b uuid := gen_random_uuid();
  v_t1 uuid := gen_random_uuid(); v_t2 uuid := gen_random_uuid();
  v_pa1 uuid := gen_random_uuid(); v_pb1 uuid := gen_random_uuid();
  v_pb2 uuid := gen_random_uuid();
BEGIN
  PERFORM _br5_user(v_u); PERFORM _br5_user(v_ca);
  PERFORM _br5_user(v_cb); PERFORM _br5_user(v_cr);

  INSERT INTO public.teams(id, display_name, league_membership, created_by)
    VALUES (v_a, 'BR5-A', 'B', v_ca), (v_b, 'BR5-B', 'B', v_cb);
  INSERT INTO public.team_memberships(id, team_id, user_id) VALUES
    (gen_random_uuid(), v_a, v_ca), (gen_random_uuid(), v_b, v_cb),
    (gen_random_uuid(), v_a, v_u),  (gen_random_uuid(), v_b, v_u);

  INSERT INTO public.tournaments(id, created_by, display_name, team_size,
      min_participants, max_participants, format, scoring, match_format, status)
    VALUES
      (v_t1, v_cr, 'BR5-T1', 6, 2, 64, 'round_robin', 'ekc',
       '{"format":"best_of_1"}'::jsonb, 'registration_open'),
      (v_t2, v_cr, 'BR5-T2', 6, 2, 64, 'round_robin', 'ekc',
       '{"format":"best_of_1"}'::jsonb, 'registration_open');

  INSERT INTO public.tournament_participants(id, tournament_id, team_id,
      user_id, registration_status) VALUES
    (v_pa1, v_t1, v_a, v_ca, 'confirmed'),
    (v_pb1, v_t1, v_b, v_cb, 'confirmed'),
    (v_pb2, v_t2, v_b, v_cb, 'confirmed');

  INSERT INTO public.tournament_roster_slots(
      participant_id, slot_index, member_user_id, assigned_by)
    VALUES (v_pa1, 1, v_u, v_ca);

  CREATE TEMP TABLE _br5_ctx ON COMMIT DROP AS
    SELECT v_u AS u, v_ca AS ca, v_pa1 AS pa1, v_pb1 AS pb1, v_pb2 AS pb2;
END $$;

-- Case 1: Doppel-Roster im selben Turnier -> 23P01.
SELECT throws_ok(format($$
    INSERT INTO public.tournament_roster_slots(
        participant_id, slot_index, member_user_id, assigned_by)
      VALUES (%L::uuid, 1, %L::uuid, %L::uuid) $$,
    (SELECT pb1 FROM _br5_ctx), (SELECT u FROM _br5_ctx),
    (SELECT ca FROM _br5_ctx)),
  '23P01', NULL,
  'BR-5: zweiter offener Slot fuer U im selben Turnier -> 23P01');

-- Case 2: Cross-Tournament -> OK.
SELECT lives_ok(format($$
    INSERT INTO public.tournament_roster_slots(
        participant_id, slot_index, member_user_id, assigned_by)
      VALUES (%L::uuid, 1, %L::uuid, %L::uuid) $$,
    (SELECT pb2 FROM _br5_ctx), (SELECT u FROM _br5_ctx),
    (SELECT ca FROM _br5_ctx)),
  'BR-5: U im Roster eines anderen Turniers -> erlaubt');

-- Case 3: replaced_at schliesst Slot -> Re-Roster OK.
UPDATE public.tournament_roster_slots
   SET replaced_at = now(), replaced_by = (SELECT ca FROM _br5_ctx)
 WHERE participant_id = (SELECT pa1 FROM _br5_ctx) AND slot_index = 1;

SELECT lives_ok(format($$
    INSERT INTO public.tournament_roster_slots(
        participant_id, slot_index, member_user_id, assigned_by)
      VALUES (%L::uuid, 1, %L::uuid, %L::uuid) $$,
    (SELECT pb1 FROM _br5_ctx), (SELECT u FROM _br5_ctx),
    (SELECT ca FROM _br5_ctx)),
  'BR-5: Slot mit replaced_at gilt als geschlossen, U wieder verfuegbar');

SELECT * FROM finish();

ROLLBACK;
