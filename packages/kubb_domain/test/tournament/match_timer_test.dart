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

    test('different pausedAt / pausedAccumSeconds / onHold are not equal', () {
      final base = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 100)),
      );
      final pausedAt = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 100)),
        pausedAt: start.add(const Duration(seconds: 60)),
      );
      final accum = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 100)),
        pausedAccumSeconds: 30,
      );
      final hold = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 100)),
        onHold: true,
      );
      expect(base, isNot(equals(pausedAt)));
      expect(base, isNot(equals(accum)));
      expect(base, isNot(equals(hold)));
    });

    test('same pause inputs are equal and share a hashCode', () {
      MatchTimer build() => MatchTimer(
            startedAt: start,
            durationSeconds: 300,
            now: start.add(const Duration(seconds: 100)),
            tiebreakAfterSeconds: 200,
            pausedAt: start.add(const Duration(seconds: 60)),
            pausedAccumSeconds: 30,
            onHold: true,
          );
      expect(build(), equals(build()));
      expect(build().hashCode, equals(build().hashCode));
    });
  });

  group('MatchTimer - backward compatibility (defaults)', () {
    test('new fields default to null / 0 / false', () {
      final t = MatchTimer(startedAt: start, durationSeconds: 300, now: start);
      expect(t.pausedAt, isNull);
      expect(t.pausedAccumSeconds, 0);
      expect(t.onHold, isFalse);
      expect(t.isFrozen, isFalse);
    });

    test('default path remaining still counts past startedAt before start', () {
      // Frozen behaviour (see "basic timeline" group): with defaults, remaining
      // keeps counting down to endsAt, so a pre-start now yields > duration.
      final t = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.subtract(const Duration(seconds: 10)),
      );
      expect(t.elapsed, Duration.zero);
      expect(t.remaining, const Duration(seconds: 310));
      expect(t.isExpired, isFalse);
    });
  });

  group('MatchTimer - pause / resume (ADR-0031 formula)', () {
    test('pause freezes remaining: advancing now keeps remaining constant', () {
      // Paused at +100s on a 300s match: remaining should stay 200s no matter
      // how far now advances, because the (now - pausedAt) slice cancels it.
      final pausedAt = start.add(const Duration(seconds: 100));
      final a = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 100)),
        pausedAt: pausedAt,
      );
      final b = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 250)),
        pausedAt: pausedAt,
      );
      expect(a.remaining, const Duration(seconds: 200));
      expect(b.remaining, const Duration(seconds: 200));
      expect(a.elapsed, const Duration(seconds: 100));
      expect(b.elapsed, const Duration(seconds: 100));
      expect(b.isFrozen, isTrue);
      expect(b.isExpired, isFalse);
    });

    test('resume subtracts accumulated paused seconds', () {
      // Ran 100s, paused for 40s (now resumed: pausedAt null,
      // pausedAccumSeconds 40), now at +200s wall time. Effective elapsed =
      // 200 - 40 = 160 ⇒ remaining 140.
      final t = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 200)),
        pausedAccumSeconds: 40,
      );
      expect(t.elapsed, const Duration(seconds: 160));
      expect(t.remaining, const Duration(seconds: 140));
      expect(t.isFrozen, isFalse);
    });

    test('multi-pause: accumulated plus active pause sum without double count',
        () {
      // Previously paused 40s (accum), currently paused since +200s wall.
      // Effective elapsed = (now-start) - 40 - (now-pausedAt). At now=+260:
      // 260 - 40 - 60 = 160 ⇒ remaining 140. Advancing now keeps it frozen.
      final pausedAt = start.add(const Duration(seconds: 200));
      final a = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 260)),
        pausedAccumSeconds: 40,
        pausedAt: pausedAt,
      );
      final b = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 999)),
        pausedAccumSeconds: 40,
        pausedAt: pausedAt,
      );
      expect(a.elapsed, const Duration(seconds: 160));
      expect(a.remaining, const Duration(seconds: 140));
      // Frozen: same remaining for a much later now.
      expect(b.remaining, const Duration(seconds: 140));
    });

    test('now < startsAt ⇒ remaining is at least the full duration, elapsed 0',
        () {
      // Before the match starts the clock has not begun ticking down: elapsed
      // is clamped to zero and the player still has (at least) the full
      // duration left. Backward-compat note: with defaults `remaining` keeps
      // counting to endsAt (see the "basic timeline / before start" case), so
      // a pre-start now reads >= durationSeconds and is never expired.
      final t = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.subtract(const Duration(seconds: 30)),
      );
      expect(t.elapsed, Duration.zero);
      expect(t.remaining >= const Duration(seconds: 300), isTrue);
      expect(t.remaining, const Duration(seconds: 330));
      expect(t.isExpired, isFalse);
    });

    test('negative-clamp: pause cannot push elapsed below zero', () {
      // now before start, no pause: elapsed clamps to zero, remaining clamps
      // to a non-negative value.
      final t = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.subtract(const Duration(seconds: 5)),
      );
      expect(t.elapsed, Duration.zero);
      expect(t.remaining.isNegative, isFalse);
    });
  });

  group('MatchTimer - onHold', () {
    test('onHold freezes an expired timer (isExpired stays true)', () {
      // Match ran out at +300s; held afterwards. Remaining stays 0, elapsed
      // stays clamped at the duration, and it remains expired regardless of
      // how far now advances.
      final a = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 360)),
        onHold: true,
      );
      final b = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 1000)),
        onHold: true,
      );
      expect(a.isExpired, isTrue);
      expect(b.isExpired, isTrue);
      expect(a.remaining, Duration.zero);
      expect(a.elapsed, const Duration(seconds: 300));
      expect(b.elapsed, const Duration(seconds: 300));
      expect(a.isFrozen, isTrue);
    });

    test('onHold before expiry does not advance elapsed past now', () {
      // Held while still running: onHold only clamps the overshoot past
      // endsAt, so a not-yet-expired held timer behaves like the live clock.
      final t = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 120)),
        onHold: true,
      );
      expect(t.isExpired, isFalse);
      expect(t.elapsed, const Duration(seconds: 120));
      expect(t.remaining, const Duration(seconds: 180));
      expect(t.isFrozen, isTrue);
    });

    test('isFrozen truth table: 00 false, onHold true, paused true', () {
      final none = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 10)),
      );
      final held = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 10)),
        onHold: true,
      );
      final paused = MatchTimer(
        startedAt: start,
        durationSeconds: 300,
        now: start.add(const Duration(seconds: 10)),
        pausedAt: start.add(const Duration(seconds: 5)),
      );
      expect(none.isFrozen, isFalse);
      expect(held.isFrozen, isTrue);
      expect(paused.isFrozen, isTrue);
    });
  });
}
