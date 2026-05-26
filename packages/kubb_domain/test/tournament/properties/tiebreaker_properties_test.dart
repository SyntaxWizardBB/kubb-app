import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../_support/tournament_generators.dart';

ParticipantStats _stats(
  String id, {
  int totalPoints = 0,
  int wins = 0,
  int kubbsScored = 0,
  int kubbsConceded = 0,
}) =>
    ParticipantStats(
      participantId: id,
      totalPoints: totalPoints,
      wins: wins,
      kubbsScored: kubbsScored,
      kubbsConceded: kubbsConceded,
      opponentIds: const [],
      opponentTotalPointsLookup: const {},
      headToHeadLookup: const {},
    );

void main() {
  group('TiebreakerChain properties', () {
    Glados2<ParticipantStats, ParticipantStats>(
      any.participantStats,
      any.participantStats,
    ).test('random criterion is antisymmetric for distinct ids', (a, b) {
      if (a.participantId == b.participantId) return;
      const chain = TiebreakerChain(
        [TiebreakerCriterion.random],
        randomSeed: 42,
      );
      expect(chain.compare(a, b), equals(-chain.compare(b, a)));
    });

    Glados2<ParticipantStats, ParticipantStats>(
      any.participantStats,
      any.participantStats,
    ).test('totalPoints criterion ranks higher totals first', (a, b) {
      if (a.totalPoints == b.totalPoints) return;
      const chain = TiebreakerChain([TiebreakerCriterion.totalPoints]);
      final cmp = chain.compare(a, b);
      if (a.totalPoints > b.totalPoints) {
        expect(cmp, lessThan(0));
      } else {
        expect(cmp, greaterThan(0));
      }
    });

    Glados2<ParticipantStats, ParticipantStats>(
      any.participantStats,
      any.participantStats,
    ).test('empty chain falls back to participantId order', (a, b) {
      const chain = TiebreakerChain([]);
      expect(
        chain.compare(a, b),
        equals(a.participantId.compareTo(b.participantId)),
      );
    });

    test('chain falls through to a later separating criterion', () {
      final a = _stats('p0', totalPoints: 10, wins: 5);
      final b = _stats('p1', totalPoints: 10, wins: 2);
      const chain = TiebreakerChain([
        TiebreakerCriterion.totalPoints,
        TiebreakerCriterion.wins,
      ]);
      expect(chain.compare(a, b), lessThan(0));
      expect(chain.compare(b, a), greaterThan(0));
    });
  });
}
