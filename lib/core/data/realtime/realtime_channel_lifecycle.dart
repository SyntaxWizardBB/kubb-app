import 'dart:async';

import 'package:kubb_domain/kubb_domain.dart';

/// Shared lifecycle mechanics for every Realtime transport adapter (CDC and
/// Broadcast). Extracted from the `SupabaseRealtimeChannel` adapter so the
/// CDC and the broadcast adapter no longer duplicate the same refcount /
/// debounce / backoff machinery (ADR-0029 §(c) FC-1).
///
/// The mixin is **transport-agnostic**: it never references a concrete
/// Supabase type. Concrete adapters supply the transport via the two seams
/// [openTransport] (bind the underlying channel for the entry's key) and
/// [teardownTransport] (tear it down). Everything else — reference counting
/// per channel-key, the 500 ms close-debounce, the exponential reconnect
/// backoff `1/2/4/8/30 s` and the per-key `stateStream` — lives here.
///
/// Concrete adapters keep one [LifecycleEntry] per channel-key inside the
/// mixin's [entries] map and may stash a transport handle on the entry's
/// [LifecycleEntry.transport] slot.
mixin RealtimeChannelLifecycle {
  /// Exponential reconnect backoff applied on `errored`. Exactly
  /// `1/2/4/8/30 s`; the final value is clamped and re-used for every
  /// further failure (steady-state).
  static const List<Duration> defaultBackoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 30),
  ];

  /// Default delay before the final teardown once the refcount hits zero.
  /// Protects against WebSocket thrashing (R-M4.1-2-Mitigation).
  static const Duration defaultCloseDebounce = Duration(milliseconds: 500);

  /// Live entries keyed by channel-key. Visible to concrete adapters so
  /// they can attach transport handles and read entry state.
  final Map<String, LifecycleEntry> entries = <String, LifecycleEntry>{};

  /// The close-debounce window. Adapters may override via their ctor.
  Duration get closeDebounce => defaultCloseDebounce;

  /// The reconnect backoff schedule. Adapters may override via their ctor.
  List<Duration> get backoffSchedule => defaultBackoff;

  // --- Transport seams (implemented by concrete adapters) ------------------

  /// Binds the underlying transport channel for [entry] (e.g. open the
  /// Supabase channel and start the subscribe handshake). Called on first
  /// subscribe and on every reconnect attempt. The adapter is responsible
  /// for pushing [RealtimeChannelState] updates via
  /// [pushState] in reaction to transport events.
  void openTransport(LifecycleEntry entry);

  /// Tears down the underlying transport channel for [entry] (best-effort).
  /// Called exactly once when the close-debounce fires with refcount zero,
  /// and during reconnect before re-binding. Must not throw.
  FutureOr<void> teardownTransport(LifecycleEntry entry);

  // --- Refcount + subscribe/close ------------------------------------------

  /// Opens (or attaches to) the entry for [key]. First caller binds the
  /// transport; subsequent callers just bump the refcount and cancel any
  /// pending close. Returns the shared entry.
  LifecycleEntry openOrAttach(String key) {
    final existing = entries[key];
    if (existing != null) {
      existing
        ..pendingClose?.cancel()
        ..pendingClose = null
        ..refCount += 1;
      return existing;
    }
    final entry = LifecycleEntry(key: key)..refCount = 1;
    entries[key] = entry;
    openTransport(entry);
    return entry;
  }

  /// Drops one reference on [channelKey]. When the last reference leaves the
  /// entry is scheduled for teardown after [closeDebounce]; a subscribe
  /// inside the window cancels the pending close.
  Future<void> closeRef(String channelKey) async {
    final entry = entries[channelKey];
    if (entry == null) return;
    if (entry.refCount > 0) entry.refCount -= 1;
    if (entry.refCount > 0) return;
    // A manual close cancels any in-flight reconnect and resets the backoff
    // so a re-subscribe inside the debounce window (or a later failure on a
    // re-opened entry) starts again at the 1 s step instead of skipping the
    // early stages of the schedule (Spec Bug 4.4).
    entry
      ..reconnectTimer?.cancel()
      ..reconnectTimer = null
      ..backoffIndex = 0
      ..pendingClose?.cancel()
      ..pendingClose = Timer(closeDebounce, () => disposeEntry(entry));
  }

  /// Tears down [entry] for good: cancels timers, removes it from the map,
  /// tears down the transport (exactly once) and closes the controllers.
  Future<void> disposeEntry(LifecycleEntry entry) async {
    if (entry.disposed) return;
    if (entry.refCount > 0) return;
    entry.disposed = true;
    entry.reconnectTimer?.cancel();
    entry.pendingClose?.cancel();
    entries.remove(entry.key);
    // The transport seam belongs to the concrete adapter and may throw on a
    // half-open Supabase channel. disposeEntry is the mixin's teardown
    // contract ("must not throw") — swallow so a misbehaving adapter never
    // aborts the controller cleanup below (Spec Bug 4.2).
    try {
      await teardownTransport(entry);
    } on Object {
      // Best-effort teardown — the entry is removed regardless.
    }
    if (!entry.stateController.isClosed) {
      entry.stateController.add(RealtimeChannelState.closed);
    }
    await entry.stateController.close();
    await entry.changeController.close();
  }

  // --- State management -----------------------------------------------------

  /// Current state stream for [channelKey]; empty when no entry exists.
  Stream<RealtimeChannelState> stateStreamFor(String channelKey) {
    final entry = entries[channelKey];
    if (entry == null) return const Stream<RealtimeChannelState>.empty();
    return entry.stateController.stream;
  }

  /// Pushes [state] onto [entry]'s state stream. On `joined` the backoff is
  /// reset; on `errored` a reconnect is scheduled. Used by adapters from
  /// inside their transport status callbacks.
  void pushState(LifecycleEntry entry, RealtimeChannelState state) {
    if (entry.disposed) return;
    switch (state) {
      case RealtimeChannelState.joined:
        entry.backoffIndex = 0;
        entry.stateController.add(state);
      case RealtimeChannelState.errored:
        entry.stateController.add(state);
        scheduleReconnect(entry);
      case RealtimeChannelState.connecting:
      case RealtimeChannelState.closed:
        entry.stateController.add(state);
    }
  }

  /// Schedules an exponential-backoff reconnect for [entry]: tear down the
  /// current transport and re-bind after `1/2/4/8/30 s` (clamped).
  void scheduleReconnect(LifecycleEntry entry) {
    if (entry.disposed) return;
    final schedule = backoffSchedule;
    final delay = schedule[entry.backoffIndex.clamp(0, schedule.length - 1)];
    if (entry.backoffIndex < schedule.length - 1) {
      entry.backoffIndex += 1;
    }
    entry.reconnectTimer?.cancel();
    entry.reconnectTimer = Timer(delay, () async {
      if (entry.disposed) return;
      entry.stateController.add(RealtimeChannelState.connecting);
      await teardownTransport(entry);
      if (entry.disposed) return;
      openTransport(entry);
    });
  }

  // --- Pause/resume lifecycle hooks (FC-8 / P5; defined + tested here, --------
  // --- NOT yet live-wired) ---------------------------------------------------

  /// Snapshot of every active (non-disposed) channel-key. Used by the
  /// app lifecycle controller (P5) to remember what to restore on resume.
  List<String> snapshotActiveKeys() => entries.values
      .where((e) => !e.disposed)
      .map((e) => e.key)
      .toList(growable: false);

  /// Tears down every transport channel and cancels every reconnect /
  /// pending-close timer, leaving zero channels and zero pending timers.
  /// Entries are removed so a later [reconnectKeys] starts from a clean
  /// slate. Used by the lifecycle controller on `paused`/`detached` (P5).
  Future<void> disconnectAll() async {
    final snapshot = entries.values.toList(growable: false);
    for (final entry in snapshot) {
      entry
        ..reconnectTimer?.cancel()
        ..reconnectTimer = null
        ..pendingClose?.cancel()
        ..pendingClose = null
        ..disposed = true;
      await teardownTransport(entry);
    }
    entries.clear();
  }

  /// Re-establishes exactly the channels named in [keys] (typically the
  /// list returned by an earlier [snapshotActiveKeys]). Existing live
  /// entries for a key are left untouched (re-attached, not duplicated).
  /// Used by the lifecycle controller on `resumed` (P5).
  void reconnectKeys(Iterable<String> keys) {
    for (final key in keys) {
      final existing = entries[key];
      if (existing != null && !existing.disposed) {
        existing
          ..pendingClose?.cancel()
          ..pendingClose = null;
        continue;
      }
      final entry = LifecycleEntry(key: key)..refCount = 1;
      entries[key] = entry;
      openTransport(entry);
    }
  }
}

/// One live channel managed by [RealtimeChannelLifecycle]. Concrete adapters
/// may stash a transport handle on [transport] and read [key] back when the
/// mixin invokes [RealtimeChannelLifecycle.openTransport] /
/// [RealtimeChannelLifecycle.teardownTransport].
class LifecycleEntry {
  LifecycleEntry({required this.key});

  /// Canonical channel-key (`<table>:<column>=<value>` for CDC).
  final String key;

  /// Per-key change feed (broadcast). Shared across all subscribers.
  final StreamController<RealtimeChange> changeController =
      StreamController<RealtimeChange>.broadcast();

  /// Per-key connection-state feed (broadcast).
  final StreamController<RealtimeChannelState> stateController =
      StreamController<RealtimeChannelState>.broadcast();

  /// Opaque transport handle, owned by the concrete adapter.
  Object? transport;

  int refCount = 0;
  int backoffIndex = 0;
  bool disposed = false;
  Timer? pendingClose;
  Timer? reconnectTimer;
}
