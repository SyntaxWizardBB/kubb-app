import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

// Golden vectors shared with the plpgsql twin _tournament_seed_random
// (supabase/tests/stage_seed_resolver_parity_test.sql). The expectation is an
// index permutation: position k holds the 1-based input index of the kth output
// id. Both sides build ids as '00000000-0000-0000-0c0c-<index>' so the SQL test
// can map back the same way. These vectors are the source of truth for the
// Dart<->plpgsql byte-parity gate (T12) — change them in both files or not at
// all. Seeds cover the edge cases (0 and 2^32-1) the LCG must round-trip.

String _id(int i) => '00000000-0000-0000-0c0c-${i.toString().padLeft(12, '0')}';

List<String> _ids(int n) => [for (var i = 1; i <= n; i++) _id(i)];

List<int> _perm(List<String> ids, List<String> shuffled) =>
    [for (final id in shuffled) ids.indexOf(id) + 1];

const _goldens = <({int n, int seed, List<int> perm})>[
  (n: 8, seed: 0, perm: [3, 6, 1, 4, 7, 2, 5, 8]),
  (n: 8, seed: 1, perm: [6, 4, 2, 7, 1, 3, 8, 5]),
  (n: 8, seed: 12345, perm: [2, 7, 4, 1, 6, 3, 8, 5]),
  (n: 8, seed: 4294967295, perm: [2, 1, 7, 6, 4, 8, 5, 3]),
  (n: 13, seed: 2025, perm: [7, 9, 2, 11, 6, 4, 1, 8, 3, 13, 5, 12, 10]),
  (n: 2, seed: 7, perm: [2, 1]),
  (n: 5, seed: 99, perm: [1, 5, 3, 2, 4]),
];

void main() {
  group('seedRandom golden vectors', () {
    for (final g in _goldens) {
      test('n=${g.n} seed=${g.seed} matches the shared permutation', () {
        final ids = _ids(g.n);
        final shuffled = seedRandom(ids, g.seed);
        expect(_perm(ids, shuffled), equals(g.perm));
      });
    }

    test('each golden output stays a permutation of the input', () {
      for (final g in _goldens) {
        final ids = _ids(g.n);
        final shuffled = seedRandom(ids, g.seed);
        expect(shuffled.toSet(), equals(ids.toSet()));
        expect(shuffled, hasLength(g.n));
      }
    });
  });
}
