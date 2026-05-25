import 'package:kubb_domain/src/tournament/ekc_score.dart';
import 'package:kubb_domain/src/values/ids.dart';
import 'package:meta/meta.dart';

/// Supported tournament formats. Hybrid formats run a group/pool stage
/// followed by single-elimination knockout brackets.
enum TournamentFormat {
  roundRobin,
  singleElimination,
  schoch,
  swiss,
  roundRobinThenKo,
  schochThenKo,
  swissThenKo,
}

/// Lifecycle status of a tournament.
enum TournamentStatus {
  draft,
  published,
  registrationOpen,
  registrationClosed,
  live,
  finalized,
  aborted,
}

/// Lifecycle status of a single tournament match. Mirrors the consensus
/// state machine described in the score-input-conflict-spec.
enum TournamentMatchStatus {
  scheduled,
  awaitingResults,
  disputed,
  finalized,
  overridden,
  voided,
}

/// Read-side snapshot of one tournament, suitable for list views.
@immutable
class TournamentSummaryRef {
  const TournamentSummaryRef({
    required this.tournamentId,
    required this.displayName,
    required this.format,
    required this.status,
    required this.startedAt,
    required this.completedAt,
    required this.participantCount,
    this.createdBy,
  });

  final TournamentId tournamentId;
  final String displayName;
  final TournamentFormat format;
  final TournamentStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int participantCount;

  /// User-id of the row's creator. Null when the server-side projection
  /// hides the column (older RPCs) or the row pre-dates the migration
  /// that added it. Used by the list screen to filter the "Meine" tab
  /// instead of leaning on a status-only heuristic.
  final UserId? createdBy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentSummaryRef &&
          other.tournamentId == tournamentId &&
          other.displayName == displayName &&
          other.format == format &&
          other.status == status &&
          other.startedAt == startedAt &&
          other.completedAt == completedAt &&
          other.participantCount == participantCount &&
          other.createdBy == createdBy;

  @override
  int get hashCode => Object.hash(
        tournamentId,
        displayName,
        format,
        status,
        startedAt,
        completedAt,
        participantCount,
        createdBy,
      );
}

/// Read-side snapshot of one tournament match. `participantB` is `null` for
/// a BYE slot. `consensusRound` is the 1..3 retry counter from the
/// consensus-retry flow; it stays at the last value after `finalized`.
@immutable
class TournamentMatchRef {
  const TournamentMatchRef({
    required this.matchId,
    required this.tournamentId,
    required this.roundNumber,
    required this.matchNumberInRound,
    required this.participantA,
    required this.participantB,
    required this.status,
    required this.consensusRound,
    this.startedAt,
    this.completedAt,
    this.winnerParticipant,
    this.finalScoreA,
    this.finalScoreB,
  });

  final TournamentMatchId matchId;
  final TournamentId tournamentId;
  final int roundNumber;
  final int matchNumberInRound;
  final TournamentParticipantId? participantA;
  final TournamentParticipantId? participantB;
  final TournamentMatchStatus status;
  final int consensusRound;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final TournamentParticipantId? winnerParticipant;
  final int? finalScoreA;
  final int? finalScoreB;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentMatchRef &&
          other.matchId == matchId &&
          other.tournamentId == tournamentId &&
          other.roundNumber == roundNumber &&
          other.matchNumberInRound == matchNumberInRound &&
          other.participantA == participantA &&
          other.participantB == participantB &&
          other.status == status &&
          other.consensusRound == consensusRound &&
          other.startedAt == startedAt &&
          other.completedAt == completedAt &&
          other.winnerParticipant == winnerParticipant &&
          other.finalScoreA == finalScoreA &&
          other.finalScoreB == finalScoreB;

  @override
  int get hashCode => Object.hash(
        matchId,
        tournamentId,
        roundNumber,
        matchNumberInRound,
        participantA,
        participantB,
        status,
        consensusRound,
        startedAt,
        completedAt,
        winnerParticipant,
        finalScoreA,
        finalScoreB,
      );
}

/// One team-side proposal for the score of one set inside one consensus
/// retry round.
@immutable
class TournamentSetScoreProposal {
  const TournamentSetScoreProposal({
    required this.matchId,
    required this.consensusRound,
    required this.setNumber,
    required this.submitterUserId,
    required this.score,
  });

  final TournamentMatchId matchId;
  final int consensusRound;
  final int setNumber;
  final UserId submitterUserId;
  final SetScore score;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentSetScoreProposal &&
          other.matchId == matchId &&
          other.consensusRound == consensusRound &&
          other.setNumber == setNumber &&
          other.submitterUserId == submitterUserId &&
          other.score == score;

  @override
  int get hashCode => Object.hash(
        matchId,
        consensusRound,
        setNumber,
        submitterUserId,
        score,
      );
}

/// Port for cloud-side tournament data.
///
/// Per ADR-0014, tournament matches use per-match-result semantics with
/// consensus-retry (max 3 attempts then dispute). No per-throw events.
/// Implementations live outside the domain package (Supabase adapter for
/// cloud, in-memory fake for tests).
abstract interface class TournamentRemote {
  // Discovery
  Future<List<TournamentSummaryRef>> listTournaments({
    TournamentStatus? statusFilter,
    int limit = 50,
  });

  Future<TournamentSummaryRef?> getTournament(TournamentId id);

  // Lifecycle (organizer)
  Future<TournamentId> createTournament({
    required String displayName,
    required int teamSize,
    required int minParticipants,
    required int maxParticipants,
    required TournamentFormat format,
    required Map<String, Object?> matchFormatConfig,
    required List<String> tiebreakerOrder,
  });

  Future<void> publish(TournamentId id);
  Future<void> openRegistration(TournamentId id);
  Future<void> closeRegistration(TournamentId id);
  Future<void> startTournament(TournamentId id);
  Future<void> finalizeTournament(TournamentId id);
  Future<void> abortTournament(TournamentId id);

  // Registration (participant)
  Future<TournamentParticipantId> registerSingle(TournamentId id);
  Future<void> withdrawRegistration(TournamentParticipantId participantId);

  // Registration management (organizer)
  Future<void> confirmRegistration(TournamentParticipantId participantId);
  Future<void> rejectRegistration(TournamentParticipantId participantId);

  // Matches
  Future<List<TournamentMatchRef>> listMatchesForTournament(TournamentId id);

  Future<TournamentMatchRef?> getMatch(TournamentMatchId id);

  /// Submit one team's proposal for the scores of all sets of a match in the
  /// given consensus retry round. `setScores.length` equals the number of
  /// sets actually played, e.g. a best-of-3 ending 2:1 yields length 3.
  Future<void> proposeSetScores({
    required TournamentMatchId matchId,
    required int consensusRound,
    required List<SetScore> setScores,
  });

  /// Organizer override. `reason` is mandatory per FR-CONF-3 and the
  /// score-input-conflict-spec.
  Future<void> organizerOverride({
    required TournamentMatchId matchId,
    required List<SetScore> finalSetScores,
    required String reason,
  });

  /// Realtime placeholder for M4. M1 implementations return an empty stream.
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id);
}
