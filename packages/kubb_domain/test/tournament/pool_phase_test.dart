import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Synthetic participant ids ('p0', 'p1', ...) keep uniqueness trivial.
List<String> _ids(int n) =>
    List<String>.generate(n, (i) => 'p$i', growable: false);

/// Flatten a PoolPhaseResult into per-group ordered id-lists (BYE → null)
/// for structural equality assertions.
List<List<String?>> _shape(PoolPhaseResult r) =>
    [for (final g in r.groups) [...g]];

void main() {
  group('PoolPhaseConfig validation', () {
    test('groupCount=0 throws ArgumentError', () {
      expect(
        () => generatePools(
          _ids(16),
          const PoolPhaseConfig(
            groupCount: 0,
            qualifiersPerGroup: 2,
            strategy: PoolGroupingStrategy.snake,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('qualifiersPerGroup > participantsPerGroup throws ArgumentError', () {
      // 8 participants in 4 groups → 2 per group, asking for 3 qualifiers.
      expect(
        () => generatePools(
          _ids(8),
          const PoolPhaseConfig(
            groupCount: 4,
            qualifiersPerGroup: 3,
            strategy: PoolGroupingStrategy.snake,
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('generatePools — snake strategy', () {
    test('16 participants in 4 groups → 4 pools of 4', () {
      final result = generatePools(
        _ids(16),
        const PoolPhaseConfig(
          groupCount: 4,
          qualifiersPerGroup: 2,
          strategy: PoolGroupingStrategy.snake,
        ),
      );
      expect(result.groups, hasLength(4));
      for (final g in result.groups) {
        expect(g, hasLength(4));
        expect(g.whereType<String>(), hasLength(4));
      }
      // Every participant appears exactly once across all pools.
      final seen = <String>{};
      for (final g in result.groups) {
        for (final id in g.whereType<String>()) {
          expect(seen.add(id), isTrue, reason: 'duplicate $id across pools');
        }
      }
      expect(seen, hasLength(16));
    });

    test('14 participants in 4 groups → sizes [4,4,3,3] with BYE slots', () {
      final result = generatePools(
        _ids(14),
        const PoolPhaseConfig(
          groupCount: 4,
          qualifiersPerGroup: 2,
          strategy: PoolGroupingStrategy.snake,
        ),
      );
      expect(result.groups, hasLength(4));
      final nonByeSizes = [
        for (final g in result.groups) g.whereType<String>().length,
      ]..sort((a, b) => b.compareTo(a));
      expect(nonByeSizes, equals([4, 4, 3, 3]));
      // Shorter groups carry one BYE-slot so all buckets share max-size.
      final maxLen =
          result.groups.fold<int>(0, (m, g) => g.length > m ? g.length : m);
      var byes = 0;
      for (final g in result.groups) {
        for (final slot in g) {
          if (slot == null) byes++;
        }
        expect(g, hasLength(maxLen));
      }
      expect(byes, equals(2), reason: 'two BYE-slots for 14-in-4 layout');
    });

    Glados<int>(any.intInRange(8, 32))
        .test('deterministic across two calls for same input', (n) {
      final ids = _ids(n);
      const config = PoolPhaseConfig(
        groupCount: 4,
        qualifiersPerGroup: 2,
        strategy: PoolGroupingStrategy.snake,
      );
      final a = generatePools(ids, config);
      final b = generatePools(ids, config);
      expect(_shape(a), equals(_shape(b)));
    });

    Glados<int>(any.intInRange(8, 24))
        .test('every participant placed exactly once', (n) {
      final ids = _ids(n);
      final result = generatePools(
        ids,
        const PoolPhaseConfig(
          groupCount: 4,
          qualifiersPerGroup: 1,
          strategy: PoolGroupingStrategy.snake,
        ),
      );
      final seen = <String>{};
      for (final g in result.groups) {
        for (final id in g.whereType<String>()) {
          expect(seen.add(id), isTrue);
        }
      }
      expect(seen, hasLength(n));
    });
  });

  group('generatePools — random strategy', () {
    test('same seed → structurally equal pools', () {
      final ids = _ids(16);
      const config = PoolPhaseConfig(
        groupCount: 4,
        qualifiersPerGroup: 2,
        strategy: PoolGroupingStrategy.random,
        randomSeed: 42,
      );
      final a = generatePools(ids, config);
      final b = generatePools(ids, config);
      expect(_shape(a), equals(_shape(b)));
    });
  });
}
