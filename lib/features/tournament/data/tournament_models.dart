import 'package:kubb_domain/kubb_domain.dart';

/// Wire <-> enum helpers for [TournamentScoring]. Kept on the data layer
/// so the port enum stays free of transport concerns.
extension TournamentScoringWire on TournamentScoring {
  static TournamentScoring fromWire(String raw) =>
      TournamentScoring.values.firstWhere(
        (v) => v.name == raw,
        orElse: () =>
            throw ArgumentError.value(raw, 'raw', 'Unknown TournamentScoring'),
      );

  String toWire() => name;
}

/// Wire <-> enum helpers for [TournamentParticipantStatus].
extension TournamentParticipantStatusWire on TournamentParticipantStatus {
  static TournamentParticipantStatus fromWire(String raw) =>
      TournamentParticipantStatus.values.firstWhere(
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

/// Wire mapping for the `phase` column on `tournament_matches`. The
/// `group` value sits outside the bracket — callers filter it out before
/// projecting into a [BracketPhase].
const Map<BracketPhase, String> _bracketPhaseWire = {
  BracketPhase.winners: 'ko',
  BracketPhase.thirdPlace: 'third_place',
  BracketPhase.finals: 'final',
};

/// Wire helper for [BracketPhase]. Returns `null` for the sentinel
/// `'group'` value so callers can drop pre-KO rows without throwing.
extension BracketPhaseWire on BracketPhase {
  static BracketPhase? fromWire(String raw) {
    if (raw == 'group') return null;
    for (final e in _bracketPhaseWire.entries) {
      if (e.value == raw) return e.key;
    }
    throw ArgumentError.value(raw, 'raw', 'Unknown BracketPhase');
  }

  String toWire() => _bracketPhaseWire[this]!;
}

/// Wire mapping for the [SeedingMode] enum. Mirrors the
/// `ko_config.seeding_mode` discriminator persisted on `tournaments`.
const Map<SeedingMode, String> _seedingModeWire = {
  SeedingMode.auto: 'auto',
  SeedingMode.manual: 'manual',
};

extension SeedingModeWire on SeedingMode {
  String toWire() => _seedingModeWire[this]!;
}

/// Encodes a [KoPhaseConfig] into the `p_ko_config` jsonb payload that
/// `tournament_start_ko_phase` expects. The server reads
/// `qualifier_count`, `with_third_place_playoff`, and `seeding_mode`.
extension KoPhaseConfigWire on KoPhaseConfig {
  Map<String, dynamic> toWire() => <String, dynamic>{
        'qualifier_count': qualifierCount,
        'with_third_place_playoff': withThirdPlacePlayoff,
        'seeding_mode': seedingMode.toWire(),
      };
}

/// Encodes a seeding map (`participantId -> seed`) into the
/// `p_seeds` jsonb object expected by `tournament_set_seeding`.
Map<String, dynamic> seedingMapToWire(
    Map<TournamentParticipantId, int> seeds) {
  return <String, dynamic>{
    for (final entry in seeds.entries) entry.key.value: entry.value,
  };
}

/// Decodes one row of the KO-match select used by `getBracket` into a
/// [KoMatchRow]. Drops `phase='group'` rows by returning `null`.
KoMatchRow? koMatchRowFromRow(Map<String, dynamic> row) {
  final phaseRaw = row['phase'] as String;
  final phase = BracketPhaseWire.fromWire(phaseRaw);
  if (phase == null) return null;
  final position = _asIntOrNull(row['bracket_position']);
  if (position == null) return null;
  final a = row['participant_a'] as String?;
  final b = row['participant_b'] as String?;
  return (
    roundNumber: _asInt(row['round_number']),
    bracketPosition: position,
    phase: phase,
    participantA: a,
    participantB: b,
    winnerParticipantId: row['winner_participant'] as String?,
    isBye: a == null || b == null,
  );
}

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

/// Decodes a `participants[]` row into a [TournamentParticipant].
TournamentParticipant tournamentParticipantFromRow(Map<String, dynamic> row) {
  return TournamentParticipant(
    participantId: row['participant_id'] as String,
    userId: row['user_id'] as String?,
    nickname: row['nickname'] as String?,
    registrationStatus: TournamentParticipantStatusWire.fromWire(
        row['registration_status'] as String),
    seed: _asIntOrNull(row['seed']),
    registeredAt: DateTime.parse(row['registered_at'] as String),
    respondedAt: _asDateOrNull(row['responded_at']),
  );
}

/// Decodes the `tournament` block within `tournament_get` into a
/// [TournamentDetailHeader].
TournamentDetailHeader tournamentDetailHeaderFromRow(
    Map<String, dynamic> row) {
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
    scoring: TournamentScoringWire.fromWire(row['scoring'] as String),
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

/// Decodes one entry of the `audit_tail` array.
TournamentAuditEvent tournamentAuditEventFromRow(Map<String, dynamic> row) {
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

/// Decodes the full `tournament_get` jsonb into a [TournamentDetail].
TournamentDetail tournamentDetailFromRow(Map<String, dynamic> row) {
  final parts = row['participants'] as List<dynamic>? ?? const <dynamic>[];
  final matches = row['matches'] as List<dynamic>? ?? const <dynamic>[];
  final audit = row['audit_tail'] as List<dynamic>? ?? const <dynamic>[];
  return TournamentDetail(
    tournament: tournamentDetailHeaderFromRow(
        row['tournament'] as Map<String, dynamic>),
    participants: parts
        .cast<Map<String, dynamic>>()
        .map(tournamentParticipantFromRow)
        .toList(growable: false),
    matches: matches
        .cast<Map<String, dynamic>>()
        .map(tournamentMatchRefFromRow)
        .toList(growable: false),
    auditTail: audit
        .cast<Map<String, dynamic>>()
        .map(tournamentAuditEventFromRow)
        .toList(growable: false),
  );
}
