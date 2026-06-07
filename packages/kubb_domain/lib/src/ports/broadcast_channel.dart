// `RealtimeChannel` is imported only for the doc-comment cross-reference
// (sibling CDC port); the broadcast port itself reuses RealtimeChannelState.
import 'package:kubb_domain/src/ports/realtime_channel.dart';
import 'package:kubb_domain/src/values/broadcast_message.dart';
import 'package:kubb_domain/src/values/realtime_change.dart';

/// Port for a transport-agnostic Broadcast subscription layer.
///
/// Sibling to [RealtimeChannel]: where CDC streams row-level diffs filtered
/// over a single indexed column, Broadcast streams curated, server-projected
/// events on a per-scope topic (e.g. the anon-spectator tournament feed). It
/// is the lowest-cost transport for anon / fan-out / PII-curated / derived
/// events (ADR-0029 transport decision).
///
/// Adapters live outside the domain package (Supabase Realtime broadcast for
/// cloud, in-memory fake for tests). Topics are sliced per scope — callers
/// pass the topic (built via the `channel_keys` builders) and the adapter
/// is free to de-duplicate the underlying WebSocket across listeners that
/// share the same topic.
abstract interface class BroadcastChannel {
  /// Subscribes to [BroadcastMessage]s on [topic]. Emits one message per
  /// broadcast event. The stream is broadcast — the underlying WebSocket is
  /// shared across all listeners on the same topic.
  Stream<BroadcastMessage> subscribe(String topic);

  /// Tears down the underlying channel when no listeners remain.
  ///
  /// Adapters may apply a short debounce before the final close to avoid
  /// thrashing the WebSocket when listeners come and go quickly
  /// (R-M4.1-2-Mitigation).
  Future<void> close(String topic);

  /// Current connection state for [topic] (`connecting`, `joined`, `closed`,
  /// `errored`). Reuses [RealtimeChannelState] from the CDC port so the UI
  /// can surface a single "reconnecting…" banner across both transports.
  Stream<RealtimeChannelState> stateStream(String topic);
}
