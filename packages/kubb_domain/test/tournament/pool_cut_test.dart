import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/tournament/pool_cut.dart';

import '../_support/tournament_generators.dart';

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

/// Four 4-participant pools with strictly decreasing totals (30/20/10/0).
List<List<ParticipantStats>> _cleanFourByFour() => [
      for (var g = 0; g < 4; g++)
        [
          for (var i = 0; i < 4; i++)
            _stats('g${g}_p$i', totalPoints: 30 - i * 10, wins: 3 - i),
        ],
    ];

const _cfg4x4Top2 = PoolPhaseConfig(
  groupCount: 4,
  qualifiersPerGroup: 2,
  strategy: PoolGroupingStrategy.snake,
);
const _cfg2x2Top1 = PoolPhaseConfig(
  groupCount: 2,
  qualifiersPerGroup: 1,
  strategy: PoolGroupingStrategy.snake,
);

void main() {
  group('selectQualifiers (ADR-0019)', () {
    test('4 pools of 4, top=2 yields 8 unique qualifiers', () {
      const chain = TiebreakerChain([TiebreakerCriterion.totalPoints]);
      final r = selectQualifiers(_cleanFourByFour(), _cfg4x4Top2, chain);
      expect(r.qualifiers, hasLength(8));
      expect(r.qualifiers.toSet(), hasLength(8));
      expect(r.tieResolutionNeeded, isEmpty);
      for (var g = 0; g < 4; g++) {
        expect(r.qualifiers, containsAll(['g${g}_p0', 'g${g}_p1']));
      }
    });

    test('full cross-pool tie emits TieResolutionNeeded marker (OD-M3-05)', () {
      final pools = [
        [
          _stats('A1', totalPoints: 20, wins: 3, kubbsScored: 12),
          _stats('A2', totalPoints: 5),
        ],
        [
          _stats('B1', totalPoints: 20, wins: 3, kubbsScored: 12),
          _stats('B2', totalPoints: 5),
        ],
      ];
      const chain = TiebreakerChain([
        TiebreakerCriterion.totalPoints,
        TiebreakerCriterion.wins,
        TiebreakerCriterion.kubbDifference,
      ]);
      final r = selectQualifiers(pools, _cfg2x2Top1, chain);
      expect(r.qualifiers, hasLength(2));
      expect(r.tieResolutionNeeded, isNotEmpty);
      expect(
        r.tieResolutionNeeded.first.participantIds.toSet(),
        equals({'A1', 'B1'}),
      );
    });

    test('directComparison is skipped cross-pool, next stage breaks tie '
        '(OD-M3-03)', () {
      final pools = [
        [
          _stats('A1',
              totalPoints: 20, wins: 3, kubbsScored: 15, kubbsConceded: 5),
          _stats('A2', totalPoints: 5),
        ],
        [
          _stats('B1',
              totalPoints: 20, wins: 3, kubbsScored: 10, kubbsConceded: 8),
          _stats('B2', totalPoints: 5),
        ],
      ];
      const chain = TiebreakerChain([
        TiebreakerCriterion.totalPoints,
        TiebreakerCriterion.wins,
        TiebreakerCriterion.directComparison,
        TiebreakerCriterion.kubbDifference,
      ]);
      final r = selectQualifiers(pools, _cfg2x2Top1, chain);
      // directComparison undefined cross-pool → fall through to kubbDiff:
      // A1 (+10) outranks B1 (+2).
      expect(r.qualifiers, equals(['A1', 'B1']));
      expect(r.tieResolutionNeeded, isEmpty);
    });

    test('twice-called with same input → identical result order', () {
      const chain = TiebreakerChain([
        TiebreakerCriterion.totalPoints,
        TiebreakerCriterion.wins,
      ]);
      final a = selectQualifiers(_cleanFourByFour(), _cfg4x4Top2, chain);
      final b = selectQualifiers(_cleanFourByFour(), _cfg4x4Top2, chain);
      expect(a.qualifiers, equals(b.qualifiers));
    });

    Glados<List<String>>(any.participantIds(min: 8, max: 12))
        .test('property: determinism over arbitrary pool participants', (ids) {
      final half = ids.length ~/ 2;
      if (half < 2) return;
      List<ParticipantStats> pool(Iterable<String> xs) => [
            for (final id in xs)
              _stats(id, totalPoints: id.hashCode & 0xff, wins: id.length),
          ];
      const chain = TiebreakerChain([
        TiebreakerCriterion.totalPoints,
        TiebreakerCriterion.wins,
      ]);
      final pools = [
        pool(ids.sublist(0, half)),
        pool(ids.sublist(half, half * 2)),
      ];
      final a = selectQualifiers(pools, _cfg2x2Top1, chain);
      final b = selectQualifiers(pools, _cfg2x2Top1, chain);
      expect(a.qualifiers, equals(b.qualifiers));
    });
  });
}
