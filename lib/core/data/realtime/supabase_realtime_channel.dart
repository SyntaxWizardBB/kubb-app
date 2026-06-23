import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:kubb_app/core/data/realtime/realtime_channel_lifecycle.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

/// Production [RealtimeChannel] adapter backed by `supabase_flutter`.
///
/// One [sb.RealtimeChannel] is opened per channel-key (table plus filter
/// expression) and shared across all callers — see OD-M4-01 / ADR-0021
/// for the per-tournament granularity decision. A reference counter plus
/// a 500 ms debounce protect against WebSocket thrashing when listeners
/// come and go quickly (R-M4.1-2-Mitigation). Channel errors trigger an
/// exponential-backoff resubscribe (1 / 2 / 4 / 8 / 30 s).
///
/// The refcount / debounce / backoff / `stateStream` mechanics are shared
/// with the broadcast adapter via [RealtimeChannelLifecycle] (ADR-0029
/// FC-1); this class only supplies the Supabase-specific transport seams.
class SupabaseRealtimeChannel
    with RealtimeChannelLifecycle
    implements RealtimeChannel {
  SupabaseRealtimeChannel(
    this._client, {
    Duration closeDebounce = RealtimeChannelLifecycle.defaultCloseDebounce,
    List<Duration>? backoffSchedule,
  })  : _closeDebounce = closeDebounce,
        _backoff =
            backoffSchedule ?? RealtimeChannelLifecycle.defaultBackoff;

  final sb.SupabaseClient _client;
  final Duration _closeDebounce;
  final List<Duration> _backoff;

  /// Pending bind parameters per channel-key, so a reconnect can re-open the
  /// transport with the original `(table, column, value)` triple.
  final Map<String, _Binding> _bindings = <String, _Binding>{};

  @override
  Duration get closeDebounce => _closeDebounce;

  @override
  List<Duration> get backoffSchedule => _backoff;

  String _keyFor(String table, String column, String value) =>
      '$table:$column=$value';

  @override
  void openTransport(LifecycleEntry entry) {
    final binding = _bindings[entry.key];
    if (binding == null) return;
    entry.stateController.add(RealtimeChannelState.connecting);
    final channel = _client.channel(entry.key)
      ..onPostgresChanges(
        event: sb.PostgresChangeEvent.all,
        schema: 'public',
        table: binding.table,
        filter: sb.PostgresChangeFilter(
          type: sb.PostgresChangeFilterType.eq,
          column: binding.filterColumn,
          value: binding.filterValue,
        ),
        callback: (payload) {
          // A CDC event can still fire after the entry was disposed (fast
          // in/out navigation tears the channel down before Supabase stops
          // delivering). Guard before touching the closed controller so we
          // never throw "StreamController is closed" (Spec Bug 4.1).
          if (entry.disposed || entry.changeController.isClosed) return;
          entry.changeController.add(_mapPayload(payload, binding.table));
        },
      )
      ..subscribe((status, error) => _handleStatus(entry, status));
    entry.transport = channel;
  }

  @override
  FutureOr<void> teardownTransport(LifecycleEntry entry) async {
    final channel = entry.transport;
    if (channel is sb.RealtimeChannel) {
      try {
        await _client.removeChannel(channel);
      } on Object {
        // Swallow — best-effort teardown; entry is removed regardless.
      }
    }
    entry.transport = null;
  }

  void _handleStatus(
      LifecycleEntry entry, sb.RealtimeSubscribeStatus status) {
    switch (status) {
      case sb.RealtimeSubscribeStatus.subscribed:
        pushState(entry, RealtimeChannelState.joined);
      case sb.RealtimeSubscribeStatus.closed:
        entry.stateController.add(RealtimeChannelState.closed);
      case sb.RealtimeSubscribeStatus.channelError:
      case sb.RealtimeSubscribeStatus.timedOut:
        pushState(entry, RealtimeChannelState.errored);
    }
  }

  RealtimeChange _mapPayload(sb.PostgresChangePayload payload, String table) {
    final eventType = switch (payload.eventType) {
      sb.PostgresChangeEvent.insert => RealtimeEventType.insert,
      sb.PostgresChangeEvent.update => RealtimeEventType.update,
      sb.PostgresChangeEvent.delete => RealtimeEventType.delete,
      sb.PostgresChangeEvent.all => RealtimeEventType.update,
    };
    final newRow = Map<String, Object?>.from(payload.newRecord);
    final oldRow = Map<String, Object?>.from(payload.oldRecord);
    final rowId = (newRow['id'] ?? oldRow['id'] ?? '').toString();
    return RealtimeChange(
      eventType: eventType,
      table: table,
      rowId: rowId,
      newRow: newRow,
      oldRow: oldRow,
      receivedAt: DateTime.now().toUtc(),
    );
  }

  @override
  Stream<RealtimeChange> subscribe({
    required String table,
    required String filterColumn,
    required String filterValue,
  }) {
    final key = _keyFor(table, filterColumn, filterValue);
    _bindings[key] = _Binding(
      table: table,
      filterColumn: filterColumn,
      filterValue: filterValue,
    );
    final entry = openOrAttach(key);
    return entry.changeController.stream;
  }

  @override
  Future<void> close(String channelKey) => closeRef(channelKey);

  @override
  Future<void> disposeEntry(LifecycleEntry entry) async {
    _bindings.remove(entry.key);
    await super.disposeEntry(entry);
  }

  @override
  Stream<RealtimeChannelState> stateStream(String channelKey) =>
      stateStreamFor(channelKey);

  /// Active reference count for [channelKey]. Test-only — adapter smoke
  /// tests (M4.1-T7) assert that two subscribes/one close leaves the
  /// counter at 1.
  @visibleForTesting
  int referenceCount(String channelKey) =>
      entries[channelKey]?.refCount ?? 0;

  /// True while the entry exists (regardless of refcount). Test-only.
  @visibleForTesting
  bool hasChannel(String channelKey) => entries.containsKey(channelKey);

  /// Total number of reconnect attempts triggered for [channelKey]. Reset
  /// to zero when a `joined` status arrives. Test-only.
  @visibleForTesting
  int reconnectAttempts(String channelKey) =>
      entries[channelKey]?.backoffIndex ?? 0;

  /// Forces the entry into [state] without touching the underlying
  /// Supabase channel. Mirrors what the real adapter does on a
  /// `channelError`/`joined` status. Test-only.
  @visibleForTesting
  void debugTransitionTo(String channelKey, RealtimeChannelState state) {
    final entry = entries[channelKey];
    if (entry == null) return;
    pushState(entry, state);
  }
}

/// The `(table, column, value)` triple a Supabase channel was opened with,
/// kept so a reconnect can re-bind the same Postgres-changes filter.
class _Binding {
  _Binding({
    required this.table,
    required this.filterColumn,
    required this.filterValue,
  });

  final String table;
  final String filterColumn;
  final String filterValue;
}
