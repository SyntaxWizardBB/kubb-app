-- Tournament feature — M2 KO seeding override RPC.
--
-- `tournament_set_seeding` lets the tournament creator upsert manual
-- seed numbers for participants of a given tournament. The map
-- `p_seeds` is a JSON object keyed by participant_id (uuid as text)
-- with positive integer seed numbers as values. Each entry becomes one
-- row in `tournament_seeding_overrides`; existing rows for the same
-- (tournament, participant) are updated in place. The KO bracket
-- generator (T3a/T3b) reads these overrides at bracket generation.
--
-- Validation order (fail-fast per T1b worker hint):
--   1. auth.uid() resolves                     -> 42501
--   2. tournament exists & caller = creator    -> 42501
--   3. p_seeds is a JSON object                -> 22023
--   4. every value is a positive integer       -> 22023
--   5. every key resolves to a participant of  -> P0001
--      this tournament                            (INVALID_PARTICIPANT)
--   6. no duplicate seed values in the call    -> P0001
--                                                 (DUPLICATE_SEED)
--   7. upsert rows + write one audit event
--
-- Seed-Uniqueness pro Turnier ist nicht per DB-Constraint erzwungen
-- (`tournament_seeding_overrides` hat PK(tournament_id, participant_id)
-- aber keinen UNIQUE auf seed_override). Wir validieren das hier
-- defensiv pro Call. Konflikte zwischen Calls (z.B. zwei nacheinander
-- gesetzte Overrides mit gleichem Seed) sind explizit erlaubt — der
-- letzte Call gewinnt, was dem "Map of intent" Modell entspricht.

CREATE OR REPLACE FUNCTION public.tournament_set_seeding(
  p_tournament_id uuid,
  p_seeds         jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_creator       uuid;
  v_key           text;
  v_value         jsonb;
  v_participant   uuid;
  v_seed          int;
  v_count         int := 0;
  v_missing       int;
  v_dup_count     int;
BEGIN
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'authentication required' USING ERRCODE = '42501';
  END IF;

  -- Defense-in-depth: SECURITY DEFINER bypasses RLS, so the creator
  -- check is enforced explicitly here.
  SELECT created_by INTO v_creator
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL THEN
    RAISE EXCEPTION 'tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;
  IF v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'only the tournament creator may set seeding'
      USING ERRCODE = '42501';
  END IF;

  IF p_seeds IS NULL OR jsonb_typeof(p_seeds) <> 'object' THEN
    RAISE EXCEPTION 'seeds must be a JSON object' USING ERRCODE = '22023';
  END IF;

  -- First pass: validate every (key, value) pair without writing.
  FOR v_key, v_value IN SELECT * FROM jsonb_each(p_seeds) LOOP
    IF jsonb_typeof(v_value) <> 'number' THEN
      RAISE EXCEPTION 'seed for % must be a number', v_key
        USING ERRCODE = '22023';
    END IF;
    v_seed := (v_value)::text::int;
    IF v_seed < 1 THEN
      RAISE EXCEPTION 'seed for % must be >= 1', v_key
        USING ERRCODE = '22023';
    END IF;
  END LOOP;

  -- Fail-fast: ensure every participant_id key actually belongs to
  -- this tournament. Without this, the FK on
  -- tournament_seeding_overrides.participant_id would raise 23503 with
  -- no contextual hint about *which* id was wrong.
  SELECT count(*) INTO v_missing
    FROM jsonb_object_keys(p_seeds) AS k(participant_id)
    WHERE NOT EXISTS (
      SELECT 1 FROM public.tournament_participants p
        WHERE p.id = k.participant_id::uuid
          AND p.tournament_id = p_tournament_id
    );
  IF v_missing > 0 THEN
    RAISE EXCEPTION 'INVALID_PARTICIPANT: % key(s) not part of this tournament',
      v_missing USING ERRCODE = 'P0001';
  END IF;

  -- Reject duplicate seed values in the same call.
  SELECT count(*) INTO v_dup_count
    FROM (
      SELECT (value)::text::int AS seed
        FROM jsonb_each(p_seeds)
      GROUP BY 1
      HAVING count(*) > 1
    ) d;
  IF v_dup_count > 0 THEN
    RAISE EXCEPTION 'DUPLICATE_SEED: same seed assigned to multiple participants'
      USING ERRCODE = 'P0001';
  END IF;

  -- Upsert each (participant, seed) row.
  FOR v_key, v_value IN SELECT * FROM jsonb_each(p_seeds) LOOP
    v_participant := v_key::uuid;
    v_seed        := (v_value)::text::int;

    INSERT INTO public.tournament_seeding_overrides(
        tournament_id, participant_id, seed_override, set_by)
      VALUES (p_tournament_id, v_participant, v_seed, v_caller)
      ON CONFLICT (tournament_id, participant_id) DO UPDATE
        SET seed_override = EXCLUDED.seed_override,
            set_by        = EXCLUDED.set_by,
            set_at        = now();
    v_count := v_count + 1;
  END LOOP;

  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'seeding_set',
      v_caller,
      jsonb_build_object(
        'seed_count', v_count,
        'seeds',      p_seeds));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'seed_count',    v_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_set_seeding(uuid, jsonb)
  TO authenticated;
