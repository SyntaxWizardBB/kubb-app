import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../_support/tournament_generators.dart';

const _chain = TiebreakerChain(
  [
    TiebreakerCriterion.totalPoints,
    TiebreakerCriterion.kubbDifference,
    TiebreakerCriterion.random,
  ],
  randomSeed: 17,
);

ParticipantStats _stats(String id, int kubbDiff) => ParticipantStats(
      participantId: id,
      totalPoints: 10,
      wins: 0,
      kubbsScored: 20 + kubbDiff,
      kubbsConceded: 20,
      opponentIds: const [],
      opponentTotalPointsLookup: const {},
      headToHeadLookup: const {},
    );

void main() {
  group('seedFromStandings', () {
    Glados<List<int>>(any.list(any.intInRange(-5, 5))).test(
        'is stable: equal totalPoints, distinct kubbDifference → '
        'two calls yield identical order', (diffs) {
      final stats = [
        for (var i = 0; i < diffs.length; i++) _stats('p$i', diffs[i]),
      ];
      final a = seedFromStandings(stats, _chain);
      final b = seedFromStandings(stats, _chain);
      expect(a, equals(b));
    });
  });

  group('seedRandom', () {
    Glados2<List<String>, int>(any.participantIds(max: 12), any.int)
        .test('same (ids, seed) yields identical order across two calls',
            (ids, seed) {
      expect(seedRandom(ids, seed), equals(seedRandom(ids, seed)));
    });

    test('is a permutation of the input', () {
      final ids = ['p0', 'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7'];
      final out = seedRandom(ids, 99);
      expect(out, hasLength(ids.length));
      expect(out.toSet(), equals(ids.toSet()));
    });

    test('does not mutate the input list', () {
      final ids = ['p0', 'p1', 'p2', 'p3'];
      final snapshot = [...ids];
      seedRandom(ids, 7);
      expect(ids, equals(snapshot));
    });

    test('different seeds usually produce a different order', () {
      final ids = [for (var i = 0; i < 16; i++) 'p$i'];
      var differing = 0;
      for (var seed = 1; seed <= 8; seed++) {
        final a = seedRandom(ids, seed).join(',');
        final b = seedRandom(ids, seed + 100).join(',');
        if (a != b) differing++;
      }
      expect(differing, greaterThanOrEqualTo(6));
    });

    test('empty and single-element inputs are returned unchanged', () {
      expect(seedRandom(const [], 5), isEmpty);
      expect(seedRandom(const ['only'], 5), equals(['only']));
    });
  });

  group('applyManualOverride', () {
    Glados<List<String>>(any.participantIds(max: 8))
        .test('with empty overrides is idempotent', (ids) {
      expect(applyManualOverride(ids, const {}), equals(ids));
    });

    test('throws ArgumentError on non-existent seed position', () {
      final seeded = ['p0', 'p1', 'p2'];
      expect(
        () => applyManualOverride(seeded, {99: 'p0'}),
        throwsArgumentError,
      );
      expect(
        () => applyManualOverride(seeded, {0: 'p0'}),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when override participant is not seeded', () {
      final seeded = ['p0', 'p1', 'p2'];
      expect(
        () => applyManualOverride(seeded, {1: 'pX'}),
        throwsArgumentError,
      );
    });
  });
}
