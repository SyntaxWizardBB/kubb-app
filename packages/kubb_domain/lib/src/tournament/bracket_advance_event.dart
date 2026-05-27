import 'package:kubb_domain/src/values/ids.dart';
import 'package:meta/meta.dart';

/// Emitted by `TournamentRemote.watchBracketAdvances` whenever a KO row in
/// the given tournament has just been finalised and the winner has been
/// propagated into the parent bracket slot. The UI uses this to invalidate
/// the bracket view without re-fetching the full match list.
///
/// `targetRound` / `targetMatchNumber` address the parent KO match that
/// the winner advances into. `advancedMatchId` is the just-finalised match
/// the winner came from. `at` is the server-side finalisation timestamp.
@immutable
class BracketAdvanceEvent {
  const BracketAdvanceEvent({
    required this.tournamentId,
    required this.advancedMatchId,
    required this.targetRound,
    required this.targetMatchNumber,
    required this.winnerParticipant,
    required this.at,
  });

  final TournamentId tournamentId;
  final TournamentMatchId advancedMatchId;
  final int targetRound;
  final int targetMatchNumber;
  final TournamentParticipantId winnerParticipant;
  final DateTime at;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BracketAdvanceEvent &&
          other.tournamentId == tournamentId &&
          other.advancedMatchId == advancedMatchId &&
          other.targetRound == targetRound &&
          other.targetMatchNumber == targetMatchNumber &&
          other.winnerParticipant == winnerParticipant &&
          other.at == at;

  @override
  int get hashCode => Object.hash(
        tournamentId,
        advancedMatchId,
        targetRound,
        targetMatchNumber,
        winnerParticipant,
        at,
      );
}
