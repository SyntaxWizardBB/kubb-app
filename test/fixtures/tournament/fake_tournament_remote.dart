import 'dart:math' as math;

import 'package:kubb_domain/kubb_domain.dart';
// Test_support sits under `lib/src/` and is not exported from the public
// `kubb_domain` library — the test-double API stays out of production
// imports. Pulling it in via the `src/` path keeps the fixture
// self-contained without widening the package's public surface.
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

// Roster exception classes — duplicated locally so this branch compiles
// in isolation. TASK-M3.2-T9 lands the canonical versions in
// `lib/features/tournament/data/tournament_repository.dart`; the
// orchestrator merge dedupes the definitions and switches this file to
// an `import` instead.

/// Thrown when a roster registration fails FR-REG-12 (at least one
/// member required). Mirrors the server's `MIN_ONE_REGISTERED` token.
class MinOneRegisteredException implements Exception {
  const MinOneRegisteredException(this.message);
  final String message;
  @override
  String toString() => 'MinOneRegisteredException: $message';
}

/// Thrown when BR-5 is violated: a user is already in an open roster
/// slot of another participant in the same tournament. Mirrors the
/// server-side unique-exclusion (`23P01`) constraint.
class RosterBR5Exception implements Exception {
  const RosterBR5Exception(this.message);
  final String message;
  @override
  String toString() => 'RosterBR5Exception: $message';
}

/// Thrown when roster mutation is blocked because the tournament has
/// reached a terminal state (finalized/aborted) or the participant has
/// an open match. Mirrors `ROSTER_LOCKED_DURING_MATCH`.
class RosterLockedException implements Exception {
  const RosterLockedException(this.message, {required this.cause});
  final String message;
  final String cause;
  @override
  String toString() => 'RosterLockedException($cause): $message';
}

/// Local mirror of the canonical exception in
/// `lib/features/tournament/data/tournament_repository.dart`. Duplicated
/// so the fake builds standalone; the orchestrator merge dedupes it the
/// same way it does the roster exceptions above.
class TieResolutionRequiredException implements Exception {
  const TieResolutionRequiredException({
    required this.conflictingParticipants,
    required this.message,
  });
  final List<TournamentParticipantId> conflictingParticipants;
  final String message;
  @override
  String toString() =>
      'TieResolutionRequiredException(${conflictingParticipants.length}): '
      '$message';
}

/// In-memory [TournamentRemote] for widget-level tests. Mirrors the
/// `tournament_propose_set_scores` consensus state machine: byte-equal
/// proposals from both sides finalise the match (with EKC final scores);
/// disagreements bump `consensus_round` up to 3, the third disagreement
/// flips the match to `disputed`. Realtime [watchMatch] is a no-op
/// since M1 callers poll on demand.
///
/// KO additions (M2): the Fake mirrors the server-side
/// `tournament_advance_ko_winner` trigger in pure Dart so that widget
/// tests around `SeedingScreen` and the bracket view see the same
/// shape of progressing rows that production hits via Supabase. See
/// `supabase/migrations/20260601000016_trigger_advance_ko_winner.sql`
/// for the wire reference.
class FakeTournamentRemote implements TournamentRemote {
  FakeTournamentRemote({
    required UserId initialUser,
    FakeRealtimeChannel? realtime,
  })  : currentUser = initialUser,
        realtime = realtime ?? FakeRealtimeChannel();

  /// "Logged-in" user that subsequent calls run as. Tests flip this to
  /// drive the same flow from different participants / the organizer.
  UserId currentUser;
  int _idSeq = 0;

  /// Realtime adapter the `watch*` streams subscribe through. Tests drive
  /// events with [FakeRealtimeChannel.emit] addressed by
  /// [fakeRealtimeChannelKey] (see [matchesChannelKeyFor]).
  final FakeRealtimeChannel realtime;

  /// Channel key for the `tournament_matches` slice of [tournamentId].
  /// Tests use this to address `realtime.emit` / `realtime.setState`;
  /// production adapters mirror the same `<table>:<column>=<value>`
  /// scheme.
  static String matchesChannelKeyFor(TournamentId tournamentId) =>
      fakeRealtimeChannelKey(
        table: 'tournament_matches',
        filterColumn: 'tournament_id',
        filterValue: tournamentId.value,
      );

  final Map<TournamentId, _Tournament> _tournaments =
      <TournamentId, _Tournament>{};
  final Map<TournamentParticipantId, _Participant> _participants =
      <TournamentParticipantId, _Participant>{};
  final Map<TournamentMatchId, _Match> _matches =
      <TournamentMatchId, _Match>{};

  /// Per-tournament KO config; populated by [createTournament] from the
  /// wizard payload when the match-format config contains a `ko_config`
  /// block. Tests may also seed this directly via [setKoConfig].
  final Map<TournamentId, KoPhaseConfig> _koConfig =
      <TournamentId, KoPhaseConfig>{};

  /// Per-tournament manual seeding overrides (participant → 1-based seed).
  /// Mirrors the `tournament_seeding_overrides` table.
  final Map<TournamentId, Map<TournamentParticipantId, int>> _seedingOverrides =
      <TournamentId, Map<TournamentParticipantId, int>>{};

  /// Per-participant roster slots (open + closed). Mirrors the
  /// `tournament_roster_slots` table — closed history rows live alongside
  /// open ones, distinguished by [_RosterSlot.replacedAt].
  final Map<TournamentParticipantId, List<_RosterSlot>> _rosterByParticipant =
      <TournamentParticipantId, List<_RosterSlot>>{};

  /// Per-tournament pool-phase config; populated by [startPoolPhase].
  final Map<TournamentId, PoolPhaseConfig> _poolConfig =
      <TournamentId, PoolPhaseConfig>{};

  /// Per-tournament participant → group_label assignment. Mirrors the
  /// `group_label` column on `tournament_participants`.
  final Map<TournamentId, Map<TournamentParticipantId, String>> _groupLabels =
      <TournamentId, Map<TournamentParticipantId, String>>{};

  /// Per-tournament cross-pool tie resolution (ordered participants).
  /// Populated by [resolveCrossPoolTie]; persists across retries.
  final Map<TournamentId, List<TournamentParticipantId>> _crossPoolOverrides =
      <TournamentId, List<TournamentParticipantId>>{};

  String _nextId(String prefix) => '$prefix-${++_idSeq}';

  /// Test-only hook to install a KO config without going through the
  /// full wizard payload. Production code passes the config inside
  /// `createTournament`'s `matchFormatConfig['ko_config']`.
  void setKoConfig(TournamentId id, KoPhaseConfig config) {
    _koConfig[id] = config;
  }

  @override
  Future<List<TournamentSummaryRef>> listTournaments({
    TournamentStatus? statusFilter,
    int limit = 50,
  }) async {
    return [
      for (final t in _tournaments.values)
        if (statusFilter == null || t.status == statusFilter) t.toSummary(),
    ].take(limit).toList(growable: false);
  }

  @override
  Future<TournamentSummaryRef?> getTournament(TournamentId id) async =>
      _tournaments[id]?.toSummary();

  @override
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async {
    // M1 integration tests don't drive UI that reads the full detail.
    // Returning null is safe — the only consumer would be the detail
    // screen, which is not part of these scenarios.
    return null;
  }

  @override
  Future<TournamentId> createTournament({
    required String displayName,
    required int teamSize,
    required int minParticipants,
    required int maxParticipants,
    required TournamentFormat format,
    required Map<String, Object?> matchFormatConfig,
    required List<String> tiebreakerOrder,
  }) async {
    final id = TournamentId(_nextId('t'));
    _tournaments[id] = _Tournament(
      id: id,
      displayName: displayName,
      format: format,
      createdByUserId: currentUser,
    );
    return id;
  }

  @override
  Future<void> publish(TournamentId id) async =>
      _tournaments[id]!.status = TournamentStatus.published;

  @override
  Future<void> openRegistration(TournamentId id) async =>
      _tournaments[id]!.status = TournamentStatus.registrationOpen;

  @override
  Future<void> closeRegistration(TournamentId id) async =>
      _tournaments[id]!.status = TournamentStatus.registrationClosed;

  @override
  Future<void> startTournament(TournamentId id) async {
    final t = _tournaments[id]!;
    final approved = t.participantIds
        .where((p) => _participants[p]!.status == _PStatus.approved)
        .map((p) => p.value)
        .toList(growable: false);
    final pool = Pool.roundRobin(approved);
    var round = 0;
    for (final r in pool.rounds) {
      round += 1;
      var num = 0;
      for (final p in r.pairings) {
        num += 1;
        final mid = TournamentMatchId(_nextId('m'));
        _matches[mid] = _Match(
          id: mid,
          tournamentId: id,
          roundNumber: round,
          matchNumberInRound: num,
          participantA: TournamentParticipantId(p.participantA),
          participantB: p.participantB == null
              ? null
              : TournamentParticipantId(p.participantB!),
        );
        t.matchIds.add(mid);
      }
    }
    t
      ..status = TournamentStatus.live
      ..startedAt = DateTime.now();
  }

  @override
  Future<void> finalizeTournament(TournamentId id) async {
    _tournaments[id]!
      ..status = TournamentStatus.finalized
      ..completedAt = DateTime.now();
  }

  @override
  Future<void> abortTournament(TournamentId id) async =>
      _tournaments[id]!.status = TournamentStatus.aborted;

  @override
  Future<TournamentParticipantId> registerSingle(TournamentId id) async {
    final pid = TournamentParticipantId(_nextId('p'));
    _participants[pid] = _Participant(userId: currentUser);
    _tournaments[id]!.participantIds.add(pid);
    return pid;
  }

  @override
  Future<void> withdrawRegistration(TournamentParticipantId pid) async =>
      _participants[pid]!.status = _PStatus.withdrawn;

  @override
  Future<void> confirmRegistration(TournamentParticipantId pid) async =>
      _participants[pid]!.status = _PStatus.approved;

  @override
  Future<void> rejectRegistration(TournamentParticipantId pid) async =>
      _participants[pid]!.status = _PStatus.rejected;

  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
    TournamentId id,
  ) async =>
      [for (final mid in _tournaments[id]!.matchIds) _matches[mid]!.toRef()];

  @override
  Future<TournamentMatchRef?> getMatch(TournamentMatchId id) async =>
      _matches[id]?.toRef();

  @override
  Future<void> proposeSetScores({
    required TournamentMatchId matchId,
    required int consensusRound,
    required List<SetScore> setScores,
  }) async {
    final m = _matches[matchId]!;
    if (m.status == TournamentMatchStatus.finalized ||
        m.status == TournamentMatchStatus.overridden ||
        m.status == TournamentMatchStatus.voided) {
      throw StateError('match already terminal: ${m.status}');
    }
    if (consensusRound != m.consensusRound) {
      throw StateError(
        'stale consensus round: client=$consensusRound, server=${m.consensusRound}',
      );
    }
    final side = _sideForCurrentUser(m);
    final round = m.proposalsByRound
        .putIfAbsent(consensusRound, () => <_Side, List<SetScore>>{});
    round[side] = List<SetScore>.unmodifiable(setScores);

    if (m.status == TournamentMatchStatus.scheduled) {
      m.status = TournamentMatchStatus.awaitingResults;
    }

    if (round.length < 2) return;

    final a = round[_Side.a]!;
    final b = round[_Side.b]!;
    if (_setListsEqual(a, b)) {
      final ekc = computeEkc(a);
      m
        ..status = TournamentMatchStatus.finalized
        ..finalScoreA = ekc.pointsForA
        ..finalScoreB = ekc.pointsForB
        ..winnerParticipant = _winnerSide(ekc, m)
        ..completedAt = DateTime.now();
      _advanceKoWinner(m);
      return;
    }
    if (consensusRound >= 3) {
      m.status = TournamentMatchStatus.disputed;
      return;
    }
    m
      ..consensusRound = consensusRound + 1
      ..status = TournamentMatchStatus.awaitingResults;
  }

  @override
  Future<void> organizerOverride({
    required TournamentMatchId matchId,
    required List<SetScore> finalSetScores,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('override reason must not be blank');
    }
    final m = _matches[matchId]!;
    final ekc = computeEkc(finalSetScores);
    m
      ..status = TournamentMatchStatus.overridden
      ..finalScoreA = ekc.pointsForA
      ..finalScoreB = ekc.pointsForB
      ..winnerParticipant = _winnerSide(ekc, m)
      ..completedAt = DateTime.now();
    _advanceKoWinner(m);
  }

  @override
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id) {
    final m = _matches[id];
    if (m == null) {
      // Unknown match — return an empty stream rather than throw so the
      // M1 placeholder contract (returning nothing) keeps working for
      // callers that fire the watch before the match row exists.
      return const Stream<TournamentMatchRef>.empty();
    }
    return watchTournamentMatches(m.tournamentId)
        .where((r) => r.matchId == id);
  }

  @override
  Stream<TournamentMatchRef> watchTournamentMatches(TournamentId tournamentId) {
    return realtime
        .subscribe(
          table: 'tournament_matches',
          filterColumn: 'tournament_id',
          filterValue: tournamentId.value,
        )
        .where((c) => c.eventType != RealtimeEventType.delete)
        .map((c) => _tournamentMatchRefFromCdcRow(c.newRow));
  }

  @override
  Stream<BracketAdvanceEvent> watchBracketAdvances(TournamentId tournamentId) {
    return realtime
        .subscribe(
          table: 'tournament_matches',
          filterColumn: 'tournament_id',
          filterValue: tournamentId.value,
        )
        .where(_isBracketAdvanceChange)
        .map(_bracketAdvanceFromChange);
  }

  bool _isBracketAdvanceChange(RealtimeChange change) {
    if (change.eventType == RealtimeEventType.delete) return false;
    final status = change.newRow['status'];
    if (status != 'finalized' && status != 'overridden') return false;
    if (change.newRow['winner_participant'] == null) return false;
    if (change.eventType == RealtimeEventType.update) {
      final prev = change.oldRow['status'];
      if (prev == 'finalized' || prev == 'overridden') return false;
    }
    return true;
  }

  BracketAdvanceEvent _bracketAdvanceFromChange(RealtimeChange change) {
    final row = change.newRow;
    final round = _asInt(row['round_number']);
    final matchNumber = _asInt(row['match_number_in_round']);
    return BracketAdvanceEvent(
      tournamentId: TournamentId(row['tournament_id']! as String),
      advancedMatchId: TournamentMatchId(row['id']! as String),
      targetRound: round + 1,
      targetMatchNumber: (matchNumber + 1) ~/ 2,
      winnerParticipant:
          TournamentParticipantId(row['winner_participant']! as String),
      at: change.receivedAt,
    );
  }

  // Local CDC-row parser. Mirrors `tournamentMatchRefFromCdcRow` in
  // `lib/features/tournament/data/tournament_models.dart`; duplicated so
  // this fixture stays domain-only (no `kubb_app` import). The
  // orchestrator merge can collapse the two if/when the fixture moves
  // under `lib/`.
  TournamentMatchRef _tournamentMatchRefFromCdcRow(Map<String, Object?> row) {
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
      status: _matchStatusFromWire(row['status']! as String),
      consensusRound: _asInt(row['consensus_round']),
      startedAt: _asDateOrNull(row['started_at']),
      completedAt: _asDateOrNull(row['finalized_at']),
      winnerParticipant: row['winner_participant'] == null
          ? null
          : TournamentParticipantId(row['winner_participant']! as String),
      finalScoreA: _asIntOrNull(row['final_score_a']),
      finalScoreB: _asIntOrNull(row['final_score_b']),
    );
  }

  int _asInt(Object? r) {
    if (r is int) return r;
    if (r is num) return r.toInt();
    throw ArgumentError.value(r, 'r', 'expected num');
  }
  int? _asIntOrNull(Object? r) => r == null ? null : _asInt(r);
  DateTime? _asDateOrNull(Object? r) =>
      r == null ? null : DateTime.parse(r as String);

  TournamentMatchStatus _matchStatusFromWire(String raw) {
    switch (raw) {
      case 'scheduled':
        return TournamentMatchStatus.scheduled;
      case 'awaiting_results':
        return TournamentMatchStatus.awaitingResults;
      case 'disputed':
        return TournamentMatchStatus.disputed;
      case 'finalized':
        return TournamentMatchStatus.finalized;
      case 'overridden':
        return TournamentMatchStatus.overridden;
      case 'voided':
        return TournamentMatchStatus.voided;
      default:
        throw ArgumentError.value(raw, 'raw', 'Unknown TournamentMatchStatus');
    }
  }

  // ---------------------------------------------------------------------
  // KO-phase additions (T7c). These four methods mirror the signatures
  // the port gains in T7a (on a parallel branch); they are declared
  // without `@override` here so the file compiles standalone. When the
  // two branches merge, the analyzer will flag missing `@override`
  // annotations and they get added in one sweep.
  // ---------------------------------------------------------------------

  /// FR-FMT-10 manual override. Stores the seeding map in
  /// [_seedingOverrides]; consumed by [startKoPhase].
  @override
  Future<void> setSeeding({
    required TournamentId tournamentId,
    required Map<TournamentParticipantId, int> seeds,
  }) async {
    if (!_tournaments.containsKey(tournamentId)) {
      throw StateError('unknown tournament: ${tournamentId.value}');
    }
    _seedingOverrides[tournamentId] =
        Map<TournamentParticipantId, int>.from(seeds);
  }

  /// Insert KO-match rows from current standings + seeding overrides.
  /// Mirrors `tournament_start_ko_phase`: throws `ALREADY_STARTED` (a
  /// [StateError]) when KO rows already exist, matching the Supabase
  /// `ERRCODE 40001` idempotency contract.
  @override
  Future<void> startKoPhase(
    TournamentId tournamentId,
    KoPhaseConfig config,
  ) async {
    final t = _tournaments[tournamentId]!;
    final hasKo =
        t.matchIds.map((mid) => _matches[mid]!).any(_isKoMatch);
    if (hasKo) {
      throw StateError('ALREADY_STARTED: ko phase already initialised');
    }

    _koConfig[tournamentId] = config;

    // Seed-order: approved participants ranked by group-phase standings,
    // then top-N qualifiers, then manual overrides applied.
    final approved = t.participantIds
        .where((p) => _participants[p]!.status == _PStatus.approved)
        .toList(growable: false);
    final ordered = _autoSeedOrder(t, approved);
    final overrides = _seedingOverrides[tournamentId] ?? const {};
    final seeded = _applyOverrides(ordered, overrides);
    final qualifiers =
        seeded.take(config.qualifierCount).toList(growable: false);

    final bracket = Bracket.singleElimination(
      [for (final p in qualifiers) p.value],
      withThirdPlace: config.withThirdPlacePlayoff,
    ) as SingleEliminationBracket;
    final finalRound = bracket.rounds
        .where((r) => r.phase != BracketPhase.thirdPlace)
        .map((r) => r.number)
        .fold<int>(0, math.max);

    for (final round in bracket.rounds) {
      var bp = 0;
      for (final pairing in round.pairings) {
        bp += 1;
        final mid = TournamentMatchId(_nextId('m'));
        final aId = pairing.$1.participantId == null
            ? null
            : TournamentParticipantId(pairing.$1.participantId!);
        final bId = pairing.$2.participantId == null
            ? null
            : TournamentParticipantId(pairing.$2.participantId!);
        final phase = round.phase == BracketPhase.thirdPlace
            ? BracketPhase.thirdPlace
            : (round.number == finalRound
                ? BracketPhase.finals
                : BracketPhase.winners);
        final isByePairing = round.number == 1 &&
            phase != BracketPhase.thirdPlace &&
            (aId == null || bId == null) &&
            (aId != null || bId != null);
        final winner = isByePairing ? (aId ?? bId) : null;
        final status = isByePairing
            ? TournamentMatchStatus.finalized
            : TournamentMatchStatus.scheduled;
        final m = _Match(
          id: mid,
          tournamentId: tournamentId,
          roundNumber: round.number,
          matchNumberInRound: bp,
          participantA: aId,
          participantB: bId,
        )
          ..phase = phase
          ..bracketPosition = bp
          ..status = status
          ..winnerParticipant = winner
          ..completedAt = isByePairing ? DateTime.now() : null;
        _matches[mid] = m;
        t.matchIds.add(mid);
      }
    }

    // Bye-rows are inserted as `finalized` with a winner — advance them
    // immediately so R2 picks them up, mirroring the trigger's behaviour
    // when the start RPC inserts pre-finalised BYE rows.
    t.matchIds
        .map((mid) => _matches[mid]!)
        .where((m) =>
            _isKoMatch(m) &&
            m.status == TournamentMatchStatus.finalized &&
            m.roundNumber == 1)
        .toList(growable: false)
        .forEach(_advanceKoWinner);
  }

  /// FR-PAIR-7. Swap participants of a not-yet-started KO pairing.
  @override
  Future<void> overrideKoPairing({
    required TournamentMatchId matchId,
    required TournamentParticipantId participantA,
    required TournamentParticipantId participantB,
    required String reason,
  }) async {
    if (reason.trim().isEmpty) {
      throw ArgumentError('override reason must not be blank');
    }
    final m = _matches[matchId]!;
    if (m.status != TournamentMatchStatus.scheduled) {
      throw StateError(
        'override pairing only allowed on scheduled matches; got ${m.status}',
      );
    }
    m
      ..participantA = participantA
      ..participantB = participantB;
  }

  /// Read current bracket via the domain mapper.
  @override
  Future<Bracket> getBracket(TournamentId tournamentId) async {
    final t = _tournaments[tournamentId]!;
    final rows = <KoMatchRow>[
      for (final mid in t.matchIds)
        if (_isKoMatch(_matches[mid]!))
          (
            roundNumber: _matches[mid]!.roundNumber,
            bracketPosition: _matches[mid]!.bracketPosition!,
            phase: _matches[mid]!.phase,
            participantA: _matches[mid]!.participantA?.value,
            participantB: _matches[mid]!.participantB?.value,
            winnerParticipantId: _matches[mid]!.winnerParticipant?.value,
            isBye: _matches[mid]!.bracketPosition != null &&
                (_matches[mid]!.participantA == null ||
                    _matches[mid]!.participantB == null) &&
                _matches[mid]!.roundNumber == 1,
          ),
    ];
    return bracketFromMatches(rows);
  }

  // ---------------------------------------------------------------------
  // Pool phase (M3.3 — T8). The Fake calls the pure-Dart [generatePools]
  // directly instead of mirroring a server RPC; that keeps the in-memory
  // assignment byte-equal to the algorithm exercised by the property
  // tests in T7. Standings are computed lazily from finalized matches.
  // ---------------------------------------------------------------------

  @override
  Future<void> startPoolPhase(
    TournamentId tournamentId,
    PoolPhaseConfig config,
  ) async {
    final t = _tournaments[tournamentId];
    if (t == null) {
      throw StateError('unknown tournament: ${tournamentId.value}');
    }
    if (_poolConfig.containsKey(tournamentId)) {
      // Idempotent — mirrors the Supabase `ERRCODE 40001` swallow.
      return;
    }
    final approved = t.participantIds
        .where((p) => _participants[p]!.status == _PStatus.approved)
        .toList(growable: false);
    final result = generatePools(
      [for (final p in approved) p.value],
      config,
    );
    final labels = <TournamentParticipantId, String>{};
    for (var g = 0; g < result.groups.length; g++) {
      final label = String.fromCharCode(65 + g); // 'A', 'B', ...
      for (final id in result.groups[g]) {
        if (id == null) continue;
        labels[TournamentParticipantId(id)] = label;
      }
    }
    _poolConfig[tournamentId] = config;
    _groupLabels[tournamentId] = labels;

    // Generate per-group round-robin matches (T14): only when no
    // matches exist yet (i.e. the caller skipped [startTournament] for
    // the pool path). Mirrors `tournament_start_pool_phase`, which
    // inserts the same RR fan-out server-side.
    if (t.matchIds.isEmpty) {
      for (final group in result.groups) {
        final ids = [for (final id in group) ?id];
        final pool = Pool.roundRobin(ids);
        var round = 0;
        for (final r in pool.rounds) {
          round += 1;
          var num = 0;
          for (final pairing in r.pairings) {
            num += 1;
            final mid = TournamentMatchId(_nextId('m'));
            _matches[mid] = _Match(
              id: mid,
              tournamentId: tournamentId,
              roundNumber: round,
              matchNumberInRound: num,
              participantA: TournamentParticipantId(pairing.participantA),
              participantB: pairing.participantB == null
                  ? null
                  : TournamentParticipantId(pairing.participantB!),
            );
            t.matchIds.add(mid);
          }
        }
      }
      t
        ..status = TournamentStatus.live
        ..startedAt ??= DateTime.now();
    }
  }

  @override
  Future<List<PoolGroupStandings>> getPoolStandings(TournamentId id) async {
    final labels = _groupLabels[id];
    if (labels == null) return const <PoolGroupStandings>[];
    final byGroup = <String, List<TournamentParticipantId>>{};
    for (final entry in labels.entries) {
      byGroup.putIfAbsent(entry.value, () => []).add(entry.key);
    }
    final out = <PoolGroupStandings>[];
    final sortedLabels = byGroup.keys.toList()..sort();
    for (final label in sortedLabels) {
      final stats = [
        for (final p in byGroup[label]!) _statsFor(id, p),
      ];
      out.add(PoolGroupStandings(label, stats));
    }
    return out;
  }

  @override
  Future<void> resolveCrossPoolTie(
    TournamentId tournamentId,
    List<TournamentParticipantId> orderedParticipants,
  ) async {
    if (!_tournaments.containsKey(tournamentId)) {
      throw StateError('unknown tournament: ${tournamentId.value}');
    }
    _crossPoolOverrides[tournamentId] =
        List<TournamentParticipantId>.unmodifiable(orderedParticipants);
  }

  /// Builds a [ParticipantStats] row from finalized non-KO matches —
  /// enough to satisfy the [PoolGroupStandings] contract without
  /// re-implementing the tiebreaker chain (callers that need a sorted
  /// view feed this into [TiebreakerChain.compare] themselves).
  ParticipantStats _statsFor(TournamentId id, TournamentParticipantId pid) {
    final t = _tournaments[id]!;
    var wins = 0;
    var kubbsScored = 0;
    var kubbsConceded = 0;
    final opponents = <String>[];
    for (final mid in t.matchIds) {
      final m = _matches[mid]!;
      if (_isKoMatch(m)) continue;
      if (m.status != TournamentMatchStatus.finalized &&
          m.status != TournamentMatchStatus.overridden) {
        continue;
      }
      final a = m.participantA;
      final b = m.participantB;
      if (a != pid && b != pid) continue;
      final isA = a == pid;
      final other = isA ? b : a;
      if (other != null) opponents.add(other.value);
      final sa = m.finalScoreA ?? 0;
      final sb = m.finalScoreB ?? 0;
      kubbsScored += isA ? sa : sb;
      kubbsConceded += isA ? sb : sa;
      if (m.winnerParticipant == pid) wins += 1;
    }
    return ParticipantStats(
      participantId: pid.value,
      totalPoints: wins,
      wins: wins,
      kubbsScored: kubbsScored,
      kubbsConceded: kubbsConceded,
      opponentIds: opponents,
      opponentTotalPointsLookup: const <String, int>{},
      headToHeadLookup: const <String, int>{},
    );
  }

  // ---------------------------------------------------------------------
  // Roster (M3.2 — stubs, real behaviour lands in TASK-M3.2-T10)
  // ---------------------------------------------------------------------

  @override
  Future<TournamentParticipantId> registerTeam({
    required TournamentId tournamentId,
    required TeamId teamId,
    required List<RosterSlotInput> roster,
  }) async {
    final t = _tournaments[tournamentId];
    if (t == null) {
      throw StateError('unknown tournament: ${tournamentId.value}');
    }
    if (!requireAtLeastOneMember(roster)) {
      throw const MinOneRegisteredException(
        'FR-REG-12: roster must reference at least one registered member',
      );
    }
    for (final slot in roster) {
      final userId = slot.memberUserId;
      if (userId != null && _userAlreadyInOpenSlot(tournamentId, userId)) {
        throw RosterBR5Exception(
          'BR-5: user ${userId.value} already occupies an open roster slot '
          'in tournament ${tournamentId.value}',
        );
      }
    }
    final pid = TournamentParticipantId(_nextId('p'));
    _participants[pid] = _Participant(userId: currentUser, teamId: teamId);
    t.participantIds.add(pid);
    final now = DateTime.now();
    final slots = _rosterByParticipant.putIfAbsent(pid, () => <_RosterSlot>[]);
    for (final input in roster) {
      slots.add(
        _RosterSlot(
          id: _nextId('rs'),
          slotIndex: input.slotIndex,
          memberUserId: input.memberUserId,
          guestPlayerId: input.guestPlayerId,
          assignedAt: now,
          assignedBy: currentUser,
        ),
      );
    }
    return pid;
  }

  @override
  Future<void> replaceRosterSlot({
    required TournamentParticipantId participantId,
    required int slotIndex,
    required RosterSlotInput newOccupant,
    String? reason,
  }) async {
    final participant = _participants[participantId];
    if (participant == null) {
      throw StateError('unknown participant: ${participantId.value}');
    }
    final tournamentId = _tournamentIdFor(participantId);
    if (tournamentId == null) {
      throw StateError('participant ${participantId.value} not in any tournament');
    }
    final t = _tournaments[tournamentId]!;
    if (t.status == TournamentStatus.finalized ||
        t.status == TournamentStatus.aborted) {
      throw RosterLockedException(
        'ROSTER_LOCKED: tournament ${tournamentId.value} is ${t.status.name}',
        cause: 'tournament-${t.status.name}',
      );
    }
    final newUser = newOccupant.memberUserId;
    if (newUser != null &&
        _userAlreadyInOpenSlot(
          tournamentId,
          newUser,
          excludeParticipant: participantId,
        )) {
      throw RosterBR5Exception(
        'BR-5: user ${newUser.value} already occupies an open roster slot '
        'in tournament ${tournamentId.value}',
      );
    }
    final slots = _rosterByParticipant.putIfAbsent(
      participantId,
      () => <_RosterSlot>[],
    );
    final now = DateTime.now();
    for (final slot in slots) {
      if (slot.slotIndex == slotIndex && slot.replacedAt == null) {
        slot
          ..replacedAt = now
          ..replacedBy = currentUser
          ..reason = reason;
      }
    }
    slots.add(
      _RosterSlot(
        id: _nextId('rs'),
        slotIndex: slotIndex,
        memberUserId: newOccupant.memberUserId,
        guestPlayerId: newOccupant.guestPlayerId,
        assignedAt: now,
        assignedBy: currentUser,
      ),
    );
  }

  @override
  Future<List<RosterSlot>> getRoster(
    TournamentParticipantId participantId,
  ) async {
    final slots = _rosterByParticipant[participantId] ?? const <_RosterSlot>[];
    final open = slots.where((s) => s.replacedAt == null).toList()
      ..sort((a, b) => a.slotIndex.compareTo(b.slotIndex));
    return [for (final s in open) s.toRosterSlot()];
  }

  TournamentId? _tournamentIdFor(TournamentParticipantId pid) {
    for (final t in _tournaments.values) {
      if (t.participantIds.contains(pid)) return t.id;
    }
    return null;
  }

  bool _userAlreadyInOpenSlot(
    TournamentId tournamentId,
    UserId userId, {
    TournamentParticipantId? excludeParticipant,
  }) {
    final t = _tournaments[tournamentId];
    if (t == null) return false;
    for (final pid in t.participantIds) {
      if (pid == excludeParticipant) continue;
      final slots = _rosterByParticipant[pid];
      if (slots == null) continue;
      for (final slot in slots) {
        if (slot.replacedAt == null && slot.memberUserId == userId) {
          return true;
        }
      }
    }
    return false;
  }

  // ---------------------------------------------------------------------
  // Trigger simulation
  // ---------------------------------------------------------------------

  /// Mirrors `tournament_advance_ko_winner`: when [m] is a KO match that
  /// just hit `finalized`/`overridden`, push the winner into the next
  /// round and (for semifinals with third-place enabled) the loser into
  /// the third-place playoff. See migration `..._trigger_advance_ko_winner.sql`.
  void _advanceKoWinner(_Match m) {
    if (!_isKoMatch(m)) return;
    if (m.winnerParticipant == null) return;
    if (m.status != TournamentMatchStatus.finalized &&
        m.status != TournamentMatchStatus.overridden) {
      return;
    }
    final bp = m.bracketPosition;
    if (bp == null) return;

    final loser = m.winnerParticipant == m.participantA
        ? m.participantB
        : (m.winnerParticipant == m.participantB ? m.participantA : null);
    final nextRound = m.roundNumber + 1;
    final nextPosition = (bp + 1) ~/ 2;
    final isOdd = bp.isOdd;

    // 1. Winner → next match (phase ko or final). third_place never
    // propagates.
    if (m.phase == BracketPhase.winners || m.phase == BracketPhase.finals) {
      final next = _findKoMatch(
        tournamentId: m.tournamentId,
        roundNumber: nextRound,
        bracketPosition: nextPosition,
        phases: const {BracketPhase.winners, BracketPhase.finals},
      );
      if (next != null) {
        if (isOdd) {
          next.participantA = m.winnerParticipant;
        } else {
          next.participantB = m.winnerParticipant;
        }
        if (next.participantA != null &&
            next.participantB != null &&
            next.status == TournamentMatchStatus.scheduled) {
          next.status = TournamentMatchStatus.awaitingResults;
        }
        // BYE chain: if the receiving slot completes against another BYE
        // already-finalized winner, the trigger does not auto-finalize —
        // production relies on a real proposal pair. We mirror that.
      }
    }

    // 2. Semifinal loser → third_place match (phase 'ko' only, next
    // round is final round, ko_config.with_third_place enabled).
    if (m.phase == BracketPhase.winners && loser != null) {
      final config = _koConfig[m.tournamentId];
      if (config != null && config.withThirdPlacePlayoff) {
        final finalRound = _finalRoundFor(m.tournamentId);
        if (finalRound != null && nextRound == finalRound) {
          final tp = _findKoMatch(
            tournamentId: m.tournamentId,
            roundNumber: finalRound,
            bracketPosition: 1,
            phases: const {BracketPhase.thirdPlace},
          );
          if (tp != null) {
            if (isOdd) {
              tp.participantA = loser;
            } else {
              tp.participantB = loser;
            }
            if (tp.participantA != null &&
                tp.participantB != null &&
                tp.status == TournamentMatchStatus.scheduled) {
              tp.status = TournamentMatchStatus.awaitingResults;
            }
          }
        }
      }
    }
  }

  bool _isKoMatch(_Match m) =>
      m.bracketPosition != null &&
      (m.phase == BracketPhase.winners ||
          m.phase == BracketPhase.finals ||
          m.phase == BracketPhase.thirdPlace);

  _Match? _findKoMatch({
    required TournamentId tournamentId,
    required int roundNumber,
    required int bracketPosition,
    required Set<BracketPhase> phases,
  }) {
    final t = _tournaments[tournamentId];
    if (t == null) return null;
    for (final mid in t.matchIds) {
      final m = _matches[mid]!;
      if (m.roundNumber == roundNumber &&
          m.bracketPosition == bracketPosition &&
          phases.contains(m.phase)) {
        return m;
      }
    }
    return null;
  }

  int? _finalRoundFor(TournamentId id) {
    final t = _tournaments[id];
    if (t == null) return null;
    int? best;
    for (final mid in t.matchIds) {
      final m = _matches[mid]!;
      if (m.phase == BracketPhase.finals) {
        if (best == null || m.roundNumber > best) best = m.roundNumber;
      }
    }
    return best;
  }

  /// Ranks approved participants by (wins DESC, kubb_diff DESC,
  /// participantId ASC) over finalized group-phase matches — a
  /// 1:1 Dart mirror of the standings ORDER BY clause in
  /// `tournament_start_ko_phase`.
  List<TournamentParticipantId> _autoSeedOrder(
    _Tournament t,
    List<TournamentParticipantId> approved,
  ) {
    final wins = <TournamentParticipantId, int>{
      for (final p in approved) p: 0,
    };
    final diff = <TournamentParticipantId, int>{
      for (final p in approved) p: 0,
    };
    for (final mid in t.matchIds) {
      final m = _matches[mid]!;
      if (_isKoMatch(m)) continue;
      if (m.status != TournamentMatchStatus.finalized &&
          m.status != TournamentMatchStatus.overridden) {
        continue;
      }
      final a = m.participantA;
      final b = m.participantB;
      final sa = m.finalScoreA ?? 0;
      final sb = m.finalScoreB ?? 0;
      if (a != null) diff[a] = (diff[a] ?? 0) + (sa - sb);
      if (b != null) diff[b] = (diff[b] ?? 0) + (sb - sa);
      final w = m.winnerParticipant;
      if (w != null && wins.containsKey(w)) {
        wins[w] = (wins[w] ?? 0) + 1;
      }
    }
    final sorted = [...approved]..sort((a, b) {
        final wc = (wins[b] ?? 0).compareTo(wins[a] ?? 0);
        if (wc != 0) return wc;
        final dc = (diff[b] ?? 0).compareTo(diff[a] ?? 0);
        if (dc != 0) return dc;
        return a.value.compareTo(b.value);
      });
    return sorted;
  }

  List<TournamentParticipantId> _applyOverrides(
    List<TournamentParticipantId> autoOrder,
    Map<TournamentParticipantId, int> overrides,
  ) {
    if (overrides.isEmpty) return autoOrder;
    // Effective-seed lookup matches the Supabase RPC: override-seed
    // wins, auto-seed + 1000 fills the gaps, ties broken by auto-seed.
    final autoSeed = <TournamentParticipantId, int>{
      for (var i = 0; i < autoOrder.length; i++) autoOrder[i]: i + 1,
    };
    final ranked = [...autoOrder]..sort((a, b) {
        final ea = overrides[a]?.toDouble() ?? (autoSeed[a]! + 1000.0);
        final eb = overrides[b]?.toDouble() ?? (autoSeed[b]! + 1000.0);
        final cmp = ea.compareTo(eb);
        if (cmp != 0) return cmp;
        return autoSeed[a]!.compareTo(autoSeed[b]!);
      });
    return ranked;
  }

  _Side _sideForCurrentUser(_Match m) {
    final a = m.participantA;
    if (a != null && _participantBelongsTo(a, currentUser)) {
      return _Side.a;
    }
    final b = m.participantB;
    if (b != null && _participantBelongsTo(b, currentUser)) {
      return _Side.b;
    }
    throw StateError(
      'currentUser ${currentUser.value} is not a member of ${m.id.value}',
    );
  }

  bool _participantBelongsTo(TournamentParticipantId pid, UserId user) {
    final p = _participants[pid];
    if (p == null) return false;
    // M1 single-path: direct user match
    if (p.userId == user) return true;
    // M3.2 team-path: any active member of the participant's team
    if (p.teamId == null) return false;
    final slots = _rosterByParticipant[pid] ?? const <_RosterSlot>[];
    return slots.any(
      (s) => s.replacedAt == null && s.memberUserId == user,
    );
  }

  TournamentParticipantId? _winnerSide(MatchEkcScore ekc, _Match m) {
    switch (ekc.matchWinner) {
      case SetWinner.teamA:
        return m.participantA;
      case SetWinner.teamB:
        return m.participantB;
      case null:
        return null;
    }
  }

  bool _setListsEqual(List<SetScore> a, List<SetScore> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

enum _Side { a, b }
enum _PStatus { pending, approved, withdrawn, rejected }

class _Tournament {
  _Tournament({
    required this.id,
    required this.displayName,
    required this.format,
    required this.createdByUserId,
  });

  final TournamentId id;
  final String displayName;
  final TournamentFormat format;
  final UserId createdByUserId;
  TournamentStatus status = TournamentStatus.draft;
  DateTime? startedAt;
  DateTime? completedAt;
  final List<TournamentParticipantId> participantIds = [];
  final List<TournamentMatchId> matchIds = [];

  TournamentSummaryRef toSummary() => TournamentSummaryRef(
        tournamentId: id,
        displayName: displayName,
        format: format,
        status: status,
        startedAt: startedAt,
        completedAt: completedAt,
        participantCount: participantIds.length,
      );
}

class _Participant {
  _Participant({required this.userId, this.teamId});
  final UserId userId;
  final TeamId? teamId;
  _PStatus status = _PStatus.pending;
}

/// In-memory mirror of one `tournament_roster_slots` row. Closed rows
/// carry [replacedAt]/[replacedBy]/[reason]; open rows leave them null.
class _RosterSlot {
  _RosterSlot({
    required this.id,
    required this.slotIndex,
    required this.memberUserId,
    required this.guestPlayerId,
    required this.assignedAt,
    required this.assignedBy,
  });

  final String id;
  final int slotIndex;
  final UserId? memberUserId;
  final TeamGuestPlayerId? guestPlayerId;
  final DateTime assignedAt;
  final UserId? assignedBy;
  DateTime? replacedAt;
  UserId? replacedBy;
  String? reason;

  RosterSlot toRosterSlot() => RosterSlot(
        id: id,
        slotIndex: slotIndex,
        memberUserId: memberUserId,
        guestPlayerId: guestPlayerId,
        assignedAt: assignedAt,
        assignedBy: assignedBy,
        replacedAt: replacedAt,
        replacedBy: replacedBy,
        reason: reason,
      );
}

class _Match {
  _Match({
    required this.id,
    required this.tournamentId,
    required this.roundNumber,
    required this.matchNumberInRound,
    required this.participantA,
    required this.participantB,
  });

  final TournamentMatchId id;
  final TournamentId tournamentId;
  final int roundNumber;
  final int matchNumberInRound;
  TournamentParticipantId? participantA;
  TournamentParticipantId? participantB;
  TournamentMatchStatus status = TournamentMatchStatus.scheduled;
  int consensusRound = 1;
  DateTime? completedAt;
  TournamentParticipantId? winnerParticipant;
  int? finalScoreA;
  int? finalScoreB;
  final Map<int, Map<_Side, List<SetScore>>> proposalsByRound = {};

  /// KO-only: phase marker mirroring `tournament_matches.phase`. Round-robin
  /// matches keep [BracketPhase.winners] as a "non-KO" sentinel; the
  /// `_isKoMatch` helper gates on [bracketPosition] being non-null to
  /// disambiguate.
  BracketPhase phase = BracketPhase.winners;

  /// KO-only: 1-based pairing index inside the round. Null for round-robin
  /// rows — those have [matchNumberInRound] instead.
  int? bracketPosition;

  TournamentMatchRef toRef() => TournamentMatchRef(
        matchId: id,
        tournamentId: tournamentId,
        roundNumber: roundNumber,
        matchNumberInRound: matchNumberInRound,
        participantA: participantA,
        participantB: participantB,
        status: status,
        consensusRound: consensusRound,
        completedAt: completedAt,
        winnerParticipant: winnerParticipant,
        finalScoreA: finalScoreA,
        finalScoreB: finalScoreB,
      );
}
