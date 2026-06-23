import 'package:kubb_domain/src/values/realtime_change.dart';

/// Port for a transport-agnostic Realtime subscription layer.
///
/// Adapters live outside the domain package (Supabase Realtime for cloud,
/// in-memory fake for tests). Per OD-M4-01, channels are sliced
/// per-tournament — callers therefore pass `filterColumn` /
/// `filterValue` (typically `tournament_id` plus the tournament id) and
/// the adapter is free to de-duplicate the underlying WebSocket across
/// listeners that share the same channel key.
abstract interface class RealtimeChannel {
  /// Subscribes to row-level change events on [table] filtered to rows
  /// where [filterColumn] equals [filterValue]. Emits one event per
  /// inserted, updated, or deleted row. The stream is broadcast — the
  /// underlying WebSocket is shared across all listeners on the same
  /// channel key.
  Stream<RealtimeChange> subscribe({
    required String table,
    required String filterColumn,
    required String filterValue,
  });

  /// Tears down the underlying channel when no listeners remain.
  ///
  /// Adapters may apply a short debounce before the final close to
  /// avoid thrashing the WebSocket when listeners come and go quickly
  /// (R-M4.1-2-Mitigation).
  Future<void> close(String channelKey);

  /// Current connection state for the channel (`connecting`, `joined`,
  /// `closed`, `errored`). Riverpod surfaces this so the UI can show a
  /// "reconnecting…" banner.
  Stream<RealtimeChannelState> stateStream(String channelKey);
}

/// Freshness tier of a synchronised concern (ADR-0041 §2, Spec §2).
///
/// A declarative property of the channel-key, not an ad-hoc decision at the
/// call-site. `critical` concerns (active match score, live standings, match
/// status/clock of a tournament the user plays in or watches live) get a
/// guaranteed catch-up refetch, a tighter fallback cadence and a never-silent
/// degraded banner — for them freshness wins over battery. `normal` concerns
/// (registration, check-in lists, friends, my-teams/-tournaments, inbox) keep
/// the standard CDC + 30 s fallback with no banner pressure.
enum RealtimeCriticality { critical, normal }
