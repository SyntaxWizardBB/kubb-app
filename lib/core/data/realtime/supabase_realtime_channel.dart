import 'dart:async';

import 'package:flutter/foundation.dart';
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
class SupabaseRealtimeChannel implements RealtimeChannel {
  SupabaseRealtimeChannel(
    this._client, {
    this.closeDebounce = const Duration(milliseconds: 500),
    List<Duration>? backoffSchedule,
  }) : _backoff = backoffSchedule ?? _defaultBackoff;

  final sb.SupabaseClient _client;
  final Map<String, _ChannelEntry> _entries = <String, _ChannelEntry>{};
  final Duration closeDebounce;
  final List<Duration> _backoff;

  static const List<Duration> _defaultBackoff = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 30),
  ];

  String _keyFor(String table, String column, String value) =>
      '$table:$column=$value';

  _ChannelEntry _openOrAttach(
      String table, String filterColumn, String filterValue) {
    final key = _keyFor(table, filterColumn, filterValue);
    final existing = _entries[key];
    if (existing != null) {
      existing
        ..pendingClose?.cancel()
        ..pendingClose = null
        ..refCount += 1;
      return existing;
    }
    final entry = _ChannelEntry(key: key)..refCount = 1;
    _entries[key] = entry;
    _bind(entry, table, filterColumn, filterValue);
    return entry;
  }

  void _bind(
      _ChannelEntry entry, String table, String filterColumn, String value) {
    entry.stateController.add(RealtimeChannelState.connecting);
    final channel = _client.channel(entry.key)
      ..onPostgresChanges(
        event: sb.PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        filter: sb.PostgresChangeFilter(
          type: sb.PostgresChangeFilterType.eq,
          column: filterColumn,
          value: value,
        ),
        callback: (payload) =>
            entry.changeController.add(_mapPayload(payload, table)),
      )
      ..subscribe((status, error) => _handleStatus(
          entry, status, table, filterColumn, value));
    entry.channel = channel;
  }

  void _handleStatus(_ChannelEntry entry, sb.RealtimeSubscribeStatus status,
      String table, String filterColumn, String value) {
    switch (status) {
      case sb.RealtimeSubscribeStatus.subscribed:
        entry.backoffIndex = 0;
        entry.stateController.add(RealtimeChannelState.joined);
      case sb.RealtimeSubscribeStatus.closed:
        entry.stateController.add(RealtimeChannelState.closed);
      case sb.RealtimeSubscribeStatus.channelError:
      case sb.RealtimeSubscribeStatus.timedOut:
        entry.stateController.add(RealtimeChannelState.errored);
        _scheduleReconnect(entry, table, filterColumn, value);
    }
  }

  void _scheduleReconnect(_ChannelEntry entry, String table,
      String filterColumn, String value) {
    if (entry.disposed) return;
    final delay =
        _backoff[entry.backoffIndex.clamp(0, _backoff.length - 1)];
    if (entry.backoffIndex < _backoff.length - 1) {
      entry.backoffIndex += 1;
    }
    entry.reconnectTimer?.cancel();
    entry.reconnectTimer = Timer(delay, () async {
      if (entry.disposed) return;
      entry.stateController.add(RealtimeChannelState.connecting);
      try {
        await entry.channel?.unsubscribe();
      } on Object {
        // Swallow — channel may already be dead; we are about to re-bind.
      }
      _bind(entry, table, filterColumn, value);
    });
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
    final entry = _openOrAttach(table, filterColumn, filterValue);
    return entry.changeController.stream;
  }

  @override
  Future<void> close(String channelKey) async {
    final entry = _entries[channelKey];
    if (entry == null) return;
    if (entry.refCount > 0) entry.refCount -= 1;
    if (entry.refCount > 0) return;
    entry.pendingClose?.cancel();
    entry.pendingClose =
        Timer(closeDebounce, () => _disposeEntry(entry));
  }

  Future<void> _disposeEntry(_ChannelEntry entry) async {
    if (entry.disposed) return;
    if (entry.refCount > 0) return;
    entry.disposed = true;
    entry.reconnectTimer?.cancel();
    _entries.remove(entry.key);
    final channel = entry.channel;
    if (channel != null) {
      try {
        await _client.removeChannel(channel);
      } on Object {
        // Swallow — best-effort teardown; entry is removed regardless.
      }
    }
    entry.stateController.add(RealtimeChannelState.closed);
    await entry.stateController.close();
    await entry.changeController.close();
  }

  @override
  Stream<RealtimeChannelState> stateStream(String channelKey) {
    final entry = _entries[channelKey];
    if (entry == null) return const Stream<RealtimeChannelState>.empty();
    return entry.stateController.stream;
  }

  /// Active reference count for [channelKey]. Test-only — adapter smoke
  /// tests (M4.1-T7) assert that two subscribes/one close leaves the
  /// counter at 1.
  @visibleForTesting
  int referenceCount(String channelKey) =>
      _entries[channelKey]?.refCount ?? 0;

  /// True while the entry exists (regardless of refcount). Test-only.
  @visibleForTesting
  bool hasChannel(String channelKey) => _entries.containsKey(channelKey);

  /// Total number of reconnect attempts triggered for [channelKey]. Reset
  /// to zero when a `joined` status arrives. Test-only.
  @visibleForTesting
  int reconnectAttempts(String channelKey) =>
      _entries[channelKey]?.backoffIndex ?? 0;

  /// Forces the entry into [state] without touching the underlying
  /// Supabase channel. Mirrors what the real adapter does on a
  /// `channelError`/`joined` status. Test-only.
  @visibleForTesting
  void debugTransitionTo(String channelKey, RealtimeChannelState state) {
    final entry = _entries[channelKey];
    if (entry == null) return;
    switch (state) {
      case RealtimeChannelState.joined:
        entry.backoffIndex = 0;
        entry.stateController.add(state);
      case RealtimeChannelState.errored:
        entry.stateController.add(state);
        _scheduleReconnect(entry, '', '', '');
      case RealtimeChannelState.connecting:
      case RealtimeChannelState.closed:
        entry.stateController.add(state);
    }
  }
}

class _ChannelEntry {
  _ChannelEntry({required this.key});

  final String key;
  final StreamController<RealtimeChange> changeController =
      StreamController<RealtimeChange>.broadcast();
  final StreamController<RealtimeChannelState> stateController =
      StreamController<RealtimeChannelState>.broadcast();

  int refCount = 0;
  int backoffIndex = 0;
  bool disposed = false;
  sb.RealtimeChannel? channel;
  Timer? pendingClose;
  Timer? reconnectTimer;
}
