import 'package:flutter/foundation.dart' show immutable;

/// Lifecycle status of a multi-player match. Mirrors the
/// `match_status` enum on the server.
enum MatchStatus {
  pendingInvites,
  active,
  awaitingResults,
  finalized,
  voided;

  static MatchStatus fromWire(String raw) {
    switch (raw) {
      case 'pending_invites':
        return MatchStatus.pendingInvites;
      case 'active':
        return MatchStatus.active;
      case 'awaiting_results':
        return MatchStatus.awaitingResults;
      case 'finalized':
        return MatchStatus.finalized;
      case 'voided':
        return MatchStatus.voided;
      default:
        throw ArgumentError.value(raw, 'raw', 'Unknown MatchStatus');
    }
  }
}

/// Best-of format chosen at match creation. The number of sets a team
/// must win to take the match is `ceil(N / 2)`. Per the database
/// constraint `matches_format_check`, valid values are bo1..bo99.
@immutable
class MatchFormat {
  const MatchFormat(this.n)
      : assert(n >= 1 && n <= 99, 'best-of must be in 1..99');

  factory MatchFormat.fromWire(String raw) {
    if (!RegExp(r'^bo[1-9][0-9]?$').hasMatch(raw)) {
      throw ArgumentError.value(raw, 'raw', 'Unknown MatchFormat');
    }
    return MatchFormat(int.parse(raw.substring(2)));
  }

  /// Convenience constants for the most common values — kept so
  /// existing call-sites compile, but any `MatchFormat(int)` works.
  static const MatchFormat bo1 = MatchFormat(1);
  static const MatchFormat bo3 = MatchFormat(3);
  static const MatchFormat bo5 = MatchFormat(5);

  /// Inclusive range used by the wizard stepper.
  static const int minN = 1;
  static const int maxN = 99;

  final int n;

  String toWire() => 'bo$n';

  /// Number of round wins required for a team to win the match.
  /// `ceil(n / 2)` — works for both odd and even n.
  int get setsToWin => (n + 1) ~/ 2;

  @override
  bool operator ==(Object other) =>
      other is MatchFormat && other.n == n;

  @override
  int get hashCode => n.hashCode;

  @override
  String toString() => 'MatchFormat(bo$n)';
}

/// How rounds are scored: pure win/loss or kubb-points based.
enum MatchScoring {
  wins,
  points;

  static MatchScoring fromWire(String raw) {
    switch (raw) {
      case 'wins':
        return MatchScoring.wins;
      case 'points':
        return MatchScoring.points;
      default:
        throw ArgumentError.value(raw, 'raw', 'Unknown MatchScoring');
    }
  }

  String toWire() {
    switch (this) {
      case MatchScoring.wins:
        return 'wins';
      case MatchScoring.points:
        return 'points';
    }
  }
}

/// State of an in-app participant's invitation row.
enum MatchInvitationStatus {
  pending,
  accepted,
  declined,
  left;

  static MatchInvitationStatus fromWire(String raw) {
    switch (raw) {
      case 'pending':
        return MatchInvitationStatus.pending;
      case 'accepted':
        return MatchInvitationStatus.accepted;
      case 'declined':
        return MatchInvitationStatus.declined;
      case 'left':
        return MatchInvitationStatus.left;
      default:
        throw ArgumentError.value(
          raw,
          'raw',
          'Unknown MatchInvitationStatus',
        );
    }
  }
}

/// Kind tag for a match participant. Server-side currently only ever
/// emits `'in_app'` (walk-in support was removed).
enum MatchParticipantKind {
  inApp;

  static MatchParticipantKind fromWire(String raw) {
    switch (raw) {
      case 'in_app':
        return MatchParticipantKind.inApp;
      default:
        throw ArgumentError.value(
          raw,
          'raw',
          'Unknown MatchParticipantKind',
        );
    }
  }
}

/// Caller's role inside a particular match.
enum MatchRole {
  creator,
  participant,
  observer;

  static MatchRole fromWire(String raw) {
    switch (raw) {
      case 'creator':
        return MatchRole.creator;
      case 'participant':
        return MatchRole.participant;
      case 'observer':
        return MatchRole.observer;
      default:
        throw ArgumentError.value(raw, 'raw', 'Unknown MatchRole');
    }
  }
}

/// One row from `match_list_for_caller`. The lightweight, list-view shape.
class MatchSummary {
  const MatchSummary({
    required this.matchId,
    required this.format,
    required this.scoring,
    required this.status,
    required this.startedAt,
    required this.completedAt,
    required this.myTeamId,
    required this.opponentTeamSize,
    required this.myRole,
  });

  factory MatchSummary.fromRow(Map<String, dynamic> row) {
    final completedRaw = row['completed_at'] as String?;
    final opponentRaw = row['opponent_team_size'];
    final opponentSize = opponentRaw is int
        ? opponentRaw
        : (opponentRaw is num
            ? opponentRaw.toInt()
            : int.parse(opponentRaw.toString()));
    return MatchSummary(
      matchId: row['match_id'] as String,
      format: MatchFormat.fromWire(row['format'] as String),
      scoring: MatchScoring.fromWire(row['scoring'] as String),
      status: MatchStatus.fromWire(row['status'] as String),
      startedAt: DateTime.parse(row['started_at'] as String),
      completedAt:
          completedRaw == null ? null : DateTime.parse(completedRaw),
      myTeamId: row['my_team_id'] as String?,
      opponentTeamSize: opponentSize,
      myRole: MatchRole.fromWire(row['my_role'] as String),
    );
  }

  final String matchId;
  final MatchFormat format;
  final MatchScoring scoring;
  final MatchStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;

  /// 'A' or 'B', or null if the caller is not on a team (observer).
  final String? myTeamId;
  final int opponentTeamSize;
  final MatchRole myRole;
}

/// Team-level metadata. `teamId` is the canonical 'A' or 'B' tag.
class MatchTeam {
  const MatchTeam({required this.teamId, required this.displayName});

  factory MatchTeam.fromRow(Map<String, dynamic> row) {
    return MatchTeam(
      teamId: row['team_id'] as String,
      displayName: row['display_name'] as String?,
    );
  }

  /// Canonical short id ('A' | 'B').
  final String teamId;

  /// Optional human-friendly label (set by creator); UI falls back to id.
  final String? displayName;
}

/// One row from the participants array of `match_get`. All participants
/// are in-app users — walk-in support was removed server-side.
class MatchParticipant {
  const MatchParticipant({
    required this.participantId,
    required this.teamId,
    required this.kind,
    required this.userId,
    required this.nickname,
    required this.invitationStatus,
    required this.joinedAt,
    required this.respondedAt,
  });

  factory MatchParticipant.fromRow(Map<String, dynamic> row) {
    final respondedRaw = row['responded_at'] as String?;
    return MatchParticipant(
      participantId: row['participant_id'] as String,
      teamId: row['team_id'] as String,
      kind: MatchParticipantKind.fromWire(row['kind'] as String),
      userId: row['user_id'] as String?,
      nickname: row['nickname'] as String?,
      invitationStatus: MatchInvitationStatus.fromWire(
        row['invitation_status'] as String,
      ),
      joinedAt: DateTime.parse(row['joined_at'] as String),
      respondedAt:
          respondedRaw == null ? null : DateTime.parse(respondedRaw),
    );
  }

  final String participantId;

  /// 'A' or 'B'.
  final String teamId;
  final MatchParticipantKind kind;

  /// uuid of the linked auth user. Always non-null in practice — kept
  /// nullable only for defensive parsing.
  final String? userId;

  /// Server-resolved nickname for the participant.
  final String? nickname;
  final MatchInvitationStatus invitationStatus;
  final DateTime joinedAt;
  final DateTime? respondedAt;

  bool get isInApp => kind == MatchParticipantKind.inApp;

  /// Best human-readable label for this participant — server-resolved
  /// nickname, falling back to a placeholder.
  String get displayLabel => nickname ?? '?';
}

/// One round-result proposal as returned in the `own_proposal` field of
/// `match_get` (or echoed back from `match_propose_result`).
class MatchResultProposal {
  const MatchResultProposal({
    required this.round,
    required this.userId,
    required this.winnerTeamId,
    required this.scoreA,
    required this.scoreB,
    required this.proposedAt,
  });

  factory MatchResultProposal.fromRow(Map<String, dynamic> row) {
    final roundRaw = row['round'];
    final scoreARaw = row['score_a'];
    final scoreBRaw = row['score_b'];
    return MatchResultProposal(
      round: roundRaw is int
          ? roundRaw
          : (roundRaw as num).toInt(),
      userId: row['user_id'] as String,
      winnerTeamId: row['winner_team_id'] as String?,
      scoreA: scoreARaw is int
          ? scoreARaw
          : (scoreARaw as num).toInt(),
      scoreB: scoreBRaw is int
          ? scoreBRaw
          : (scoreBRaw as num).toInt(),
      proposedAt: DateTime.parse(row['proposed_at'] as String),
    );
  }

  final int round;
  final String userId;

  /// 'A', 'B', or null for a draw.
  final String? winnerTeamId;
  final int scoreA;
  final int scoreB;
  final DateTime proposedAt;
}

/// One audit-log entry as exposed in `match_get`.`audit_tail`.
class MatchAuditEvent {
  const MatchAuditEvent({
    required this.kind,
    required this.actorUserId,
    required this.payload,
    required this.at,
  });

  factory MatchAuditEvent.fromRow(Map<String, dynamic> row) {
    final payloadRaw = row['payload'];
    return MatchAuditEvent(
      kind: row['kind'] as String,
      actorUserId: row['actor_user_id'] as String?,
      payload: payloadRaw is Map<String, dynamic>
          ? Map<String, dynamic>.from(payloadRaw)
          : <String, dynamic>{},
      at: DateTime.parse(row['at'] as String),
    );
  }

  final String kind;
  final String? actorUserId;
  final Map<String, dynamic> payload;
  final DateTime at;
}

/// Header block within the `match_get` payload — mirrors [MatchSummary]
/// but with the live-detail extras (currentRound, settings).
class MatchDetailHeader {
  const MatchDetailHeader({
    required this.matchId,
    required this.createdByUserId,
    required this.format,
    required this.scoring,
    required this.status,
    required this.startedAt,
    required this.completedAt,
    required this.currentRound,
    required this.settings,
    this.winnerTeamId,
    this.finalScoreA,
    this.finalScoreB,
  });

  factory MatchDetailHeader.fromRow(Map<String, dynamic> row) {
    final completedRaw = row['completed_at'] as String?;
    final currentRoundRaw = row['current_round'];
    final settingsRaw = row['settings'];
    final scoreARaw = row['final_score_a'];
    final scoreBRaw = row['final_score_b'];
    return MatchDetailHeader(
      matchId: row['match_id'] as String,
      createdByUserId: row['created_by'] as String?,
      format: MatchFormat.fromWire(row['format'] as String),
      scoring: MatchScoring.fromWire(row['scoring'] as String),
      status: MatchStatus.fromWire(row['status'] as String),
      startedAt: DateTime.parse(row['started_at'] as String),
      completedAt:
          completedRaw == null ? null : DateTime.parse(completedRaw),
      currentRound: currentRoundRaw is int
          ? currentRoundRaw
          : (currentRoundRaw as num).toInt(),
      settings: settingsRaw is Map<String, dynamic>
          ? Map<String, dynamic>.from(settingsRaw)
          : <String, dynamic>{},
      winnerTeamId: row['winner_team_id'] as String?,
      finalScoreA: scoreARaw == null
          ? null
          : (scoreARaw is int ? scoreARaw : (scoreARaw as num).toInt()),
      finalScoreB: scoreBRaw == null
          ? null
          : (scoreBRaw is int ? scoreBRaw : (scoreBRaw as num).toInt()),
    );
  }

  final String matchId;

  /// Server-tagged creator user id. Nullable because the underlying FK is
  /// `ON DELETE SET NULL` — the creator could have deleted their account.
  final String? createdByUserId;
  final MatchFormat format;
  final MatchScoring scoring;
  final MatchStatus status;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int currentRound;
  final Map<String, dynamic> settings;

  /// 'A', 'B', or null. Populated once the match status is `finalized`.
  /// Null for ongoing matches and for ties (points scoring with equal
  /// final scores — see [MatchDetail.derivedWinner]).
  final String? winnerTeamId;
  final int? finalScoreA;
  final int? finalScoreB;
}

/// Full match payload returned by `match_get`. Bundles the header,
/// teams, participants, the caller's pending proposal (if any) and a
/// short audit tail used by the lobby/results screens.
class MatchDetail {
  const MatchDetail({
    required this.match,
    required this.teams,
    required this.participants,
    required this.ownProposal,
    required this.auditTail,
  });

  factory MatchDetail.fromRow(Map<String, dynamic> row) {
    final teamsRaw = row['teams'] as List<dynamic>? ?? const <dynamic>[];
    final participantsRaw =
        row['participants'] as List<dynamic>? ?? const <dynamic>[];
    final auditRaw =
        row['audit_tail'] as List<dynamic>? ?? const <dynamic>[];
    final ownProposalRaw = row['own_proposal'];
    return MatchDetail(
      match: MatchDetailHeader.fromRow(row['match'] as Map<String, dynamic>),
      teams: teamsRaw
          .cast<Map<String, dynamic>>()
          .map(MatchTeam.fromRow)
          .toList(growable: false),
      participants: participantsRaw
          .cast<Map<String, dynamic>>()
          .map(MatchParticipant.fromRow)
          .toList(growable: false),
      ownProposal: ownProposalRaw is Map<String, dynamic>
          ? MatchResultProposal.fromRow(ownProposalRaw)
          : null,
      auditTail: auditRaw
          .cast<Map<String, dynamic>>()
          .map(MatchAuditEvent.fromRow)
          .toList(growable: false),
    );
  }

  final MatchDetailHeader match;
  final List<MatchTeam> teams;
  final List<MatchParticipant> participants;

  /// The caller's outstanding result proposal for the current round, if
  /// any. Used by the results screen to pre-fill its inputs.
  final MatchResultProposal? ownProposal;
  final List<MatchAuditEvent> auditTail;

  Iterable<MatchParticipant> participantsForTeam(String teamId) {
    return participants.where((p) => p.teamId == teamId);
  }

  /// Winner-team derivation for finalized matches. Falls back to the
  /// final-score comparison when the server-side `winner_team_id` is
  /// absent (which it is for ties in points-scoring matches).
  /// Returns 'A', 'B', or null for a tie / not-yet-finalized.
  String? get derivedWinner {
    if (match.status != MatchStatus.finalized) return null;
    if (match.winnerTeamId != null) return match.winnerTeamId;
    final a = match.finalScoreA;
    final b = match.finalScoreB;
    if (a == null || b == null || a == b) return null;
    return a > b ? 'A' : 'B';
  }

  /// True when [callerUserId] matches the server-tagged creator of the
  /// match. Returns false for nulls on either side so callers can pass
  /// `currentUserId` directly without a pre-check.
  bool isCallerCreator(String? callerUserId) {
    if (callerUserId == null) return false;
    final creator = match.createdByUserId;
    if (creator == null) return false;
    return creator == callerUserId;
  }
}
