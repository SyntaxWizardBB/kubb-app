import 'package:kubb_domain/src/tournament/bracket.dart';
import 'package:kubb_domain/src/tournament/bracket_advance_event.dart';
import 'package:kubb_domain/src/tournament/ekc_score.dart';
import 'package:kubb_domain/src/tournament/king_outcome.dart';
import 'package:kubb_domain/src/tournament/ko_phase.dart';
import 'package:kubb_domain/src/tournament/pool_group_standings.dart';
import 'package:kubb_domain/src/tournament/pool_phase.dart';
import 'package:kubb_domain/src/tournament/roster_slot.dart';
import 'package:kubb_domain/src/tournament/round_schedule.dart';
import 'package:kubb_domain/src/tournament/shootout.dart';
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
    this.eventStartsAt,
    this.createdBy,
  });

  final TournamentId tournamentId;
  final String displayName;
  final TournamentFormat format;
  final TournamentStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int participantCount;

  /// Scheduled kickoff of the event (`tournaments.event_starts_at`). Null
  /// when undated or when an older RPC projection omits the column. Drives
  /// the hub's "Kuenftige Turniere" date filter (>= today OR null).
  final DateTime? eventStartsAt;

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
          other.eventStartsAt == eventStartsAt &&
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
        eventStartsAt,
        createdBy,
      );
}

/// Read-side snapshot of one administrable tournament for the organizer
/// dashboard / cockpit (ADR-0031 §Dashboard, Phase B). Pure data — no
/// Flutter/Supabase imports. Backed by the `tournament_list_administrable`
/// RPC, which LEFT JOINs `tournament_round_schedule`, so the schedule-side
/// fields ([currentRound], [scheduleStatus], [remainingSeconds], [pausedAt])
/// are all nullable: a published/live tournament with no schedule row yet
/// (the LEFT-JOIN-NULL path) is fully constructible without them.
@immutable
class TournamentAdminCardRef {
  const TournamentAdminCardRef({
    required this.tournamentId,
    required this.displayName,
    required this.format,
    required this.status,
    this.currentRound,
    this.scheduleStatus,
    this.remainingSeconds,
    this.openMatchCount = 0,
    this.disputedMatchCount = 0,
    this.pausedAt,
  });

  final TournamentId tournamentId;
  final String displayName;
  final TournamentFormat format;
  final TournamentStatus status;

  /// 1-based number of the currently active round, or `null` when the
  /// tournament has no schedule row yet (LEFT-JOIN-NULL path).
  final int? currentRound;

  /// Status of the active round's schedule, or `null` when no schedule row
  /// exists yet. Reuses the canonical [RoundStatus] from
  /// `round_schedule.dart` for wire parity — no parallel enum.
  final RoundStatus? scheduleStatus;

  /// Server-computed remaining seconds of the active round window
  /// (`app_server_now()`-based formula), or `null` without a schedule row.
  final int? remainingSeconds;

  /// Count of matches still open (`scheduled` | `awaiting_results`).
  final int openMatchCount;

  /// Count of matches currently disputed — drives the escalation badge.
  final int disputedMatchCount;

  /// Anchor of the tournament-wide pause on the active schedule row (K5),
  /// or `null` when not paused / no schedule row exists.
  final DateTime? pausedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentAdminCardRef &&
          other.tournamentId == tournamentId &&
          other.displayName == displayName &&
          other.format == format &&
          other.status == status &&
          other.currentRound == currentRound &&
          other.scheduleStatus == scheduleStatus &&
          other.remainingSeconds == remainingSeconds &&
          other.openMatchCount == openMatchCount &&
          other.disputedMatchCount == disputedMatchCount &&
          other.pausedAt == pausedAt;

  @override
  int get hashCode => Object.hash(
        tournamentId,
        displayName,
        format,
        status,
        currentRound,
        scheduleStatus,
        remainingSeconds,
        openMatchCount,
        disputedMatchCount,
        pausedAt,
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
    this.setsWonA,
    this.setsWonB,
    this.participantADisplayName,
    this.participantBDisplayName,
    this.phase = MatchPhase.group,
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
  /// FF2 or comes from the realtime CDC channel (raw table columns) —
  /// the standings synthesis then falls back to the single-set / match-win
  /// approximation. In classic mode these drive the real set-win count so
  /// client and server standings agree for best-of-3.
  final int? setsWonA;
  final int? setsWonB;

  /// W3-T4: server-projected display name for participant A — same
  /// `COALESCE(user_profiles.nickname, teams.display_name)` shape used by
  /// the participants[] block, replicated onto the match row so the
  /// detail header / live dashboard don't need a join hop. Null when
  /// the slot is empty (BYE) or the participant has neither a nickname
  /// nor a team name on record.
  final String? participantADisplayName;
  final String? participantBDisplayName;

  /// M2a: the match's phase, used by the canonical set-winner derivation
  /// to decide whether a king-less set is non-decisive (group) or owned
  /// by the KO finisher (M2b). Defaults to [MatchPhase.group] — the
  /// safe, non-forcing default for wire rows / fakes that don't project
  /// the column, so no caller ever fabricates an auto kubb-majority
  /// winner.
  final MatchPhase phase;

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
          other.setsWonA == setsWonA &&
          other.setsWonB == setsWonB &&
          other.participantADisplayName == participantADisplayName &&
          other.participantBDisplayName == participantBDisplayName &&
          other.phase == phase;

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
        setsWonA,
        setsWonB,
        participantADisplayName,
        participantBDisplayName,
        phase,
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
    this.checkedInAt,
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

  /// On-site presence timestamp (ADR-0031 Phase D). NULL until an organizer
  /// (Creator OR an active club role in {owner, admin, organizer, referee} —
  /// K4) checks the participant in via `tournament_checkin_participant`, and
  /// reset to NULL again by `tournament_undo_checkin`. Distinct from
  /// [registrationStatus]: confirmed = pool membership, check-in = physical
  /// attendance. Projected by `tournament_get` (`checked_in_at`) and pushed
  /// over the `tournament_participants` CDC channel. Nullable and additive:
  /// older RPC/CDC payloads that omit the column decode to `null`.
  final DateTime? checkedInAt;

  /// True once this participant has been marked physically present on site.
  bool get isCheckedIn => checkedInAt != null;

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
    required this.clubId,
    required this.teamSize,
    required this.maxTeamSize,
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
    this.setup = const <String, Object?>{},
  });

  final String tournamentId;
  final String displayName;
  final String? createdByUserId;

  /// Optional organizing club (`tournaments.club_id`). When set, an active
  /// owner/admin/organizer of this club may manage the tournament alongside
  /// the creator (server: `tournament_caller_can_manage`). NULL means the
  /// tournament has no club and only the creator may manage it.
  final String? clubId;

  /// Raw P6 setup wire map as projected by `tournament_get`
  /// (20261201000021). Carries the snake_case keys produced by
  /// `TournamentConfigDraft.toSetupConfig()` — location, dates, fees,
  /// rule_variants, ko_config, pitch_plan, etc. Kept as an opaque map (the
  /// same pattern as [matchFormatConfig]) so the edit screen can rebuild a
  /// draft via `TournamentConfigDraft.fromDetail(...)` without the domain
  /// header growing ~24 typed fields. Empty when the server omits them
  /// (older RPC revisions / the test fake).
  final Map<String, Object?> setup;

  /// Minimum players per team registration (`tournaments.team_size`).
  /// For solo tournaments this is `1`.
  final int teamSize;

  /// Maximum players per team registration
  /// (`tournaments.max_team_size`). When the server projects no explicit
  /// max — older `tournament_get` versions, or a fixed-size tournament —
  /// the wire parser falls back to [teamSize], so a registration roster
  /// must always satisfy `teamSize <= n <= maxTeamSize`.
  final int maxTeamSize;

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

/// Consensus state of one shoot-out tie group, mirroring the
/// `tournament_shootouts.status` column (P6 D2a migration
/// `20261202000000_tournament_shootout_server.sql`).
///
///  * [pending]  — detected, no winner ordering reported yet.
///  * [reported] — one involved side submitted an ordering; awaiting the
///    other side's matching confirmation.
///  * [resolved] — both sides agreed; [PendingShootout.orderedWinners] is
///    frozen and the group is no longer open.
enum ShootoutStatus {
  pending,
  reported,
  resolved;

  static ShootoutStatus fromWire(String raw) {
    switch (raw) {
      case 'pending':
        return ShootoutStatus.pending;
      case 'reported':
        return ShootoutStatus.reported;
      case 'resolved':
        return ShootoutStatus.resolved;
      default:
        throw ArgumentError.value(raw, 'raw', 'Unknown ShootoutStatus');
    }
  }
}

/// Read-side snapshot of one `tournament_shootouts` row plus the
/// display-names of the tied participants — enough for the report/confirm
/// UI without a second round-trip.
///
/// [tiedParticipants] are the involved participants in their pre-shoot-out
/// chain order (the order the server stored in `tied_participant_ids`).
/// [orderedWinners] is the resolved best-first permutation once a side has
/// reported it; empty while [status] is [ShootoutStatus.pending]. The
/// invariant from [ShootoutResult] applies: when non-empty, it is a full
/// permutation of the tied participant ids.
@immutable
class PendingShootout {
  PendingShootout({
    required this.shootoutId,
    required this.tournamentId,
    required this.startRank,
    required List<ShootoutParticipantRef> tiedParticipants,
    required List<TournamentParticipantId> orderedWinners,
    required this.status,
  })  : tiedParticipants = List.unmodifiable(tiedParticipants),
        orderedWinners = List.unmodifiable(orderedWinners);

  final String shootoutId;
  final TournamentId tournamentId;

  /// Zero-based rank of the first tied member in the overall ranking
  /// (mirrors `tournament_shootouts.start_rank` / [ShootoutGroup.startRank]).
  final int startRank;

  final List<ShootoutParticipantRef> tiedParticipants;
  final List<TournamentParticipantId> orderedWinners;
  final ShootoutStatus status;

  /// Tied participant ids only, in stored order — convenience for callers
  /// that build a [ShootoutResult]/permutation check.
  List<TournamentParticipantId> get tiedParticipantIds =>
      [for (final p in tiedParticipants) p.participantId];

  /// Still open for input: not yet resolved.
  bool get isOpen => status != ShootoutStatus.resolved;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PendingShootout &&
          other.shootoutId == shootoutId &&
          other.tournamentId == tournamentId &&
          other.startRank == startRank &&
          _listEq(other.tiedParticipants, tiedParticipants) &&
          _listEq(other.orderedWinners, orderedWinners) &&
          other.status == status;

  @override
  int get hashCode => Object.hash(
        shootoutId,
        tournamentId,
        startRank,
        Object.hashAll(tiedParticipants),
        Object.hashAll(orderedWinners),
        status,
      );
}

/// A tied participant with its server-projected display name, used to label
/// the shoot-out UI rows. [displayName] is null when the server projection
/// has neither a nickname nor a team name on record; callers render
/// `tournamentParticipantUnknown` ("Unbekannt") in that case.
@immutable
class ShootoutParticipantRef {
  const ShootoutParticipantRef({
    required this.participantId,
    this.displayName,
  });

  final TournamentParticipantId participantId;
  final String? displayName;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShootoutParticipantRef &&
          other.participantId == participantId &&
          other.displayName == displayName;

  @override
  int get hashCode => Object.hash(participantId, displayName);
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
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

  /// Edits an existing tournament's header + P6 setup fields after it has
  /// been created (P7 / USER SPEC: organiser may edit details after
  /// publish). Mirrors [createTournament]'s parameter shape; [setup]
  /// carries the same snake_case wire map from
  /// `TournamentConfigDraft.toSetupConfig()`. The server
  /// (`tournament_update`) gates on the creator and refuses edits once the
  /// tournament has gone live (status must be pre-start: draft /
  /// published / registration_open / registration_closed).
  Future<void> updateTournament({
    required TournamentId id,
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

  // Invite-only fun tournaments (Spaßturnier "auf Einladung")
  //
  // Backed by the SECURITY DEFINER RPCs from migration `20261272…`:
  // - `tournament_invite_user(p_tournament_id, p_user_id)` — organizer invites
  //   a user to an `invite_only` tournament; writes an inbox message.
  // - `tournament_invitation_respond(p_invitation_id, p_accept)` — invitee
  //   accepts (→ registered `pending`) or declines.
  // - `tournament_revoke_invitation(p_invitation_id)` — organizer revokes a
  //   pending invitation.
  //
  // The invitation id travels as a plain String (the inbox `action_payload`
  // carries it); there is no dedicated value object since the respond path
  // runs through the generic inbox surface.

  /// Invites [userId] to the `invite_only` tournament [tournamentId]. The
  /// server gates on the organizer and requires the tournament to be
  /// invite-only. Idempotent per (tournament, user): a re-invite after
  /// revoke/decline re-activates the invitation.
  Future<void> inviteUser(TournamentId tournamentId, UserId userId);

  /// Invitee response to a tournament invitation. [accept] true registers the
  /// caller as `pending` for the tournament; false declines it.
  Future<void> respondInvitation(String invitationId, {required bool accept});

  /// Organizer revokes a pending tournament invitation.
  Future<void> revokeInvitation(String invitationId);

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

  // On-site check-in (ADR-0031 Phase D)

  /// Marks a confirmed participant as physically present on site
  /// (ADR-0031 Phase D). Backed by the `tournament_checkin_participant`
  /// RPC (migration `20261265000000`), which sets
  /// `tournament_participants.checked_in_at = now()`. Server-authoritative:
  /// the RPC enforces the manage gate (`tournament_caller_can_manage` — K4),
  /// the tournament status window (`registration_open|registration_closed|
  /// live`) and a `registration_status = 'confirmed'` precondition; the
  /// client does NOT re-implement those checks. Idempotent — checking in an
  /// already-checked-in participant is a server-side no-op. Throws the
  /// underlying Postgres error (e.g. `42501` gate, `22023` status) rather
  /// than swallowing it.
  Future<void> checkinParticipant(TournamentParticipantId participantId);

  /// Clears a participant's on-site presence (ADR-0031 Phase D). Backed by
  /// the `tournament_undo_checkin` RPC (migration `20261265000000`), which
  /// resets `tournament_participants.checked_in_at = NULL`. Same server-side
  /// gate/status semantics as [checkinParticipant] and idempotent (undoing
  /// an already-cleared participant is a no-op). Errors propagate.
  Future<void> undoCheckin(TournamentParticipantId participantId);

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

  /// Realtime-Subscribe for the participant list of a tournament (ADR-0031
  /// Phase D). Fires on insert/update of any `tournament_participants` row
  /// carrying the given [tournamentId] (the CDC filter column) — most
  /// notably when `checked_in_at` flips on check-in / undo. Implementations
  /// route through the shared per-tournament `RealtimeChannel` and translate
  /// raw CDC payloads into a [TournamentParticipant]; DELETE events are
  /// filtered out. The table already ships in the realtime publication
  /// (migration `20261236000000`), so no new subscription/poll is needed —
  /// CDC drives the push (ADR-0029). Signature mirrors
  /// [watchTournamentMatches].
  Stream<TournamentParticipant> watchTournamentParticipants(
    TournamentId tournamentId,
  );

  /// Realtime-Subscribe für Bracket-Advances. Fires whenever a KO row
  /// in [tournamentId] flips to `finalized` and the winner has been
  /// propagated into the parent bracket slot. Convenience over
  /// [watchTournamentMatches] with a status-finalised filter; the UI
  /// uses it to invalidate the bracket view without re-fetching the
  /// full match list.
  Stream<BracketAdvanceEvent> watchBracketAdvances(TournamentId tournamentId);

  // Timed runner (ADR-0031 Block A3b/A3c)

  /// Server-authoritative clock source (ADR-0031 §Uhr). Calls the
  /// `app_server_now()` RPC and returns the server's `now()` as UTC. The
  /// client derives a skew offset `offset = serverNow - DateTime.now().toUtc()`
  /// once at app start / reconnect and renders `now = DateTime.now() + offset`
  /// with a pure 1s UI ticker — a rare offset-sync, never a per-second poll
  /// (ADR-0029).
  Future<DateTime> fetchServerNow();

  /// Realtime-Subscribe für die Runden-Schedule eines Turniers (ADR-0031
  /// Block A1/A3c). Fires on insert/update of any
  /// `tournament_round_schedule` row carrying the given [tournamentId]
  /// (the CDC filter column). Each event carries the per-round timestamps
  /// (`starts_at`/`ends_at`), the round [RoundStatus], and the pause anchors
  /// (`paused_at`/`paused_accum_seconds`) the runner uses to drive the
  /// server-/pause-corrected countdown. Implementations route through the
  /// `RealtimeChannel` port and translate raw CDC payloads into a
  /// [TournamentRoundScheduleRef]; DELETE events are filtered out.
  Stream<TournamentRoundScheduleRef> watchRoundSchedule(
    TournamentId tournamentId,
  );

  // Organizer dashboard (ADR-0031 Phase B — Veranstalter-Cockpit)

  /// Lists the tournaments the caller may administer (Creator OR an active
  /// club role in {owner, admin, organizer, referee} — K4). Backed by the
  /// `tournament_list_administrable` RPC; each card carries the active
  /// round's schedule status, remaining seconds, and open/disputed match
  /// counts so the dashboard renders without an N+1 fan-out.
  Future<List<TournamentAdminCardRef>> listAdministrableTournaments();

  /// Tournament-wide pause (K5). Writes `paused_at = now()` on the active
  /// `tournament_round_schedule` row when not already paused (idempotent);
  /// the Restzeit-Formel then freezes the clock. Never touches
  /// `tournament_matches`.
  Future<void> pauseTournament(TournamentId id);

  /// Resumes a paused tournament. Credits the elapsed pause back into
  /// `paused_accum_seconds` and clears `paused_at` on the active schedule
  /// row (idempotent).
  Future<void> resumeTournament(TournamentId id);

  /// Skips the active round's call window forward — starts play now
  /// (`starts_at = now()`, status `running`). Writes only the schedule row.
  Future<void> skipScheduleForward(TournamentId id);

  /// Re-opens the active round's call window — re-announces the round
  /// (status `call`, a fresh break window). Writes only the schedule row.
  Future<void> skipScheduleBackward(TournamentId id);

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

  /// P6 "TournierStart" auto-seeding. Derives a full seed order from each
  /// confirmed participant's ELO (per P6_RULES_DECISIONS §I: team rating =
  /// SUM of members' ELO, missing ratings default to 1200) and persists it
  /// into the SAME `tournament_seeding_overrides` store the manual
  /// [setSeeding] writes — the KO generator already reads that store.
  ///
  /// Returns the resulting seed order best-first (seed 1 .. N) so the
  /// caller can reflect the authoritative server result. The organizer can
  /// still manually reorder afterwards via [setSeeding].
  ///
  /// Out of scope (Phase 6): the match->ELO writer is not implemented yet,
  /// so `player_ratings` is empty and every participant currently resolves
  /// to 1200 — the order is decided entirely by a deterministic tie-break.
  Future<List<TournamentParticipantId>> autoseedFromElo(
    TournamentId tournamentId,
  );

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

  // Shoot-Out tiebreak (P6 D2b — docs/P6_SHOOTOUT_TIEBREAK.md). The server
  // side (D2a, migration 20261202000000_tournament_shootout_server.sql)
  // exposes no "list-pending" RPC; the client reads the RLS-gated
  // `tournament_shootouts` table directly and acts via the two consensus
  // RPCs `tournament_report_shootout_winners` / `tournament_confirm_shootout`.

  /// Loads the shoot-out tie groups of [tournamentId] that are still open
  /// for the caller (status `pending` or `reported`), with the involved
  /// participants and their display names. Backed by a direct select on the
  /// RLS-gated `tournament_shootouts` table (no dedicated RPC exists) — RLS
  /// already restricts visibility to the organizer and registered
  /// participants. Resolved groups are filtered out so they no longer show
  /// as open. Returns an empty list when none are open.
  Future<List<PendingShootout>> listPendingShootouts(TournamentId tournamentId);

  /// Reports the shoot-out winner ordering for one tie group via the D2a
  /// `tournament_report_shootout_winners` RPC. [orderedWinners] must be a
  /// full permutation of the group's tied participant ids (best first); the
  /// server enforces the [ShootoutResult] permutation invariant and rejects
  /// a partial/duplicate ordering with `INVALID_ORDER`. A second report by an
  /// involved user overwrites the previous one and resets any confirmation.
  Future<void> reportShootoutWinners({
    required String shootoutId,
    required List<TournamentParticipantId> orderedWinners,
  });

  /// Confirms a previously reported ordering for one tie group via the D2a
  /// `tournament_confirm_shootout` RPC. [orderedWinners] must match the
  /// reported ordering exactly (server raises `ORDER_MISMATCH` otherwise) and
  /// the confirming side must differ from the reporter. On success the group
  /// becomes [ShootoutStatus.resolved].
  Future<void> confirmShootout({
    required String shootoutId,
    required List<TournamentParticipantId> orderedWinners,
  });
}
