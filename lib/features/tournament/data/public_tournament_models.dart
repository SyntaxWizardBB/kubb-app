import 'package:flutter/foundation.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Wire-Models fuer den anon-Spectator-Pfad nach ADR-0026 Strategie A.
///
/// Bewusste Trennung von [TournamentDetail] / [TournamentParticipant]:
/// der Public-Envelope der `public_tournament_get`-RPC liefert strikt
/// weniger Felder (kein `user_id`, kein `nickname` aus `user_profiles`,
/// kein `set_score_proposals`, kein `audit_tail`). Eigene Typen
/// verhindern das "Null-Splatter"-Anti-Pattern, bei dem authenticated-
/// Modelle mit nullbaren Spalten fuer den anon-Pfad missbraucht werden.
///
/// Bewusst KEIN Import von `tournament_models.dart` oder
/// `tournament_repository.dart` — die Wire-Helper sind dupliziert, um
/// die Privacy-Grenze auch auf Dart-Importebene sichtbar zu halten.
///
/// Quelle: ADR-0026 §"Client-Repository", anon-rls-plan.md T3.

/// Detail-Snapshot eines public-sichtbaren Turniers fuer anonyme
/// Spectator. Enthaelt Header, Matches und einen anonymisierten
/// Roster-Eintrag pro Slot (nur display_name).
@immutable
class PublicTournamentDetail {
  const PublicTournamentDetail({
    required this.tournament,
    required this.matches,
    required this.roster,
    required this.participantCount,
  });

  final PublicTournamentHeader tournament;
  final List<PublicMatchDetail> matches;
  final List<PublicRosterEntry> roster;
  final int participantCount;

  /// Lookup-Helper fuer Anzeige: gibt den ersten `display_name` zurueck,
  /// der zu [participantId] gehoert; faellt auf `null` zurueck, wenn der
  /// Roster fuer diesen Teilnehmer noch keinen Slot kennt (z.B. BYE).
  String? displayNameFor(TournamentParticipantId? participantId) {
    if (participantId == null) return null;
    final value = participantId.value;
    for (final entry in roster) {
      if (entry.participantId == value) return entry.displayName;
    }
    return null;
  }
}

/// Header-Felder, die `public_tournament_get` liefert. Strikt eine
/// Teilmenge von [TournamentDetailHeader] — kein `createdByUserId`,
/// kein `tiebreakerOrder`, keine internen Punkte-Felder.
@immutable
class PublicTournamentHeader {
  const PublicTournamentHeader({
    required this.tournamentId,
    required this.displayName,
    required this.teamSize,
    required this.format,
    required this.scoring,
    required this.status,
    required this.matchFormatConfig,
    this.startedAt,
    this.completedAt,
  });

  final TournamentId tournamentId;
  final String displayName;
  final int teamSize;
  final TournamentFormat format;

  /// FF2 / Finding A: the tournament scoring mode (`ekc` / `classic`),
  /// now projected by `public_tournament_get`. The anon spectator
  /// standings use this instead of a hard-coded EKC fallback so a classic
  /// tournament renders classic totals. Backward-compat: the decoder maps
  /// a missing / unknown wire value to [TournamentScoring.ekc].
  final TournamentScoring scoring;
  final TournamentStatus status;
  final Map<String, Object?> matchFormatConfig;
  final DateTime? startedAt;
  final DateTime? completedAt;
}

/// Match-Eintrag im Public-Envelope. Trotz Namensgleichheit zu
/// [TournamentMatchRef] absichtlich eigenstaendig — anon sieht weder
/// `set_score_proposals` noch `submitter_user_id`.
@immutable
class PublicMatchDetail {
  const PublicMatchDetail({
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
    this.setsWonA,
    this.setsWonB,
    this.phase,
    this.bracketPosition,
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

  /// FF2 / Finding B: the real per-side set wins, aggregated server-side
  /// from `tournament_set_score_proposals` exactly like
  /// `tournament_pool_standings` (CF2). Null when the wire row predates
  /// FF2 (backward-compat); in that case the standings synthesis falls
  /// back to the single-set / match-win approximation. In classic mode
  /// these drive the real set-win count so client and server standings
  /// agree for best-of-3.
  final int? setsWonA;
  final int? setsWonB;

  /// Wire-Wert der `phase`-Spalte (`group`, `ko`, `third_place`,
  /// `final`). Bewusst als String belassen; der Public-Pfad nutzt das
  /// Feld nur zur Filterung im Bracket-Tab und braucht keine Enum.
  final String? phase;
  final int? bracketPosition;
}

/// Ein Slot des Public-Rosters — display_name only.
@immutable
class PublicRosterEntry {
  const PublicRosterEntry({
    required this.slotId,
    required this.participantId,
    required this.slotIndex,
    required this.displayName,
  });

  /// Opaque, optional slot identifier. Team roster entries carry the
  /// roster-slot UUID; single participants have no roster slot, so the
  /// server projects `slot_id = NULL` for them (CF3 / K08).
  final String? slotId;
  final String participantId;
  final int slotIndex;
  final String displayName;
}

/// Decoder: Public-Tournament-Envelope (`public_tournament_get`-RPC).
PublicTournamentDetail publicTournamentDetailFromEnvelope(
  Map<String, dynamic> envelope,
) {
  final tournament = envelope['tournament'] as Map<String, dynamic>;
  final matches =
      envelope['matches'] as List<dynamic>? ?? const <dynamic>[];
  final roster =
      envelope['roster'] as List<dynamic>? ?? const <dynamic>[];
  return PublicTournamentDetail(
    tournament: _headerFromRow(tournament),
    matches: matches
        .cast<Map<String, dynamic>>()
        .map(publicMatchDetailFromRow)
        .toList(growable: false),
    roster: roster
        .cast<Map<String, dynamic>>()
        .map(_rosterEntryFromRow)
        .toList(growable: false),
    participantCount: _asInt(envelope['participant_count']),
  );
}

PublicTournamentHeader _headerFromRow(Map<String, dynamic> row) {
  final cfg = row['match_format_config'];
  return PublicTournamentHeader(
    tournamentId: TournamentId(row['tournament_id'] as String),
    displayName: row['display_name'] as String,
    teamSize: _asInt(row['team_size']),
    format: _formatFromWire(row['format'] as String),
    scoring: _scoringFromWire(row['scoring']),
    status: _statusFromWire(row['status'] as String),
    matchFormatConfig: cfg is Map<String, dynamic>
        ? Map<String, Object?>.from(cfg)
        : const <String, Object?>{},
    startedAt: _asDateOrNull(row['started_at']),
    completedAt: _asDateOrNull(row['completed_at']),
  );
}

/// Public-Wire-Decoder fuer einen `matches[]`-Eintrag bzw. den Envelope
/// der `public_tournament_match_get`-RPC (gleiche Spaltennamen).
PublicMatchDetail publicMatchDetailFromRow(Map<String, dynamic> row) {
  return PublicMatchDetail(
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
    status: _matchStatusFromWire(row['status'] as String),
    consensusRound: _asInt(row['consensus_round']),
    startedAt: _asDateOrNull(row['started_at']),
    completedAt: _asDateOrNull(row['completed_at']),
    winnerParticipant: row['winner_participant_id'] == null
        ? null
        : TournamentParticipantId(row['winner_participant_id'] as String),
    finalScoreA: _asIntOrNull(row['final_score_a']),
    finalScoreB: _asIntOrNull(row['final_score_b']),
    setsWonA: _asIntOrNull(row['sets_won_a']),
    setsWonB: _asIntOrNull(row['sets_won_b']),
    phase: row['phase'] as String?,
    bracketPosition: _asIntOrNull(row['bracket_position']),
  );
}

PublicRosterEntry _rosterEntryFromRow(Map<String, dynamic> row) {
  return PublicRosterEntry(
    slotId: row['slot_id'] as String?,
    participantId: row['participant_id'] as String,
    slotIndex: _asInt(row['slot_index']),
    displayName: row['display_name'] as String,
  );
}

// ---- Inline-Wire-Tabellen --------------------------------------------
//
// Bewusst dupliziert von `tournament_models.dart`, damit der Public-
// Pfad keinen Import auf den authenticated Adapter braucht. Die
// Tabellen sind klein und stabil; bei zukuenftigen Enum-Erweiterungen
// muessen beide Stellen synchron gepflegt werden (ADR-0026 §Consequences
// "Code-Duplikation").

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

const Map<TournamentScoring, String> _scoringWire = {
  TournamentScoring.ekc: 'ekc',
  TournamentScoring.classic: 'classic',
};

const Map<TournamentMatchStatus, String> _matchStatusWire = {
  TournamentMatchStatus.scheduled: 'scheduled',
  TournamentMatchStatus.awaitingResults: 'awaiting_results',
  TournamentMatchStatus.disputed: 'disputed',
  TournamentMatchStatus.finalized: 'finalized',
  TournamentMatchStatus.overridden: 'overridden',
  TournamentMatchStatus.voided: 'voided',
};

TournamentFormat _formatFromWire(String raw) {
  for (final entry in _formatWire.entries) {
    if (entry.value == raw) return entry.key;
  }
  throw ArgumentError.value(raw, 'raw', 'Unknown TournamentFormat');
}

TournamentStatus _statusFromWire(String raw) {
  for (final entry in _statusWire.entries) {
    if (entry.value == raw) return entry.key;
  }
  throw ArgumentError.value(raw, 'raw', 'Unknown TournamentStatus');
}

/// FF2 / Finding A: maps the wire `scoring` value to [TournamentScoring].
/// Unlike the other wire helpers this is DELIBERATELY lenient — a missing
/// or unknown value (older RPC revision without the field) falls back to
/// [TournamentScoring.ekc], the historical default, so the spectator
/// screen never crashes on a stale envelope.
TournamentScoring _scoringFromWire(Object? raw) {
  for (final entry in _scoringWire.entries) {
    if (entry.value == raw) return entry.key;
  }
  return TournamentScoring.ekc;
}

TournamentMatchStatus _matchStatusFromWire(String raw) {
  for (final entry in _matchStatusWire.entries) {
    if (entry.value == raw) return entry.key;
  }
  throw ArgumentError.value(raw, 'raw', 'Unknown TournamentMatchStatus');
}

int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  throw ArgumentError.value(value, 'value', 'expected num');
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  return _asInt(value);
}

DateTime? _asDateOrNull(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.parse(value as String);
}
