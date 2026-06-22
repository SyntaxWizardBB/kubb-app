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

/// Schoch chain straight from production: points -> §5 Buchholz -> shoot-out.
final TiebreakerChain _schochChain = chainForStageType(StageNodeType.schoch);

/// Builds a Schoch ParticipantStats with a settable Buchholz. The current
/// `_stats` helper hard-codes empty opponent lookups, so Buchholz is always 0
/// there. Here the opponent total feeds the §5 sum directly (no head-to-head
/// subtrahend), so `buchholz == buchholzValue` exactly.
ParticipantStats _schochStats(
  String id, {
  int totalPoints = 0,
  int buchholzValue = 0,
}) =>
    ParticipantStats(
      participantId: id,
      totalPoints: totalPoints,
      wins: 0,
      kubbsScored: 0,
      kubbsConceded: 0,
      opponentIds: ['$id-opp'],
      opponentTotalPointsLookup: {'$id-opp': buchholzValue},
      headToHeadLookup: const {},
    );

/// Ranking helper: sort a list by the chain so detection runs on the real
/// chain-produced order (mirrors how selectQualifiers feeds the cut).
List<ParticipantStats> _ranked(List<ParticipantStats> xs) =>
    [...xs]..sort(_chain.compare);

List<ParticipantStats> _rankedSchoch(List<ParticipantStats> xs) =>
    [...xs]..sort(_schochChain.compare);

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

  group('detectShootoutGroups — Schoch chain (Buchholz tied-key)', () {
    test('M2-T07: points-equal pair with DIFFERENT Buchholz at the cut → no '
        'shoot-out (Buchholz already separates them)', () {
      // Cut at 2. P0 top. P1 & P2 are point-equal and straddle the cut
      // (ranks 1 and 2), but their Buchholz differs → the Schoch chain breaks
      // the tie before the shoot-out, so nothing should fire.
      final ranking = _rankedSchoch([
        _schochStats('P0', totalPoints: 30, buchholzValue: 100),
        _schochStats('P1', totalPoints: 20, buchholzValue: 90),
        _schochStats('P2', totalPoints: 20, buchholzValue: 70),
        _schochStats('P3', totalPoints: 10, buchholzValue: 50),
      ]);
      expect(detectShootoutGroups(ranking, 2, _schochChain), isEmpty);
    });

    test('M2-T07: points-equal pair with IDENTICAL Buchholz at the cut → '
        'shoot-out needed', () {
      // Same cut, but P1 & P2 are equal on BOTH points and Buchholz and the
      // pair straddles the cut → a real qualification-relevant shoot-out.
      final ranking = _rankedSchoch([
        _schochStats('P0', totalPoints: 30, buchholzValue: 100),
        _schochStats('P1', totalPoints: 20, buchholzValue: 80),
        _schochStats('P2', totalPoints: 20, buchholzValue: 80),
        _schochStats('P3', totalPoints: 10, buchholzValue: 50),
      ]);
      final groups = detectShootoutGroups(ranking, 2, _schochChain);
      expect(groups, hasLength(1));
      expect(groups.single.participantIds.toSet(), equals({'P1', 'P2'}));
      expect(groups.single.startRank, equals(1));
    });

    test('M2-T07: Buchholz is the load-bearing key — the same DIFFERENT-Buchholz '
        'pair DOES fire under a chain that ignores Buchholz', () {
      // Pins exactly the SQL bug (M2-T08): a tied-key WITHOUT Buchholz flags
      // point-equal Schoch players as tied and fires a spurious shoot-out that
      // the §5 Buchholz had already settled. With the points-only chain below
      // the pair straddles the cut and IS detected; the Schoch chain (above)
      // must not. Both run on the identical fixture.
      const pointsOnlyChain = TiebreakerChain([TiebreakerCriterion.totalPoints]);
      final stats = [
        _schochStats('P0', totalPoints: 30, buchholzValue: 100),
        _schochStats('P1', totalPoints: 20, buchholzValue: 90),
        _schochStats('P2', totalPoints: 20, buchholzValue: 70),
        _schochStats('P3', totalPoints: 10, buchholzValue: 50),
      ];
      final pointsRanking = [...stats]..sort(pointsOnlyChain.compare);
      final spurious = detectShootoutGroups(pointsRanking, 2, pointsOnlyChain);
      expect(spurious, hasLength(1));
      expect(spurious.single.participantIds.toSet(), equals({'P1', 'P2'}));
      // The Schoch chain on the same data fires nothing (Buchholz separates).
      expect(detectShootoutGroups(_rankedSchoch(stats), 2, _schochChain),
          isEmpty);
    });

    test('M2-T09: Schoch cosmetic tie — Buchholz-equal pair wholly above OR '
        'below the cut → no shoot-out (straddle does not apply)', () {
      // Tie wholly ABOVE the cut: P0 & P1 equal on points AND Buchholz at
      // ranks 0,1; cut = 3 → both safely qualified, decides nothing.
      final aboveCut = _rankedSchoch([
        _schochStats('P0', totalPoints: 30, buchholzValue: 100),
        _schochStats('P1', totalPoints: 30, buchholzValue: 100),
        _schochStats('P2', totalPoints: 20, buchholzValue: 80),
        _schochStats('P3', totalPoints: 10, buchholzValue: 50),
      ]);
      expect(detectShootoutGroups(aboveCut, 3, _schochChain), isEmpty);

      // Tie wholly BELOW the cut: P2 & P3 equal on points AND Buchholz at
      // ranks 2,3; cut = 1 → both safely out, decides nothing.
      final belowCut = _rankedSchoch([
        _schochStats('P0', totalPoints: 30, buchholzValue: 100),
        _schochStats('P1', totalPoints: 20, buchholzValue: 80),
        _schochStats('P2', totalPoints: 10, buchholzValue: 50),
        _schochStats('P3', totalPoints: 10, buchholzValue: 50),
      ]);
      expect(detectShootoutGroups(belowCut, 1, _schochChain), isEmpty);
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
      // C3: the contested last qualifier slot must NOT be filled by the
      // arbitrary participantId fallback. qualifiers is truncated at the
      // pending startRank (here 1) — P1 is not authoritatively placed.
      expect(res.qualifiers, equals(['P0']));
      expect(res.qualifiers, isNot(contains('P1')));
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
