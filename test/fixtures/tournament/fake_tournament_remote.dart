import 'package:kubb_domain/kubb_domain.dart';

/// In-memory [TournamentRemote] for widget-level tests. Mirrors the
/// `tournament_propose_set_scores` consensus state machine: byte-equal
/// proposals from both sides finalise the match (with EKC final scores);
/// disagreements bump `consensus_round` up to 3, the third disagreement
/// flips the match to `disputed`. Realtime [watchMatch] is a no-op
/// since M1 callers poll on demand.
class FakeTournamentRemote implements TournamentRemote {
  FakeTournamentRemote({required UserId initialUser})
      : currentUser = initialUser;

  /// "Logged-in" user that subsequent calls run as. Tests flip this to
  /// drive the same flow from different participants / the organizer.
  UserId currentUser;
  int _idSeq = 0;

  final Map<TournamentId, _Tournament> _tournaments =
      <TournamentId, _Tournament>{};
  final Map<TournamentParticipantId, _Participant> _participants =
      <TournamentParticipantId, _Participant>{};
  final Map<TournamentMatchId, _Match> _matches =
      <TournamentMatchId, _Match>{};

  String _nextId(String prefix) => '$prefix-${++_idSeq}';

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
  }

  @override
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id) =>
      const Stream<TournamentMatchRef>.empty();

  _Side _sideForCurrentUser(_Match m) {
    if (_participants[m.participantA]?.userId == currentUser) {
      return _Side.a;
    }
    if (m.participantB != null &&
        _participants[m.participantB]?.userId == currentUser) {
      return _Side.b;
    }
    throw StateError(
      'currentUser ${currentUser.value} is not a member of ${m.id.value}',
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
  _Participant({required this.userId});
  final UserId userId;
  _PStatus status = _PStatus.pending;
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
  final TournamentParticipantId? participantA;
  final TournamentParticipantId? participantB;
  TournamentMatchStatus status = TournamentMatchStatus.scheduled;
  int consensusRound = 1;
  DateTime? completedAt;
  TournamentParticipantId? winnerParticipant;
  int? finalScoreA;
  int? finalScoreB;
  final Map<int, Map<_Side, List<SetScore>>> proposalsByRound = {};

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
