import 'package:kubb_domain/src/tournament/ekc_score.dart';
import 'package:test/test.dart';

void main() {
  group('SetScore', () {
    test('it throws on negative basekubb counts', () {
      expect(
        () => SetScore(
          basekubbsKnockedByA: -1,
          basekubbsKnockedByB: 2,
          winner: SetWinner.teamA,
        ),
        throwsArgumentError,
      );
      expect(
        () => SetScore(
          basekubbsKnockedByA: 1,
          basekubbsKnockedByB: -2,
          winner: SetWinner.teamB,
        ),
        throwsArgumentError,
      );
    });

    test('it does value equality on SetScore', () {
      final a = SetScore(
        basekubbsKnockedByA: 5,
        basekubbsKnockedByB: 2,
        winner: SetWinner.teamA,
      );
      final b = SetScore(
        basekubbsKnockedByA: 5,
        basekubbsKnockedByB: 2,
        winner: SetWinner.teamA,
      );
      final c = SetScore(
        basekubbsKnockedByA: 5,
        basekubbsKnockedByB: 2,
        winner: SetWinner.teamB,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('computeEkc', () {
    test('it credits 3 bonus points to the set winner', () {
      final result = computeEkc([
        SetScore(
          basekubbsKnockedByA: 0,
          basekubbsKnockedByB: 0,
          winner: SetWinner.teamA,
        ),
      ]);
      expect(result.pointsForA, 3);
      expect(result.pointsForB, 0);
    });

    test('it credits 1 point per basekubb knocked, regardless of set winner',
        () {
      final result = computeEkc([
        SetScore(
          basekubbsKnockedByA: 2,
          basekubbsKnockedByB: 4,
          winner: SetWinner.teamA,
        ),
      ]);
      expect(result.pointsForA, 2 + 3);
      expect(result.pointsForB, 4);
    });

    test('it sums points across all sets in the match', () {
      final result = computeEkc([
        SetScore(
          basekubbsKnockedByA: 1,
          basekubbsKnockedByB: 2,
          winner: SetWinner.teamA,
        ),
        SetScore(
          basekubbsKnockedByA: 3,
          basekubbsKnockedByB: 0,
          winner: SetWinner.teamB,
        ),
      ]);
      expect(result.pointsForA, 1 + 3 + 3);
      expect(result.pointsForB, 2 + 0 + 3);
    });

    test('it counts sets won correctly', () {
      final result = computeEkc([
        SetScore(
          basekubbsKnockedByA: 5,
          basekubbsKnockedByB: 0,
          winner: SetWinner.teamA,
        ),
        SetScore(
          basekubbsKnockedByA: 0,
          basekubbsKnockedByB: 5,
          winner: SetWinner.teamB,
        ),
        SetScore(
          basekubbsKnockedByA: 5,
          basekubbsKnockedByB: 1,
          winner: SetWinner.teamA,
        ),
      ]);
      expect(result.setsWonA, 2);
      expect(result.setsWonB, 1);
    });

    test('matchWinner is the team with more sets won', () {
      final result = computeEkc([
        SetScore(
          basekubbsKnockedByA: 5,
          basekubbsKnockedByB: 0,
          winner: SetWinner.teamA,
        ),
        SetScore(
          basekubbsKnockedByA: 5,
          basekubbsKnockedByB: 0,
          winner: SetWinner.teamA,
        ),
      ]);
      expect(result.matchWinner, SetWinner.teamA);
    });

    test('matchWinner is null when both teams have equal sets', () {
      final result = computeEkc([
        SetScore(
          basekubbsKnockedByA: 5,
          basekubbsKnockedByB: 0,
          winner: SetWinner.teamA,
        ),
        SetScore(
          basekubbsKnockedByA: 0,
          basekubbsKnockedByB: 5,
          winner: SetWinner.teamB,
        ),
      ]);
      expect(result.matchWinner, isNull);
    });

    test('matchWinner is null on empty match', () {
      final result = computeEkc(const []);
      expect(result.matchWinner, isNull);
      expect(result.pointsForA, 0);
      expect(result.pointsForB, 0);
    });

    test('it computes the example case bo3 ending 2-1 with given tallies', () {
      final result = computeEkc([
        SetScore(
          basekubbsKnockedByA: 5,
          basekubbsKnockedByB: 2,
          winner: SetWinner.teamA,
        ),
        SetScore(
          basekubbsKnockedByA: 1,
          basekubbsKnockedByB: 5,
          winner: SetWinner.teamB,
        ),
        SetScore(
          basekubbsKnockedByA: 4,
          basekubbsKnockedByB: 3,
          winner: SetWinner.teamA,
        ),
      ]);
      expect(result.pointsForA, 16);
      expect(result.pointsForB, 13);
      expect(result.setsWonA, 2);
      expect(result.setsWonB, 1);
      expect(result.matchWinner, SetWinner.teamA);
    });

    test('it does value equality on MatchEkcScore', () {
      final sets = [
        SetScore(
          basekubbsKnockedByA: 5,
          basekubbsKnockedByB: 2,
          winner: SetWinner.teamA,
        ),
        SetScore(
          basekubbsKnockedByA: 1,
          basekubbsKnockedByB: 5,
          winner: SetWinner.teamB,
        ),
      ];
      final a = computeEkc(sets);
      final b = computeEkc([
        SetScore(
          basekubbsKnockedByA: 5,
          basekubbsKnockedByB: 2,
          winner: SetWinner.teamA,
        ),
        SetScore(
          basekubbsKnockedByA: 1,
          basekubbsKnockedByB: 5,
          winner: SetWinner.teamB,
        ),
      ]);
      final c = computeEkc([
        SetScore(
          basekubbsKnockedByA: 5,
          basekubbsKnockedByB: 2,
          winner: SetWinner.teamA,
        ),
      ]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
