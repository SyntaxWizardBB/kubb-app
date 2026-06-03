import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

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

const _chain = TiebreakerChain([
  TiebreakerCriterion.totalPoints,
  TiebreakerCriterion.wins,
  TiebreakerCriterion.kubbDifference,
]);

/// Ranking helper: sort a list by the chain so detection runs on the real
/// chain-produced order (mirrors how selectQualifiers feeds the cut).
List<ParticipantStats> _ranked(List<ParticipantStats> xs) =>
    [...xs]..sort(_chain.compare);

void main() {
  group('ShootoutResult value object', () {
    test('DOD-4: JSON round-trip preserves value equality', () {
      final r = ShootoutResult(
        tiedParticipantIds: const ['A', 'B', 'C'],
        orderedWinners: const ['B', 'A', 'C'],
      );
      final back = ShootoutResult.fromJson(r.toJson());
      expect(back, equals(r));
      expect(back.hashCode, equals(r.hashCode));
    });

    test('DOD-4: pending (no winners) round-trips and is unresolved', () {
      final r = ShootoutResult(
        tiedParticipantIds: const ['A', 'B'],
        orderedWinners: const [],
      );
      expect(r.isResolved, isFalse);
      final back = ShootoutResult.fromJson(r.toJson());
      expect(back, equals(r));
      expect(back.isResolved, isFalse);
    });

    test('value equality distinguishes different winner orders', () {
      final a = ShootoutResult(
        tiedParticipantIds: const ['A', 'B'],
        orderedWinners: const ['A', 'B'],
      );
      final b = ShootoutResult(
        tiedParticipantIds: const ['A', 'B'],
        orderedWinners: const ['B', 'A'],
      );
      expect(a == b, isFalse);
    });

    test('rejects winners that are not a permutation of the tied set', () {
      expect(
        () => ShootoutResult(
          tiedParticipantIds: const ['A', 'B'],
          orderedWinners: const ['A'],
        ),
        throwsArgumentError,
      );
    });
  });

  group('detectShootoutGroups', () {
    test('DOD-6 / test (a): exact tie ON the cut line is detected', () {
      // Cut at 2 qualifiers. Ranks: P0 (top) qualifies, then P1 & P2 tied
      // straddle the cut (rank 1 in, rank 2 out), P3 below.
      final ranking = _ranked([
        _stats('P0', totalPoints: 30, wins: 3),
        _stats('P1', totalPoints: 20, wins: 2),
        _stats('P2', totalPoints: 20, wins: 2),
        _stats('P3', totalPoints: 10, wins: 1),
      ]);
      final groups = detectShootoutGroups(ranking, 2, _chain);
      expect(groups, hasLength(1));
      expect(groups.single.participantIds.toSet(), equals({'P1', 'P2'}));
      expect(groups.single.startRank, equals(1));
    });

    test('DOD-7 / test (b): ties wholly above OR below the cut do not '
        'trigger a shoot-out', () {
      // Tie wholly ABOVE the cut: P0 & P1 tied at ranks 0,1; cut = 3 → both in.
      final aboveCut = _ranked([
        _stats('P0', totalPoints: 30, wins: 3),
        _stats('P1', totalPoints: 30, wins: 3),
        _stats('P2', totalPoints: 20, wins: 2),
        _stats('P3', totalPoints: 10, wins: 1),
      ]);
      expect(detectShootoutGroups(aboveCut, 3, _chain), isEmpty);

      // Tie wholly BELOW the cut: P2 & P3 tied at ranks 2,3; cut = 1 → out.
      final belowCut = _ranked([
        _stats('P0', totalPoints: 30, wins: 3),
        _stats('P1', totalPoints: 20, wins: 2),
        _stats('P2', totalPoints: 10, wins: 1),
        _stats('P3', totalPoints: 10, wins: 1),
      ]);
      expect(detectShootoutGroups(belowCut, 1, _chain), isEmpty);
    });

    test('no qualifiers / everyone qualifies → no groups', () {
      final ranking = _ranked([
        _stats('P0', totalPoints: 10),
        _stats('P1', totalPoints: 10),
      ]);
      expect(detectShootoutGroups(ranking, 0, _chain), isEmpty);
      expect(detectShootoutGroups(ranking, 2, _chain), isEmpty);
    });

    test('a chain ending in random never triggers a shoot-out', () {
      // random is a deterministic-by-seed decider that never returns 0, so
      // _allCriteriaEqualForShootout can never hold while it is in the chain:
      // the chain itself always separates the pair, leaving no exact tie for
      // the shoot-out to resolve. This pins that interaction.
      const randomChain = TiebreakerChain([
        TiebreakerCriterion.totalPoints,
        TiebreakerCriterion.wins,
        TiebreakerCriterion.random,
      ]);
      final ranking = [
        _stats('P0', totalPoints: 30, wins: 3),
        _stats('P1', totalPoints: 20, wins: 2),
        _stats('P2', totalPoints: 20, wins: 2),
        _stats('P3', totalPoints: 10, wins: 1),
      ]..sort(randomChain.compare);
      expect(detectShootoutGroups(ranking, 2, randomChain), isEmpty);
    });
  });

  group('resolveWithShootouts', () {
    test('DOD-8 / test (c): recorded winner orders the group and makes '
        'qualification unique', () {
      final ranking = _ranked([
        _stats('P0', totalPoints: 30, wins: 3),
        _stats('P1', totalPoints: 20, wins: 2),
        _stats('P2', totalPoints: 20, wins: 2),
        _stats('P3', totalPoints: 10, wins: 1),
      ]);
      // Shoot-out: P2 beats P1 → P2 takes the last qualifier slot.
      final result = ShootoutResult(
        tiedParticipantIds: const ['P1', 'P2'],
        orderedWinners: const ['P2', 'P1'],
      );
      final res = resolveWithShootouts(ranking, 2, _chain, [result]);
      expect(res.isFinal, isTrue);
      expect(res.pending, isEmpty);
      expect(res.qualifiers, equals(['P0', 'P2']));
    });

    test('DOD-9 / test (d): 3-way tie at the cut is fully ordered, no '
        'residual ambiguity', () {
      // Cut = 2. P1,P2,P3 all tied (ranks 1..3) straddle the cut.
      final ranking = _ranked([
        _stats('P0', totalPoints: 30, wins: 3),
        _stats('P1', totalPoints: 20, wins: 2),
        _stats('P2', totalPoints: 20, wins: 2),
        _stats('P3', totalPoints: 20, wins: 2),
      ]);
      final groups = detectShootoutGroups(ranking, 2, _chain);
      expect(groups.single.participantIds.toSet(), equals({'P1', 'P2', 'P3'}));

      // Recorded full order: P3 > P1 > P2.
      final result = ShootoutResult(
        tiedParticipantIds: const ['P1', 'P2', 'P3'],
        orderedWinners: const ['P3', 'P1', 'P2'],
      );
      final res = resolveWithShootouts(ranking, 2, _chain, [result]);
      expect(res.isFinal, isTrue);
      // P0 plus the shoot-out winner P3 qualify; full order unambiguous.
      expect(res.qualifiers, equals(['P0', 'P3']));
    });

    test('DOD-10 / test (e): no result → group stays pending, no silent '
        'ID fallback', () {
      final ranking = _ranked([
        _stats('P0', totalPoints: 30, wins: 3),
        _stats('P1', totalPoints: 20, wins: 2),
        _stats('P2', totalPoints: 20, wins: 2),
        _stats('P3', totalPoints: 10, wins: 1),
      ]);
      final res = resolveWithShootouts(ranking, 2, _chain, const []);
      expect(res.isFinal, isFalse);
      expect(res.pending, hasLength(1));
      expect(res.pending.single.participantIds.toSet(), equals({'P1', 'P2'}));
    });

    test('cosmetic tie below the cut keeps deterministic order, not pending',
        () {
      final ranking = _ranked([
        _stats('P0', totalPoints: 30, wins: 3),
        _stats('P1', totalPoints: 20, wins: 2),
        _stats('P2', totalPoints: 10, wins: 1),
        _stats('P3', totalPoints: 10, wins: 1),
      ]);
      final res = resolveWithShootouts(ranking, 2, _chain, const []);
      expect(res.isFinal, isTrue);
      expect(res.pending, isEmpty);
      expect(res.qualifiers, equals(['P0', 'P1']));
    });

    test('DOD-12: detection + resolution are deterministic across repeated '
        'calls', () {
      final ranking = _ranked([
        _stats('P0', totalPoints: 30, wins: 3),
        _stats('P1', totalPoints: 20, wins: 2),
        _stats('P2', totalPoints: 20, wins: 2),
        _stats('P3', totalPoints: 20, wins: 2),
      ]);
      final result = ShootoutResult(
        tiedParticipantIds: const ['P1', 'P2', 'P3'],
        orderedWinners: const ['P3', 'P1', 'P2'],
      );
      final g1 = detectShootoutGroups(ranking, 2, _chain);
      final g2 = detectShootoutGroups(ranking, 2, _chain);
      expect(g1, equals(g2));
      final r1 = resolveWithShootouts(ranking, 2, _chain, [result]);
      final r2 = resolveWithShootouts(ranking, 2, _chain, [result]);
      expect(r1, equals(r2));
    });
  });
}
