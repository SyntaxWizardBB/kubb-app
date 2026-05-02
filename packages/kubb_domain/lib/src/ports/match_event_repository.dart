import 'package:kubb_domain/src/match/match_event.dart';
import 'package:kubb_domain/src/values/ids.dart';

/// Port for persisting and reading match events.
///
/// Implementations live outside the domain package (drift adapter for local,
/// supabase adapter for cloud, in-memory for tests).
abstract interface class MatchEventRepository {
  /// Append an event to the match log. Idempotent on `event.eventId`:
  /// re-inserting the same id is a no-op.
  Future<void> append(MatchEvent event);

  /// All events for a match in causal order (lamport ordering).
  Future<List<MatchEvent>> eventsFor(MatchId matchId);

  /// Stream of new events for live updates.
  Stream<MatchEvent> watch(MatchId matchId);
}
