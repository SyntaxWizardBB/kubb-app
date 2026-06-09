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
  /// Maps the DB `registration_status` vocabulary
  /// (`pending|confirmed|rejected|withdrawn|waitlist`) onto the domain
  /// enum. The DB says `confirmed` where the domain says `approved`, so a
  /// `.name`-based lookup would throw on every confirmed participant —
  /// which is exactly what broke participant parsing once registration
  /// auto-confirms. This is the single canonical wire→enum mapping.
  static TournamentParticipantStatus fromWire(String raw) {
    switch (raw) {
      case 'pending':
        return TournamentParticipantStatus.pending;
      case 'confirmed':
      case 'approved':
        return TournamentParticipantStatus.approved;
      case 'waitlist':
        return TournamentParticipantStatus.waitlist;
      case 'withdrawn':
        return TournamentParticipantStatus.withdrawn;
      case 'rejected':
        return TournamentParticipantStatus.rejected;
      default:
        throw ArgumentError.value(
            raw, 'raw', 'Unknown TournamentParticipantStatus');
    }
  }
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

/// Wire mapping for the `status` column on `tournament_round_schedule`
/// (ADR-0031 Block A1). Mirrors EXACTLY the server CHECK constraint of the
/// table (migration 20261251000000): published | call | running |
/// awaiting_results | completed.
const Map<RoundStatus, String> _roundStatusWire = {
  RoundStatus.published: 'published',
  RoundStatus.call: 'call',
  RoundStatus.running: 'running',
  RoundStatus.awaitingResults: 'awaiting_results',
  RoundStatus.completed: 'completed',
};

/// Wire mapping for the `phase` column on `tournament_matches`. The
/// `group` value sits outside the bracket — callers filter it out before
/// projecting into a [BracketPhase].
const Map<BracketPhase, String> _bracketPhaseWire = {
  BracketPhase.winners: 'ko',
  BracketPhase.thirdPlace: 'third_place',
  BracketPhase.finals: 'final',
  // Double-Elimination (ADR-0027 §1.1 / §4.1).
  BracketPhase.wb: 'wb',
  BracketPhase.lb: 'lb',
  BracketPhase.grandFinal: 'grand_final',
  BracketPhase.grandFinalReset: 'grand_final_reset',
  // Consolation / Trostturnier (ADR-0028 §7.1 / §7.3).
  BracketPhase.consolation: 'consolation',
  BracketPhase.consolationThirdPlace: 'consolation_third_place',
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

/// Encodes a [PoolPhaseConfig] into the jsonb payload the pool-phase
/// generator (`_tournament_compute_pools`) reads as `p_config`, and that
/// `tournament_create` persists as `tournaments.pool_phase_config`. The
/// server reads `group_count`, `qualifiers_per_group`, `strategy` and the
/// optional `random_seed`.
extension PoolPhaseConfigWire on PoolPhaseConfig {
  Map<String, dynamic> toWire() => <String, dynamic>{
        'group_count': groupCount,
        'qualifiers_per_group': qualifiersPerGroup,
        'strategy': strategy.name,
        if (randomSeed != null) 'random_seed': randomSeed,
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

extension RoundStatusWire on RoundStatus {
  static RoundStatus fromWire(String raw) =>
      _enumFromWire(_roundStatusWire, raw, 'RoundStatus');
  String toWire() => _roundStatusWire[this]!;
}

int _asInt(Object? r) => r is int ? r : (r as num).toInt();
int? _asIntOrNull(Object? r) => r == null ? null : _asInt(r);
DateTime? _asDateOrNull(Object? r) =>
    r == null ? null : DateTime.parse(r as String);

/// Decodes a `participants[]` row into a [TournamentParticipant].
///
/// `display_name` is the server-side projection introduced by
/// `20260601000003_tournament_get_with_display_names`
/// (`COALESCE(user_profiles.nickname, teams.display_name)`). It's
/// optional on the wire so wire-rows from older RPC versions still
/// decode — callers fall back to the localized `tournamentParticipantUnknown`
/// string in that case.
TournamentParticipant tournamentParticipantFromRow(Map<String, dynamic> row) {
  return TournamentParticipant(
    participantId: row['participant_id'] as String,
    userId: row['user_id'] as String?,
    nickname: row['nickname'] as String?,
    displayName: row['display_name'] as String?,
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
  final teamSize = _asInt(row['team_size']);
  // `max_team_size` is optional on the wire: older `tournament_get`
  // versions (and fixed-size tournaments) omit it. Fall back to the min
  // so the range collapses to a single fixed size and existing callers
  // keep working.
  final maxTeamSize = _asIntOrNull(row['max_team_size']) ?? teamSize;
  return TournamentDetailHeader(
    tournamentId: row['tournament_id'] as String,
    displayName: row['display_name'] as String,
    createdByUserId: row['created_by'] as String?,
    clubId: row['club_id'] as String?,
    teamSize: teamSize,
    maxTeamSize: maxTeamSize < teamSize ? teamSize : maxTeamSize,
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
    setup: _setupFromHeaderRow(row),
  );
}

/// Collects the P6 setup fields from a `tournament` block into the opaque
/// `setup` map carried by [TournamentDetailHeader.setup]. The keys mirror
/// the snake_case shape `TournamentConfigDraft.toSetupConfig()` emits, so
/// `TournamentConfigDraft.fromDetail(...)` can invert them for the edit
/// wizard. Projected by `tournament_get` from migration 20261201000021;
/// keys absent on older RPC revisions / the test fake simply stay out of
/// the map, leaving the draft on its defaults.
Map<String, Object?> _setupFromHeaderRow(Map<String, dynamic> row) {
  const keys = <String>[
    'location',
    'venue_address',
    'event_starts_at',
    'checkin_until',
    'registration_closes_at',
    'weather_note',
    'info_food',
    'info_travel',
    'info_accommodation',
    'contact_name',
    'contact_phone',
    'entry_fee_cents',
    'currency',
    'max_team_size',
    'payment_methods',
    'league_categories',
    'scoring',
    'rule_variants',
    'ko_match_format',
    'ko_round_formats',
    'pitch_plan',
    'mighty_finisher_quali',
    'consolation_bracket',
    'bracket_type',
    'ko_matchup',
    'ko_tiebreak_method',
    'pool_phase_config',
    'ko_config',
    'rules_pdf_url',
    'site_map_pdf_url',
  ];
  final out = <String, Object?>{};
  for (final key in keys) {
    if (row.containsKey(key)) out[key] = row[key];
  }
  return out;
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

/// Decodes a raw `tournament_matches` CDC row (column-name keyed, as
/// delivered by `RealtimeChannel`) into a domain [TournamentMatchRef].
///
/// The RPC-shaped wire used by [tournamentMatchRefFromRow] renames `id` to
/// `match_id` and `participant_a`/`_b` to `participant_a_id`/`_b_id`;
/// Realtime CDC payloads ship the raw table columns instead. Keeping the
/// two parsers separate avoids leaking the rename into the table schema.
TournamentMatchRef tournamentMatchRefFromCdcRow(Map<String, Object?> row) {
  return TournamentMatchRef(
    matchId: TournamentMatchId(row['id']! as String),
    tournamentId: TournamentId(row['tournament_id']! as String),
    roundNumber: _asInt(row['round_number']),
    matchNumberInRound: _asInt(row['match_number_in_round']),
    participantA: row['participant_a'] == null
        ? null
        : TournamentParticipantId(row['participant_a']! as String),
    participantB: row['participant_b'] == null
        ? null
        : TournamentParticipantId(row['participant_b']! as String),
    status: TournamentMatchStatusWire.fromWire(row['status']! as String),
    consensusRound: _asInt(row['consensus_round']),
    startedAt: _asDateOrNull(row['started_at']),
    completedAt: _asDateOrNull(row['finalized_at']),
    winnerParticipant: row['winner_participant'] == null
        ? null
        : TournamentParticipantId(row['winner_participant']! as String),
    finalScoreA: _asIntOrNull(row['final_score_a']),
    finalScoreB: _asIntOrNull(row['final_score_b']),
    // M2a: raw CDC table column carries the phase token directly.
    phase: matchPhaseFromWire(row['phase'] as String?),
  );
}

/// Decodes a raw `tournament_round_schedule` CDC row (column-name keyed, as
/// delivered by `RealtimeChannel`) into a domain [TournamentRoundScheduleRef]
/// (ADR-0031 Block A1/A3c).
///
/// Reuses the file's established cast helpers ([_asInt] / [_asIntOrNull] /
/// [_asDateOrNull]) instead of duplicating parsers. `starts_at`, `ends_at`
/// and `published_at` are NOT NULL on the table, so they decode via
/// `_asDateOrNull(...)!`; `stage_node_id`, `tiebreak_after_seconds` and
/// `paused_at` are nullable. The `status` string is mapped through
/// [RoundStatusWire.fromWire] (all five CHECK values).
TournamentRoundScheduleRef tournamentRoundScheduleRefFromCdcRow(
  Map<String, Object?> row,
) {
  return TournamentRoundScheduleRef(
    tournamentId: TournamentId(row['tournament_id']! as String),
    stageNodeId: row['stage_node_id'] as String?,
    roundNumber: _asInt(row['round_number']),
    phase: row['phase']! as String,
    status: RoundStatusWire.fromWire(row['status']! as String),
    publishedAt: _asDateOrNull(row['published_at'])!,
    startsAt: _asDateOrNull(row['starts_at'])!,
    endsAt: _asDateOrNull(row['ends_at'])!,
    breakSeconds: _asInt(row['break_seconds']),
    matchSeconds: _asInt(row['match_seconds']),
    tiebreakAfterSeconds: _asIntOrNull(row['tiebreak_after_seconds']),
    pausedAt: _asDateOrNull(row['paused_at']),
    pausedAccumSeconds: _asInt(row['paused_accum_seconds']),
  );
}

/// Decodes a `tournament_list_administrable` RPC row into a domain
/// [TournamentAdminCardRef] (ADR-0031 Phase B, Block B1c).
///
/// The wire columns mirror the `jsonb_build_object` projection of migration
/// `20261255000000_tournament_administrable_gate_and_list.sql`:
/// `tournament_id`, `display_name`, `format`, `status`,
/// `current_round`, `schedule_status`, `paused_at`, `remaining_seconds`,
/// `open_match_count`, `disputed_match_count`.
///
/// The schedule-derived fields (`current_round`, `schedule_status`,
/// `remaining_seconds`, `paused_at`) are nullable: the RPC LEFT-JOINs
/// `tournament_round_schedule`, so a tournament without a schedule row
/// surfaces with those columns NULL. They decode to `null` rather than
/// throwing. `open_match_count` / `disputed_match_count` default to 0 when
/// the wire value is NULL.
TournamentAdminCardRef tournamentAdminCardRefFromRow(Map<String, dynamic> row) {
  final scheduleStatusRaw = row['schedule_status'] as String?;
  return TournamentAdminCardRef(
    tournamentId: TournamentId(row['tournament_id'] as String),
    displayName: row['display_name'] as String,
    format: TournamentFormatWire.fromWire(row['format'] as String),
    status: TournamentStatusWire.fromWire(row['status'] as String),
    currentRound: _asIntOrNull(row['current_round']),
    scheduleStatus: scheduleStatusRaw == null
        ? null
        : RoundStatusWire.fromWire(scheduleStatusRaw),
    remainingSeconds: _asIntOrNull(row['remaining_seconds']),
    openMatchCount: _asIntOrNull(row['open_match_count']) ?? 0,
    disputedMatchCount: _asIntOrNull(row['disputed_match_count']) ?? 0,
    pausedAt: _asDateOrNull(row['paused_at']),
  );
}

/// Decodes a wire row into a domain [TournamentMatchRef].
///
/// `participant_{a,b}_display_name` are the server-projected display
/// names added by `20260601000003_tournament_get_with_display_names`
/// so the match-detail header (R10-F-06) can render `Alice vs. Bob`
/// instead of `ba9c12 vs. f02e91`. Both fields are optional on the
/// wire — wire payloads from older RPC revisions or the realtime CDC
/// channel still decode cleanly.
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
    participantADisplayName: row['participant_a_display_name'] as String?,
    participantBDisplayName: row['participant_b_display_name'] as String?,
    status: TournamentMatchStatusWire.fromWire(row['status'] as String),
    consensusRound: _asInt(row['consensus_round']),
    startedAt: _asDateOrNull(row['started_at']),
    completedAt: _asDateOrNull(row['completed_at']),
    // FF2 / Finding B: real per-side set wins from tournament_list_matches
    // (null on older RPC revisions — synthesis falls back to single-set).
    setsWonA: _asIntOrNull(row['sets_won_a']),
    setsWonB: _asIntOrNull(row['sets_won_b']),
    // M2a: 'phase' is projected by both tournament_list_matches
    // (since 20261212000000) and tournament_match_get — the latter being
    // the detail-screen path — since 20261239000000. Older RPC revisions
    // and CDC rows omit it -> defaults to group (non-forcing, never
    // fabricates a KO auto-winner).
    phase: matchPhaseFromWire(row['phase'] as String?),
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
    // Additive projection (migration 20261240000000); null-tolerant for
    // older RPC revisions / fakes that omit the column.
    eventStartsAt: _asDateOrNull(row['event_starts_at']),
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
