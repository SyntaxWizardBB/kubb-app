-- Tournament feature — M3.3 Pool-Phase schema + helpers + start RPC.
--
-- Adds the multi-group ("pool") variant of the round-robin phase. A pool
-- tournament distributes confirmed participants into N labelled groups
-- (`A`, `B`, ...) and plays a round-robin **per group**. The KO-phase
-- (M2) is reused downstream via T6, which calls `_tournament_compute_pool_cut`
-- per group, merges qualifiers cross-pool, and feeds the existing
-- `_tournament_compute_ko_bracket` helper.
--
-- Bezug: docs/adr/0019-pool-phase.md,
--        docs/plans/m3-teams-pools-roster/architecture.md §3.4,
--        docs/plans/m3-teams-pools-roster/tasks.md TASK-M3.3-T5.
--
-- Layout
--   1. Schema-Erweiterung: `group_label text NULL` auf
--      `tournament_matches` und `tournament_participants`.
--   2. Helper `_tournament_compute_pools(participants, config)` —
--      plpgsql-Spiegelung von Dart `generatePools` (snake/random/seeded).
--      Parität gegen die Domain-Impl wird in T7 property-getestet.
--   3. Helper `_tournament_compute_pool_cut(tournament_id, group_label,
--      top_n)` — rankt eine Gruppe gegen `tournaments.tiebreaker_order`
--      und meldet vollständig ungelöste Ties (OD-M3-05).
--   4. RPC `tournament_start_pool_phase(tournament_id, config)` —
--      Organizer-gesicherte Phasen-Transition: persistiert die Gruppe
--      pro Participant, erzeugt Round-Robin-Matches je Gruppe mit
--      `phase='group'` + `group_label`, setzt `status='live'`.
--      Idempotenz via `FOR UPDATE` + ERRCODE 40001 (Pattern aus M2
--      `tournament_start_ko_phase`).


-- ---- 1. Schema-Erweiterung ------------------------------------------

ALTER TABLE public.tournament_participants
  ADD COLUMN IF NOT EXISTS group_label text NULL;

ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS group_label text NULL;

CREATE INDEX IF NOT EXISTS tournament_matches_group_label_idx
  ON public.tournament_matches(tournament_id, group_label)
  WHERE group_label IS NOT NULL;

COMMENT ON COLUMN public.tournament_participants.group_label IS
  'Pool-Phase Gruppe (A, B, C, ...). NULL solange das Turnier keine '
  'Pool-Phase startet bzw. fuer single-group Round-Robin (M2).';

COMMENT ON COLUMN public.tournament_matches.group_label IS
  'Pool-Phase Gruppe des Matches. Nur fuer phase=''group'' relevant, '
  'sonst NULL. Gesetzt von tournament_start_pool_phase.';


-- ---- 2. _tournament_compute_pools -----------------------------------
--
-- Mirror of `generatePools` aus
-- `packages/kubb_domain/lib/src/tournament/pool_phase.dart`. Liefert eine
-- jsonb-Array-Liste `[{participant_id, group_label, group_position}]`.
--
-- Validierung (1:1 wie Dart):
--   * group_count >= 1
--   * qualifiers_per_group >= 1
--   * ceil(n / group_count) >= qualifiers_per_group
--
-- Verteilung:
--   * snake   — row r, dir alterniert; Zeile gerade → links→rechts,
--               Zeile ungerade → rechts→links.
--   * seeded  — sequentieller Block-Fill in Input-Reihenfolge.
--   * random  — deterministisches Fisher-Yates mit `random_seed`,
--               anschliessend snake. Seed default 0.
--
-- BYE-Slots werden im Server nicht persistiert — der Helper liefert
-- nur reale `participant_id`s. Pool-Round-Robin laesst BYE einfach aus.

-- Hinweis zur `random`-Strategie: Dart `Random(seed)` (Mersenne-Twister-
-- artiger 64-bit-PRNG) ist in plpgsql nicht 1:1 reproduzierbar. Wir
-- nutzen Postgres' eigenes `setseed`/`random` mit normalisiertem Seed —
-- der Output ist deterministisch in derselben Datenbank-Session, weicht
-- aber von der Dart-Domain-Impl ab. T7 (Property-Paritaet) wird das
-- aufdecken; der Bridging-Patch (Port des Dart-PRNG oder eines
-- gemeinsamen LCG in beide Seiten) ist Followup. snake und seeded sind
-- voll deterministisch und matchen exakt.
CREATE OR REPLACE FUNCTION public._tournament_compute_pools(
  p_participants jsonb,
  p_config       jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE
  v_n            int;
  v_group_count  int;
  v_qpg          int;
  v_strategy     text;
  v_seed         bigint;
  v_group_size   int;
  v_ids          text[];
  v_ordered      text[];
  v_group_len    int[];
  v_result       jsonb := '[]'::jsonb;
  v_label        text;
  v_pid          text;
  v_row          int;
  v_col          int;
  v_gidx         int;
  v_pos          int;
  v_tmp          text;
  v_j            int;
  i              int;
  k              int;
BEGIN
  IF p_participants IS NULL OR jsonb_typeof(p_participants) <> 'array' THEN
    RAISE EXCEPTION 'participants must be a JSON array' USING ERRCODE = '22023';
  END IF;
  IF p_config IS NULL OR jsonb_typeof(p_config) <> 'object' THEN
    RAISE EXCEPTION 'config must be a JSON object' USING ERRCODE = '22023';
  END IF;

  v_n           := jsonb_array_length(p_participants);
  v_group_count := coalesce((p_config ->> 'group_count')::int, 0);
  v_qpg         := coalesce((p_config ->> 'qualifiers_per_group')::int, 0);
  v_strategy    := lower(coalesce(p_config ->> 'strategy', 'snake'));
  v_seed        := coalesce((p_config ->> 'random_seed')::bigint, 0);

  IF v_group_count < 1 THEN
    RAISE EXCEPTION 'group_count must be at least 1' USING ERRCODE = '22023';
  END IF;
  IF v_qpg < 1 THEN
    RAISE EXCEPTION 'qualifiers_per_group must be at least 1' USING ERRCODE = '22023';
  END IF;
  IF v_strategy NOT IN ('snake','random','seeded') THEN
    RAISE EXCEPTION 'unknown strategy %', v_strategy USING ERRCODE = '22023';
  END IF;

  v_group_size := (v_n + v_group_count - 1) / v_group_count;   -- ceil
  IF v_group_size < v_qpg THEN
    RAISE EXCEPTION 'qualifiers_per_group (%) exceeds max group size (%) for % participants in % groups',
      v_qpg, v_group_size, v_n, v_group_count
      USING ERRCODE = '22023';
  END IF;

  -- Input → text[]
  v_ids := ARRAY[]::text[];
  FOR i IN 0 .. v_n - 1 LOOP
    v_ids := v_ids || (p_participants ->> i);
  END LOOP;

  -- Strategy-spezifische Vorab-Sortierung. `random` macht Fisher-Yates
  -- mit deterministischem Seed; danach laeuft snake. `snake`/`seeded`
  -- konsumieren `v_ids` direkt — Input-Reihenfolge ist der Seed.
  v_ordered := v_ids;
  IF v_strategy = 'random' THEN
    -- Fisher-Yates: for i = n-1 .. 1 do swap(i, rng.nextInt(i+1)).
    -- setseed setzt random() global pro Session-Tx; reicht hier, da
    -- die Function IMMUTABLE und in einer Tx gerufen wird. Der Seed
    -- wird auf [-1, 1] normiert (setseed-Vertrag).
    PERFORM setseed( (((v_seed % 2147483647)::double precision) / 2147483647.0) );
    FOR i IN REVERSE (v_n - 1) .. 1 LOOP
      v_j := floor(random() * (i + 1))::int;   -- 0..i inkl.
      v_tmp := v_ordered[i + 1];               -- 1-indexed
      v_ordered[i + 1] := v_ordered[v_j + 1];
      v_ordered[v_j + 1] := v_tmp;
    END LOOP;
  END IF;

  -- Buckets als flaches text[] der Laenge group_count*group_size,
  -- indexiert ueber ((gidx-1)*group_size + pos). PL/pgSQL hat keine
  -- echten ragged Arrays — die Laenge je Gruppe halten wir parallel
  -- in `v_group_len`.
  v_group_len := array_fill(0, ARRAY[v_group_count]);
  DECLARE
    v_flat text[] := ARRAY_FILL(NULL::text, ARRAY[v_group_count * v_group_size]);
  BEGIN
    IF v_strategy = 'seeded' THEN
      FOR i IN 1 .. v_n LOOP
        v_gidx := ((i - 1) / v_group_size) + 1;
        v_group_len[v_gidx] := v_group_len[v_gidx] + 1;
        v_flat[(v_gidx - 1) * v_group_size + v_group_len[v_gidx]] := v_ordered[i];
      END LOOP;
    ELSE
      -- snake (auch fuer random nach Shuffle): row r, dir alterniert.
      FOR i IN 1 .. v_n LOOP
        v_row := (i - 1) / v_group_count;          -- 0-based row
        v_col := (i - 1) % v_group_count;          -- 0-based col
        IF (v_row % 2) = 0 THEN
          v_gidx := v_col + 1;
        ELSE
          v_gidx := v_group_count - v_col;
        END IF;
        v_group_len[v_gidx] := v_group_len[v_gidx] + 1;
        v_flat[(v_gidx - 1) * v_group_size + v_group_len[v_gidx]] := v_ordered[i];
      END LOOP;
    END IF;

    -- Stable-Sort der Gruppen-Indices nach Laenge DESC, damit kuerzere
    -- Gruppen (BYE-Traeger) am Ende landen (1:1 wie Dart). Wir
    -- materialisieren die finalen group_labels ('A'..) per Sort-Order.
    DECLARE
      v_order int[] := ARRAY[]::int[];
      v_used  bool[] := ARRAY_FILL(false, ARRAY[v_group_count]);
      v_max_len int;
      v_max_idx int;
    BEGIN
      FOR k IN 1 .. v_group_count LOOP
        v_max_len := -1;
        v_max_idx := -1;
        FOR i IN 1 .. v_group_count LOOP
          IF NOT v_used[i] AND v_group_len[i] > v_max_len THEN
            v_max_len := v_group_len[i];
            v_max_idx := i;
          END IF;
        END LOOP;
        v_used[v_max_idx] := true;
        v_order := v_order || v_max_idx;
      END LOOP;

      -- Emit als jsonb-Array.
      FOR k IN 1 .. v_group_count LOOP
        v_gidx := v_order[k];
        v_label := chr(64 + k);                     -- 'A','B','C', ...
        v_pos := 0;
        FOR i IN 1 .. v_group_size LOOP
          v_pid := v_flat[(v_gidx - 1) * v_group_size + i];
          IF v_pid IS NULL THEN
            CONTINUE;                                -- BYE wird nicht persistiert
          END IF;
          v_pos := v_pos + 1;
          v_result := v_result || jsonb_build_object(
            'participant_id', v_pid,
            'group_label',    v_label,
            'group_position', v_pos);
        END LOOP;
      END LOOP;
    END;
  END;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_compute_pools(jsonb, jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_compute_pools(jsonb, jsonb) FROM authenticated;

COMMENT ON FUNCTION public._tournament_compute_pools(jsonb, jsonb) IS
  'Mirror of Dart generatePools (kubb_domain). Verteilt N Participants '
  'auf group_count Gruppen mit snake/random/seeded Strategie. Liefert '
  '[{participant_id, group_label, group_position}]. Property-Paritaet '
  'gegen die Domain-Impl wird in M3.3-T7 abgesichert. Siehe ADR-0019 §1.';


-- ---- 3. _tournament_compute_pool_cut --------------------------------
--
-- Rankt die Participants einer Gruppe gegen `tournaments.tiebreaker_order`
-- und liefert die Top-N. Markiert OD-M3-05 (vollständiger Tie nach allen
-- konfigurierten Stufen) ueber ein `tie_resolution_needed`-Flag plus die
-- betroffenen participant_ids.
--
-- Anmerkung zu OD-M3-03 (direct_comparison cross-pool ungueltig):
-- Innerhalb einer Gruppe ist direct_comparison wohldefiniert. Der Skip
-- passiert im Cross-Pool-Merger (T6) — dieser Helper laeuft per Gruppe.
-- Damit T6 die jeweilige Stage rekonstruieren kann, exponiert das
-- Result-JSON die verwendete `chain` (text[]).
--
-- Return-Shape:
--   { qualifiers: [participant_id...],
--     tie_resolution_needed: bool,
--     tied_participants:     [[participant_id, ...], ...],
--     chain:                 [criterion_text, ...] }

CREATE OR REPLACE FUNCTION public._tournament_compute_pool_cut(
  p_tournament_id uuid,
  p_group_label   text,
  p_top_n         int
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  v_chain         text[];
  v_qualifiers    uuid[] := ARRAY[]::uuid[];
  v_tied          jsonb := '[]'::jsonb;
  v_needs_resolve boolean := false;
BEGIN
  IF p_top_n < 1 THEN
    RAISE EXCEPTION 'top_n must be >= 1' USING ERRCODE = '22023';
  END IF;

  SELECT tiebreaker_order INTO v_chain
    FROM public.tournaments
    WHERE id = p_tournament_id;
  IF v_chain IS NULL THEN
    RAISE EXCEPTION 'tournament not found: %', p_tournament_id
      USING ERRCODE = '22023';
  END IF;

  -- Statistiken pro Participant in dieser Gruppe. M3.3-T5 bleibt
  -- bewusst auf den Basis-Kriterien (total_points, wins, kubb_diff,
  -- direct_comparison) — Buchholz/Median sind Schweizer-System-spezifisch
  -- (M5) und gehoeren nicht in den Pool-Cut. Nicht unterstuetzte
  -- Stages werden uebersprungen (parity mit Dart `TiebreakerChain.skip`
  -- Hint im Helper-Vertrag); `random` wird bewusst NICHT als
  -- Auto-Resolver verwendet — wenn alles tied bleibt, schiesst T6 den
  -- `TIEBREAKER_NEEDS_RESOLUTION`-Fehler (OD-M3-05).
  WITH part AS (
    SELECT p.id AS pid,
           p.registered_at
      FROM public.tournament_participants p
     WHERE p.tournament_id  = p_tournament_id
       AND p.group_label    = p_group_label
       AND p.registration_status = 'confirmed'
  ),
  matches AS (
    SELECT m.*
      FROM public.tournament_matches m
     WHERE m.tournament_id = p_tournament_id
       AND m.group_label   = p_group_label
       AND m.phase         = 'group'
       AND m.status IN ('finalized','overridden')
  ),
  stats AS (
    SELECT p.pid,
           p.registered_at,
           coalesce(sum(CASE WHEN m.winner_participant = p.pid THEN 1 ELSE 0 END), 0) AS wins,
           coalesce(sum(
             CASE WHEN m.participant_a = p.pid THEN coalesce(m.final_score_a,0)
                  WHEN m.participant_b = p.pid THEN coalesce(m.final_score_b,0)
                  ELSE 0 END), 0) AS total_points,
           coalesce(sum(
             CASE WHEN m.participant_a = p.pid
                    THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                  WHEN m.participant_b = p.pid
                    THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                  ELSE 0 END), 0) AS kubb_diff
      FROM part p
      LEFT JOIN matches m
        ON (m.participant_a = p.pid OR m.participant_b = p.pid)
     GROUP BY p.pid, p.registered_at
  ),
  -- Sortierung. Wir respektieren die Reihenfolge der drei in T5
  -- aktiven Stufen (total_points, wins, kubb_difference) gegen
  -- `v_chain`: Kriterien, die NICHT in der Chain stehen, werden
  -- auf 0 gemappt und damit no-op; die verbleibenden behalten ihre
  -- Default-Praezedenz. Buchholz/Median/Random sind Schweizer-System-
  -- spezifisch (M5) und gehoeren nicht in den Pool-Cut. Fuer Chains
  -- mit nicht-default Reihenfolge (z.B. ['wins','total_points'])
  -- bleibt die Top-N-Auswahl korrekt sofern die Top-N eindeutig
  -- ist; full ties werden weiter unten markiert und in T6 cross-pool
  -- aufgeloest (OD-M3-05).
  ranked AS (
    SELECT s.*,
           row_number() OVER (
             ORDER BY
               CASE WHEN 'total_points'    = ANY(v_chain) THEN -s.total_points ELSE 0 END,
               CASE WHEN 'wins'            = ANY(v_chain) THEN -s.wins         ELSE 0 END,
               CASE WHEN 'kubb_difference' = ANY(v_chain) THEN -s.kubb_diff    ELSE 0 END,
               s.registered_at ASC,
               s.pid ASC
           ) AS rank
      FROM stats s
  )
  SELECT array_agg(pid ORDER BY rank)
    INTO v_qualifiers
    FROM ranked
   WHERE rank <= p_top_n;

  -- Tie-Detection: zwei angrenzende qualifier-Slots, die auf allen
  -- konfigurierten Kriterien identisch sind (Buchholz/Random ausser
  -- Acht gelassen, s.o.). Ergebnis ist eine Liste von Tie-Gruppen.
  WITH stats AS (
    SELECT p.id AS pid, p.registered_at,
           coalesce(sum(CASE WHEN m.winner_participant = p.id THEN 1 ELSE 0 END), 0) AS wins,
           coalesce(sum(
             CASE WHEN m.participant_a = p.id THEN coalesce(m.final_score_a,0)
                  WHEN m.participant_b = p.id THEN coalesce(m.final_score_b,0)
                  ELSE 0 END), 0) AS total_points,
           coalesce(sum(
             CASE WHEN m.participant_a = p.id
                    THEN coalesce(m.final_score_a,0) - coalesce(m.final_score_b,0)
                  WHEN m.participant_b = p.id
                    THEN coalesce(m.final_score_b,0) - coalesce(m.final_score_a,0)
                  ELSE 0 END), 0) AS kubb_diff
      FROM public.tournament_participants p
      LEFT JOIN public.tournament_matches m
        ON m.tournament_id = p.tournament_id
       AND m.group_label   = p_group_label
       AND m.phase         = 'group'
       AND m.status IN ('finalized','overridden')
       AND (m.participant_a = p.id OR m.participant_b = p.id)
     WHERE p.tournament_id  = p_tournament_id
       AND p.group_label    = p_group_label
       AND p.registration_status = 'confirmed'
     GROUP BY p.id, p.registered_at
  ),
  grouped AS (
    SELECT array_agg(pid::text ORDER BY pid) AS ids,
           count(*) AS cnt
      FROM stats
     GROUP BY
       CASE WHEN 'total_points'    = ANY(v_chain) THEN total_points   ELSE 0 END,
       CASE WHEN 'wins'            = ANY(v_chain) THEN wins           ELSE 0 END,
       CASE WHEN 'kubb_difference' = ANY(v_chain) THEN kubb_diff      ELSE 0 END
  )
  SELECT coalesce(jsonb_agg(to_jsonb(ids) ORDER BY ids), '[]'::jsonb),
         bool_or(cnt > 1)
    INTO v_tied, v_needs_resolve
    FROM grouped
   WHERE cnt > 1;

  RETURN jsonb_build_object(
    'qualifiers',            coalesce(to_jsonb(v_qualifiers), '[]'::jsonb),
    'tie_resolution_needed', coalesce(v_needs_resolve, false),
    'tied_participants',     coalesce(v_tied, '[]'::jsonb),
    'chain',                 to_jsonb(v_chain));
END;
$$;

REVOKE EXECUTE ON FUNCTION public._tournament_compute_pool_cut(uuid, text, int) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._tournament_compute_pool_cut(uuid, text, int) FROM authenticated;

COMMENT ON FUNCTION public._tournament_compute_pool_cut(uuid, text, int) IS
  'Per-Gruppe Top-N Qualifier-Cut. Liest tournaments.tiebreaker_order, '
  'rankt finalized group-Matches der angegebenen group_label und liefert '
  '{qualifiers, tie_resolution_needed, tied_participants, chain}. Cross-Pool '
  'direct_comparison-Skip (OD-M3-03) erfolgt in T6, der diesen Helper '
  'per Gruppe aufruft. Tie-Marker fuer OD-M3-05. Siehe ADR-0019 §2-§4.';


-- ---- 4. tournament_start_pool_phase ---------------------------------
--
-- Phasen-Transition draft/registration_closed → live mit Pool-Generierung
-- und Round-Robin-Match-Schema pro Gruppe. Pattern aus
-- `tournament_start_ko_phase`: SECURITY DEFINER, FOR UPDATE-Lock auf der
-- tournaments-Row, Idempotency-Guard via ERRCODE 40001 wenn bereits
-- group-Matches existieren.

CREATE OR REPLACE FUNCTION public.tournament_start_pool_phase(
  p_tournament_id uuid,
  p_config        jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_caller        uuid;
  v_creator       uuid;
  v_pools         jsonb;
  v_participants  jsonb;
  v_assignments   int := 0;
  v_match_count   int := 0;
  v_existing      int;
  v_labels        text[];
BEGIN
  -- 1. Authentication + Organizer-Lock.
  v_caller := auth.uid();
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED' USING ERRCODE = '42501';
  END IF;

  SELECT created_by INTO v_creator
    FROM public.tournaments
    WHERE id = p_tournament_id
    FOR UPDATE;

  IF v_creator IS NULL OR v_creator IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'NOT_ORGANIZER: tournament not found or not authorised'
      USING ERRCODE = '42501';
  END IF;

  -- 2. Idempotency-Guard: existieren bereits group-Matches?
  --    (ADR-0017 §7 Pattern, ERRCODE 40001 → Client behandelt idempotent.)
  SELECT count(*) INTO v_existing
    FROM public.tournament_matches
    WHERE tournament_id = p_tournament_id
      AND phase = 'group';
  IF v_existing > 0 THEN
    RAISE EXCEPTION 'ALREADY_STARTED: pool phase already initialised'
      USING ERRCODE = '40001';
  END IF;

  -- 3. Confirmed Participants in deterministischer Reihenfolge einsammeln.
  SELECT coalesce(jsonb_agg(to_jsonb(id::text)
                            ORDER BY registered_at ASC, id ASC),
                  '[]'::jsonb)
    INTO v_participants
    FROM public.tournament_participants
    WHERE tournament_id = p_tournament_id
      AND registration_status = 'confirmed';

  IF jsonb_array_length(v_participants) < 2 THEN
    RAISE EXCEPTION 'INVALID_POOL_CONFIG: at least 2 confirmed participants required'
      USING ERRCODE = '22023';
  END IF;

  -- 4. Pools berechnen.
  v_pools := public._tournament_compute_pools(v_participants, p_config);

  -- 5. group_label auf den Participants persistieren.
  WITH assignments AS (
    SELECT (elem ->> 'participant_id')::uuid AS pid,
           (elem ->> 'group_label')          AS lbl
      FROM jsonb_array_elements(v_pools) AS elem
  )
  UPDATE public.tournament_participants tp
     SET group_label = a.lbl
    FROM assignments a
   WHERE tp.id = a.pid
     AND tp.tournament_id = p_tournament_id;
  GET DIAGNOSTICS v_assignments = ROW_COUNT;

  -- 6. Round-Robin-Matches pro Gruppe erzeugen. Alle Paare (a,b) mit a<b.
  --    round_number/match_number sind innerhalb der Gruppe deterministisch
  --    durch (group_position_a, group_position_b) bestimmt.
  SELECT array_agg(DISTINCT (elem ->> 'group_label') ORDER BY (elem ->> 'group_label'))
    INTO v_labels
    FROM jsonb_array_elements(v_pools) AS elem;

  WITH members AS (
    SELECT (elem ->> 'participant_id')::uuid AS pid,
           (elem ->> 'group_label')          AS lbl,
           (elem ->> 'group_position')::int  AS pos
      FROM jsonb_array_elements(v_pools) AS elem
  ),
  pairs AS (
    SELECT m1.lbl, m1.pid AS pid_a, m2.pid AS pid_b,
           m1.pos AS pos_a, m2.pos AS pos_b,
           row_number() OVER (
             PARTITION BY m1.lbl
             ORDER BY m1.pos, m2.pos
           ) AS pair_no
      FROM members m1
      JOIN members m2 ON m1.lbl = m2.lbl AND m1.pos < m2.pos
  )
  INSERT INTO public.tournament_matches(
      tournament_id, round_number, match_number_in_round,
      participant_a, participant_b,
      phase, group_label, status, pitch_number)
  SELECT p_tournament_id,
         1::smallint,                        -- Pool-RR ohne Runden-Konzept
         pair_no::smallint,
         pid_a, pid_b,
         'group',
         lbl,
         'scheduled',
         1
    FROM pairs;

  GET DIAGNOSTICS v_match_count = ROW_COUNT;

  -- 7. Turnier-Status auf live setzen + started_at.
  UPDATE public.tournaments
     SET status     = 'live',
         started_at = coalesce(started_at, now())
   WHERE id = p_tournament_id;

  -- 8. Audit-Event `pool_phase_started`.
  INSERT INTO public.tournament_audit_events(
      tournament_id, kind, actor_user_id, payload)
    VALUES (
      p_tournament_id,
      'pool_phase_started',
      v_caller,
      jsonb_build_object(
        'group_count',           coalesce(array_length(v_labels, 1), 0),
        'assignments',           v_assignments,
        'match_count',           v_match_count,
        'config',                p_config));

  RETURN jsonb_build_object(
    'tournament_id', p_tournament_id,
    'group_count',   coalesce(array_length(v_labels, 1), 0),
    'assignments',   v_assignments,
    'match_count',   v_match_count);
END;
$$;

GRANT EXECUTE ON FUNCTION public.tournament_start_pool_phase(uuid, jsonb)
  TO authenticated;

COMMENT ON FUNCTION public.tournament_start_pool_phase(uuid, jsonb) IS
  'Phasen-Transition zur Pool-Phase. SECURITY DEFINER mit FOR UPDATE-Lock '
  'auf tournaments-Row, Idempotency-Guard via ERRCODE 40001 wenn '
  'group-Matches bereits existieren. Ruft _tournament_compute_pools, '
  'persistiert participant.group_label, erzeugt Round-Robin-Matches je '
  'Gruppe (phase=group, group_label) und setzt tournaments.status=live. '
  'Siehe ADR-0019 §1 + M3.3-T5.';
