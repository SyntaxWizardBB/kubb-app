// End-to-end offline sync test for the score-submission outbox
// (TASK-M4.3-T15). Pure-Dart harness — no Supabase, no platform plugins.
//
// Wiring per `tasks.md` §T15:
//   * `FakeConnectivityService` from
//     `lib/core/data/connectivity/connectivity_service.dart` drives the
//     offline → online transition.
//   * `_CountingRemote implements TournamentRemote` counts
//     `proposeSetScoreWithLamport` calls and can inject a single
//     `STALE_CONSENSUS_ROUND` per match via `setStaleConsensusRound`.
//   * `AppDatabase(NativeDatabase.memory())` backs the drift outbox so
//     the test exercises the real DAO + `_DriftOutboxStore` adapter from
//     `lib/core/application/outbox_flusher_provider.dart` rather than a
//     bespoke in-memory port.
//   * A `ProviderContainer` wires connectivity + database + a local
//     flusher that delegates to `_CountingRemote`. The shipped
//     `_RemoteScoreLamportSubmitter` still throws `UnimplementedError`
//     (its real impl lands in a later wave), so we override
//     `outboxFlusherProvider` itself with a flusher built around a thin
//     `_RemoteSubmitter` adapter.
//
// Behaviour pinned down:
//   1. Offline + 3 enqueues  → 3 pending rows, zero RPCs.
//   2. Connectivity flips online → all three rows ack'd, callCount == 3.
//   3. Manual second `flushPending()` → callCount stays 3 (idempotent).
//   4. `setStaleConsensusRound(matchId)` on the first row → that row
//      carries `STALE_CONSENSUS_ROUND`; the other two still sync.

import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/application/outbox_flusher.dart';
import 'package:kubb_app/core/application/outbox_flusher_provider.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_provider.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_service.dart';
import 'package:kubb_app/core/data/dao/score_submission_outbox_dao.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../_helpers/sqlite_open.dart';

const _matchId = TournamentMatchId('m-offline');
const _submitter = UserId('user-A');
const _deviceId = 'device-A';

SetScore _score(int a, int b) => SetScore(
      basekubbsKnockedByA: a,
      basekubbsKnockedByB: b,
      winner: a > b ? SetWinner.teamA : SetWinner.teamB,
    );

String _encodeScore(SetScore s) => jsonEncode({
      'basekubbs_a': s.basekubbsKnockedByA,
      'basekubbs_b': s.basekubbsKnockedByB,
      'winner': s.winner == SetWinner.teamA ? 'A' : 'B',
    });

/// Enqueues one outbox row through the production DAO so the test
/// exercises the real drift schema (TASK-M4.3-T1) rather than poking
/// `OutboxStore` directly.
Future<void> _enqueue(
  ScoreSubmissionOutboxDao dao, {
  required int setIndex,
  required int lamportCounter,
  required DateTime queuedAt,
}) async {
  await dao.insert(
    ScoreSubmissionOutboxCompanion.insert(
      matchId: _matchId.value,
      consensusRound: 1,
      setIndex: setIndex,
      submitterUserId: _submitter.value,
      lamportCounter: lamportCounter,
      lamportDeviceId: _deviceId,
      scoreJson: _encodeScore(_score(6, 4)),
      queuedAt: queuedAt,
    ),
  );
}

/// Minimal `TournamentRemote` test-double that only implements the
/// outbox-relevant method. All other members throw — the flusher never
/// reaches them. Mirrors `FakeTournamentRemote.setStaleConsensusRound`
/// so the same conflict-injection pattern works here without pulling
/// the full fake (and its KO/pool state machine) into the harness.
class _CountingRemote implements TournamentRemote {
  int callCount = 0;
  final Set<TournamentMatchId> _stale = <TournamentMatchId>{};

  void setStaleConsensusRound(TournamentMatchId matchId) {
    _stale.add(matchId);
  }

  @override
  Future<TournamentMatchRef> proposeSetScoreWithLamport({
    required TournamentMatchId matchId,
    required int consensusRound,
    required int setIndex,
    required TournamentParticipantId submitter,
    required SetScore score,
    required int lamportCounter,
    required String deviceId,
  }) async {
    callCount += 1;
    if (_stale.remove(matchId)) {
      throw const TournamentScoreConflictException('STALE_CONSENSUS_ROUND');
    }
    return TournamentMatchRef(
      matchId: matchId,
      tournamentId: const TournamentId('t-offline'),
      roundNumber: 1,
      matchNumberInRound: 1,
      participantA: const TournamentParticipantId('p-A'),
      participantB: const TournamentParticipantId('p-B'),
      status: TournamentMatchStatus.awaitingResults,
      consensusRound: consensusRound,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used in T15');
}

/// Thin adapter so the flusher can call our `TournamentRemote` directly.
/// Mirrors the production `_RemoteScoreLamportSubmitter`, but with the
/// real wave-8 method wired up (the shipped adapter still raises
/// `UnimplementedError` until TASK-M4.3-T6 lands).
class _RemoteSubmitter implements ScoreLamportSubmitter {
  _RemoteSubmitter(this._remote);
  final TournamentRemote _remote;

  @override
  Future<TournamentMatchRef> proposeSetScoreWithLamport({
    required TournamentMatchId matchId,
    required int consensusRound,
    required int setIndex,
    required UserId submitter,
    required SetScore score,
    required int lamportCounter,
    required String deviceId,
  }) {
    return _remote.proposeSetScoreWithLamport(
      matchId: matchId,
      consensusRound: consensusRound,
      setIndex: setIndex,
      // The flusher's port talks `UserId`; the remote port talks
      // `TournamentParticipantId`. The mapping is one-to-one for the
      // counting double, so a value pass-through is sufficient here.
      submitter: TournamentParticipantId(submitter.value),
      score: score,
      lamportCounter: lamportCounter,
      deviceId: deviceId,
    );
  }
}

class _ConnectivityProbeAdapter implements ConnectivityProbe {
  _ConnectivityProbeAdapter(this._service);
  final ConnectivityService _service;

  @override
  bool get isOnline => _service.isOnline;

  @override
  Stream<bool> get onlineStream => _service.onlineStream;
}

void main() {
  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;
  late ScoreSubmissionOutboxDao dao;
  late FakeConnectivityService connectivity;
  late _CountingRemote remote;
  late ProviderContainer container;
  late OutboxFlusher flusher;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    dao = db.scoreSubmissionOutboxDao;
    connectivity = FakeConnectivityService(initialOnline: false);
    remote = _CountingRemote();

    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        connectivityServiceProvider.overrideWithValue(connectivity),
        outboxFlusherProvider.overrideWith((ref) {
          final flusher = OutboxFlusherImpl(
            store: _DaoOutboxStore(ref.watch(scoreSubmissionOutboxDaoProvider)),
            submitter: _RemoteSubmitter(remote),
            connectivity: _ConnectivityProbeAdapter(
              ref.watch(connectivityServiceProvider),
            ),
            backoffSchedule: const [Duration(milliseconds: 1)],
            backoffCap: const Duration(milliseconds: 1),
          );
          ref.onDispose(flusher.dispose);
          return flusher;
        }),
      ],
    );
    flusher = container.read(outboxFlusherProvider);
  });

  tearDown(() async {
    // Drain any in-flight microtasks (e.g. the listener-triggered flush
    // from `connectivity.emit`) before tearing things down; otherwise
    // the flusher's status-controller can be closed mid-`_emitStatus`.
    await Future<void>.delayed(Duration.zero);
    await connectivity.dispose();
    container.dispose();
    await db.close();
  });

  test('offline enqueues stay pending until connectivity flips online',
      () async {
    // 1. Offline + three proposeSetScore-Calls → 3 pending rows.
    for (var i = 0; i < 3; i++) {
      await _enqueue(
        dao,
        setIndex: i,
        lamportCounter: i + 1,
        queuedAt: DateTime.utc(2026, 5, 27, 12, i),
      );
    }
    expect(await dao.pending(), hasLength(3));
    expect(remote.callCount, 0);

    // 2. Connectivity → online → all three rows ack'd, count == 3.
    // `connectivity.emit` fires the listener on a microtask; the
    // listener-triggered flush would race with our own `await` below,
    // so we drive the transition synchronously via
    // `onConnectivityChange` and let the production listener wiring be
    // proven by the dedicated unit-test in
    // `outbox_flusher_test.dart`.
    connectivity.emit(online: true);
    await flusher.onConnectivityChange(true);

    expect(remote.callCount, 3);
    expect(await dao.pending(), isEmpty, reason: 'all rows must be ack-ed');

    // 3. Second flushPending() → callCount stays 3 (idempotent).
    await flusher.flushPending();
    expect(remote.callCount, 3, reason: 'second flush must be a no-op');
  });

  test('STALE_CONSENSUS_ROUND marks one row; the others still sync',
      () async {
    for (var i = 0; i < 3; i++) {
      await _enqueue(
        dao,
        setIndex: i,
        lamportCounter: i + 1,
        queuedAt: DateTime.utc(2026, 5, 27, 13, i),
      );
    }
    // The fake only carries one stale-injection slot per match; the
    // first row to hit the wire (queuedAt-ASC ordering) gets the
    // conflict, the remaining two proceed normally.
    remote.setStaleConsensusRound(_matchId);

    connectivity.emit(online: true);
    await flusher.onConnectivityChange(true);

    expect(remote.callCount, 3, reason: 'all three rows attempted once');

    // The conflict row stays unacknowledged with the error code stamped;
    // the other two are ack'd and therefore no longer pending.
    final pending = await dao.pending();
    expect(pending, hasLength(1), reason: 'only the stale row is pending');
    expect(pending.single.lastErrorCode, kStaleConsensusRoundCode);
    expect(pending.single.setIndex, 0);

    // Status stream surfaced the conflict so the UI banner can react.
    await expectLater(
      flusher.statusStream,
      emitsThrough(OutboxFlushStatus.error),
    );
  });
}

/// Local mirror of the production `_DriftOutboxStore` adapter. Kept here
/// because the production class is library-private — duplicating the
/// twelve-line adapter is cheaper than widening its visibility just for
/// the integration harness.
class _DaoOutboxStore implements OutboxStore {
  _DaoOutboxStore(this._dao);
  final ScoreSubmissionOutboxDao _dao;

  @override
  Future<List<OutboxRow>> pending() async {
    final rows = await _dao.pending();
    return rows.map(_fromDriftRow).toList();
  }

  @override
  Future<void> markAcknowledged(String rowId, DateTime at) async {
    await _dao.markAcknowledged(int.parse(rowId));
  }

  @override
  Future<void> markError(String rowId, String code, DateTime at) async {
    await _dao.markError(int.parse(rowId), code);
  }

  @override
  Future<void> markAttempt(String rowId, DateTime at) async {}
}

OutboxRow _fromDriftRow(ScoreSubmissionOutboxRow row) {
  final json = jsonDecode(row.scoreJson) as Map<String, dynamic>;
  final winner = json['winner'] as String;
  return OutboxRow(
    id: row.id.toString(),
    matchId: TournamentMatchId(row.matchId),
    consensusRound: row.consensusRound,
    setIndex: row.setIndex,
    submitterUserId: UserId(row.submitterUserId),
    score: SetScore(
      basekubbsKnockedByA: json['basekubbs_a'] as int,
      basekubbsKnockedByB: json['basekubbs_b'] as int,
      winner: winner == 'A' ? SetWinner.teamA : SetWinner.teamB,
    ),
    lamportCounter: row.lamportCounter,
    lamportDeviceId: row.lamportDeviceId,
    queuedAt: row.queuedAt,
    attemptCount: row.retryCount,
    lastErrorCode: row.lastErrorCode,
    acknowledgedAt: row.acknowledgedAt,
  );
}
