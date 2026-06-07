import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/realtime/realtime_channel_lifecycle.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart'
    show forceReSignWireSessionProvider;
import 'package:kubb_app/features/auth/application/keypair_session_refresher.dart'
    show keypairSessionRefresherProvider;
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart'
    show realtimeChannelProvider;

/// Orchestrates the foreground/background Realtime lifecycle against the
/// app-wide CDC adapter singleton (ADR-0029 §(c) TR-P0-3 / FC-8).
///
/// LIVE-WIRED (FC-9 / phase P5): `KubbApp` watches
/// [realtimeLifecycleControllerProvider] and routes EVERY [AppLifecycleState]
/// into [onLifecycleState]; the controller owns the single production
/// lifecycle path (the old `AppLifecycleListener` / `_reSignOnResume` is gone).
/// The provider binds the real `realtimeChannelProvider` singleton (cast to
/// its [RealtimeChannelLifecycle] mixin) plus the re-sign and refresher seams.
///
/// Sequence (ADR-0029 §"battery lifecycle"):
/// - `resumed`  → re-sign FIRST (seam), THEN [RealtimeChannelLifecycle.reconnectKeys]
///                with the snapshot taken on the preceding pause.
/// - `inactive` → no-op (transient OS state, e.g. notification shade).
/// - `paused`   → after a 5 s debounce: snapshot the active keys, then
///                [RealtimeChannelLifecycle.disconnectAll] (zero sockets,
///                zero pending timers) plus the refresher-pause seam.
/// - `detached` → immediate [RealtimeChannelLifecycle.disconnectAll] (no
///                debounce — the process is going away).
///
/// The debounce uses a single one-shot [Timer]; there is intentionally NO
/// `Timer.periodic` anywhere (battery invariant).
class RealtimeLifecycleController {
  RealtimeLifecycleController({
    required RealtimeChannelLifecycle adapter,
    Future<void> Function()? reSign,
    void Function()? pauseRefresher,
    void Function()? resumeRefresher,
    Duration pauseDebounce = defaultPauseDebounce,
  })  : _adapter = adapter,
        _reSign = reSign,
        _pauseRefresher = pauseRefresher,
        _resumeRefresher = resumeRefresher,
        _pauseDebounce = pauseDebounce;

  /// Default debounce before tearing channels down on `paused`. Mirrors the
  /// ADR-0029 5 s window so a quick app-switch does not thrash the socket.
  static const Duration defaultPauseDebounce = Duration(seconds: 5);

  /// The lifecycle-capable CDC adapter (the `realtimeChannelProvider`
  /// singleton in production; a fake in tests). Owns the
  /// snapshot/disconnect/reconnect mechanics via the shared mixin.
  final RealtimeChannelLifecycle _adapter;

  /// Re-sign seam (TR-P0-3). On `resumed` this runs BEFORE any reconnect so
  /// the keypair wire session is fresh before a subscription re-authorises.
  /// Wired by FC-9 to `forceReSignWireSessionProvider`.
  final Future<void> Function()? _reSign;

  /// Refresher-pause seam (TR-P0-3). On `paused`/`detached` the keypair
  /// session refresher stops its timer; on `resumed` it resumes after re-sign.
  /// Wired by FC-9 to `KeypairSessionRefresher.pause`/`resume`.
  final void Function()? _pauseRefresher;
  final void Function()? _resumeRefresher;

  final Duration _pauseDebounce;

  /// Pending 5 s pause-debounce. One-shot; cancelled by any state change
  /// before it fires. Never a periodic timer.
  Timer? _pauseTimer;

  /// Keys captured at the last pause teardown, restored on the next resume.
  List<String> _snapshot = const <String>[];

  /// Snapshot exposed for tests / diagnostics.
  List<String> get lastSnapshot => List<String>.unmodifiable(_snapshot);

  /// Routes a Flutter [AppLifecycleState] onto the matching handler.
  void onLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        resume();
      case AppLifecycleState.inactive:
        // No-op: transient OS overlay; keep the socket as-is.
        break;
      case AppLifecycleState.paused:
        pause();
      case AppLifecycleState.detached:
        detach();
      case AppLifecycleState.hidden:
        // Treated like `paused` on platforms that emit `hidden`.
        pause();
    }
  }

  /// `paused`: arm (or re-arm) the 5 s debounce. When it fires we snapshot
  /// the active keys, tear every channel down and pause the refresher.
  void pause() {
    _pauseTimer?.cancel();
    _pauseTimer = Timer(_pauseDebounce, _teardown);
  }

  /// `resumed`: cancel any pending pause teardown, re-sign FIRST, then
  /// reconnect exactly the keys captured on the last teardown.
  void resume() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    unawaited(_resumeSequence());
  }

  /// `detached`: tear everything down immediately (no debounce).
  void detach() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
    _teardown();
  }

  Future<void> _resumeSequence() async {
    // Re-sign BEFORE reconnect so the refreshed wire session authorises the
    // re-subscribe (ADR-0029 order invariant).
    final reSign = _reSign;
    if (reSign != null) {
      await reSign();
    }
    _resumeRefresher?.call();
    _adapter.reconnectKeys(_snapshot);
  }

  void _teardown() {
    _pauseTimer = null;
    _snapshot = _adapter.snapshotActiveKeys();
    unawaited(_adapter.disconnectAll());
    _pauseRefresher?.call();
  }

  /// Releases the pending debounce timer. Does NOT tear channels down — that
  /// is the lifecycle's job, not disposal's.
  void dispose() {
    _pauseTimer?.cancel();
    _pauseTimer = null;
  }
}

/// Provider for the lifecycle controller (TR-P0-3 / FC-8 / FC-9). Bound to
/// the app-wide CDC adapter singleton via `realtimeChannelProvider`.
///
/// LIVE: `KubbApp` watches this provider and feeds every [AppLifecycleState]
/// into [RealtimeLifecycleController.onLifecycleState]. The adapter is the
/// `realtimeChannelProvider` singleton (`SupabaseRealtimeChannel`), which
/// mixes in [RealtimeChannelLifecycle]; we cast to that mixin at the wiring
/// point so the snapshot/disconnect/reconnect mechanics run on the ONE shared
/// adapter (FC-10(c): no second instantiation). When the wired adapter does
/// not expose the mixin (a bare test fake), the controller is omitted so the
/// app stays inert rather than crashing — KubbApp treats null as "no lifecycle
/// management".
///
/// Seams:
/// - re-sign  → `forceReSignWireSessionProvider` (runs FIRST on resume).
/// - refresher pause/resume → `KeypairSessionRefresher.pause`/`resume`.
final Provider<RealtimeLifecycleController?> realtimeLifecycleControllerProvider =
    Provider<RealtimeLifecycleController?>((ref) {
  final adapter = ref.watch(realtimeChannelProvider);
  // The production singleton (`SupabaseRealtimeChannel`) mixes in
  // `RealtimeChannelLifecycle`; the `RealtimeChannel` port itself does not
  // expose those hooks, so reach the mixin via a checked cast here (FC-8/
  // FC-10(c): one shared instance, no second instantiation).
  if (adapter is! RealtimeChannelLifecycle) {
    // The wired adapter does not expose the lifecycle mixin (e.g. a minimal
    // test fake). Stay inert — no lifecycle teardown/restore happens.
    return null;
  }
  // Reach the mixin on the ONE shared singleton via an explicit cast (FC-8/
  // FC-10(c): no second instantiation). The guard above already proved the
  // type; the cast keeps the strongly-typed adapter argument unambiguous.
  final lifecycleAdapter = adapter as RealtimeChannelLifecycle;
  final refresher = ref.read(keypairSessionRefresherProvider);
  final controller = RealtimeLifecycleController(
    adapter: lifecycleAdapter,
    reSign: ref.read(forceReSignWireSessionProvider),
    pauseRefresher: refresher.pause,
    resumeRefresher: refresher.resume,
  );
  ref.onDispose(controller.dispose);
  return controller;
});
