import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/realtime/realtime_channel_lifecycle.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Minimal transport-agnostic test-double over [RealtimeChannelLifecycle].
/// It records every `openTransport`/`teardownTransport` call so the shared
/// refcount / debounce / backoff mechanics can be pinned down without a real
/// Supabase backend (ADR-0029 FC-1). All timing runs through [FakeAsync].
class _TestLifecycle with RealtimeChannelLifecycle {
  _TestLifecycle({List<Duration>? backoff}) : _backoff = backoff;

  final List<Duration>? _backoff;

  int openCount = 0;
  int teardownCount = 0;
  final List<String> openedKeys = <String>[];

  @override
  List<Duration> get backoffSchedule =>
      _backoff ?? RealtimeChannelLifecycle.defaultBackoff;

  @override
  void openTransport(LifecycleEntry entry) {
    openCount += 1;
    openedKeys.add(entry.key);
    // Mark transport as live so teardownTransport has something to drop.
    entry.transport = Object();
    entry.stateController.add(RealtimeChannelState.connecting);
  }

  @override
  FutureOr<void> teardownTransport(LifecycleEntry entry) {
    if (entry.transport != null) {
      teardownCount += 1;
      entry.transport = null;
    }
  }

  /// Convenience: simulate a `subscribe()` for [key] (bump refcount, bind).
  LifecycleEntry subscribe(String key) => openOrAttach(key);
}

void main() {
  const keyA = 'tournament_matches:tournament_id=t1';
  const keyB = 'team_memberships:team_id=tm1';
  const backoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 30),
  ];

  test('(a) two subscribes for the same key share one entry, refCount==2', () {
    final lc = _TestLifecycle();
    expect(lc.subscribe(keyA), same(lc.subscribe(keyA)));
    expect(lc.entries[keyA]!.refCount, equals(2));
    // One underlying channel only — second subscribe does not re-open.
    expect(lc.openCount, equals(1));
  });

  test(
      '(b) first close keeps channel open; second close tears down after '
      'exactly 500 ms (0 at 499 ms, 1 at 500 ms)', () {
    FakeAsync().run((async) {
      final lc = _TestLifecycle();
      expect(lc.subscribe(keyA), same(lc.subscribe(keyA)));

      // First close: still one reference → channel stays open, no teardown.
      unawaited(lc.closeRef(keyA));
      async.elapse(const Duration(seconds: 2));
      expect(lc.teardownCount, equals(0));
      expect(lc.entries.containsKey(keyA), isTrue);

      // Second close: refcount hits zero → debounce starts.
      unawaited(lc.closeRef(keyA));
      async.elapse(const Duration(milliseconds: 499));
      expect(lc.teardownCount, equals(0));
      expect(lc.entries.containsKey(keyA), isTrue);

      async.elapse(const Duration(milliseconds: 1));
      expect(lc.teardownCount, equals(1));
      expect(lc.entries.containsKey(keyA), isFalse);
    });
  });

  test('(c) errored schedules reconnects on exactly 1/2/4/8/30 s', () {
    FakeAsync().run((async) {
      final lc = _TestLifecycle(backoff: backoff);
      final entry = lc.subscribe(keyA);

      // Step through the schedule; each errored arms the next-larger delay.
      for (final wait in backoff) {
        final before = lc.openCount;
        lc.pushState(entry, RealtimeChannelState.errored);
        // 1 ms short of the delay → reconnect has NOT fired yet.
        async.elapse(wait - const Duration(milliseconds: 1));
        expect(lc.openCount, equals(before),
            reason: 'reconnect fired early for $wait');
        async.elapse(const Duration(milliseconds: 1));
        expect(lc.openCount, equals(before + 1),
            reason: 'reconnect did not fire at $wait');
      }
      // Clamped: a further error reuses the last (30 s) delay and the
      // backoff index stays pinned to the final slot.
      final before = lc.openCount;
      lc.pushState(entry, RealtimeChannelState.errored);
      async.elapse(const Duration(seconds: 30));
      expect(lc.openCount, equals(before + 1));
      expect(entry.backoffIndex, equals(backoff.length - 1));
    });
  });

  test('(d) snapshotActiveKeys returns the active keys', () {
    final lc = _TestLifecycle()
      ..subscribe(keyA)
      ..subscribe(keyB);
    expect(lc.snapshotActiveKeys().toSet(), equals({keyA, keyB}));
  });

  test('(e) disconnectAll leaves 0 channels and 0 pending timers', () {
    FakeAsync().run((async) {
      final lc = _TestLifecycle();
      final entry = lc.subscribe(keyA);
      lc.subscribe(keyB);
      expect(lc.entries.length, equals(2));
      // Arm a reconnect timer and a pending-close timer to prove both
      // are cancelled by disconnectAll.
      lc.pushState(entry, RealtimeChannelState.errored);
      unawaited(lc.closeRef(keyB));
      expect(async.pendingTimers, isNotEmpty);

      unawaited(lc.disconnectAll());
      async.flushMicrotasks();

      expect(lc.entries, isEmpty);
      expect(async.pendingTimers, isEmpty);
      // Both live transports were torn down.
      expect(lc.teardownCount, equals(2));
    });
  });

  test('(f) reconnectKeys restores exactly the snapshot keys', () {
    FakeAsync().run((async) {
      final lc = _TestLifecycle()
        ..subscribe(keyA)
        ..subscribe(keyB);
      final snapshot = lc.snapshotActiveKeys();

      unawaited(lc.disconnectAll());
      async.flushMicrotasks();
      expect(lc.entries, isEmpty);

      lc.reconnectKeys(snapshot);
      expect(lc.entries.keys.toSet(), equals(snapshot.toSet()));
      expect(lc.entries.keys.toSet(), equals({keyA, keyB}));
      // No extra keys, no fewer.
      expect(lc.entries.length, equals(2));
    });
  });
}
