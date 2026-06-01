import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1, 12);

  group('MatchTimer - basic timeline (300s match)', () {
    MatchTimer at(DateTime now) =>
        MatchTimer(startedAt: start, durationSeconds: 300, now: now);

    test('before start: elapsed 0, fraction 0, not expired', () {
      final t = at(start.subtract(const Duration(seconds: 10)));
      // elapsed is clamped to zero before start...
      expect(t.elapsed, Duration.zero);
      // ...while remaining counts down to endsAt (310s away here).
      expect(t.remaining, const Duration(seconds: 310));
      expect(t.fractionElapsed, 0.0);
      expect(t.isExpired, isFalse);
    });

    test('at start: full remaining, fraction 0, not expired', () {
      final t = at(start);
      expect(t.remaining, const Duration(seconds: 300));
      expect(t.fractionElapsed, 0.0);
      expect(t.isExpired, isFalse);
    });

    test('mid: half remaining, fraction 0.5', () {
      final t = at(start.add(const Duration(seconds: 150)));
      expect(t.elapsed, const Duration(seconds: 150));
      expect(t.remaining, const Duration(seconds: 150));
      expect(t.fractionElapsed, closeTo(0.5, 1e-9));
      expect(t.isExpired, isFalse);
    });

    test('exactly at expiry: zero remaining, fraction 1, expired', () {
      final t = at(start.add(const Duration(seconds: 300)));
      expect(t.remaining, Duration.zero);
      expect(t.fractionElapsed, 1.0);
      expect(t.isExpired, isTrue);
    });

    test('past expiry: remaining clamped to zero, fraction clamped to 1', () {
      final t = at(start.add(const Duration(seconds: 450)));
      expect(t.elapsed, const Duration(seconds: 450));
      expect(t.remaining, Duration.zero);
      expect(t.fractionElapsed, 1.0);
      expect(t.isExpired, isTrue);
    });

    test('endsAt is startedAt + duration', () {
      expect(at(start).endsAt, start.add(const Duration(seconds: 300)));
    });
  });

  group('MatchTimer - clamping / edge inputs', () {
    test('negative durationSeconds is clamped to zero', () {
      final t = MatchTimer(startedAt: start, durationSeconds: -10, now: start);
      expect(t.durationSeconds, 0);
      expect(t.endsAt, start);
    });

    test('zero-duration match is expired at/after start, fraction 1', () {
      final t = MatchTimer(startedAt: start, durationSeconds: 0, now: start);
      expect(t.isExpired, isTrue);
      expect(t.remaining, Duration.zero);
      expect(t.fractionElapsed, 1.0);
    });

    test('zero-duration match is not expired strictly before start', () {
      final t = MatchTimer(
        startedAt: start,
        durationSeconds: 0,
        now: start.subtract(const Duration(seconds: 1)),
      );
      expect(t.isExpired, isFalse);
      expect(t.fractionElapsed, 0.0);
    });
  });

  group('MatchTimer - tiebreak trigger', () {
    MatchTimer at(DateTime now) => MatchTimer(
          startedAt: start,
          durationSeconds: 300,
          now: now,
          tiebreakAfterSeconds: 200,
        );

    test('no tiebreak configured: tiebreakAt null, never reached', () {
      final t = MatchTimer(startedAt: start, durationSeconds: 300, now: start);
      expect(t.tiebreakAt, isNull);
      expect(t.tiebreakReached, isFalse);
    });

    test('before boundary: not reached', () {
      final t = at(start.add(const Duration(seconds: 199)));
      expect(t.tiebreakAt, start.add(const Duration(seconds: 200)));
      expect(t.tiebreakReached, isFalse);
    });

    test('exactly at boundary: reached', () {
      final t = at(start.add(const Duration(seconds: 200)));
      expect(t.tiebreakReached, isTrue);
    });

    test('after boundary: reached', () {
      final t = at(start.add(const Duration(seconds: 250)));
      expect(t.tiebreakReached, isTrue);
    });

    test('negative tiebreakAfterSeconds is clamped to zero', () {
      final t = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start,
        tiebreakAfterSeconds: -5,
      );
      expect(t.tiebreakAfterSeconds, 0);
      expect(t.tiebreakAt, start);
      expect(t.tiebreakReached, isTrue);
    });
  });

  group('MatchTimer - value equality', () {
    test('same inputs are equal and share a hashCode', () {
      final a = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start,
        tiebreakAfterSeconds: 200,
      );
      final b = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start,
        tiebreakAfterSeconds: 200,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different now is not equal', () {
      final a = MatchTimer(startedAt: start, durationSeconds: 300, now: start);
      final b = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 1)),
      );
      expect(a, isNot(equals(b)));
    });
  });
}
