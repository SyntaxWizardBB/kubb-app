import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/application/outbox_flusher.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:mocktail/mocktail.dart';

/// Property-tests for the wave-7 `OutboxFlusher` contract (TASK-M4.3-T5).
///
/// Five behaviours pinned down per `tasks.md` §T5:
///   1. `queuedAt ASC` order during a flush pass.
///   2. `SocketException` is retryable with backoff.
///   3. `STALE_CONSENSUS_ROUND` is terminal — no further retry.
///   4. Success writes `acknowledgedAt`.
///   5. Offline connectivity pauses the flusher.
///
/// Today these run against the wave-7 stub and raise
/// `UnimplementedError`; TASK-M4.3-T7 (wave 8) turns them green.

class _MockSubmitter extends Mock implements ScoreLamportSubmitter {}

/// Minimal in-memory port over the TASK-M4.3-T1 DAO. Captures the
/// writeback effects the flusher must produce.
class _InMemoryStore implements OutboxStore {
  _InMemoryStore(this._rows);
  final List<OutboxRow> _rows;
  final List<String> ack = <String>[];
  final Map<String, String> errors = <String, String>{};

  @override
  Future<List<OutboxRow>> pending() async =>
      _rows.where((r) => !ack.contains(r.id) && !errors.containsKey(r.id))
          .toList()
        ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));

  @override
  Future<void> markAcknowledged(String rowId, DateTime at) async =>
      ack.add(rowId);

  @override
  Future<void> markError(String rowId, String errorCode, DateTime at) async =>
      errors[rowId] = errorCode;

  @override
  Future<void> markAttempt(String rowId, DateTime at) async {}
}

/// Local stand-in for the wave-8 `FakeConnectivityService` (T9). Kept
/// inline so this wave-7 test does not depend on a wave-8 artefact.
class _FakeConnectivityService implements ConnectivityProbe {
  _FakeConnectivityService({bool online = true}) : _online = online;
  bool _online;
  final _controller = StreamController<bool>.broadcast();

  @override
  bool get isOnline => _online;
  @override
  Stream<bool> get onlineStream => _controller.stream;

  void emit({required bool online}) {
    _online = online;
    _controller.add(online);
  }
}

OutboxRow _row(String id, DateTime queuedAt, {int counter = 1}) => OutboxRow(
      id: id,
      matchId: const TournamentMatchId('m-1'),
      consensusRound: 1,
      setIndex: 0,
      submitterUserId: const UserId('u-1'),
      score: SetScore(
        basekubbsKnockedByA: 5,
        basekubbsKnockedByB: 0,
        winner: SetWinner.teamA,
      ),
      lamportCounter: counter,
      lamportDeviceId: 'device-A',
      queuedAt: queuedAt,
    );

const _snapshot = TournamentMatchRef(
  matchId: TournamentMatchId('m-1'),
  tournamentId: TournamentId('t-1'),
  roundNumber: 1,
  matchNumberInRound: 1,
  participantA: TournamentParticipantId('p-A'),
  participantB: TournamentParticipantId('p-B'),
  status: TournamentMatchStatus.awaitingResults,
  consensusRound: 1,
);

void _stubAny(_MockSubmitter m, Future<TournamentMatchRef> Function(Invocation) h) {
  when(
    () => m.proposeSetScoreWithLamport(
      matchId: any(named: 'matchId'),
      consensusRound: any(named: 'consensusRound'),
      setIndex: any(named: 'setIndex'),
      submitter: any(named: 'submitter'),
      score: any(named: 'score'),
      lamportCounter: any(named: 'lamportCounter'),
      deviceId: any(named: 'deviceId'),
    ),
  ).thenAnswer(h);
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      SetScore(
        basekubbsKnockedByA: 0,
        basekubbsKnockedByB: 0,
        winner: SetWinner.teamA,
      ),
    );
    registerFallbackValue(const TournamentMatchId('fb'));
    registerFallbackValue(const UserId('fb'));
  });

  late _MockSubmitter submitter;
  late _FakeConnectivityService connectivity;

  setUp(() {
    submitter = _MockSubmitter();
    connectivity = _FakeConnectivityService();
  });

  OutboxFlusher build(OutboxStore store) => OutboxFlusherStub(
        store: store,
        submitter: submitter,
        connectivity: connectivity,
      );

  test('flushes rows in queuedAt ASC order', () async {
    final store = _InMemoryStore([
      _row('r-c', DateTime.utc(2026, 7, 1, 10, 2), counter: 3),
      _row('r-a', DateTime.utc(2026, 7, 1, 10)),
      _row('r-b', DateTime.utc(2026, 7, 1, 10, 1), counter: 2),
    ]);
    final order = <int>[];
    _stubAny(submitter, (inv) async {
      order.add(
        inv.namedArguments[const Symbol('lamportCounter')] as int,
      );
      return _snapshot;
    });

    await build(store).flushPending();

    expect(order, [1, 2, 3]);
  });

  test('SocketException triggers retry after backoff', () async {
    final store = _InMemoryStore([_row('r-1', DateTime.utc(2026, 7, 1, 10))]);
    var calls = 0;
    _stubAny(submitter, (_) async {
      calls += 1;
      if (calls == 1) throw const SocketException('boom');
      return _snapshot;
    });

    await build(store).flushPending();

    expect(calls, greaterThanOrEqualTo(2));
    expect(store.ack, ['r-1']);
  });

  test('STALE_CONSENSUS_ROUND marks row and stops retry', () async {
    final store = _InMemoryStore([_row('r-x', DateTime.utc(2026, 7, 1, 10))]);
    var calls = 0;
    _stubAny(submitter, (_) async {
      calls += 1;
      throw const TournamentScoreConflictException('STALE_CONSENSUS_ROUND');
    });

    await build(store).flushPending();

    expect(store.errors['r-x'], 'STALE_CONSENSUS_ROUND');
    expect(store.ack, isEmpty);
    expect(calls, 1, reason: 'conflict is terminal — no retry');
  });

  test('successful flush marks acknowledgedAt', () async {
    final store = _InMemoryStore([_row('r-ok', DateTime.utc(2026, 7, 1, 10))]);
    _stubAny(submitter, (_) async => _snapshot);

    await build(store).flushPending();

    expect(store.ack, ['r-ok']);
  });

  test('offline connectivity pauses the flusher', () async {
    final store = _InMemoryStore([_row('r-p', DateTime.utc(2026, 7, 1, 10))]);
    connectivity.emit(online: false);
    final flusher = build(store);

    await flusher.onConnectivityChange(false);
    await flusher.flushPending();

    verifyNever(
      () => submitter.proposeSetScoreWithLamport(
        matchId: any(named: 'matchId'),
        consensusRound: any(named: 'consensusRound'),
        setIndex: any(named: 'setIndex'),
        submitter: any(named: 'submitter'),
        score: any(named: 'score'),
        lamportCounter: any(named: 'lamportCounter'),
        deviceId: any(named: 'deviceId'),
      ),
    );
    expect(store.ack, isEmpty);
    expect(flusher.statusStream, emitsThrough(OutboxFlushStatus.paused));
  });
}

/// Placeholder for the wave-8 conflict exception (TASK-M4.3-T6). The
/// real type lands in `packages/kubb_domain/lib/src/tournament/`.
class TournamentScoreConflictException implements Exception {
  const TournamentScoreConflictException(this.code);
  final String code;

  @override
  String toString() => 'TournamentScoreConflictException($code)';
}
