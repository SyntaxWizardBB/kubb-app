import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

ParticipantStats statsFor(
  String id, {
  int totalPoints = 0,
  int wins = 0,
  int kubbsScored = 0,
  int kubbsConceded = 0,
  List<String> opponentIds = const [],
  Map<String, int> opponentTotalPointsLookup = const {},
  Map<String, int> headToHeadLookup = const {},
}) {
  return ParticipantStats(
    participantId: id,
    totalPoints: totalPoints,
    wins: wins,
    kubbsScored: kubbsScored,
    kubbsConceded: kubbsConceded,
    opponentIds: opponentIds,
    opponentTotalPointsLookup: opponentTotalPointsLookup,
    headToHeadLookup: headToHeadLookup,
  );
}

void main() {
  group('TiebreakerChain', () {
    test('it returns 0 when stats are identical and chain is exhausted', () {
      const chain = TiebreakerChain([
        TiebreakerCriterion.totalPoints,
        TiebreakerCriterion.wins,
        TiebreakerCriterion.kubbDifference,
      ]);
      final a = statsFor('a', totalPoints: 5, wins: 2, kubbsScored: 10);
      final b = statsFor('b', totalPoints: 5, wins: 2, kubbsScored: 10);
      expect(chain.compare(a, b), equals(0));
    });

    test('it ranks higher totalPoints first', () {
      const chain = TiebreakerChain([TiebreakerCriterion.totalPoints]);
      final a = statsFor('a', totalPoints: 7);
      final b = statsFor('b', totalPoints: 4);
      expect(chain.compare(a, b), lessThan(0));
      expect(chain.compare(b, a), greaterThan(0));
    });

    test('it falls through to next criterion when first ties', () {
      const chain = TiebreakerChain([
        TiebreakerCriterion.totalPoints,
        TiebreakerCriterion.wins,
      ]);
      final a = statsFor('a', totalPoints: 5, wins: 1);
      final b = statsFor('b', totalPoints: 5, wins: 3);
      expect(chain.compare(a, b), greaterThan(0));
    });

    test('it subtracts head-to-head wins in buchholzMinusH2H', () {
      const chain = TiebreakerChain([TiebreakerCriterion.buchholzMinusH2H]);
      final a = statsFor(
        'a',
        opponentIds: const ['b', 'c'],
        opponentTotalPointsLookup: const {'b': 5, 'c': 4},
        headToHeadLookup: const {'b': 5},
      );
      final b = statsFor(
        'b',
        opponentIds: const ['a', 'c'],
        opponentTotalPointsLookup: const {'a': 5, 'c': 4},
        headToHeadLookup: const {'a': -5},
      );
      // a buchholz=9, h2h vs b=5 -> 4. b buchholz=9, h2h vs a=-5 -> 14.
      expect(chain.compare(a, b), greaterThan(0));
    });

    test('it drops best and worst opponent in medianBuchholz', () {
      const chain = TiebreakerChain([TiebreakerCriterion.medianBuchholz]);
      final a = statsFor(
        'a',
        opponentIds: const ['x', 'y', 'z', 'w'],
        opponentTotalPointsLookup: const {'x': 10, 'y': 5, 'z': 4, 'w': 1},
      );
      final b = statsFor(
        'b',
        opponentIds: const ['x', 'y', 'z', 'w'],
        opponentTotalPointsLookup: const {'x': 6, 'y': 6, 'z': 6, 'w': 6},
      );
      // a median = 5+4 = 9 (drops 10 and 1). b median = 6+6 = 12.
      expect(chain.compare(a, b), greaterThan(0));
    });

    test('it falls back to buchholz when opponentCount < 2 in medianBuchholz',
        () {
      const chain = TiebreakerChain([TiebreakerCriterion.medianBuchholz]);
      final a = statsFor(
        'a',
        opponentIds: const ['x'],
        opponentTotalPointsLookup: const {'x': 9},
      );
      final b = statsFor(
        'b',
        opponentIds: const ['y'],
        opponentTotalPointsLookup: const {'y': 3},
      );
      expect(chain.compare(a, b), lessThan(0));
    });

    test('it uses (scored - conceded) in kubbDifference', () {
      const chain = TiebreakerChain([TiebreakerCriterion.kubbDifference]);
      final a = statsFor('a', kubbsScored: 30, kubbsConceded: 10);
      final b = statsFor('b', kubbsScored: 25, kubbsConceded: 20);
      expect(chain.compare(a, b), lessThan(0));
    });

    test('it returns 0 in directComparison if no direct match played', () {
      const chain = TiebreakerChain([TiebreakerCriterion.directComparison]);
      final a = statsFor('a');
      final b = statsFor('b');
      expect(chain.compare(a, b), equals(0));
    });

    test('it ranks the direct winner higher in directComparison', () {
      const chain = TiebreakerChain([TiebreakerCriterion.directComparison]);
      final a = statsFor('a', headToHeadLookup: const {'b': 1});
      final b = statsFor('b', headToHeadLookup: const {'a': -1});
      expect(chain.compare(a, b), lessThan(0));
      expect(chain.compare(b, a), greaterThan(0));
    });

    test('it ranks higher count first in wins criterion', () {
      const chain = TiebreakerChain([TiebreakerCriterion.wins]);
      final a = statsFor('a', wins: 4);
      final b = statsFor('b', wins: 2);
      expect(chain.compare(a, b), lessThan(0));
    });

    test('it gives same answer for random with same seed', () {
      const t1 =
          TiebreakerChain([TiebreakerCriterion.random], randomSeed: 42);
      const t2 =
          TiebreakerChain([TiebreakerCriterion.random], randomSeed: 42);
      final a = statsFor('alice');
      final b = statsFor('bob');
      expect(t1.compare(a, b), equals(t2.compare(a, b)));
    });

    test('it is symmetric in random (compare(a,b) == -compare(b,a))', () {
      const chain =
          TiebreakerChain([TiebreakerCriterion.random], randomSeed: 7);
      final a = statsFor('alice');
      final b = statsFor('bob');
      expect(chain.compare(a, b), equals(-chain.compare(b, a)));
    });
  });
}
