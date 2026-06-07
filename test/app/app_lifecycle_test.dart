import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/app/app.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/app/realtime_lifecycle_controller.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/data/realtime/realtime_channel_lifecycle.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/auth/application/keypair_session_refresher.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/training/application/crash_recovery_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../fixtures/auth/fake_supabase_auth_adapter.dart';

/// Lifecycle-capable CDC adapter double (reuses the production
/// [RealtimeChannelLifecycle] mixin) that records every controller-driven
/// reconnect against a shared recorder, so the WIRING (KubbApp → controller →
/// adapter) can be asserted end-to-end — not just the controller in isolation.
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
    _recorder.add('teardown:${entry.key}');
    entry.transport = null;
  }

  LifecycleEntry subscribe(String key) => openOrAttach(key);
}

/// Bare CDC port double that implements ONLY the [RealtimeChannel] interface
/// and deliberately does NOT mix in [RealtimeChannelLifecycle]. Used to drive
/// the inert branch of [realtimeLifecycleControllerProvider] (FC-8/FC-9 cast
/// seam): an adapter without the lifecycle hooks must yield a `null` controller
/// so KubbApp stays inert instead of crashing.
class _BarePortChannel implements RealtimeChannel {
  @override
  Stream<RealtimeChange> subscribe({
    required String table,
    required String filterColumn,
    required String filterValue,
  }) =>
      const Stream<RealtimeChange>.empty();

  @override
  Future<void> close(String channelKey) async {}

  @override
  Stream<RealtimeChannelState> stateStream(String channelKey) =>
      const Stream<RealtimeChannelState>.empty();
}

/// Lifecycle-capable CDC port double: a [RealtimeChannel] that ALSO mixes in
/// [RealtimeChannelLifecycle], i.e. the shape of the production
/// `SupabaseRealtimeChannel` singleton. Drives the live branch of the cast
/// seam (controller must be non-null).
class _MixinPortChannel with RealtimeChannelLifecycle
    implements RealtimeChannel {
  @override
  Stream<RealtimeChange> subscribe({
    required String table,
    required String filterColumn,
    required String filterValue,
  }) =>
      const Stream<RealtimeChange>.empty();

  @override
  Future<void> close(String channelKey) async {}

  @override
  Stream<RealtimeChannelState> stateStream(String channelKey) =>
      const Stream<RealtimeChannelState>.empty();

  @override
  void openTransport(LifecycleEntry entry) {
    entry.transport = Object();
  }

  @override
  FutureOr<void> teardownTransport(LifecycleEntry entry) {
    entry.transport = null;
  }
}

class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  _FakeAppSettingsNotifier(this._initial);

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;
}

class _StubAuthController extends AuthController {
  _StubAuthController(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;
}

void main() {
  const k1 = 'tournament_matches:tournament_id=t1';

  testWidgets(
    'KubbApp routes lifecycle states into the controller: paused tears the '
    'socket down + pauses the refresher; resume re-signs BEFORE reconnect',
    (tester) async {
      final recorder = <String>[];
      final adapter = _FakeAdapter(recorder)..subscribe(k1);
      // Drop the initial subscribe-bind so the recorder only carries
      // controller-driven calls.
      recorder.clear();

      // Build the controller with the fake adapter + recorder seams and
      // override the provider so KubbApp drives THIS controller. A short
      // debounce keeps the test fast (still a one-shot timer).
      final controller = RealtimeLifecycleController(
        adapter: adapter,
        reSign: () async => recorder.add('re-sign'),
        pauseRefresher: () => recorder.add('pause-refresher'),
        resumeRefresher: () => recorder.add('resume-refresher'),
        pauseDebounce: const Duration(milliseconds: 50),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appSettingsProvider.overrideWith(
              () => _FakeAppSettingsNotifier(
                const AppSettings(),
              ),
            ),
            appBootstrapProvider.overrideWith((ref) async => null),
            authControllerProvider.overrideWith(
              () => _StubAuthController(
                const AuthSession.keypair(
                  userId: 'test-id',
                  displayName: 'Test',
                ),
              ),
            ),
            recentSessionsProvider.overrideWith(
              (ref) => Stream.value(const <RecentSessionView>[]),
            ),
            crashRecoveryProvider.overrideWith((ref) async => null),
            realtimeLifecycleControllerProvider.overrideWithValue(controller),
          ],
          child: const KubbApp(),
        ),
      );
      await tester.pumpAndSettle();

      // --- backgrounding: the OS walks inactive → hidden → paused. The
      // controller arms the 5 s (here 50 ms) debounce on paused. -----------
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      // Channel still live before the debounce fires.
      expect(adapter.entries.length, equals(1));

      // Cross the debounce → snapshot + disconnectAll + refresher pause.
      await tester.pump(const Duration(milliseconds: 60));

      expect(adapter.entries, isEmpty,
          reason: 'paused must leave 0 channels (disconnectAll wired)');
      expect(recorder, contains('teardown:$k1'));
      expect(recorder, contains('pause-refresher'),
          reason: 'paused must pause the keypair refresher');
      expect(controller.lastSnapshot, equals(<String>[k1]));

      recorder.clear();

      // --- foregrounding: the OS walks paused → hidden → inactive →
      // resumed. Re-sign FIRST, then refresher resume, then reconnect. ------
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      final reSignIdx = recorder.indexOf('re-sign');
      final resumeRefresherIdx = recorder.indexOf('resume-refresher');
      final firstReconnectIdx =
          recorder.indexWhere((e) => e.startsWith('reconnect:'));

      expect(reSignIdx, isNonNegative, reason: 're-sign was not driven');
      expect(firstReconnectIdx, isNonNegative, reason: 'no reconnect happened');
      expect(reSignIdx, lessThan(firstReconnectIdx),
          reason: 're-sign must run BEFORE reconnect (no Auth-Storm)');
      expect(resumeRefresherIdx, isNonNegative);
      expect(reSignIdx, lessThan(resumeRefresherIdx));

      // Exactly the previously-active key came back.
      expect(adapter.entries.keys, equals(<String>[k1]));
    },
  );

  testWidgets('inactive is a no-op: KubbApp leaves the socket untouched',
      (tester) async {
    final recorder = <String>[];
    final adapter = _FakeAdapter(recorder)..subscribe(k1);
    recorder.clear();

    final controller = RealtimeLifecycleController(
      adapter: adapter,
      reSign: () async => recorder.add('re-sign'),
      pauseRefresher: () => recorder.add('pause-refresher'),
      resumeRefresher: () => recorder.add('resume-refresher'),
      pauseDebounce: const Duration(milliseconds: 50),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(
            () => _FakeAppSettingsNotifier(
              const AppSettings(),
            ),
          ),
          appBootstrapProvider.overrideWith((ref) async => null),
          authControllerProvider.overrideWith(
            () => _StubAuthController(
              const AuthSession.keypair(userId: 'test-id', displayName: 'Test'),
            ),
          ),
          recentSessionsProvider.overrideWith(
            (ref) => Stream.value(const <RecentSessionView>[]),
          ),
          crashRecoveryProvider.overrideWith((ref) async => null),
          realtimeLifecycleControllerProvider.overrideWithValue(controller),
        ],
        child: const KubbApp(),
      ),
    );
    await tester.pumpAndSettle();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 1));

    expect(adapter.entries.length, equals(1),
        reason: 'inactive must not tear the channel down');
    expect(recorder, isEmpty,
        reason: 'inactive must not drive any seam');
  });

  // --- FC8-01/FC8-02 cast seam ------------------------------------------
  // The two widget tests above override `realtimeLifecycleControllerProvider`
  // directly, so they never exercise the provider's OWN wiring path
  // (`realtimeChannelProvider` → checked cast to `RealtimeChannelLifecycle`).
  // These container-level tests pin exactly that seam: a bare `RealtimeChannel`
  // (no mixin) must yield a `null` controller (inert), while the production-
  // shaped mixin adapter must yield a live controller bound to that SAME
  // singleton instance (no second instantiation).
  group('realtimeLifecycleControllerProvider cast seam (FC-8)', () {
    ProviderContainer makeContainer(RealtimeChannel channel) {
      final container = ProviderContainer(
        overrides: [
          realtimeChannelProvider.overrideWithValue(channel),
          // Build a real refresher over the auth-adapter fake so the live
          // branch can read `pause`/`resume` seams without the production
          // Supabase wiring.
          keypairSessionRefresherProvider.overrideWith(
            (ref) => KeypairSessionRefresher(
              adapter: FakeSupabaseAuthAdapter(),
              reSign: () async {},
            ),
          ),
          forceReSignWireSessionProvider.overrideWithValue(
            () async => WireSessionOutcome.keypairResigned,
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('bare RealtimeChannel without the mixin → null controller (inert)',
        () {
      final container = makeContainer(_BarePortChannel());
      expect(
        container.read(realtimeLifecycleControllerProvider),
        isNull,
        reason: 'an adapter without RealtimeChannelLifecycle must stay inert',
      );
    });

    test('mixin-capable adapter → non-null controller bound to that singleton',
        () async {
      final channel = _MixinPortChannel();
      final container = makeContainer(channel);
      final controller =
          container.read(realtimeLifecycleControllerProvider);
      expect(controller, isNotNull,
          reason: 'a RealtimeChannelLifecycle adapter must be wired live');

      // The controller drives the SAME singleton: a detach teardown runs
      // disconnectAll against `channel` (proving the wiring binds the live
      // instance, not a duplicate).
      channel.openOrAttach('tournament_matches:tournament_id=t1');
      expect(channel.entries.length, equals(1));
      controller!.onLifecycleState(AppLifecycleState.detached);
      // disconnectAll awaits teardownTransport, so let the microtask drain.
      await Future<void>.delayed(Duration.zero);
      expect(channel.entries, isEmpty,
          reason: 'detach must tear the wired singleton down immediately');
    });
  });
}
