import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

MatchEkcScore winFor(SetWinner winner, {int kubbsByA = 0, int kubbsByB = 0}) {
  return MatchEkcScore([
    SetScore(
      basekubbsKnockedByA: kubbsByA,
      basekubbsKnockedByB: kubbsByB,
      winner: winner,
    ),
    SetScore(
      basekubbsKnockedByA: kubbsByA,
      basekubbsKnockedByB: kubbsByB,
      winner: winner,
    ),
  ]);
}

MatchEkcScore drawScore() => MatchEkcScore([
      SetScore(
        basekubbsKnockedByA: 5,
        basekubbsKnockedByB: 3,
        winner: SetWinner.teamA,
      ),
      SetScore(
        basekubbsKnockedByA: 2,
        basekubbsKnockedByB: 5,
        winner: SetWinner.teamB,
      ),
    ]);

TournamentMatchResult res(String a, String? b, MatchEkcScore s) =>
    TournamentMatchResult(participantA: a, participantB: b, score: s);

const chain = TiebreakerChain([
  TiebreakerCriterion.totalPoints,
  TiebreakerCriterion.wins,
  TiebreakerCriterion.kubbDifference,
]);

void main() {
  group('computeStandings', () {
    test('it ranks the sole winner first when one match is played', () {
      final out = computeStandings(
        participantIds: ['a', 'b'],
        results: [res('a', 'b', winFor(SetWinner.teamA, kubbsByA: 5))],
        tiebreaker: chain,
      );
      expect(out.first.participantId, equals('a'));
      expect(out.first.wins, equals(1));
      expect(out.last.participantId, equals('b'));
    });

    test('it credits a BYE as a win with the configured score', () {
      final out = computeStandings(
        participantIds: ['a', 'b'],
        results: [res('a', null, winFor(SetWinner.teamA))],
        tiebreaker: chain,
        byeScoreForUnopposedParticipant: 7,
      );
      final a = out.firstWhere((s) => s.participantId == 'a');
      expect(a.totalPoints, equals(7));
      expect(a.wins, equals(1));
      expect(a.opponentIds, isEmpty);
    });

    test('it sums basekubbs and wins across multiple matches', () {
      final out = computeStandings(
        participantIds: ['a', 'b', 'c'],
        results: [
          res('a', 'b', winFor(SetWinner.teamA, kubbsByA: 4, kubbsByB: 2)),
          res('a', 'c', winFor(SetWinner.teamA, kubbsByA: 3, kubbsByB: 1)),
        ],
        tiebreaker: chain,
      );
      final a = out.firstWhere((s) => s.participantId == 'a');
      expect(a.wins, equals(2));
      expect(a.kubbsScored, equals(4 * 2 + 3 * 2));
      expect(a.kubbsConceded, equals(2 * 2 + 1 * 2));
    });

    test(
        'opponentTotalPointsLookup reflects opponent final totals (Buchholz input)',
        () {
      // a beats b, b beats c. b's opponentTotalPointsLookup contains a and c.
      final out = computeStandings(
        participantIds: ['a', 'b', 'c'],
        results: [
          res('a', 'b', winFor(SetWinner.teamA)),
          res('b', 'c', winFor(SetWinner.teamA)),
        ],
        tiebreaker: chain,
      );
      final a = out.firstWhere((s) => s.participantId == 'a');
      final b = out.firstWhere((s) => s.participantId == 'b');
      final c = out.firstWhere((s) => s.participantId == 'c');
      expect(b.opponentTotalPointsLookup['a'], equals(a.totalPoints));
      expect(b.opponentTotalPointsLookup['c'], equals(c.totalPoints));
    });

    test('headToHeadLookup is symmetric (a beats b means a:+1, b:-1)', () {
      final out = computeStandings(
        participantIds: ['a', 'b'],
        results: [res('a', 'b', winFor(SetWinner.teamA))],
        tiebreaker: chain,
      );
      final a = out.firstWhere((s) => s.participantId == 'a');
      final b = out.firstWhere((s) => s.participantId == 'b');
      expect(a.headToHeadLookup['b'], equals(1));
      expect(b.headToHeadLookup['a'], equals(-1));
    });

    test('it returns a stable sort when tiebreaker chain ties through', () {
      const tiePoints = TiebreakerChain([TiebreakerCriterion.totalPoints]);
      final out = computeStandings(
        participantIds: ['a', 'b', 'c', 'd'],
        results: const [],
        tiebreaker: tiePoints,
      );
      expect(out.map((s) => s.participantId).toList(),
          equals(['a', 'b', 'c', 'd']));
    });

    test(
        'it applies the tiebreaker chain order (totalPoints first, then wins)',
        () {
      // 'a' and 'b' tie on totalPoints, but 'b' has more wins.
      // Use a custom draw to make pointsForA == pointsForB despite a win.
      final out = computeStandings(
        participantIds: ['a', 'b'],
        results: [
          // a: 1 win → 3 pts; b: 0 wins → 0 pts. Force tie on totalPoints by
          // also crediting 'b' with kubbs. Easier path: build matches so both
          // end at same totalPoints but differ in wins.
          res(
            'a',
            'b',
            MatchEkcScore([
              SetScore(
                basekubbsKnockedByA: 0,
                basekubbsKnockedByB: 3,
                winner: SetWinner.teamA,
              ),
            ]),
          ),
        ],
        tiebreaker: chain,
      );
      // a: pointsForA = 0 + 3 = 3, wins=1. b: pointsForB = 3 + 0 = 3, wins=0.
      // totalPoints tie at 3; chain falls to wins → a first.
      expect(out.first.participantId, equals('a'));
      expect(out.first.totalPoints, equals(out.last.totalPoints));
      expect(out.first.wins, equals(1));
    });

    test(
        'it handles a tournament where no matches have been played (everyone tied at 0)',
        () {
      final out = computeStandings(
        participantIds: ['a', 'b', 'c'],
        results: const [],
        tiebreaker: chain,
      );
      expect(out.length, equals(3));
      for (final s in out) {
        expect(s.totalPoints, equals(0));
        expect(s.wins, equals(0));
        expect(s.opponentIds, isEmpty);
      }
    });

    test('it produces correct rankings for the 4-participant round-robin '
        'example', () {
      // Round robin: a,b,c,d; 6 matches. Wins:
      //   a beats b, c, d → 3 wins
      //   b beats c, d    → 2 wins
      //   c beats d       → 1 win
      //   d              → 0 wins
      // Each win → +3 pts (no basekubbs). Loser → 0.
      final out = computeStandings(
        participantIds: ['a', 'b', 'c', 'd'],
        results: [
          res('a', 'b', winFor(SetWinner.teamA)),
          res('a', 'c', winFor(SetWinner.teamA)),
          res('a', 'd', winFor(SetWinner.teamA)),
          res('b', 'c', winFor(SetWinner.teamA)),
          res('b', 'd', winFor(SetWinner.teamA)),
          res('c', 'd', winFor(SetWinner.teamA)),
        ],
        tiebreaker: chain,
      );
      expect(
        out.map((s) => s.participantId).toList(),
        equals(['a', 'b', 'c', 'd']),
      );
      expect(out[0].wins, equals(3));
      expect(out[1].wins, equals(2));
      expect(out[2].wins, equals(1));
      expect(out[3].wins, equals(0));
      // Each match: winner gets 2 sets * 3 = 6 pts; loser 0.
      expect(out[0].totalPoints, equals(18));
      expect(out[3].totalPoints, equals(0));
    });

    test('it throws when a result references a participant not in '
        'participantIds', () {
      expect(
        () => computeStandings(
          participantIds: ['a', 'b'],
          results: [res('a', 'ghost', winFor(SetWinner.teamA))],
          tiebreaker: chain,
        ),
        throwsArgumentError,
      );
    });

    test('it handles drawn matches without crediting either side a win', () {
      final out = computeStandings(
        participantIds: ['a', 'b'],
        results: [res('a', 'b', drawScore())],
        tiebreaker: chain,
      );
      final a = out.firstWhere((s) => s.participantId == 'a');
      final b = out.firstWhere((s) => s.participantId == 'b');
      expect(a.wins, equals(0));
      expect(b.wins, equals(0));
      expect(a.headToHeadLookup['b'], equals(0));
      expect(b.headToHeadLookup['a'], equals(0));
    });
  });
}
