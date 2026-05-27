import 'dart:async';

import 'package:kubb_domain/src/ports/realtime_channel.dart';

/// Deterministic channel-key derived from the subscribe filter triple.
/// Tests use the same scheme when calling [FakeRealtimeChannel.emit] and
/// [FakeRealtimeChannel.setState] so that producer and consumer agree on
/// the addressed channel.
String fakeRealtimeChannelKey({
  required String table,
  required String filterColumn,
  required String filterValue,
}) => '$table:$filterColumn=$filterValue';

/// In-memory [RealtimeChannel] for tests.
///
/// Holds one broadcast [StreamController] per channel-key. Two subscribers
/// to the same `(table, filterColumn, filterValue)` triple share the
/// stream — both receive every [emit]. The state-stream is a separate
/// broadcast controller that replays the last known state to late
/// subscribers (mirrors the BehaviorSubject contract from the task spec).
class FakeRealtimeChannel implements RealtimeChannel {
  final Map<String, StreamController<RealtimeChange>> _changes = {};
  final Map<String, StreamController<RealtimeChannelState>> _states = {};
  final Map<String, RealtimeChannelState> _latestState = {};

  @override
  Stream<RealtimeChange> subscribe({
    required String table,
    required String filterColumn,
    required String filterValue,
  }) {
    final key = fakeRealtimeChannelKey(
      table: table,
      filterColumn: filterColumn,
      filterValue: filterValue,
    );
    final controller = _changes.putIfAbsent(
      key,
      StreamController<RealtimeChange>.broadcast,
    );
    // Subscribing transitions an unknown channel into `joined` to mirror
    // the happy-path connection lifecycle adapters report.
    if (!_latestState.containsKey(key)) {
      setState(key, RealtimeChannelState.joined);
    }
    return controller.stream;
  }

  @override
  Future<void> close(String channelKey) async {
    final changes = _changes.remove(channelKey);
    await changes?.close();
    final state = _states.remove(channelKey);
    await state?.close();
    _latestState.remove(channelKey);
  }

  @override
  Stream<RealtimeChannelState> stateStream(String channelKey) {
    final controller = _states.putIfAbsent(
      channelKey,
      StreamController<RealtimeChannelState>.broadcast,
    );
    final stream = controller.stream;
    final latest = _latestState[channelKey];
    if (latest == null) return stream;
    // Replay the last seen state so a late subscriber observes the
    // current channel status without waiting for the next transition.
    return _replay(latest, stream);
  }

  /// Test-only: pushes [change] to every subscriber on [channelKey]. No-op
  /// when no `subscribe(...)` has registered the key yet.
  void emit(String channelKey, RealtimeChange change) {
    _changes[channelKey]?.add(change);
  }

  /// Test-only: drives the lifecycle state for [channelKey] and replays
  /// it to future `stateStream` listeners.
  void setState(String channelKey, RealtimeChannelState state) {
    _latestState[channelKey] = state;
    _states
        .putIfAbsent(
          channelKey,
          StreamController<RealtimeChannelState>.broadcast,
        )
        .add(state);
  }

  Stream<RealtimeChannelState> _replay(
    RealtimeChannelState seed,
    Stream<RealtimeChannelState> source,
  ) async* {
    yield seed;
    yield* source;
  }
}
