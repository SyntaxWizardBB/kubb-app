import 'package:kubb_domain/src/values/ids.dart';
import 'package:meta/meta.dart';

/// Reduced view of a match for UI consumption.
///
/// This is a sealed union: every reachable runtime state is one of the
/// concrete variants, and an exhaustive `switch` keeps the UI in sync as new
/// states are added.
@immutable
sealed class MatchState {
  const MatchState({required this.matchId});
  final MatchId matchId;
}

final class MatchSetup extends MatchState {
  const MatchSetup({required super.matchId});
}

final class MatchInProgress extends MatchState {
  const MatchInProgress({
    required super.matchId,
    required this.currentRound,
    required this.attackingTeamId,
    required this.standingBaseKubbsTeamA,
    required this.standingBaseKubbsTeamB,
    required this.standingFieldKubbsTeamA,
    required this.standingFieldKubbsTeamB,
    required this.batonsLeftThisRound,
  });

  final int currentRound;
  final TeamId attackingTeamId;
  final int standingBaseKubbsTeamA;
  final int standingBaseKubbsTeamB;
  final int standingFieldKubbsTeamA;
  final int standingFieldKubbsTeamB;
  final int batonsLeftThisRound;
}

final class MatchAwaitingDispute extends MatchState {
  const MatchAwaitingDispute({
    required super.matchId,
    required this.disputedEventId,
    required this.reason,
  });

  final EventId disputedEventId;
  final String reason;
}

final class MatchCompleted extends MatchState {
  const MatchCompleted({
    required super.matchId,
    required this.winnerTeamId,
  });

  final TeamId winnerTeamId;
}
