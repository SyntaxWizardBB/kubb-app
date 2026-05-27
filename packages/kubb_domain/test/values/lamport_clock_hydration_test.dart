// Property-tests pinning the public API contract of `LamportClock`'s
// hydration helpers. Implementation lands in TASK-M4.3-T8 — until then these
// tests are expected to fail (UnimplementedError); the goal of this file is
// to lock the signatures and acceptance behaviour described in
// TASK-M4.3-T4.

import 'dart:async';

import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

void main() {
  group('LamportClock.hydrateFromOutbox', () {
    test('advances past the highest outbox counter seen for the pair', () {
      final clock = LamportClock(deviceId: const DeviceId('dev-a'));
      const matchId = MatchId('match-1');
      const deviceId = DeviceId('dev-a');

      // Mock outbox counters: [3, 7, 5] — the maximum is 7.
      clock.hydrateFromOutbox(matchId, deviceId, 7);

      expect(clock.tick().counter, equals(8));
    });

    test('observeFromStream lifts the counter above later server max', () {
      final clock = LamportClock(deviceId: const DeviceId('dev-a'));
      const matchId = MatchId('match-1');
      const deviceId = DeviceId('dev-a');

      clock.hydrateFromOutbox(matchId, deviceId, 10);

      final controller = StreamController<int>();
      clock.observeFromStream(controller.stream);
      controller.add(15);

      // The clock must have absorbed the server-side maximum before the
      // next local tick; the next emission must therefore be 16.
      expect(clock.tick().counter, equals(16));
      unawaited(controller.close());
    });

    test('two clocks for different (match, device) pairs stay independent',
        () {
      final clockA = LamportClock(deviceId: const DeviceId('dev-a'));
      final clockB = LamportClock(deviceId: const DeviceId('dev-b'));

      clockA.hydrateFromOutbox(
        const MatchId('match-1'),
        const DeviceId('dev-a'),
        4,
      );
      clockB.hydrateFromOutbox(
        const MatchId('match-2'),
        const DeviceId('dev-b'),
        9,
      );

      expect(clockA.tick().counter, equals(5));
      expect(clockB.tick().counter, equals(10));
    });

    Glados<int>(any.intInRange(0, 1 << 20)).test(
      'forall n >= 0: hydrateFromOutbox(n) then tick() > n',
      (n) {
        final clock = LamportClock(deviceId: const DeviceId('dev-prop'))
          ..hydrateFromOutbox(
            const MatchId('match-prop'),
            const DeviceId('dev-prop'),
            n,
          );
        expect(clock.tick().counter, greaterThan(n));
      },
    );
  });
}
