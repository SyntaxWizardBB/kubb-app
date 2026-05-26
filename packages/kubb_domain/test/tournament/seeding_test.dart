import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/tournament/seeding.dart';

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
