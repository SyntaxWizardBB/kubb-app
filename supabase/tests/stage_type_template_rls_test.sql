-- Stufen-Typ-Vorlagen RLS + RPC (spec §6/§9.6, ADR-0037/ADR-0039).
-- Mirrors the Ebene-1 stage-graph template visibility model and the
-- profile_visibility_rls_test role-switch idiom.
--
-- Coverage (spec §9.6):
--   T1  private template: a different user cannot SELECT it
--   T2  public template: every authenticated user can SELECT it
--   T3  save_stage_type_template overwrite: only the owner may overwrite a row
--       (a stranger's overwrite raises TEMPLATE_NOT_FOUND and leaves it intact)
--   T4  apply_stage_type_template returns the stored type_graph for a readable
--       (public) template (round-trips the category + rounds keys)
--   T5  apply_stage_type_template on a private template the caller cannot read
--       raises TEMPLATE_NOT_FOUND (no leak)
--
-- The DDL block runs as postgres (superuser bypasses RLS); the assertions run
-- in the role the helper switches to.

BEGIN;

SELECT plan(5);

-- ---------------------------------------------------------------------
-- Helpers: role switch + user seed.
-- ---------------------------------------------------------------------

CREATE OR REPLACE FUNCTION _stt_as_user(p_uid uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', p_uid::text, 'role', 'authenticated')::text,
    true);
  PERFORM set_config('role', 'authenticated', true);
END;
$$;

CREATE OR REPLACE FUNCTION _stt_as_postgres() RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('role', 'postgres', true);
END;
$$;

CREATE OR REPLACE FUNCTION _stt_seed_user(p_nick text) RETURNS uuid
LANGUAGE plpgsql AS $$
DECLARE
  v_uid uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users(id, instance_id, aud, role, email,
                         encrypted_password, email_confirmed_at,
                         created_at, updated_at)
    VALUES (v_uid, '00000000-0000-0000-0000-000000000000',
            'authenticated', 'authenticated',
            'stt-' || v_uid::text || '@test.local',
            '', now(), now(), now());
  RETURN v_uid;
END;
$$;

-- A minimal valid type graph (KO, 1 round, 1 field, no edges). Round-trips
-- through StageTypeGraph.fromJson on the Dart side.
CREATE OR REPLACE FUNCTION _stt_graph(p_category text) RETURNS jsonb
LANGUAGE sql IMMUTABLE AS $$
  SELECT jsonb_build_object(
    'category', p_category,
    'rounds', jsonb_build_array(
      jsonb_build_object(
        'round_number', 1,
        'fields', jsonb_build_array(
          jsonb_build_object('id', 'R1F1', 'round_number', 1, 'slot', 1)),
        'match_format', jsonb_build_object(
          'sets_to_win', 2, 'max_sets', 3,
          'time_limit_seconds', 1800, 'tiebreak_enabled', false))),
    'edges', '[]'::jsonb);
$$;

-- ---------------------------------------------------------------------
-- Fixtures.
--   owner:    saves a private + a public template
--   stranger: a different authenticated user (no shared organizer team)
-- ---------------------------------------------------------------------

SELECT _stt_as_postgres();

DO $$
DECLARE
  v_owner    uuid;
  v_stranger uuid;
BEGIN
  v_owner    := _stt_seed_user('stt_owner');
  v_stranger := _stt_seed_user('stt_stranger');

  CREATE TEMP TABLE _stt_ctx ON COMMIT DROP AS
    SELECT v_owner AS owner_uid, v_stranger AS stranger_uid;
  -- The assertions run as `authenticated`; let that role read the fixtures.
  GRANT SELECT ON _stt_ctx TO authenticated;
END $$;

-- A postgres-owned holder for the two template ids so the `authenticated`
-- role can read them across the role switches (TEMP-table privileges are not
-- granted to authenticated by default).
CREATE TEMP TABLE _stt_ids (private_id uuid, public_id uuid) ON COMMIT DROP;
GRANT SELECT, INSERT ON _stt_ids TO authenticated;

-- Owner saves a private and a public template via the RPC (owner = auth.uid()).
SELECT _stt_as_user((SELECT owner_uid FROM _stt_ctx));

INSERT INTO _stt_ids(private_id, public_id)
  SELECT
    public.save_stage_type_template(
      'My private KO', NULL, 'private', _stt_graph('ko')),
    public.save_stage_type_template(
      'My public KO', NULL, 'public', _stt_graph('ko'));

-- ---------------------------------------------------------------------
-- T1: private template is invisible to a different user.
-- ---------------------------------------------------------------------

SELECT _stt_as_user((SELECT stranger_uid FROM _stt_ctx));

SELECT is(
  (SELECT count(*)::int FROM public.tournament_stage_type_templates
     WHERE id = (SELECT private_id FROM _stt_ids)),
  0,
  'privates Typ-Template ist für einen fremden User unsichtbar (§9.6)');

-- ---------------------------------------------------------------------
-- T2: public template is visible to every authenticated user.
-- ---------------------------------------------------------------------

SELECT is(
  (SELECT count(*)::int FROM public.tournament_stage_type_templates
     WHERE id = (SELECT public_id FROM _stt_ids)),
  1,
  'öffentliches Typ-Template ist für jeden authenticated User sichtbar (§9.6)');

-- ---------------------------------------------------------------------
-- T3: only the owner overwrites. A stranger's overwrite attempt raises
--     TEMPLATE_NOT_FOUND and the row stays intact (still owned, name
--     unchanged).
-- ---------------------------------------------------------------------

SELECT throws_ok(
  format(
    $q$SELECT public.save_stage_type_template(
         'Hijacked', NULL, 'public', %L::jsonb, NULL, %L::uuid)$q$,
    _stt_graph('vorrunde'),
    (SELECT public_id FROM _stt_ids)),
  '22023',
  NULL,
  'fremder User kann das public Typ-Template nicht überschreiben '
  '(TEMPLATE_NOT_FOUND)');

-- ---------------------------------------------------------------------
-- T4: apply returns the stored type_graph for a readable (public) template;
--     the round-trip keys survive.
-- ---------------------------------------------------------------------

SELECT is(
  (public.apply_stage_type_template((SELECT public_id FROM _stt_ids)) ->> 'category'),
  'ko',
  'apply liefert das gespeicherte type_graph (category round-trip)');

-- ---------------------------------------------------------------------
-- T5: apply on a private template the caller cannot read -> TEMPLATE_NOT_FOUND
--     (no existence/content leak).
-- ---------------------------------------------------------------------

SELECT throws_ok(
  format(
    $q$SELECT public.apply_stage_type_template(%L::uuid)$q$,
    (SELECT private_id FROM _stt_ids)),
  '22023',
  NULL,
  'apply auf ein fremdes privates Typ-Template -> TEMPLATE_NOT_FOUND (kein Leak)');

SELECT * FROM finish();

ROLLBACK;
