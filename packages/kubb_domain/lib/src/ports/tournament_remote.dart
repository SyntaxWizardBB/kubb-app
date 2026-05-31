import 'package:kubb_domain/src/tournament/bracket.dart';
import 'package:kubb_domain/src/tournament/bracket_advance_event.dart';
import 'package:kubb_domain/src/tournament/ekc_score.dart';
import 'package:kubb_domain/src/tournament/king_outcome.dart';
import 'package:kubb_domain/src/tournament/ko_phase.dart';
import 'package:kubb_domain/src/tournament/pool_group_standings.dart';
import 'package:kubb_domain/src/tournament/pool_phase.dart';
import 'package:kubb_domain/src/tournament/roster_slot.dart';
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

/// One entry of "tournaments the caller is registered for" — a
/// [TournamentSummaryRef] paired with the caller's own participant id and
/// registration status. Lets the hub's registrations list render the row
/// and offer a self-withdraw without a second round-trip. Backed by the
/// `tournament_list_my_registrations` RPC (P1 Tournament-Hub).
@immutable
class MyTournamentRegistration {
  const MyTournamentRegistration({
    required this.tournament,
    required this.participantId,
    required this.status,
  });

  final TournamentSummaryRef tournament;
  final TournamentParticipantId participantId;
  final TournamentParticipantStatus status;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MyTournamentRegistration &&
          other.tournament == tournament &&
          other.participantId == participantId &&
          other.status == status;

  @override
  int get hashCode => Object.hash(tournament, participantId, status);
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
    this.participantADisplayName,
    this.participantBDisplayName,
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

  /// W3-T4: server-projected display name for participant A — same
  /// `COALESCE(user_profiles.nickname, teams.display_name)` shape used by
  /// the participants[] block, replicated onto the match row so the
  /// detail header / live dashboard don't need a join hop. Null when
  /// the slot is empty (BYE) or the participant has neither a nickname
  /// nor a team name on record.
  final String? participantADisplayName;
  final String? participantBDisplayName;

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
          other.finalScoreB == finalScoreB &&
          other.participantADisplayName == participantADisplayName &&
          other.participantBDisplayName == participantBDisplayName;

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
        participantADisplayName,
        participantBDisplayName,
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
    this.kingOutcome = const KingMissed(),
  });

  final TournamentMatchId matchId;
  final int consensusRound;
  final int setNumber;
  final UserId submitterUserId;
  final SetScore score;

  /// Per R11-F-01: the king-outcome attached to this set proposal. Drives
  /// the EKC tally on consensus and is part of the wire payload Wave 3
  /// will ship to the server. Defaults to [KingMissed] so the field is
  /// optional for the current UI call sites that still emit the legacy
  /// `kingHitBy?` shape; they go through [KingOutcome.fromLegacy] to
  /// upgrade.
  final KingOutcome kingOutcome;

  /// Backward-compat projection of [kingOutcome] into the legacy nullable
  /// participant shape. Sprint A W3-T2 migrated the match-detail UI to
  /// the [KingOutcome] tri-toggle and the wire payload to the new
  /// `set_king_outcome` column (migration 20260601000002); this getter
  /// is kept for downstream call sites — notably the conflict-screen
  /// summary — that still render the legacy `kingHitBy?` shape.
  TournamentParticipantId? get kingHitBy => kingOutcome.legacyKingHitBy;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentSetScoreProposal &&
          other.matchId == matchId &&
          other.consensusRound == consensusRound &&
          other.setNumber == setNumber &&
          other.submitterUserId == submitterUserId &&
          other.score == score &&
          other.kingOutcome == kingOutcome;

  @override
  int get hashCode => Object.hash(
        matchId,
        consensusRound,
        setNumber,
        submitterUserId,
        score,
        kingOutcome,
      );
}

/// How a tournament's per-set score is interpreted on the server.
enum TournamentScoring {
  ekc,
  classic,
}

/// Lifecycle of a single registration row. See FR-REG-6 / FR-REG-7.
enum TournamentParticipantStatus {
  pending,
  approved,
  waitlist,
  withdrawn,
  rejected,
}

/// One row from the `participants` array of the full tournament payload.
/// Pure data — adapters fill it in from whatever wire shape they speak.
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
    this.displayName,
  });

  final String participantId;
  final String? userId;
  final String? nickname;

  /// Server-projected display name for this participant — single source
  /// for the four UI surfaces that previously fell back to UUID
  /// substrings (R10-F-06 / R13-F-02 / R14-F-10 / R19-F-09). Filled by
  /// the `tournament_get` RPC as
  /// `COALESCE(user_profiles.nickname, teams.display_name)`. Nullable so
  /// older adapters that haven't been re-pointed still compile; callers
  /// should render `tournamentParticipantUnknown` ("Unbekannt") when
  /// it's missing.
  final String? displayName;

  final TournamentParticipantStatus registrationStatus;
  final int? seed;
  final DateTime registeredAt;
  final DateTime? respondedAt;

  String get displayLabel => displayName ?? nickname ?? '?';
}

/// Header block within the full tournament payload — the row from
/// `tournaments` plus a few derived flags. The wizard reads the
/// match-format settings as a wire map so wave-2 additions don't need
/// a Dart migration.
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

  final String tournamentId;
  final String displayName;
  final String? createdByUserId;
  final int teamSize;
  final int minParticipants;
  final int maxParticipants;
  final TournamentFormat format;
  final TournamentScoring scoring;
  final Map<String, Object?> matchFormatConfig;
  final List<String> tiebreakerOrder;
  final int? byePoints;
  final int? forfeitPoints;
  final TournamentStatus status;
  final DateTime? publishedAt;
  final DateTime? startedAt;
  final DateTime? completedAt;
}

/// One audit-log entry exposed via the full tournament payload.
@immutable
class TournamentAuditEvent {
  const TournamentAuditEvent({
    required this.kind,
    required this.actorUserId,
    required this.payload,
    required this.at,
  });

  final String kind;
  final String? actorUserId;
  final Map<String, Object?> payload;
  final DateTime at;
}

/// Full tournament payload — header, participants, matches, audit tail.
/// Returned by [TournamentRemote.getTournamentDetail].
@immutable
class TournamentDetail {
  const TournamentDetail({
    required this.tournament,
    required this.participants,
    required this.matches,
    required this.auditTail,
  });

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

/// Thrown when a `proposeSetScoreWithLamport` submission cannot be
/// applied because the server has already moved on to a newer consensus
/// retry round (token `STALE_CONSENSUS_ROUND`) or rejected the payload
/// for another conflict reason. The [code] mirrors the server-side
/// token so the outbox flusher and UI can switch on it without parsing
/// messages. See M4.3 architecture §3.5.
class TournamentScoreConflictException implements Exception {
  const TournamentScoreConflictException(this.code);

  /// Server-side token, e.g. `STALE_CONSENSUS_ROUND`.
  final String code;

  @override
  String toString() => 'TournamentScoreConflictException($code)';
}

/// Which side of a match was absent at the pitch when the organizer
/// declared a forfeit (spec DSCORE-63). Wire format is the single-char
/// upper-case token expected by the `tournament_match_forfeit` RPC.
enum ForfeitAbsentSide {
  a,
  b;

  String toWire() => this == ForfeitAbsentSide.a ? 'A' : 'B';
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

  /// Full detail payload — header, participants, matches, audit tail.
  /// Returns `null` when the caller has no read access on the row.
  Future<TournamentDetail?> getTournamentDetail(TournamentId id);

  /// Tournaments the caller is actively registered for (P1 Tournament-Hub).
  /// Backed by `tournament_list_my_registrations`; each entry carries the
  /// caller's own participant id + status so the UI can drive
  /// [withdrawRegistration] without a second lookup. "Active" excludes
  /// rejected/withdrawn rows.
  Future<List<MyTournamentRegistration>> listMyRegistrations();

  // Lifecycle (organizer)

  /// Creates a draft tournament. [setup] carries the P6 header fields
  /// (meta, league, rule variants, KO match format, pitch plan, quali /
  /// consolation config) as the snake_case wire map produced by
  /// `TournamentConfigDraft.toSetupConfig()`. Optional so older callers /
  /// fakes keep compiling; defaults to an empty map (server applies its
  /// column defaults).
  Future<TournamentId> createTournament({
    required String displayName,
    required int teamSize,
    required int minParticipants,
    required int maxParticipants,
    required TournamentFormat format,
    required Map<String, Object?> matchFormatConfig,
    required List<String> tiebreakerOrder,
    Map<String, Object?> setup,
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

  /// Idempotent variant of [proposeSetScores] that carries the local
  /// Lamport tick alongside one single-set payload. The server treats a
  /// repeated submission with identical `(matchId, consensusRound,
  /// setIndex, submitter, lamportCounter, deviceId)` as already-applied
  /// and returns the current [TournamentMatchRef] snapshot without
  /// recording a new score row. Used by the outbox flusher so retries
  /// stay safe under at-least-once delivery (see M4.3 architecture §3.5
  /// and migration `20260701000001_score_rpc_idempotency.sql`).
  ///
  /// Throws [TournamentScoreConflictException] with code
  /// `STALE_CONSENSUS_ROUND` when the server has already moved on to a
  /// later consensus retry round.
  Future<TournamentMatchRef> proposeSetScoreWithLamport({
    required TournamentMatchId matchId,
    required int consensusRound,
    required int setIndex,
    required TournamentParticipantId submitter,
    required SetScore score,
    required int lamportCounter,
    required String deviceId,
  });

  /// Organizer override. `reason` is mandatory per FR-CONF-3 and the
  /// score-input-conflict-spec.
  Future<void> organizerOverride({
    required TournamentMatchId matchId,
    required List<SetScore> finalSetScores,
    required String reason,
  });

  /// Organizer-driven forfeit declaration (spec DSCORE-62..-66 +
  /// FR-MATCH-7 + FR-CFG-11). The absent side is recorded, the score
  /// derives from `tournaments.forfeit_points`, and the match is moved
  /// to `finalized`. `reason` is mandatory and the server enforces a
  /// minimum length of 10 characters per DSCORE-65.
  Future<void> declareForfeit({
    required TournamentMatchId matchId,
    required ForfeitAbsentSide absentSide,
    required String reason,
  });

  /// Realtime-Subscribe (M4). Replaces the M1 placeholder. Emits one
  /// match snapshot per row-update event from Supabase Realtime.
  /// Implementations route through the `RealtimeChannel` port and
  /// translate raw CDC payloads into [TournamentMatchRef]. Backward
  /// compat: returns an empty stream if Realtime is disabled by the
  /// feature flag. Internally subscribes to the per-tournament channel
  /// and filters client-side on [id].
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id);

  /// Realtime-Subscribe für die Match-Liste eines Turniers. Fires on
  /// insert/update/delete of any `tournament_matches` row carrying the
  /// given [tournamentId]. Used by the live dashboard and the spectator
  /// view; for the latter the underlying subscription runs with the
  /// anon role, so RLS gates visibility.
  Stream<TournamentMatchRef> watchTournamentMatches(TournamentId tournamentId);

  /// Realtime-Subscribe für Bracket-Advances. Fires whenever a KO row
  /// in [tournamentId] flips to `finalized` and the winner has been
  /// propagated into the parent bracket slot. Convenience over
  /// [watchTournamentMatches] with a status-finalised filter; the UI
  /// uses it to invalidate the bracket view without re-fetching the
  /// full match list.
  Stream<BracketAdvanceEvent> watchBracketAdvances(TournamentId tournamentId);

  // KO-Phase (M2.2 — see architecture.md §4 and ADR-0017)

  /// FR-FMT-10 manual override. Writes the seeding order of the qualified
  /// participants for the upcoming KO phase. `seeds` must contain a complete
  /// mapping of every qualified participant to a 1-based seed position.
  Future<void> setSeeding({
    required TournamentId tournamentId,
    required Map<TournamentParticipantId, int> seeds,
  });

  /// Inserts the KO-match rows from the current standings + seeding.
  /// Server-side validates that the round-robin / pool phase is fully
  /// finalised. The Supabase adapter must treat `ERRCODE 40001` (already
  /// started) as idempotent — see TASK-M2.2-T7b.
  ///
  /// Contract evolution vs. architecture.md §4: the doc-block lists only
  /// `(tournamentId)`, but the underlying `tournament_start_ko_phase`
  /// RPC takes a `p_ko_config jsonb` payload (TASK-M2.2-T3b). The signature
  /// therefore accepts a [KoPhaseConfig] so callers can pass through the
  /// qualifier count, third-place flag, and seeding mode without a second
  /// round-trip. Architecture doc should be updated to match (handled by
  /// the architect-domain follow-up edit).
  Future<void> startKoPhase(TournamentId tournamentId, KoPhaseConfig config);

  /// FR-PAIR-7. Swaps the participants of a not-yet-started KO pairing.
  /// `reason` is mandatory and lands in the audit trail. Targeting a
  /// pairing whose match has already started is rejected server-side.
  Future<void> overrideKoPairing({
    required TournamentMatchId matchId,
    required TournamentParticipantId participantA,
    required TournamentParticipantId participantB,
    required String reason,
  });

  /// Reads the current bracket state as a domain value object for the
  /// visualisation widget. Pure read path — adapters may compose this on
  /// top of [listMatchesForTournament] plus the `bracketFromMatches`
  /// mapper, or hit a dedicated read RPC. The port exposes it as a
  /// convenience so the UI layer does not have to re-glue the parts.
  Future<Bracket> getBracket(TournamentId tournamentId);

  // Roster (M3.2 — see architecture.md §3.5 and tournament-mode-spec
  // §3.6 FR-REG / §3.7 FR-TEAM)

  /// FR-REG-2 + FR-REG-12. Registers a team for a tournament with an
  /// initial roster. `roster` length must equal the tournament's team
  /// size; at least one entry must reference a registered user
  /// (member_user_id) per FR-REG-12. BR-5 is enforced server-side.
  Future<TournamentParticipantId> registerTeam({
    required TournamentId tournamentId,
    required TeamId teamId,
    required List<RosterSlotInput> roster,
  });

  /// FR-TEAM-13/-14. Replaces one roster slot. The previous occupant is
  /// kept as a closed history row. `reason` is optional in the spec but
  /// always written to the audit trail when present.
  Future<void> replaceRosterSlot({
    required TournamentParticipantId participantId,
    required int slotIndex,
    required RosterSlotInput newOccupant,
    String? reason,
  });

  /// Reads the current roster for a participant (the team-side
  /// equivalent of looking up an individual participant). Returns the
  /// open slots ordered by `slot_index`. Closed history rows are not
  /// returned here — those flow through the audit-tail view.
  Future<List<RosterSlot>> getRoster(TournamentParticipantId participantId);

  // Pool phase (M3.3 — see architecture.md §3.5 and ADR-0019)

  /// Starts the pool/group phase. Reads the approved participant list,
  /// groups them per [config], and inserts pool-phase matches with
  /// `group_label` populated. Backed by `tournament_start_pool_phase`
  /// on the server. Idempotent via the same `ERRCODE 40001` pattern as
  /// `tournament_start_ko_phase` — a second call against an already
  /// initialised phase is swallowed.
  Future<void> startPoolPhase(
    TournamentId tournamentId,
    PoolPhaseConfig config,
  );

  /// Reads the per-group standings snapshot for [id]. Backed by
  /// `tournament_pool_standings(p_tournament_id)`; the server returns
  /// one entry per `group_label`, each already sorted by the
  /// tournament's configured tiebreaker chain.
  Future<List<PoolGroupStandings>> getPoolStandings(TournamentId id);

  /// Veranstalter-Override per OD-M3-05. After `startKoPhase` raised
  /// `TIEBREAKER_NEEDS_RESOLUTION`, the organizer manually orders the
  /// tied qualifiers and submits the resulting permutation. The server
  /// writes it into `tournament_seeding_overrides`; the caller then
  /// retries [startKoPhase].
  Future<void> resolveCrossPoolTie(
    TournamentId tournamentId,
    List<TournamentParticipantId> orderedParticipants,
  );
}
