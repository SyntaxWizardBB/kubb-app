import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

const _mapEq = MapEquality<String, Object?>();

/// One message delivered over a `BroadcastChannel`.
///
/// Broadcast is the transport for anon / fan-out / curated-event payloads
/// (e.g. the anon-spectator tournament topic). Unlike CDC (`RealtimeChange`),
/// the payload is a free-form server-projected map rather than a CDC row
/// diff: the producing trigger curates exactly which columns it sends. This
/// value stays minimal and generic — concern-specific decoding lives in the
/// adapter/mapper layer, not here.
@immutable
class BroadcastMessage {
  const BroadcastMessage({
    required this.topic,
    required this.event,
    required this.payload,
  });

  /// Channel topic this message arrived on (e.g.
  /// `public_tournament_events:<tid>`).
  final String topic;

  /// Discriminator naming the broadcast event (e.g. `match_status`,
  /// `proposal_created`).
  final String event;

  /// Curated, server-projected key/value payload for [event].
  final Map<String, Object?> payload;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BroadcastMessage &&
          other.topic == topic &&
          other.event == event &&
          _mapEq.equals(other.payload, payload);

  @override
  int get hashCode => Object.hash(topic, event, _mapEq.hash(payload));

  @override
  String toString() =>
      'BroadcastMessage(topic: $topic, event: $event, payload: $payload)';
}
