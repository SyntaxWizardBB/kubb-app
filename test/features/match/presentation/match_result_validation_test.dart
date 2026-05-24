import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/match/presentation/match_result_screen.dart';

void main() {
  group('validateMatchResult', () {
    test('zero-zero score is rejected', () {
      expect(
        validateMatchResult(scoreA: 0, scoreB: 0),
        'Score fehlt',
      );
    });

    test('equal non-zero score is rejected', () {
      expect(
        validateMatchResult(scoreA: 2, scoreB: 2),
        'Score muss eindeutig sein',
      );
    });

    test('negative scores are rejected', () {
      expect(
        validateMatchResult(scoreA: -1, scoreB: 0),
        'Punkte dürfen nicht negativ sein',
      );
    });

    test('clear lead is accepted', () {
      expect(validateMatchResult(scoreA: 2, scoreB: 1), isNull);
      expect(validateMatchResult(scoreA: 1, scoreB: 3), isNull);
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
