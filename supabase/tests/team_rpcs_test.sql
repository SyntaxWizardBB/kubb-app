-- RPC-Integrationstests fuer die Team-Mutationspfade (TASK-M3.1-T7).
--
-- Deckt die zehn SECURITY-DEFINER-RPCs aus den Migrationen
-- 20260615000002 (team_rpcs_a) und 20260615000003 (team_rpcs_b) ab:
--   * team_create / team_invite / team_invitation_respond     (T4)
--   * team_add_guest / team_remove_member / team_remove_guest
--   * team_leave / team_dissolve                              (T5)
-- plus die Inbox-Fan-Out-Kontrakte aus 20260615000004 (T6).
--
-- Auth-Kontext wird wie in `tournament_ko_rpcs.sql` ueber
-- `SET LOCAL request.jwt.claims` umgeschaltet (Supabase-Standard,
-- pgtap-feasibility.md §Option A). Direkt-Inserts in `auth.users`
-- legen die minimal noetigen Auth-Rows fuer FK-Pflichten an.
--
-- Der Helper `_seedTeam(...)` ist Kontrakt aus TASK-M3.1-T3
-- (`team_schema_test.sql`) und wird hier signaturkompatibel
-- redeklariert, weil pgTAP-Test-Files separate Transaktionen sind.

BEGIN;

SELECT plan(17);

-- ---------------------------------------------------------------------
-- Helpers: Auth-Switch + Fixture-Builder.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _team_as(p_user uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    jsonb_build_object('sub', p_user::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _team_as_anon() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'anon', true);
END;
$$;

-- Back to superuser for direct seeding (bypasses RLS / auth.users grants).
-- Needed after _team_as_anon(): set_config(..., true) is transaction-local,
-- so the anon role would otherwise leak into the next fixture DO block and
-- its auth.users INSERT (permission denied). Pattern as in
-- role_consolidation_test.sql (_rc_su).
CREATE OR REPLACE FUNCTION _team_su() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims', '', true);
  PERFORM set_config('role', 'postgres', true);
END;
$$;

-- Auth-User minimal viable shape (FK-Pflicht fuer team_memberships,
-- team_invitations etc.). Idempotent ueber ON CONFLICT.
CREATE OR REPLACE FUNCTION _team_mk_user(p_uid uuid) RETURNS uuid
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO auth.users (id, instance_id, aud, role, email,
                          encrypted_password, email_confirmed_at,
                          created_at, updated_at)
    VALUES (p_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'rpc-' || p_uid::text || '@test.local',
            '', now(), now(), now())
    ON CONFLICT (id) DO NOTHING;
  RETURN p_uid;
END;
$$;

-- Kontrakt-Helper aus T3 (signaturkompatibel) — legt User + Team +
-- Creator-Membership via Direct-Insert an (umgeht RLS, valide fuer
-- Fixture-Setup); produktiv laeuft das via `team_create`-RPC.
CREATE OR REPLACE FUNCTION _seedTeam(
  p_creator uuid, p_display_name text DEFAULT 'Hammer-Crew')
RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_team_id uuid := gen_random_uuid();
BEGIN
  PERFORM _team_mk_user(p_creator);
  INSERT INTO public.teams(id, display_name, league_membership, created_by)
    VALUES (v_team_id, p_display_name, 'B', p_creator);
  INSERT INTO public.team_memberships(id, team_id, user_id)
    VALUES (gen_random_uuid(), v_team_id, p_creator);
  RETURN v_team_id;
END;
$$;

-- ---------------------------------------------------------------------
-- 1. team_create — Happy-Path: Audit-Row + Creator-Membership.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_team_id uuid;
BEGIN
  PERFORM _team_mk_user(v_creator);
  PERFORM _team_as(v_creator);
  v_team_id := public.team_create('Create-Crew', 'A', NULL, NULL);
  CREATE TEMP TABLE _t7_create_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_team_id AS team_id;
END $$;

-- Verifikations-Reads laufen direkt auf den Tabellen — als postgres, da der
-- DO-Block oben zuletzt auf 'authenticated' stand (kein Direct-Read-Grant).
SELECT _team_su();

SELECT is(
  (SELECT count(*)::int FROM public.team_memberships
    WHERE team_id = (SELECT team_id FROM _t7_create_ctx)
      AND user_id = (SELECT creator FROM _t7_create_ctx)
      AND removed_at IS NULL),
  1,
  'team_create: Creator-Membership wird angelegt');

SELECT is(
  (SELECT count(*)::int FROM public.team_audit_events
    WHERE team_id = (SELECT team_id FROM _t7_create_ctx)
      AND kind = 'team_created'),
  1,
  'team_create: schreibt team_created Audit-Event');

-- ---------------------------------------------------------------------
-- 2. team_create — anonymer Caller → ERRCODE 42501.
-- ---------------------------------------------------------------------

SELECT _team_as_anon();
SELECT throws_ok(
  $$ SELECT public.team_create('Forbidden', 'B', NULL, NULL) $$,
  '42501', NULL,
  'team_create: anonymer Caller → 42501');

-- Reset to superuser: the anon role set above is transaction-local and
-- would break the auth.users seeding in the next fixture block.
SELECT _team_su();

-- ---------------------------------------------------------------------
-- 3. team_invite — Happy-Path + Inbox + Duplicate-Guard.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_invitee uuid := gen_random_uuid();
  v_team_id uuid;
  v_inv     uuid;
BEGIN
  v_team_id := _seedTeam(v_creator, 'Invite-Crew');
  PERFORM _team_mk_user(v_invitee);
  PERFORM _team_as(v_creator);
  v_inv := public.team_invite(v_team_id, v_invitee);
  CREATE TEMP TABLE _t7_inv_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_invitee AS invitee,
           v_team_id AS team_id, v_inv AS invitation_id;
END $$;

-- Direkt-Read auf team_invitations — als postgres (DO-Block endete als creator).
SELECT _team_su();

SELECT is(
  (SELECT state FROM public.team_invitations
    WHERE id = (SELECT invitation_id FROM _t7_inv_ctx)),
  'pending',
  'team_invite: Einladung im Zustand pending');

-- Inbox rows of OTHER users are invisible under RLS — assert as superuser.
SELECT _team_su();

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
    WHERE user_id = (SELECT invitee FROM _t7_inv_ctx)
      AND kind = 'team_invitation'),
  1,
  'team_invite: Inbox-Item team_invitation an Invitee');

SELECT _team_as((SELECT creator FROM _t7_inv_ctx));
SELECT throws_ok(
  format($$
    SELECT public.team_invite(%L::uuid, %L::uuid)
  $$, (SELECT team_id FROM _t7_inv_ctx),
       (SELECT invitee FROM _t7_inv_ctx)),
  'P0001', 'INVITATION_ALREADY_PENDING',
  'team_invite: zweite offene Einladung → P0001 INVITATION_ALREADY_PENDING');

-- ---------------------------------------------------------------------
-- 4. team_invitation_respond(accept=true) — Happy-Path + Membership.
-- ---------------------------------------------------------------------

DO $$
DECLARE
  v_ctx record;
BEGIN
  SELECT * INTO v_ctx FROM _t7_inv_ctx;
  PERFORM _team_as(v_ctx.invitee);
  PERFORM public.team_invitation_respond(v_ctx.invitation_id, true);
END $$;

-- Direkt-Read auf team_memberships — als postgres (DO-Block endete als invitee).
SELECT _team_su();

SELECT is(
  (SELECT count(*)::int FROM public.team_memberships
    WHERE team_id = (SELECT team_id FROM _t7_inv_ctx)
      AND user_id = (SELECT invitee FROM _t7_inv_ctx)
      AND removed_at IS NULL),
  1,
  'team_invitation_respond(accept): Membership-Row fuer Invitee');

-- ---------------------------------------------------------------------
-- 5. team_invitation_respond — Non-Invitee → ERRCODE 42501.
-- ---------------------------------------------------------------------

SELECT _team_su();

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_invitee uuid := gen_random_uuid();
  v_third   uuid := gen_random_uuid();
  v_team_id uuid;
  v_inv     uuid;
BEGIN
  v_team_id := _seedTeam(v_creator, 'Foreign-Crew');
  PERFORM _team_mk_user(v_invitee);
  PERFORM _team_mk_user(v_third);
  PERFORM _team_as(v_creator);
  v_inv := public.team_invite(v_team_id, v_invitee);
  CREATE TEMP TABLE _t7_foreign_ctx ON COMMIT DROP AS
    SELECT v_third AS third, v_inv AS invitation_id;
END $$;

SELECT _team_as((SELECT third FROM _t7_foreign_ctx));
SELECT throws_ok(
  format($$
    SELECT public.team_invitation_respond(%L::uuid, true)
  $$, (SELECT invitation_id FROM _t7_foreign_ctx)),
  '42501', NULL,
  'team_invitation_respond: Non-Invitee → 42501');

-- ---------------------------------------------------------------------
-- 6. team_add_guest — Happy-Path.
-- ---------------------------------------------------------------------

SELECT _team_su();

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_team_id uuid;
  v_guest   uuid;
BEGIN
  v_team_id := _seedTeam(v_creator, 'Guest-Crew');
  PERFORM _team_as(v_creator);
  v_guest := public.team_add_guest(v_team_id, 'Gast-Spieler');
  CREATE TEMP TABLE _t7_guest_ctx ON COMMIT DROP AS
    SELECT v_team_id AS team_id, v_guest AS guest_id;
END $$;

-- Direkt-Read auf team_guest_players — als postgres (DO-Block endete als creator).
SELECT _team_su();

SELECT is(
  (SELECT display_name FROM public.team_guest_players
    WHERE id = (SELECT guest_id FROM _t7_guest_ctx)
      AND removed_at IS NULL),
  'Gast-Spieler',
  'team_add_guest: Gast-Row mit display_name angelegt');

-- ---------------------------------------------------------------------
-- 7. team_remove_member — A entfernt B; C bekommt Inbox-Item; Audit.
-- ---------------------------------------------------------------------

SELECT _team_su();

DO $$
DECLARE
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_c uuid := gen_random_uuid();
  v_team_id uuid;
BEGIN
  v_team_id := _seedTeam(v_a, 'Remove-Crew');
  PERFORM _team_mk_user(v_b);
  PERFORM _team_mk_user(v_c);
  INSERT INTO public.team_memberships(team_id, user_id)
    VALUES (v_team_id, v_b), (v_team_id, v_c);
  PERFORM _team_as(v_a);
  PERFORM public.team_remove_member(v_team_id, v_b);
  CREATE TEMP TABLE _t7_remove_ctx ON COMMIT DROP AS
    SELECT v_a AS a, v_b AS b, v_c AS c, v_team_id AS team_id;
END $$;

-- Direkt-Reads auf team_memberships/team_audit_events — als postgres
-- (DO-Block endete als Aktor A).
SELECT _team_su();

SELECT isnt(
  (SELECT removed_at FROM public.team_memberships
    WHERE team_id = (SELECT team_id FROM _t7_remove_ctx)
      AND user_id = (SELECT b FROM _t7_remove_ctx)),
  NULL,
  'team_remove_member: removed_at gesetzt fuer entferntes Mitglied');

SELECT is(
  (SELECT count(*)::int FROM public.team_audit_events
    WHERE team_id = (SELECT team_id FROM _t7_remove_ctx)
      AND kind = 'member_removed'),
  1,
  'team_remove_member: member_removed Audit-Event geschrieben');

-- Inbox rows of OTHER users are invisible under RLS — assert as superuser.
SELECT _team_su();

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
    WHERE user_id = (SELECT c FROM _t7_remove_ctx)
      AND kind = 'team_member_removed'),
  1,
  'team_remove_member: Inbox-Item team_member_removed an C (OD-M3-01)');

-- ---------------------------------------------------------------------
-- 8. team_remove_member — Non-Member-Aktor → ERRCODE 42501.
-- ---------------------------------------------------------------------

SELECT _team_su();

DO $$
DECLARE
  v_creator uuid := gen_random_uuid();
  v_other   uuid := gen_random_uuid();
  v_team_id uuid;
BEGIN
  v_team_id := _seedTeam(v_creator, 'Guard-Crew');
  PERFORM _team_mk_user(v_other);
  CREATE TEMP TABLE _t7_guard_ctx ON COMMIT DROP AS
    SELECT v_creator AS creator, v_other AS other, v_team_id AS team_id;
END $$;

-- Fixture block above ran as postgres, so the temp table is postgres-owned;
-- it is read below while acting as 'authenticated'.
GRANT SELECT ON _t7_guard_ctx TO authenticated;

SELECT _team_as((SELECT other FROM _t7_guard_ctx));
SELECT throws_ok(
  format($$
    SELECT public.team_remove_member(%L::uuid, %L::uuid)
  $$, (SELECT team_id FROM _t7_guard_ctx),
       (SELECT creator FROM _t7_guard_ctx)),
  '42501', NULL,
  'team_remove_member: Non-Member-Aktor → 42501 (NOT_POOL_MEMBER)');

-- ---------------------------------------------------------------------
-- 9. team_leave — letztes Mitglied → Auto-Dissolve (FR-TEAM-19).
-- ---------------------------------------------------------------------

SELECT _team_su();

DO $$
DECLARE
  v_solo uuid := gen_random_uuid();
  v_team_id uuid;
BEGIN
  v_team_id := _seedTeam(v_solo, 'Solo-Crew');
  PERFORM _team_as(v_solo);
  PERFORM public.team_leave(v_team_id);
  CREATE TEMP TABLE _t7_leave_ctx ON COMMIT DROP AS
    SELECT v_team_id AS team_id;
END $$;

-- Direkt-Read auf teams — als postgres (DO-Block endete als Solo-Mitglied).
SELECT _team_su();

SELECT isnt(
  (SELECT dissolved_at FROM public.teams
    WHERE id = (SELECT team_id FROM _t7_leave_ctx)),
  NULL,
  'team_leave: letztes Mitglied → Team auto-dissolved (FR-TEAM-19)');

-- ---------------------------------------------------------------------
-- 10. team_dissolve ohne Consent aller → DISSOLVE_NEEDS_CONSENT.
-- ---------------------------------------------------------------------

SELECT _team_su();

DO $$
DECLARE
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_team_id uuid;
BEGIN
  v_team_id := _seedTeam(v_a, 'Dissolve-Need-Crew');
  PERFORM _team_mk_user(v_b);
  INSERT INTO public.team_memberships(team_id, user_id)
    VALUES (v_team_id, v_b);
  CREATE TEMP TABLE _t7_dn_ctx ON COMMIT DROP AS
    SELECT v_a AS a, v_b AS b, v_team_id AS team_id;
END $$;

-- Fixture block above ran as postgres, so the temp table is postgres-owned;
-- it is read below while acting as 'authenticated'.
GRANT SELECT ON _t7_dn_ctx TO authenticated;

SELECT _team_as((SELECT a FROM _t7_dn_ctx));
SELECT throws_ok(
  format($$
    SELECT public.team_dissolve(%L::uuid)
  $$, (SELECT team_id FROM _t7_dn_ctx)),
  '22023', NULL,
  'team_dissolve: ohne Consent aller → 22023 DISSOLVE_NEEDS_CONSENT');

-- ---------------------------------------------------------------------
-- 11. team_dissolve mit Consent aller → erfolgreich, dissolved_at gesetzt.
-- ---------------------------------------------------------------------

SELECT _team_su();

DO $$
DECLARE
  v_a uuid := gen_random_uuid();
  v_b uuid := gen_random_uuid();
  v_team_id uuid;
BEGIN
  v_team_id := _seedTeam(v_a, 'Dissolve-Ok-Crew');
  PERFORM _team_mk_user(v_b);
  INSERT INTO public.team_memberships(team_id, user_id)
    VALUES (v_team_id, v_b);
  -- B erteilt vorab Consent (Pattern aus team_rpcs_b.sql §dissolve).
  INSERT INTO public.team_audit_events(team_id, kind, actor_user_id, payload)
    VALUES (v_team_id, 'dissolve_consent', v_b, '{}'::jsonb);
  PERFORM _team_as(v_a);
  PERFORM public.team_dissolve(v_team_id);
  CREATE TEMP TABLE _t7_do_ctx ON COMMIT DROP AS
    SELECT v_team_id AS team_id, v_b AS b;
END $$;

-- Direkt-Read auf teams — als postgres (DO-Block endete als Aktor A).
SELECT _team_su();

SELECT isnt(
  (SELECT dissolved_at FROM public.teams
    WHERE id = (SELECT team_id FROM _t7_do_ctx)),
  NULL,
  'team_dissolve: mit Consent aller → dissolved_at gesetzt');

-- Inbox rows of OTHER users are invisible under RLS — assert as superuser.
SELECT _team_su();

SELECT is(
  (SELECT count(*)::int FROM public.user_inbox_messages
    WHERE user_id = (SELECT b FROM _t7_do_ctx)
      AND kind = 'team_dissolved'),
  1,
  'team_dissolve: Inbox-Item team_dissolved an verbleibendes Mitglied (OD-M3-01)');

SELECT * FROM finish();

ROLLBACK;
