import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_result_screen.dart';

void main() {
  group('validateMatchResult — wins scoring', () {
    test('missing winner is rejected', () {
      expect(
        validateMatchResult(
          scoring: MatchScoring.wins,
          scoreA: 2,
          scoreB: 1,
          winner: null,
        ),
        'Sieger fehlt',
      );
    });

    test('winner set is accepted regardless of score columns', () {
      expect(
        validateMatchResult(
          scoring: MatchScoring.wins,
          scoreA: 0,
          scoreB: 0,
          winner: 'A',
        ),
        isNull,
      );
      expect(
        validateMatchResult(
          scoring: MatchScoring.wins,
          scoreA: 3,
          scoreB: 2,
          winner: 'B',
        ),
        isNull,
      );
    });
  });

  group('validateMatchResult — points scoring', () {
    test('tie with no winner is accepted', () {
      expect(
        validateMatchResult(
          scoring: MatchScoring.points,
          scoreA: 4,
          scoreB: 4,
          winner: null,
        ),
        isNull,
      );
    });

    test('tie with a winner picked is rejected', () {
      expect(
        validateMatchResult(
          scoring: MatchScoring.points,
          scoreA: 4,
          scoreB: 4,
          winner: 'A',
        ),
        'Punktegleichstand: bitte Unentschieden wählen',
      );
    });

    test('non-tie without a winner is rejected', () {
      expect(
        validateMatchResult(
          scoring: MatchScoring.points,
          scoreA: 5,
          scoreB: 2,
          winner: null,
        ),
        'Sieger fehlt',
      );
    });

    test('winner mismatches higher score', () {
      expect(
        validateMatchResult(
          scoring: MatchScoring.points,
          scoreA: 2,
          scoreB: 5,
          winner: 'A',
        ),
        'Punkte stimmen nicht mit Sieger überein',
      );
    });

    test('winner equals leader is accepted', () {
      expect(
        validateMatchResult(
          scoring: MatchScoring.points,
          scoreA: 5,
          scoreB: 2,
          winner: 'A',
        ),
        isNull,
      );
      expect(
        validateMatchResult(
          scoring: MatchScoring.points,
          scoreA: 2,
          scoreB: 5,
          winner: 'B',
        ),
        isNull,
      );
    });
  });

  group('validateMatchResult — generic guards', () {
    test('negative scores are rejected', () {
      expect(
        validateMatchResult(
          scoring: MatchScoring.wins,
          scoreA: -1,
          scoreB: 0,
          winner: 'A',
        ),
        'Punkte dürfen nicht negativ sein',
      );
    });

    test('unknown winner token is rejected', () {
      expect(
        validateMatchResult(
          scoring: MatchScoring.points,
          scoreA: 3,
          scoreB: 1,
          winner: 'C',
        ),
        'Ungültiger Sieger',
      );
    });
  });
}
