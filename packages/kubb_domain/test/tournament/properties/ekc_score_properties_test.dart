import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../_support/king_outcome_generators.dart';
import '../../_support/tournament_generators.dart';

void main() {
  group('computeEkc properties', () {
    Glados<MatchEkcScore>(any.matchEkcScore())
        .test('each set credits the 3-point bonus to the set winner', (match) {
      var bonusA = 0;
      var bonusB = 0;
      for (final set in match.sets) {
        if (set.winner == SetWinner.teamA) {
          bonusA += 3;
        } else {
          bonusB += 3;
        }
      }
      final basekubbsA =
          match.sets.fold<int>(0, (s, x) => s + x.basekubbsKnockedByA);
      final basekubbsB =
          match.sets.fold<int>(0, (s, x) => s + x.basekubbsKnockedByB);
      expect(match.pointsForA, bonusA + basekubbsA);
      expect(match.pointsForB, bonusB + basekubbsB);
    });

    Glados<MatchEkcScore>(any.matchEkcScore())
        .test('sets won by either team sum to total sets played', (match) {
      expect(match.setsWonA + match.setsWonB, match.sets.length);
    });

    test('an empty match scores zero points for both teams', () {
      final empty = computeEkc(const []);
      expect(empty.pointsForA, 0);
      expect(empty.pointsForB, 0);
      expect(empty.setsWonA, 0);
      expect(empty.setsWonB, 0);
      expect(empty.matchWinner, isNull);
    });

    Glados<MatchEkcScore>(any.matchEkcScore()).test(
        'computeEkc reconstructs an equivalent score from the same sets',
        (match) {
      final rebuilt = computeEkc(match.sets);
      expect(rebuilt.pointsForA, match.pointsForA);
      expect(rebuilt.pointsForB, match.pointsForB);
      expect(rebuilt.setsWonA, match.setsWonA);
      expect(rebuilt.setsWonB, match.setsWonB);
    });

    // R11-F-01: a TimedOut set contributes 0:0 to the EKC tally, so a
    // match made entirely of TimedOut sets must score 0 for both teams.
    Glados<MatchEkcScore>(any.timedOutMatch()).test(
      'a TimedOut-only match scores zero EKC points additively',
      (match) {
        expect(match.pointsForA, 0);
        expect(match.pointsForB, 0);
      },
    );
  });
}
