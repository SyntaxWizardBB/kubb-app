import 'package:flutter/foundation.dart' show immutable;
import 'package:kubb_domain/kubb_domain.dart';

/// How the tournament's per-set score is interpreted on the server.
enum TournamentScoring {
  ekc,
  classic;

  static TournamentScoring fromWire(String raw) => values.firstWhere(
        (v) => v.name == raw,
        orElse: () =>
            throw ArgumentError.value(raw, 'raw', 'Unknown TournamentScoring'),
      );

  String toWire() => name;
}

/// Lifecycle of a participant row. See FR-REG-6 / FR-REG-7.
enum TournamentParticipantStatus {
  pending,
  approved,
  waitlist,
  withdrawn,
  rejected;

  static TournamentParticipantStatus fromWire(String raw) =>
      values.firstWhere(
        (v) => v.name == raw,
        orElse: () => throw ArgumentError.value(
            raw, 'raw', 'Unknown TournamentParticipantStatus'),
      );
}

/// Snake_case wire mapping for the [TournamentFormat] domain enum.
/// Defined here because the data layer owns the RPC contract.
const Map<TournamentFormat, String> _formatWire = {
  TournamentFormat.roundRobin: 'round_robin',
  TournamentFormat.singleElimination: 'single_elimination',
  TournamentFormat.schoch: 'schoch',
  TournamentFormat.swiss: 'swiss',
  TournamentFormat.roundRobinThenKo: 'round_robin_then_ko',
  TournamentFormat.schochThenKo: 'schoch_then_ko',
  TournamentFormat.swissThenKo: 'swiss_then_ko',
};

const Map<TournamentStatus, String> _statusWire = {
  TournamentStatus.draft: 'draft',
  TournamentStatus.published: 'published',
  TournamentStatus.registrationOpen: 'registration_open',
  TournamentStatus.registrationClosed: 'registration_closed',
  TournamentStatus.live: 'live',
  TournamentStatus.finalized: 'finalized',
  TournamentStatus.aborted: 'aborted',
};

const Map<TournamentMatchStatus, String> _matchStatusWire = {
  TournamentMatchStatus.scheduled: 'scheduled',
  TournamentMatchStatus.awaitingResults: 'awaiting_results',
  TournamentMatchStatus.disputed: 'disputed',
  TournamentMatchStatus.finalized: 'finalized',
  TournamentMatchStatus.overridden: 'overridden',
  TournamentMatchStatus.voided: 'voided',
};

K _enumFromWire<K, V>(Map<K, V> table, V raw, String label) {
  for (final e in table.entries) {
    if (e.value == raw) return e.key;
  }
  throw ArgumentError.value(raw, 'raw', 'Unknown $label');
}

extension TournamentFormatWire on TournamentFormat {
  static TournamentFormat fromWire(String raw) =>
      _enumFromWire(_formatWire, raw, 'TournamentFormat');
  String toWire() => _formatWire[this]!;
}

extension TournamentStatusWire on TournamentStatus {
  static TournamentStatus fromWire(String raw) =>
      _enumFromWire(_statusWire, raw, 'TournamentStatus');
  String toWire() => _statusWire[this]!;
}

extension TournamentMatchStatusWire on TournamentMatchStatus {
  static TournamentMatchStatus fromWire(String raw) =>
      _enumFromWire(_matchStatusWire, raw, 'TournamentMatchStatus');
}

int _asInt(Object? r) => r is int ? r : (r as num).toInt();
int? _asIntOrNull(Object? r) => r == null ? null : _asInt(r);
DateTime? _asDateOrNull(Object? r) =>
    r == null ? null : DateTime.parse(r as String);

/// One row from the `participants` array of `tournament_get`.
@immutable
class TournamentParticipant {
  const TournamentParticipant({
    required this.participantId,
    required this.userId,
    required this.nickname,
    required this.registrationStatus,
    required this.seed,
    required this.registeredAt,
    required this.respondedAt,
  });

  factory TournamentParticipant.fromRow(Map<String, dynamic> row) {
    return TournamentParticipant(
      participantId: row['participant_id'] as String,
      userId: row['user_id'] as String?,
      nickname: row['nickname'] as String?,
      registrationStatus: TournamentParticipantStatus.fromWire(
          row['registration_status'] as String),
      seed: _asIntOrNull(row['seed']),
      registeredAt: DateTime.parse(row['registered_at'] as String),
      respondedAt: _asDateOrNull(row['responded_at']),
    );
  }

  final String participantId;
  final String? userId;
  final String? nickname;
  final TournamentParticipantStatus registrationStatus;
  final int? seed;
  final DateTime registeredAt;
  final DateTime? respondedAt;

  String get displayLabel => nickname ?? '?';
}

/// Header block within the `tournament_get` payload.
@immutable
class TournamentDetailHeader {
  const TournamentDetailHeader({
    required this.tournamentId,
    required this.displayName,
    required this.createdByUserId,
    required this.teamSize,
    required this.minParticipants,
    required this.maxParticipants,
    required this.format,
    required this.scoring,
    required this.matchFormatConfig,
    required this.tiebreakerOrder,
    required this.byePoints,
    required this.forfeitPoints,
    required this.status,
    required this.publishedAt,
    required this.startedAt,
    required this.completedAt,
  });

  factory TournamentDetailHeader.fromRow(Map<String, dynamic> row) {
    final cfg = row['match_format_config'];
    final tb = row['tiebreaker_order'];
    return TournamentDetailHeader(
      tournamentId: row['tournament_id'] as String,
      displayName: row['display_name'] as String,
      createdByUserId: row['created_by'] as String?,
      teamSize: _asInt(row['team_size']),
      minParticipants: _asInt(row['min_participants']),
      maxParticipants: _asInt(row['max_participants']),
      format: TournamentFormatWire.fromWire(row['format'] as String),
      scoring: TournamentScoring.fromWire(row['scoring'] as String),
      matchFormatConfig: cfg is Map<String, dynamic>
          ? Map<String, Object?>.from(cfg)
          : <String, Object?>{},
      tiebreakerOrder: tb is List<dynamic>
          ? tb.cast<String>().toList(growable: false)
          : const <String>[],
      byePoints: _asIntOrNull(row['bye_points']),
      forfeitPoints: _asIntOrNull(row['forfeit_points']),
      status: TournamentStatusWire.fromWire(row['status'] as String),
      publishedAt: _asDateOrNull(row['published_at']),
      startedAt: _asDateOrNull(row['started_at']),
      completedAt: _asDateOrNull(row['completed_at']),
    );
  }

  final String tournamentId;
  final String displayName;
  final String? createdByUserId;
  final int teamSize;
  final int minParticipants;
  final int maxParticipants;
  final TournamentFormat format;
  final TournamentScoring scoring;

  /// Wizard-controlled match-format settings. Kept as a wire map so
  /// wave-2 additions don't need a Dart migration.
  final Map<String, Object?> matchFormatConfig;
  final List<String> tiebreakerOrder;
  final int? byePoints;
  final int? forfeitPoints;
  final TournamentStatus status;
  final DateTime? publishedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
}

/// One audit-log entry as exposed in `tournament_get`.`audit_tail`.
@immutable
class TournamentAuditEvent {
  const TournamentAuditEvent({
    required this.kind,
    required this.actorUserId,
    required this.payload,
    required this.at,
  });

  factory TournamentAuditEvent.fromRow(Map<String, dynamic> row) {
    final p = row['payload'];
    return TournamentAuditEvent(
      kind: row['kind'] as String,
      actorUserId: row['actor_user_id'] as String?,
      payload: p is Map<String, dynamic>
          ? Map<String, Object?>.from(p)
          : <String, Object?>{},
      at: DateTime.parse(row['at'] as String),
    );
  }

  final String kind;
  final String? actorUserId;
  final Map<String, Object?> payload;
  final DateTime at;
}

/// Decodes a wire row into a domain [TournamentMatchRef].
TournamentMatchRef tournamentMatchRefFromRow(Map<String, dynamic> row) {
  return TournamentMatchRef(
    matchId: TournamentMatchId(row['match_id'] as String),
    tournamentId: TournamentId(row['tournament_id'] as String),
    roundNumber: _asInt(row['round_number']),
    matchNumberInRound: _asInt(row['match_number_in_round']),
    participantA: row['participant_a_id'] == null
        ? null
        : TournamentParticipantId(row['participant_a_id'] as String),
    participantB: row['participant_b_id'] == null
        ? null
        : TournamentParticipantId(row['participant_b_id'] as String),
    status: TournamentMatchStatusWire.fromWire(row['status'] as String),
    consensusRound: _asInt(row['consensus_round']),
    startedAt: _asDateOrNull(row['started_at']),
    completedAt: _asDateOrNull(row['completed_at']),
  );
}

/// Decodes a wire row into a domain [TournamentSummaryRef].
TournamentSummaryRef tournamentSummaryRefFromRow(Map<String, dynamic> row) {
  final creator = row['created_by'] as String?;
  return TournamentSummaryRef(
    tournamentId: TournamentId(row['tournament_id'] as String),
    displayName: row['display_name'] as String,
    format: TournamentFormatWire.fromWire(row['format'] as String),
    status: TournamentStatusWire.fromWire(row['status'] as String),
    startedAt: _asDateOrNull(row['started_at']),
    completedAt: _asDateOrNull(row['completed_at']),
    participantCount: _asInt(row['participant_count']),
    createdBy: creator == null ? null : UserId(creator),
  );
}

/// Full payload returned by `tournament_get`.
@immutable
class TournamentDetail {
  const TournamentDetail({
    required this.tournament,
    required this.participants,
    required this.matches,
    required this.auditTail,
  });

  factory TournamentDetail.fromRow(Map<String, dynamic> row) {
    final parts = row['participants'] as List<dynamic>? ?? const <dynamic>[];
    final matches = row['matches'] as List<dynamic>? ?? const <dynamic>[];
    final audit = row['audit_tail'] as List<dynamic>? ?? const <dynamic>[];
    return TournamentDetail(
      tournament: TournamentDetailHeader.fromRow(
          row['tournament'] as Map<String, dynamic>),
      participants: parts
          .cast<Map<String, dynamic>>()
          .map(TournamentParticipant.fromRow)
          .toList(growable: false),
      matches: matches
          .cast<Map<String, dynamic>>()
          .map(tournamentMatchRefFromRow)
          .toList(growable: false),
      auditTail: audit
          .cast<Map<String, dynamic>>()
          .map(TournamentAuditEvent.fromRow)
          .toList(growable: false),
    );
  }

  final TournamentDetailHeader tournament;
  final List<TournamentParticipant> participants;
  final List<TournamentMatchRef> matches;
  final List<TournamentAuditEvent> auditTail;

  bool isCallerCreator(String? callerUserId) {
    if (callerUserId == null) return false;
    final creator = tournament.createdByUserId;
    return creator != null && creator == callerUserId;
  }
}
