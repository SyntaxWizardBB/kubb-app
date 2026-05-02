import 'package:kubb_domain/src/values/ids.dart';
import 'package:kubb_domain/src/values/lamport_clock.dart';
import 'package:meta/meta.dart';

/// Append-only events that make up a match.
///
/// All score state is reconstructed from the ordered list of events; events
/// are never mutated. Multi-device sync sends events; conflict resolution is
/// modelled as `DisputeRaised` and `OrganizerOverride` events rather than
/// last-write-wins on a mutable row.
@immutable
sealed class MatchEvent {
  const MatchEvent({
    required this.eventId,
    required this.matchId,
    required this.timestamp,
    required this.emittedBy,
  });

  final EventId eventId;
  final MatchId matchId;
  final LamportTimestamp timestamp;
  final DeviceId emittedBy;
}

final class MatchStarted extends MatchEvent {
  const MatchStarted({
    required super.eventId,
    required super.matchId,
    required super.timestamp,
    required super.emittedBy,
    required this.ruleSetId,
    required this.openingCode,
    required this.teamAId,
    required this.teamBId,
  });

  final String ruleSetId;
  final String openingCode;
  final TeamId teamAId;
  final TeamId teamBId;
}

final class ThrowRecorded extends MatchEvent {
  const ThrowRecorded({
    required super.eventId,
    required super.matchId,
    required super.timestamp,
    required super.emittedBy,
    required this.byTeamId,
    required this.byPlayerId,
    required this.outcome,
  });

  final TeamId byTeamId;
  final PlayerId byPlayerId;
  final ThrowOutcome outcome;
}

enum ThrowOutcome {
  hitFieldKubb,
  hitBaseKubb,
  hitKing,
  miss,
  invalidThrow,
}

final class KubbsThrownIn extends MatchEvent {
  const KubbsThrownIn({
    required super.eventId,
    required super.matchId,
    required super.timestamp,
    required super.emittedBy,
    required this.byTeamId,
    required this.kubbCount,
  });

  final TeamId byTeamId;
  final int kubbCount;
}

final class DisputeRaised extends MatchEvent {
  const DisputeRaised({
    required super.eventId,
    required super.matchId,
    required super.timestamp,
    required super.emittedBy,
    required this.disputedEventId,
    required this.reason,
  });

  final EventId disputedEventId;
  final String reason;
}

final class OrganizerOverride extends MatchEvent {
  const OrganizerOverride({
    required super.eventId,
    required super.matchId,
    required super.timestamp,
    required super.emittedBy,
    required this.targetEventId,
    required this.replacement,
  });

  final EventId targetEventId;
  final ThrowOutcome replacement;
}

final class MatchFinished extends MatchEvent {
  const MatchFinished({
    required super.eventId,
    required super.matchId,
    required super.timestamp,
    required super.emittedBy,
    required this.winnerTeamId,
    required this.reason,
  });

  final TeamId winnerTeamId;
  final MatchEndReason reason;
}

enum MatchEndReason {
  allKubbsAndKingDown,
  prematureKingFall,
  forfeit,
}
