import 'dart:async';

import 'package:kubb_domain/src/ports/broadcast_channel.dart';
import 'package:kubb_domain/src/values/broadcast_message.dart';
import 'package:kubb_domain/src/values/realtime_change.dart';

/// In-memory [BroadcastChannel] for tests.
///
/// Mirrors `FakeRealtimeChannel`: holds one broadcast [StreamController] per
/// topic. Two subscribers to the same topic share the stream — both receive
/// every [emit]. The state-stream is a separate broadcast controller that
/// replays the last known state to late subscribers (mirrors the
/// BehaviorSubject contract from the task spec).
class FakeBroadcastChannel implements BroadcastChannel {
  final Map<String, StreamController<BroadcastMessage>> _messages = {};
  final Map<String, StreamController<RealtimeChannelState>> _states = {};
  final Map<String, RealtimeChannelState> _latestState = {};

  @override
  Stream<BroadcastMessage> subscribe(String topic) {
    final controller = _messages.putIfAbsent(
      topic,
      StreamController<BroadcastMessage>.broadcast,
    );
    // Subscribing transitions an unknown topic into `joined` to mirror the
    // happy-path connection lifecycle adapters report.
    if (!_latestState.containsKey(topic)) {
      setState(topic, RealtimeChannelState.joined);
    }
    return controller.stream;
  }

  @override
  Future<void> close(String topic) async {
    final messages = _messages.remove(topic);
    await messages?.close();
    final state = _states.remove(topic);
    await state?.close();
    _latestState.remove(topic);
  }

  @override
  Stream<RealtimeChannelState> stateStream(String topic) {
    final controller = _states.putIfAbsent(
      topic,
      StreamController<RealtimeChannelState>.broadcast,
    );
    final stream = controller.stream;
    final latest = _latestState[topic];
    if (latest == null) return stream;
    // Replay the last seen state so a late subscriber observes the current
    // channel status without waiting for the next transition.
    return _replay(latest, stream);
  }

  /// Test-only: pushes [message] to every subscriber on [topic]. No-op when
  /// no `subscribe(...)` has registered the topic yet.
  void emit(String topic, BroadcastMessage message) {
    _messages[topic]?.add(message);
  }

  /// Test-only: drives the lifecycle state for [topic] and replays it to
  /// future `stateStream` listeners.
  void setState(String topic, RealtimeChannelState state) {
    _latestState[topic] = state;
    _states
        .putIfAbsent(
          topic,
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
