import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/realtime/realtime_channel_lifecycle.dart';

/// Orchestrates the foreground/background Realtime lifecycle against the
/// app-wide CDC adapter singleton (ADR-0029 §(c) TR-P0-3 / FC-8).
///
/// SKELETON ONLY — the class, its seams and the [realtimeLifecycleControllerProvider]
/// exist here so the resume/pause sequence can be unit-tested in isolation
/// (Test class D). The controller is deliberately NOT live-wired into
/// `lib/app/app.dart`; that happens with FC-9 in phase P5. Until then the
/// existing `AppLifecycleListener` / `_reSignOnResume` in `KubbApp` stays
/// the production path.
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
  /// Left null in the skeleton; FC-9 wires `forceReSignWireSessionProvider`.
  final Future<void> Function()? _reSign;

  /// Refresher-pause seam (TR-P0-3). On `paused`/`detached` the keypair
  /// session refresher should stop its timer; on `resumed` it resumes.
  /// Defined as a seam only here — NOT live-wired until FC-9/P5.
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

/// Provider for the lifecycle controller (TR-P0-3). Bound to the app-wide
/// CDC adapter singleton via `realtimeChannelProvider`.
///
/// SKELETON: this provider is intentionally NOT watched anywhere in the
/// widget tree — FC-9/P5 activates it from `KubbApp`. The re-sign and
/// refresher seams stay null until then.
final Provider<RealtimeLifecycleController?> realtimeLifecycleControllerProvider =
    Provider<RealtimeLifecycleController?>((ref) {
  // The adapter is the `realtimeChannelProvider` singleton, which is a
  // `RealtimeChannelLifecycle` in production (`SupabaseRealtimeChannel`).
  // Returning null when the override does not expose the mixin keeps the
  // skeleton inert in containers that have not wired the production adapter.
  // FC-9 will read the real adapter + seams here.
  return null;
});
