-- Seed-Resolver-Parität — plpgsql `_tournament_seed_random` <-> Dart
-- `seedRandom` (M3-T12). Merge-Gate für Seeding-Spec §7.3 (Zufall
-- reproduzierbar) und die byte-genaue Algorithmus-Identität aus
-- 20261299000000_stage_seed_resolver.sql.
--
-- Quelle der Wahrheit: die GLEICHEN Golden-Vektoren wie im Dart-Test
-- packages/kubb_domain/test/tournament/seeding_parity_test.dart. Ein
-- Golden-Vektor ist eine Index-Permutation: Position k trägt den 1-basierten
-- Eingangs-Index der k-ten Ausgabe-id. Beide Seiten bauen die ids als
-- '00000000-0000-0000-0c0c-<index>', daher ist die Zuordnung id<->index
-- reversibel. Ändern -> in BEIDEN Dateien oder gar nicht.
--
-- Der LCG ist reine Integer-Arithmetik (Multiplikation, Addition, Maske auf
-- 32 bit); bigint rechnet jedes Zwischenprodukt exakt. Die Seeds decken die
-- Randfälle 0 und 2^32-1 ab, die der LCG sauber round-trippen muss.
--
-- pgTAP läuft transient in BEGIN..ROLLBACK; nichts wird persistiert.

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(7);

-- ---------------------------------------------------------------------
-- Helper: n ids by index (mirrors the Dart _id/_ids builder).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _ssr_ids(p_n int)
RETURNS uuid[]
LANGUAGE sql IMMUTABLE AS $$
  SELECT array_agg(('00000000-0000-0000-0c0c-' || lpad(i::text, 12, '0'))::uuid
                   ORDER BY i)
    FROM generate_series(1, p_n) AS i;
$$;

-- ---------------------------------------------------------------------
-- Helper: run the twin and map its output back to a 1-based index
-- permutation over the input order (mirrors the Dart _perm helper).
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _ssr_perm(p_n int, p_seed bigint)
RETURNS int[]
LANGUAGE sql STABLE AS $$
  WITH ids AS (SELECT _ssr_ids(p_n) AS a),
       o   AS (SELECT public._tournament_seed_random((SELECT a FROM ids), p_seed) AS r)
  SELECT array_agg(
           (SELECT idx
              FROM unnest((SELECT a FROM ids)) WITH ORDINALITY AS u(v, idx)
             WHERE u.v = elem)
           ORDER BY ord)
    FROM unnest((SELECT r FROM o)) WITH ORDINALITY AS e(elem, ord);
$$;

-- ---------------------------------------------------------------------
-- The shared golden vectors. Identical to seeding_parity_test.dart.
-- ---------------------------------------------------------------------
SELECT is(_ssr_perm(8, 0),
          ARRAY[3,6,1,4,7,2,5,8],
          'n=8 seed=0 matches the shared permutation');
SELECT is(_ssr_perm(8, 1),
          ARRAY[6,4,2,7,1,3,8,5],
          'n=8 seed=1 matches the shared permutation');
SELECT is(_ssr_perm(8, 12345),
          ARRAY[2,7,4,1,6,3,8,5],
          'n=8 seed=12345 matches the shared permutation');
SELECT is(_ssr_perm(8, 4294967295),
          ARRAY[2,1,7,6,4,8,5,3],
          'n=8 seed=2^32-1 matches the shared permutation');
SELECT is(_ssr_perm(13, 2025),
          ARRAY[7,9,2,11,6,4,1,8,3,13,5,12,10],
          'n=13 seed=2025 matches the shared permutation');
SELECT is(_ssr_perm(2, 7),
          ARRAY[2,1],
          'n=2 seed=7 matches the shared permutation');
SELECT is(_ssr_perm(5, 99),
          ARRAY[1,5,3,2,4],
          'n=5 seed=99 matches the shared permutation');

SELECT * FROM finish();
ROLLBACK;
