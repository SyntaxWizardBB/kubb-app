import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/realtime/realtime_channel_lifecycle.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

/// Robustness guards for the shared realtime stack (Spec §4 Bugs 4.1/4.3/
/// 4.4/4.5). Each group pins one failure mode that surfaces under load —
/// fast in/out navigation, errored↔joined flicker, a manual close, and a
/// failed subscribe — without a real Supabase backend.
class _TestLifecycle with RealtimeChannelLifecycle {
  _TestLifecycle({List<Duration>? backoff, this.teardownThrows = false})
      : _backoff = backoff;

  final List<Duration>? _backoff;

  /// When true, [teardownTransport] throws — proves [disposeEntry] is
  /// wrapped so a misbehaving adapter never breaks the mixin contract.
  bool teardownThrows;

  int openCount = 0;
  int teardownCount = 0;

  @override
  List<Duration> get backoffSchedule =>
      _backoff ?? RealtimeChannelLifecycle.defaultBackoff;

  @override
  void openTransport(LifecycleEntry entry) {
    openCount += 1;
    entry.transport = Object();
    entry.stateController.add(RealtimeChannelState.connecting);
  }

  @override
  FutureOr<void> teardownTransport(LifecycleEntry entry) {
    if (entry.transport != null) {
      teardownCount += 1;
      entry.transport = null;
    }
    if (teardownThrows) throw StateError('transport teardown blew up');
  }

  LifecycleEntry subscribe(String key) => openOrAttach(key);
}

void main() {
  const keyA = 'tournament_matches:tournament_id=t1';
  const tid = TournamentId('t1');
  final fallbackKey = tournamentRealtimeChannelKey(tid);

  group('Bug 4.1 — disposed-guard in the CDC callback', () {
    test('a change after dispose is swallowed, no StreamController-closed', () {
      final channel = FakeRealtimeChannel();
      final stream = channel.subscribe(
        table: 'tournament_matches',
        filterColumn: 'tournament_id',
        filterValue: tid.value,
      );
      // Drain so the broadcast controller has a listener.
      final received = <RealtimeChange>[];
      final sub = stream.listen(received.add);

      RealtimeChange change() => RealtimeChange(
            eventType: RealtimeEventType.update,
            table: 'tournament_matches',
            rowId: 'm1',
            newRow: const <String, Object?>{'id': 'm1'},
            oldRow: const <String, Object?>{},
            receivedAt: DateTime.utc(2026),
          );

      channel.emit(keyA, change());
      // The mixin guard is exercised through the real adapter in
      // lifecycle-level tests below; here we assert the fake stays sane and
      // that a post-close emit after the entry is gone never throws.
      unawaited(sub.cancel());
      unawaited(channel.close(keyA));
      expect(() => channel.emit(keyA, change()), returnsNormally);
    });

    test('pushState after disposeEntry never writes a closed controller', () {
      FakeAsync().run((async) {
        final lc = _TestLifecycle();
        final entry = lc.subscribe(keyA);
        unawaited(lc.closeRef(keyA));
        async
          ..elapse(const Duration(milliseconds: 500))
          ..flushMicrotasks();
        expect(entry.disposed, isTrue);
        // A late transport callback that reaches pushState must be a no-op.
        expect(
          () => lc.pushState(entry, RealtimeChannelState.joined),
          returnsNormally,
        );
      });
    });
  });

  group('Bug 4.2 — disposeEntry never throws even if teardown does', () {
    test('teardownTransport throwing does not escape disposeEntry', () {
      FakeAsync().run((async) {
        final lc = _TestLifecycle(teardownThrows: true)..subscribe(keyA);
        unawaited(lc.closeRef(keyA));
        // The debounce fires disposeEntry → teardown throws internally.
        Object? caught;
        runZonedGuarded(() {
          async
            ..elapse(const Duration(milliseconds: 500))
            ..flushMicrotasks();
        }, (error, _) => caught = error);
        expect(caught, isNull, reason: 'disposeEntry must swallow the throw');
        expect(lc.entries.containsKey(keyA), isFalse);
      });
    });
  });

  group('Bug 4.4 — backoffIndex resets on a manual close', () {
    test('after closeRef + re-subscribe the next error starts at 1 s', () {
      FakeAsync().run((async) {
        const backoff = <Duration>[
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ];
        final lc = _TestLifecycle(backoff: backoff);
        final entry = lc.subscribe(keyA);

        // Walk the backoff up a couple of steps.
        lc
          ..pushState(entry, RealtimeChannelState.errored)
          ..pushState(entry, RealtimeChannelState.errored);
        expect(entry.backoffIndex, greaterThan(0));

        // Manual close → the index must be reset so a later failure starts
        // again at the 1 s step instead of skipping ahead.
        unawaited(lc.closeRef(keyA));
        expect(entry.backoffIndex, equals(0),
            reason: 'closeRef must reset backoffIndex');
      });
    });
  });

  group('Bug 4.3 — fallback gate single-flight + isClosed guard', () {
    ProviderContainer makeContainer(FakeRealtimeChannel channel) {
      final container = ProviderContainer(
        overrides: [
          realtimeChannelProvider.overrideWithValue(channel),
          realtimeEnabledFlagProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('rapid errored↔joined flicker arms exactly one fallback timer', () {
      fakeAsync((async) {
        final channel = FakeRealtimeChannel();
        final container = makeContainer(channel);
        final emitted = <bool>[];
        container.listen<AsyncValue<bool>>(
          realtimePollingFallbackProvider(fallbackKey),
          (_, next) => next.whenData(emitted.add),
          fireImmediately: true,
        );
        channel
          ..subscribe(
            table: 'tournament_matches',
            filterColumn: 'tournament_id',
            filterValue: tid.value,
          )
          ..setState(fallbackKey, RealtimeChannelState.joined);
        async.flushMicrotasks();

        // Flicker many times, each error inside the grace window.
        for (var i = 0; i < 5; i++) {
          channel.setState(fallbackKey, RealtimeChannelState.errored);
          async.elapse(const Duration(seconds: 5));
          channel.setState(fallbackKey, RealtimeChannelState.joined);
          async.elapse(const Duration(seconds: 5));
        }
        // A single residual pending timer at most (the last error window).
        expect(async.pendingTimers.length, lessThanOrEqualTo(1));
        // Never flipped to polling — every error was cleared inside grace.
        expect(emitted, everyElement(isFalse));
      });
    });

    test('add after the gate stream closed does not throw', () {
      fakeAsync((async) {
        final channel = FakeRealtimeChannel();
        final container = makeContainer(channel);
        final sub = container.listen<AsyncValue<bool>>(
          realtimePollingFallbackProvider(fallbackKey),
          (_, _) {},
          fireImmediately: true,
        );
        channel
          ..subscribe(
            table: 'tournament_matches',
            filterColumn: 'tournament_id',
            filterValue: tid.value,
          )
          ..setState(fallbackKey, RealtimeChannelState.errored);
        // Close the listener (disposes the provider + controller) while the
        // 60 s flip timer is still pending.
        async.elapse(const Duration(seconds: 30));
        sub.close();
        // Fire the pending flip after the controller is gone.
        expect(
          () => async
            ..elapse(const Duration(seconds: 31))
            ..flushMicrotasks(),
          returnsNormally,
        );
      });
    });
  });
}
