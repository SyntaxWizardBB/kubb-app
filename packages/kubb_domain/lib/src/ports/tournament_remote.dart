import 'package:kubb_domain/src/match/match_event.dart';
import 'package:kubb_domain/src/values/ids.dart';

/// Port for cloud-side tournament data.
///
/// The contract is event-centric on the match side (push and subscribe to
/// events) and value-centric on the registration side (teams and players are
/// rows that the organizer pushes).
abstract interface class TournamentRemote {
  Future<void> publishMatchEvent(MatchEvent event);

  Stream<MatchEvent> subscribeToMatch(MatchId matchId);

  Future<void> upsertTeam({
    required TournamentId tournamentId,
    required TeamId teamId,
    required String displayName,
    required List<PlayerId> playerIds,
  });
}
