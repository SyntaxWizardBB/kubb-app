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

  // CF2 / ChangeSpec K04: the scoring mode steers the point source.
  group('computeStandings scoring mode (CF2)', () {
    // Best-of-3 ending 2:1 for A, with arbitrary basekubbs per set.
    MatchEkcScore boSomeKubbs({
      required int kubbsA,
      required int kubbsB,
    }) =>
        MatchEkcScore([
          SetScore(
            basekubbsKnockedByA: kubbsA,
            basekubbsKnockedByB: kubbsB,
            winner: SetWinner.teamA,
          ),
          SetScore(
            basekubbsKnockedByA: kubbsB,
            basekubbsKnockedByB: kubbsA,
            winner: SetWinner.teamB,
          ),
          SetScore(
            basekubbsKnockedByA: kubbsA,
            basekubbsKnockedByB: kubbsB,
            winner: SetWinner.teamA,
          ),
        ]);

    test('scoring=ekc is the default and reproduces the historical total', () {
      final m = boSomeKubbs(kubbsA: 4, kubbsB: 2);
      final explicit = computeStandings(
        participantIds: ['a', 'b'],
        results: [res('a', 'b', m)],
        tiebreaker: chain,
        // explicitly asserting the ekc value equals the default is the point
        // ignore: avoid_redundant_argument_values
        scoring: TournamentScoring.ekc,
      );
      final defaulted = computeStandings(
        participantIds: ['a', 'b'],
        results: [res('a', 'b', m)],
        tiebreaker: chain,
      );
      final a = explicit.firstWhere((s) => s.participantId == 'a');
      final b = explicit.firstWhere((s) => s.participantId == 'b');
      // EKC: A wins sets 1+3 (4 kubbs + 3 bonus each) and loses set 2 (2),
      //      = 4+3 + 2 + 4+3 = 16. B = 2 + 4+3 + 2 = 11.
      expect(a.totalPoints, equals(16));
      expect(b.totalPoints, equals(11));
      // Default param must match the explicit ekc result exactly.
      expect(
        defaulted.map((s) => (s.participantId, s.totalPoints)).toList(),
        equals(explicit.map((s) => (s.participantId, s.totalPoints)).toList()),
      );
    });

    test('scoring=classic counts only set wins, not basekubbs', () {
      final out = computeStandings(
        participantIds: ['a', 'b'],
        results: [res('a', 'b', boSomeKubbs(kubbsA: 4, kubbsB: 2))],
        tiebreaker: chain,
        scoring: TournamentScoring.classic,
      );
      final a = out.firstWhere((s) => s.participantId == 'a');
      final b = out.firstWhere((s) => s.participantId == 'b');
      // 2:1 sets → A 2 points, B 1 point. Basekubbs do not contribute.
      expect(a.totalPoints, equals(2));
      expect(b.totalPoints, equals(1));
    });

    test('classic: varying basekubbs does not change the points', () {
      final lowKubbs = computeStandings(
        participantIds: ['a', 'b'],
        results: [res('a', 'b', boSomeKubbs(kubbsA: 1, kubbsB: 0))],
        tiebreaker: chain,
        scoring: TournamentScoring.classic,
      );
      final highKubbs = computeStandings(
        participantIds: ['a', 'b'],
        results: [res('a', 'b', boSomeKubbs(kubbsA: 6, kubbsB: 5))],
        tiebreaker: chain,
        scoring: TournamentScoring.classic,
      );
      int pts(List<ParticipantStats> s, String id) =>
          s.firstWhere((e) => e.participantId == id).totalPoints;
      // Same set outcome (2:1), wildly different kubbs → identical points.
      expect(pts(lowKubbs, 'a'), equals(pts(highKubbs, 'a')));
      expect(pts(lowKubbs, 'b'), equals(pts(highKubbs, 'b')));
      expect(pts(highKubbs, 'a'), equals(2));
      expect(pts(highKubbs, 'b'), equals(1));
      // kubbsScored still tracks the real kubbs for the tiebreak.
      final aHigh = highKubbs.firstWhere((s) => s.participantId == 'a');
      final aLow = lowKubbs.firstWhere((s) => s.participantId == 'a');
      expect(aHigh.kubbsScored, isNot(equals(aLow.kubbsScored)));
    });

    test('classic: kubb-difference breaks a set-win tie without changing '
        'totalPoints', () {
      // a and b each win one match 1:0; c loses both. a beats c with more
      // kubbs than b beats c, so a > b on kubbDifference at equal points.
      MatchEkcScore winA({required int kA, required int kB}) => MatchEkcScore([
            SetScore(
              basekubbsKnockedByA: kA,
              basekubbsKnockedByB: kB,
              winner: SetWinner.teamA,
            ),
          ]);
      final out = computeStandings(
        participantIds: ['a', 'b', 'c'],
        results: [
          // a beats c with a wide kubb margin.
          res('a', 'c', winA(kA: 6, kB: 0)),
          // b beats c with a narrow kubb margin.
          res('b', 'c', winA(kA: 6, kB: 5)),
        ],
        tiebreaker: const TiebreakerChain([
          TiebreakerCriterion.totalPoints,
          TiebreakerCriterion.kubbDifference,
        ]),
        scoring: TournamentScoring.classic,
      );
      final a = out.firstWhere((s) => s.participantId == 'a');
      final b = out.firstWhere((s) => s.participantId == 'b');
      // Equal set wins → equal points under classic, despite different kubbs.
      expect(a.totalPoints, equals(1));
      expect(b.totalPoints, equals(1));
      expect(a.totalPoints, equals(b.totalPoints));
      // kubbDifference tiebreak orders a ahead of b.
      expect(out.indexWhere((s) => s.participantId == 'a'),
          lessThan(out.indexWhere((s) => s.participantId == 'b')));
    });
  });

  group('schochByeScoreFor', () {
    test('Schoch and its KO hybrid grant a full-win bye', () {
      expect(schochByeScoreFor(TournamentFormat.schoch), equals(16));
      expect(schochByeScoreFor(TournamentFormat.schochThenKo), equals(16));
      expect(schochByeScoreFor(TournamentFormat.schoch), equals(schochByeScore));
    });

    test('every other format keeps the zero bye', () {
      expect(schochByeScoreFor(TournamentFormat.roundRobin), equals(0));
      expect(schochByeScoreFor(TournamentFormat.singleElimination), equals(0));
      expect(schochByeScoreFor(TournamentFormat.roundRobinThenKo), equals(0));
    });

    test('feeds 16 into a Schoch bye player and 0 into a round-robin one', () {
      final byes = [res('a', null, winFor(SetWinner.teamA))];
      final schoch = computeStandings(
        participantIds: ['a', 'b'],
        results: byes,
        tiebreaker: chain,
        byeScoreForUnopposedParticipant:
            schochByeScoreFor(TournamentFormat.schoch),
      );
      final roundRobin = computeStandings(
        participantIds: ['a', 'b'],
        results: byes,
        tiebreaker: chain,
        byeScoreForUnopposedParticipant:
            schochByeScoreFor(TournamentFormat.roundRobin),
      );
      expect(schoch.firstWhere((s) => s.participantId == 'a').totalPoints,
          equals(16));
      expect(roundRobin.firstWhere((s) => s.participantId == 'a').totalPoints,
          equals(0));
    });
  });
}
