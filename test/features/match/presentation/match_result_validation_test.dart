import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_result_screen.dart';

void main() {
  group('validateMatchResult', () {
    test('zero-zero score is rejected', () {
      for (final scoring in MatchScoring.values) {
        expect(
          validateMatchResult(scoring: scoring, scoreA: 0, scoreB: 0),
          'Score fehlt',
          reason: 'scoring=$scoring',
        );
      }
    });

    test('equal non-zero score is rejected for both scoring modes', () {
      for (final scoring in MatchScoring.values) {
        expect(
          validateMatchResult(scoring: scoring, scoreA: 2, scoreB: 2),
          'Score muss eindeutig sein',
          reason: 'scoring=$scoring',
        );
      }
    });

    test('negative scores are rejected', () {
      expect(
        validateMatchResult(
          scoring: MatchScoring.wins,
          scoreA: -1,
          scoreB: 0,
        ),
        'Punkte dürfen nicht negativ sein',
      );
    });

    test('clear lead is accepted for both scoring modes', () {
      expect(
        validateMatchResult(
          scoring: MatchScoring.wins,
          scoreA: 2,
          scoreB: 1,
        ),
        isNull,
      );
      expect(
        validateMatchResult(
          scoring: MatchScoring.points,
          scoreA: 5,
          scoreB: 2,
        ),
        isNull,
      );
    });
  });

  group('deriveWinner', () {
    test('returns A when team A leads', () {
      expect(deriveWinner(3, 1), 'A');
    });

    test('returns B when team B leads', () {
      expect(deriveWinner(1, 3), 'B');
    });

    test('returns null on an equal score', () {
      expect(deriveWinner(0, 0), isNull);
      expect(deriveWinner(2, 2), isNull);
    });
  });
}
