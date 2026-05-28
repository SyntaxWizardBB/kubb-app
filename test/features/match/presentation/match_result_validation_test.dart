import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_result_screen.dart';

MatchAuditEvent _ev({
  required String kind,
  Map<String, dynamic>? payload,
  String? actor,
  DateTime? at,
}) {
  return MatchAuditEvent(
    kind: kind,
    actorUserId: actor,
    payload: payload ?? const <String, dynamic>{},
    at: at ?? DateTime(2026, 5, 27, 12),
  );
}

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

  group('extractHalfsetHistory', () {
    test('returns empty list when no proposal_received events present', () {
      final history = extractHalfsetHistory([
        _ev(kind: 'created'),
        _ev(kind: 'started'),
        _ev(kind: 'awaiting_results_started'),
      ]);
      expect(history, isEmpty);
    });

    test('extracts one row per proposal_received event, sorted by round', () {
      final history = extractHalfsetHistory([
        _ev(kind: 'proposal_received', payload: {
          'round': 2,
          'score_a': 5,
          'score_b': 6,
        }),
        _ev(kind: 'proposal_received', payload: {
          'round': 1,
          'score_a': 6,
          'score_b': 4,
        }),
        _ev(kind: 'round_bumped', payload: {'from': 1, 'to': 2}),
      ]);
      expect(history, hasLength(2));
      expect(history[0].round, 1);
      expect(history[0].scoreA, 6);
      expect(history[0].scoreB, 4);
      expect(history[1].round, 2);
      expect(history[1].scoreA, 5);
      expect(history[1].scoreB, 6);
    });

    test('keeps the latest proposal per round on duplicates', () {
      final history = extractHalfsetHistory([
        _ev(kind: 'proposal_received', payload: {
          'round': 1,
          'score_a': 5,
          'score_b': 5,
        }),
        _ev(kind: 'proposal_received', payload: {
          'round': 1,
          'score_a': 6,
          'score_b': 4,
        }),
      ]);
      expect(history, hasLength(1));
      expect(history[0].round, 1);
      expect(history[0].scoreA, 6);
      expect(history[0].scoreB, 4);
    });

    test('ignores malformed payloads', () {
      final history = extractHalfsetHistory([
        _ev(kind: 'proposal_received', payload: {
          'round': 'not-a-number',
          'score_a': 1,
          'score_b': 0,
        }),
        _ev(kind: 'proposal_received', payload: {
          'round': 1,
          'score_a': null,
          'score_b': 2,
        }),
      ]);
      expect(history, isEmpty);
    });
  });
}
