import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/app/realtime_lifecycle_controller.dart';
import 'package:kubb_app/core/data/realtime/realtime_channel_lifecycle.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../support/fake_app_lifecycle.dart';

/// Minimal lifecycle-capable CDC adapter double. Reuses the production
/// [RealtimeChannelLifecycle] mixin so snapshot/disconnect/reconnect behave
/// exactly as in prod, but records `openTransport` (reconnect) calls against
/// a shared recorder so we can assert the controller's ordering.
class _FakeAdapter with RealtimeChannelLifecycle {
  _FakeAdapter(this._recorder);

  final List<String> _recorder;

  @override
  void openTransport(LifecycleEntry entry) {
    _recorder.add('reconnect:${entry.key}');
    entry
      ..transport = Object()
      ..stateController.add(RealtimeChannelState.connecting);
  }

  @override
  FutureOr<void> teardownTransport(LifecycleEntry entry) {
    if (entry.transport != null) {
      entry.transport = null;
    }
  }

  /// Simulate a live subscription for [key].
  LifecycleEntry subscribe(String key) => openOrAttach(key);
}

void main() {
  const k1 = 'tournament_matches:tournament_id=t1';
  const k2 = 'team_memberships:team_id=tm1';

  ({
    RealtimeLifecycleController controller,
    _FakeAdapter adapter,
    List<String> recorder,
    FakeAppLifecycle lifecycle,
  }) setup({List<String> initialKeys = const [k1, k2]}) {
    final recorder = <String>[];
    final adapter = _FakeAdapter(recorder);
    initialKeys.forEach(adapter.subscribe);
    // Drop the `reconnect:` entries that the initial subscribe-bind emitted
    // so the recorder only carries controller-driven calls afterwards.
    recorder.clear();
    final controller = RealtimeLifecycleController(
      adapter: adapter,
      reSign: () async => recorder.add('re-sign'),
      pauseRefresher: () => recorder.add('pause-refresher'),
      resumeRefresher: () => recorder.add('resume-refresher'),
    );
    final lifecycle = FakeAppLifecycle(controller.onLifecycleState);
    return (
      controller: controller,
      adapter: adapter,
      recorder: recorder,
      lifecycle: lifecycle,
    );
  }

  test(
    '(a) paused -> after 5 s debounce snapshot=={k1,k2}, disconnectAll '
    'leaves 0 channels and 0 pending timers',
    () {
      fakeAsync((async) {
        final s = setup();
        s.lifecycle.paused();

        // Before the debounce elapses: nothing torn down yet.
        async.elapse(const Duration(seconds: 4, milliseconds: 999));
        expect(s.adapter.entries.length, equals(2),
            reason: 'teardown fired before the 5 s debounce');

        // Cross the 5 s threshold → snapshot + disconnectAll.
        async
          ..elapse(const Duration(milliseconds: 1))
          ..flushMicrotasks();

        expect(s.controller.lastSnapshot.toSet(), equals({k1, k2}));
        expect(s.adapter.entries, isEmpty, reason: '0 channels after teardown');
        expect(async.pendingTimers, isEmpty, reason: '0 pending timers');
        expect(s.recorder, contains('pause-refresher'));

        s.controller.dispose();
      });
    },
  );

  test(
    '(b) resumed -> re-sign runs BEFORE reconnect; reconnectKeys == snapshot',
    () {
      fakeAsync((async) {
        final s = setup();

        // Drive a full pause teardown first so a snapshot exists.
        s.lifecycle.paused();
        async
          ..elapse(const Duration(seconds: 5))
          ..flushMicrotasks();
        expect(s.adapter.entries, isEmpty);
        s.recorder.clear();

        // Resume: re-sign must precede every reconnect.
        s.lifecycle.resumed();
        async.flushMicrotasks();

        final reSignIdx = s.recorder.indexOf('re-sign');
        final firstReconnectIdx =
            s.recorder.indexWhere((e) => e.startsWith('reconnect:'));
        expect(reSignIdx, isNonNegative, reason: 're-sign was not called');
        expect(firstReconnectIdx, isNonNegative,
            reason: 'no reconnect happened');
        expect(reSignIdx, lessThan(firstReconnectIdx),
            reason: 're-sign must run BEFORE reconnect');

        // Exactly the snapshot keys came back — no more, no fewer.
        expect(s.adapter.entries.keys.toSet(), equals({k1, k2}));

        s.controller.dispose();
      });
    },
  );

  test('(c) inactive -> no-op (channels untouched, no teardown scheduled)', () {
    fakeAsync((async) {
      final s = setup();

      s.lifecycle.inactive();
      async
        ..elapse(const Duration(seconds: 10))
        ..flushMicrotasks();

      expect(s.adapter.entries.length, equals(2),
          reason: 'inactive must not tear channels down');
      expect(async.pendingTimers, isEmpty,
          reason: 'inactive must not arm a debounce');
      expect(s.recorder, isEmpty);

      s.controller.dispose();
    });
  });

  test('(d) detached -> immediate disconnectAll (no 5 s wait)', () {
    fakeAsync((async) {
      final s = setup();

      s.lifecycle.detached();
      // No virtual time elapsed at all — teardown is synchronous.
      async.flushMicrotasks();

      expect(s.controller.lastSnapshot.toSet(), equals({k1, k2}));
      expect(s.adapter.entries, isEmpty,
          reason: 'detached tears down immediately');
      expect(async.pendingTimers, isEmpty);
      expect(s.recorder, contains('pause-refresher'));

      s.controller.dispose();
    });
  });

  test(
    '(e) resumed -> re-sign BEFORE resume-refresher BEFORE reconnect; '
    'reconnectKeys is exactly the prior snapshot',
    () {
      fakeAsync((async) {
        final s = setup();

        // Pause to capture a snapshot, then resume.
        s.lifecycle.paused();
        async
          ..elapse(const Duration(seconds: 5))
          ..flushMicrotasks();
        s.recorder.clear();

        s.lifecycle.resumed();
        async.flushMicrotasks();

        final reSignIdx = s.recorder.indexOf('re-sign');
        final resumeRefresherIdx = s.recorder.indexOf('resume-refresher');
        final firstReconnectIdx =
            s.recorder.indexWhere((e) => e.startsWith('reconnect:'));

        expect(reSignIdx, isNonNegative);
        expect(resumeRefresherIdx, isNonNegative);
        expect(firstReconnectIdx, isNonNegative);
        // re-sign FIRST, then refresher resume, then reconnect — no Auth-Storm.
        expect(reSignIdx, lessThan(resumeRefresherIdx));
        expect(resumeRefresherIdx, lessThan(firstReconnectIdx));

        // Only the keys live at pause came back — no extras.
        expect(s.adapter.entries.keys.toSet(), equals({k1, k2}));
        expect(s.controller.lastSnapshot.toSet(), equals({k1, k2}));

        s.controller.dispose();
      });
    },
  );

  test('(f) hidden is treated like paused (5 s debounce -> teardown)', () {
    fakeAsync((async) {
      final s = setup();

      s.lifecycle.drive(AppLifecycleState.hidden);
      async.elapse(const Duration(seconds: 4, milliseconds: 999));
      expect(s.adapter.entries.length, equals(2),
          reason: 'hidden must honour the 5 s debounce like paused');

      async
        ..elapse(const Duration(milliseconds: 1))
        ..flushMicrotasks();
      expect(s.adapter.entries, isEmpty);
      expect(async.pendingTimers, isEmpty);

      s.controller.dispose();
    });
  });

  test('onLifecycleState routes paused + inactive', () {
    fakeAsync((async) {
      final s = setup(initialKeys: const [k1]);

      s.controller.onLifecycleState(AppLifecycleState.inactive);
      expect(s.adapter.entries.length, equals(1));

      s.controller.onLifecycleState(AppLifecycleState.paused);
      async
        ..elapse(const Duration(seconds: 5))
        ..flushMicrotasks();
      expect(s.adapter.entries, isEmpty);

      s.controller.dispose();
    });
  });
}
