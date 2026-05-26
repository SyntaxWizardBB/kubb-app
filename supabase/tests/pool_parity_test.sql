-- Property-Paritaet-Test: Dart `generatePools`
-- (`packages/kubb_domain/lib/src/tournament/pool_phase.dart`) ↔ plpgsql
-- `_tournament_compute_pools` (T5). Merge-Gate fuer ADR-0019 §1.
--
-- Strategie: Inline-Snapshots ueber n ∈ {8, 12, 16} × g ∈ {2, 4} fuer
-- snake- und seeded-Strategy. Pro Kombi wird das per-Group ordered-
-- participant-Tupel mit der direkt aus dem Dart-Algorithmus
-- abgeleiteten Erwartung verglichen. Vereinfachter Sweep statt 25
-- Kombinationen (LOC-Budget); deckt aber alle Distributionsmuster ab
-- (gerade/ungerade Reihen, 2- und 4-Gruppen-Snake).
--
-- BYE-Distribution wird separat fuer n=10/g=4 geprueft (Dart sortiert
-- kuerzere Gruppen ans Ende und padded mit NULL bis groupSize).
--
-- Random-Strategy bewusst ausgeklammert: Dart nutzt `dart:math.Random`
-- (linear congruential, Dart-SDK-spezifisch). Die plpgsql-Spiegelung
-- darf nicht bitidentisch sein und wird stattdessen separat in zwei
-- Property-Tests abgedeckt: `pool_phase_test.dart` ("random ist
-- deterministisch fuer identischen Seed") plus der entsprechende
-- pgTAP-Test in T5-Migration ("plpgsql random ist deterministisch fuer
-- identischen Seed"). Bitparitaet ist damit NICHT Vertragsteil.
--
-- Synthetische Seeds: UUIDs `00000000-0000-0000-0000-NNNNNNNNNNNN`
-- (N = 1-based Index) — analog M2 bracket_parity. Reversible per
-- `right(uuid::text, 12)::int`. T5-Helper-Signatur per
-- tasks.md §T5-Notes: `_tournament_compute_pools(p_participants jsonb,
-- p_config jsonb) returns jsonb` (Array `{participant_id, group_label,
-- group_position}`); BYE-Slots erscheinen als Eintrag mit
-- `participant_id = NULL`.

BEGIN;

SELECT plan(16);

-- Erzeugt `[<uuid 1>, ..., <uuid n>]` als jsonb fuer p_participants.
CREATE OR REPLACE FUNCTION _test_pool_ids(p_n int)
RETURNS jsonb
LANGUAGE sql
AS $$
  SELECT jsonb_agg(format('00000000-0000-0000-0000-%s', lpad(i::text, 12, '0')))
    FROM generate_series(1, p_n) AS i;
$$;

-- Map uuid-text → seed-index (NULL bei BYE).
CREATE OR REPLACE FUNCTION _test_pool_seed_of(p_uuid text)
RETURNS int
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE WHEN p_uuid IS NULL THEN NULL
              ELSE to_number(right(p_uuid, 12), '999999999999')::int END;
$$;

-- Per-Group Ordered Shape: liefert pro group_label das array der seed-
-- indices in group_position-Ordnung (NULL fuer BYE-Slots).
CREATE OR REPLACE FUNCTION _test_pool_shape(p_result jsonb)
RETURNS TABLE(group_label text, seeds int[])
LANGUAGE sql
AS $$
  SELECT group_label, array_agg(seed_index ORDER BY group_position)
    FROM (
      SELECT (elem->>'group_label') AS group_label,
             (elem->>'group_position')::int AS group_position,
             _test_pool_seed_of(elem->>'participant_id') AS seed_index
        FROM jsonb_array_elements(p_result) AS elem
    ) t
   GROUP BY group_label;
$$;

-- Convenience: ruft Helper auf und reicht das jsonb-Resultat in shape.
CREATE OR REPLACE FUNCTION _test_pools(p_n int, p_g int, p_strategy text)
RETURNS jsonb
LANGUAGE sql
AS $$
  SELECT public._tournament_compute_pools(
           _test_pool_ids(p_n),
           jsonb_build_object(
             'group_count', p_g,
             'qualifiers_per_group', 1,
             'strategy', p_strategy));
$$;

-- ---------------------------------------------------------------------
-- Snake-Strategy Snapshots. Expected aus Dart `generatePools` per
-- Hand abgeleitet: row r=i/g, col c=i%g, groupIndex = r%2==0 ? c : g-1-c.
-- ---------------------------------------------------------------------

-- n=8, g=2, snake → G0=[1,4,5,8], G1=[2,3,6,7]
SELECT results_eq(
  $$ SELECT group_label, seeds FROM _test_pool_shape(_test_pools(8, 2, 'snake')) ORDER BY group_label $$,
  $$ VALUES ('A', ARRAY[1,4,5,8]), ('B', ARRAY[2,3,6,7]) $$,
  'n=8/g=2 snake: per-group ordered seeds');

-- n=8, g=4, snake → G0=[1,8], G1=[2,7], G2=[3,6], G3=[4,5]
SELECT results_eq(
  $$ SELECT group_label, seeds FROM _test_pool_shape(_test_pools(8, 4, 'snake')) ORDER BY group_label $$,
  $$ VALUES ('A', ARRAY[1,8]), ('B', ARRAY[2,7]), ('C', ARRAY[3,6]), ('D', ARRAY[4,5]) $$,
  'n=8/g=4 snake: per-group ordered seeds');

-- n=12, g=2, snake → G0=[1,4,5,8,9,12], G1=[2,3,6,7,10,11]
SELECT results_eq(
  $$ SELECT group_label, seeds FROM _test_pool_shape(_test_pools(12, 2, 'snake')) ORDER BY group_label $$,
  $$ VALUES ('A', ARRAY[1,4,5,8,9,12]), ('B', ARRAY[2,3,6,7,10,11]) $$,
  'n=12/g=2 snake: per-group ordered seeds');

-- n=12, g=4, snake → G0=[1,8,9], G1=[2,7,10], G2=[3,6,11], G3=[4,5,12]
SELECT results_eq(
  $$ SELECT group_label, seeds FROM _test_pool_shape(_test_pools(12, 4, 'snake')) ORDER BY group_label $$,
  $$ VALUES ('A', ARRAY[1,8,9]), ('B', ARRAY[2,7,10]), ('C', ARRAY[3,6,11]), ('D', ARRAY[4,5,12]) $$,
  'n=12/g=4 snake: per-group ordered seeds');

-- n=16, g=2, snake → G0=[1,4,5,8,9,12,13,16], G1=[2,3,6,7,10,11,14,15]
SELECT results_eq(
  $$ SELECT group_label, seeds FROM _test_pool_shape(_test_pools(16, 2, 'snake')) ORDER BY group_label $$,
  $$ VALUES ('A', ARRAY[1,4,5,8,9,12,13,16]), ('B', ARRAY[2,3,6,7,10,11,14,15]) $$,
  'n=16/g=2 snake: per-group ordered seeds');

-- n=16, g=4, snake → G0=[1,8,9,16], G1=[2,7,10,15], G2=[3,6,11,14], G3=[4,5,12,13]
SELECT results_eq(
  $$ SELECT group_label, seeds FROM _test_pool_shape(_test_pools(16, 4, 'snake')) ORDER BY group_label $$,
  $$ VALUES ('A', ARRAY[1,8,9,16]), ('B', ARRAY[2,7,10,15]), ('C', ARRAY[3,6,11,14]), ('D', ARRAY[4,5,12,13]) $$,
  'n=16/g=4 snake: per-group ordered seeds');

-- ---------------------------------------------------------------------
-- Seeded-Strategy Snapshots: sequenzielle Bloecke groupSize=ceil(n/g).
-- ---------------------------------------------------------------------

-- n=8, g=2, seeded → G0=[1..4], G1=[5..8]
SELECT results_eq(
  $$ SELECT group_label, seeds FROM _test_pool_shape(_test_pools(8, 2, 'seeded')) ORDER BY group_label $$,
  $$ VALUES ('A', ARRAY[1,2,3,4]), ('B', ARRAY[5,6,7,8]) $$,
  'n=8/g=2 seeded: per-group ordered seeds');

-- n=8, g=4, seeded → G0=[1,2], G1=[3,4], G2=[5,6], G3=[7,8]
SELECT results_eq(
  $$ SELECT group_label, seeds FROM _test_pool_shape(_test_pools(8, 4, 'seeded')) ORDER BY group_label $$,
  $$ VALUES ('A', ARRAY[1,2]), ('B', ARRAY[3,4]), ('C', ARRAY[5,6]), ('D', ARRAY[7,8]) $$,
  'n=8/g=4 seeded: per-group ordered seeds');

-- n=12, g=2, seeded
SELECT results_eq(
  $$ SELECT group_label, seeds FROM _test_pool_shape(_test_pools(12, 2, 'seeded')) ORDER BY group_label $$,
  $$ VALUES ('A', ARRAY[1,2,3,4,5,6]), ('B', ARRAY[7,8,9,10,11,12]) $$,
  'n=12/g=2 seeded: per-group ordered seeds');

-- n=12, g=4, seeded
SELECT results_eq(
  $$ SELECT group_label, seeds FROM _test_pool_shape(_test_pools(12, 4, 'seeded')) ORDER BY group_label $$,
  $$ VALUES ('A', ARRAY[1,2,3]), ('B', ARRAY[4,5,6]), ('C', ARRAY[7,8,9]), ('D', ARRAY[10,11,12]) $$,
  'n=12/g=4 seeded: per-group ordered seeds');

-- n=16, g=2, seeded
SELECT results_eq(
  $$ SELECT group_label, seeds FROM _test_pool_shape(_test_pools(16, 2, 'seeded')) ORDER BY group_label $$,
  $$ VALUES ('A', ARRAY[1,2,3,4,5,6,7,8]), ('B', ARRAY[9,10,11,12,13,14,15,16]) $$,
  'n=16/g=2 seeded: per-group ordered seeds');

-- n=16, g=4, seeded
SELECT results_eq(
  $$ SELECT group_label, seeds FROM _test_pool_shape(_test_pools(16, 4, 'seeded')) ORDER BY group_label $$,
  $$ VALUES ('A', ARRAY[1,2,3,4]), ('B', ARRAY[5,6,7,8]), ('C', ARRAY[9,10,11,12]), ('D', ARRAY[13,14,15,16]) $$,
  'n=16/g=4 seeded: per-group ordered seeds');

-- ---------------------------------------------------------------------
-- BYE-Distribution: n=10, g=4, snake. groupSize=ceil(10/4)=3, also
-- 4*3 - 10 = 2 BYE-Slots. Dart sortiert kuerzere Gruppen nach hinten
-- vor dem Padding → BYE-Slots landen in den letzten Labels (C, D).
-- Strukturell statt positionsfest geprueft (Dart `List.sort` ist nicht
-- garantiert stabil; nur die Mengen-Properties sind Vertrag).
-- ---------------------------------------------------------------------

-- 1) Jeder Slot pro Gruppe ist genau groupSize (=3).
SELECT is(
  (SELECT bool_and(jsonb_array_length(
     (SELECT jsonb_agg(elem) FROM jsonb_array_elements(_test_pools(10, 4, 'snake')) elem
       WHERE elem->>'group_label' = gl)) = 3)
     FROM unnest(ARRAY['A','B','C','D']) AS gl),
  true, 'n=10/g=4 snake: jede Gruppe hat groupSize=3 Slots');

-- 2) Genau 2 BYE-Slots gesamt.
SELECT is(
  (SELECT count(*)::int
     FROM jsonb_array_elements(_test_pools(10, 4, 'snake')) AS elem
    WHERE (elem->>'participant_id') IS NULL),
  2, 'n=10/g=4 snake: genau 2 BYE-Slots (groupCount*groupSize - n)');

-- 3) BYE-Slots ausschliesslich in den lexikografisch letzten Gruppen
--    (Dart: kuerzere Gruppen nach hinten → C/D). Erlaubt: {C,D},
--    {D,D} ist ausgeschlossen weil Snake max 1 BYE pro Gruppe schreibt.
SELECT is(
  (SELECT bool_and((elem->>'group_label') IN ('C','D'))
     FROM jsonb_array_elements(_test_pools(10, 4, 'snake')) AS elem
    WHERE (elem->>'participant_id') IS NULL),
  true, 'n=10/g=4 snake: BYE-Slots nur in kuerzesten Gruppen (C, D)');

-- ---------------------------------------------------------------------
-- Validierungs-Pfad: qualifiersPerGroup > groupSize → ERRCODE 22023
-- (Dart wirft ArgumentError; T5 spiegelt mit invalid_parameter_value).
-- ---------------------------------------------------------------------
SELECT throws_ok(
  $$ SELECT public._tournament_compute_pools(
       _test_pool_ids(8),
       jsonb_build_object('group_count', 4, 'qualifiers_per_group', 3, 'strategy', 'snake')) $$,
  '22023', NULL,
  'qualifiers_per_group > groupSize → ERRCODE 22023');

SELECT * FROM finish();

ROLLBACK;
