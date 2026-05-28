import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/application/outbox_flusher.dart';
import 'package:kubb_app/core/application/outbox_flusher_provider.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Unit-tests for the `_RemoteScoreLamportSubmitter` adapter wired up by
/// [outboxFlusherProvider] (TASK-W1-T1 / R17-F-01). The adapter is
/// file-private, so we exercise it indirectly through the provider's
/// public [ScoreLamportSubmitter] surface — built via the Riverpod
/// container so the production wiring (DAO + connectivity + submitter)
/// stays in scope.

class _MockTournamentRemote extends Mock implements TournamentRemote {}

final _row = OutboxRow(
  id: 'r-1',
  matchId: const TournamentMatchId('m-1'),
  consensusRound: 1,
  setIndex: 1,
  submitterUserId: const UserId('u-1'),
  score: SetScore(
    basekubbsKnockedByA: 5,
    basekubbsKnockedByB: 2,
    winner: SetWinner.teamA,
  ),
  lamportCounter: 7,
  lamportDeviceId: 'device-A',
  queuedAt: DateTime.utc(2026, 7, 1, 10),
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

/// Minimal in-memory store mirroring the on-device DAO surface that
/// the flusher needs. Lets us observe `markAcknowledged` on success,
/// `markError` on terminal conflict, and `markAttempt` on transient
/// retry without spinning up drift.
class _InMemoryStore implements OutboxStore {
  _InMemoryStore(this._rows);
  final List<OutboxRow> _rows;

  final List<String> ack = <String>[];
  final Map<String, String> errors = <String, String>{};
  int attempts = 0;

  @override
  Future<List<OutboxRow>> pending() async {
    return _rows
        .where((r) => !ack.contains(r.id) && !errors.containsKey(r.id))
        .toList();
  }

  @override
  Future<void> markAcknowledged(String rowId, DateTime at) async {
    ack.add(rowId);
  }

  @override
  Future<void> markError(String rowId, String errorCode, DateTime at) async {
    errors[rowId] = errorCode;
  }

  @override
  Future<void> markAttempt(String rowId, DateTime at) async {
    attempts += 1;
  }
}

class _AlwaysOnline implements ConnectivityProbe {
  @override
  bool get isOnline => true;
  @override
  Stream<bool> get onlineStream => const Stream<bool>.empty();
}

/// Builds an [OutboxFlusherImpl] whose `submitter` is the production
/// `_RemoteScoreLamportSubmitter` adapter wired against [remote] via
/// the `@visibleForTesting` factory exposed by the provider module.
/// Mirrors the wiring inside [outboxFlusherProvider] without spinning
/// up drift / connectivity.
OutboxFlusherImpl _buildFlusher({
  required TournamentRemote remote,
  required OutboxStore store,
}) {
  return OutboxFlusherImpl(
    store: store,
    submitter: buildScoreLamportSubmitterForTest(remote),
    connectivity: _AlwaysOnline(),
    backoffSchedule: const [Duration(milliseconds: 1)],
    backoffCap: const Duration(milliseconds: 1),
    maxRetries: 1,
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(const TournamentMatchId('fb'));
    registerFallbackValue(const TournamentParticipantId('fb'));
    registerFallbackValue(
      SetScore(
        basekubbsKnockedByA: 0,
        basekubbsKnockedByB: 0,
        winner: SetWinner.teamA,
      ),
    );
  });

  late _MockTournamentRemote remote;

  setUp(() {
    remote = _MockTournamentRemote();
  });

  group('_RemoteScoreLamportSubmitter (via outboxFlusherProvider wiring)', () {
    test('forwards row params to TournamentRemote and acks on success',
        () async {
      when(
        () => remote.proposeSetScoreWithLamport(
          matchId: any(named: 'matchId'),
          consensusRound: any(named: 'consensusRound'),
          setIndex: any(named: 'setIndex'),
          submitter: any(named: 'submitter'),
          score: any(named: 'score'),
          lamportCounter: any(named: 'lamportCounter'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenAnswer((_) async => _snapshot);

      final store = _InMemoryStore([_row]);
      final flusher = _buildFlusher(remote: remote, store: store);
      addTearDown(flusher.dispose);

      await flusher.flushPending();

      expect(store.ack, ['r-1']);
      final captured = verify(
        () => remote.proposeSetScoreWithLamport(
          matchId: captureAny(named: 'matchId'),
          consensusRound: captureAny(named: 'consensusRound'),
          setIndex: captureAny(named: 'setIndex'),
          submitter: captureAny(named: 'submitter'),
          score: captureAny(named: 'score'),
          lamportCounter: captureAny(named: 'lamportCounter'),
          deviceId: captureAny(named: 'deviceId'),
        ),
      ).captured;
      expect(captured[0], const TournamentMatchId('m-1'));
      expect(captured[1], 1);
      expect(captured[2], 1);
      // R17-B-01 bridge: UserId('u-1') flows through as a
      // TournamentParticipantId carrying the same opaque token. The
      // server keys the actual submitter via auth.uid().
      expect(captured[3], const TournamentParticipantId('u-1'));
      expect(captured[5], 7);
      expect(captured[6], 'device-A');
    });

    test('classifies SocketException as TransientSubmitException (retry path)',
        () async {
      var calls = 0;
      when(
        () => remote.proposeSetScoreWithLamport(
          matchId: any(named: 'matchId'),
          consensusRound: any(named: 'consensusRound'),
          setIndex: any(named: 'setIndex'),
          submitter: any(named: 'submitter'),
          score: any(named: 'score'),
          lamportCounter: any(named: 'lamportCounter'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) throw const SocketException('boom');
        return _snapshot;
      });

      final store = _InMemoryStore([_row]);
      final flusher = _buildFlusher(remote: remote, store: store);
      addTearDown(flusher.dispose);

      await flusher.flushPending();

      // Two attempts recorded (first failed, second succeeded) and the
      // row was eventually acknowledged — that is the externally visible
      // contract of "transient → retry".
      expect(calls, 2);
      expect(store.attempts, greaterThanOrEqualTo(2));
      expect(store.ack, ['r-1']);
    });

    test('classifies TimeoutException as TransientSubmitException', () async {
      var calls = 0;
      when(
        () => remote.proposeSetScoreWithLamport(
          matchId: any(named: 'matchId'),
          consensusRound: any(named: 'consensusRound'),
          setIndex: any(named: 'setIndex'),
          submitter: any(named: 'submitter'),
          score: any(named: 'score'),
          lamportCounter: any(named: 'lamportCounter'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenAnswer((_) async {
        calls += 1;
        if (calls == 1) throw TimeoutException('slow rpc');
        return _snapshot;
      });

      final store = _InMemoryStore([_row]);
      final flusher = _buildFlusher(remote: remote, store: store);
      addTearDown(flusher.dispose);

      await flusher.flushPending();

      expect(calls, 2);
      expect(store.ack, ['r-1']);
    });

    test('maps STALE_CONSENSUS_ROUND PostgREST hint to TerminalSubmitException',
        () async {
      when(
        () => remote.proposeSetScoreWithLamport(
          matchId: any(named: 'matchId'),
          consensusRound: any(named: 'consensusRound'),
          setIndex: any(named: 'setIndex'),
          submitter: any(named: 'submitter'),
          score: any(named: 'score'),
          lamportCounter: any(named: 'lamportCounter'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenThrow(
        const PostgrestException(
          message: 'stale consensus_round',
          code: '40001',
          hint: 'STALE_CONSENSUS_ROUND',
        ),
      );

      final store = _InMemoryStore([_row]);
      final flusher = _buildFlusher(remote: remote, store: store);
      addTearDown(flusher.dispose);

      await flusher.flushPending();

      expect(store.errors['r-1'], 'STALE_CONSENSUS_ROUND');
      expect(store.ack, isEmpty);
    });

    test('maps override_pending hint to TerminalSubmitException', () async {
      when(
        () => remote.proposeSetScoreWithLamport(
          matchId: any(named: 'matchId'),
          consensusRound: any(named: 'consensusRound'),
          setIndex: any(named: 'setIndex'),
          submitter: any(named: 'submitter'),
          score: any(named: 'score'),
          lamportCounter: any(named: 'lamportCounter'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenThrow(
        const PostgrestException(
          message: 'organizer override pending',
          code: 'P0001',
          hint: 'override_pending',
        ),
      );

      final store = _InMemoryStore([_row]);
      final flusher = _buildFlusher(remote: remote, store: store);
      addTearDown(flusher.dispose);

      await flusher.flushPending();

      expect(store.errors['r-1'], 'override_pending');
      expect(store.ack, isEmpty);
    });

    test('maps conflict_* prefix to TerminalSubmitException', () async {
      when(
        () => remote.proposeSetScoreWithLamport(
          matchId: any(named: 'matchId'),
          consensusRound: any(named: 'consensusRound'),
          setIndex: any(named: 'setIndex'),
          submitter: any(named: 'submitter'),
          score: any(named: 'score'),
          lamportCounter: any(named: 'lamportCounter'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenThrow(
        const PostgrestException(
          message: 'conflict — winner mismatch',
          code: 'P0001',
          hint: 'conflict_winner_mismatch',
        ),
      );

      final store = _InMemoryStore([_row]);
      final flusher = _buildFlusher(remote: remote, store: store);
      addTearDown(flusher.dispose);

      await flusher.flushPending();

      expect(store.errors['r-1'], 'conflict_winner_mismatch');
    });

    test('lifts existing TournamentScoreConflictException into Terminal',
        () async {
      when(
        () => remote.proposeSetScoreWithLamport(
          matchId: any(named: 'matchId'),
          consensusRound: any(named: 'consensusRound'),
          setIndex: any(named: 'setIndex'),
          submitter: any(named: 'submitter'),
          score: any(named: 'score'),
          lamportCounter: any(named: 'lamportCounter'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenThrow(
        const TournamentScoreConflictException('STALE_CONSENSUS_ROUND'),
      );

      final store = _InMemoryStore([_row]);
      final flusher = _buildFlusher(remote: remote, store: store);
      addTearDown(flusher.dispose);

      await flusher.flushPending();

      expect(store.errors['r-1'], 'STALE_CONSENSUS_ROUND');
    });

    test('unknown PostgrestException bubbles up unchanged', () async {
      when(
        () => remote.proposeSetScoreWithLamport(
          matchId: any(named: 'matchId'),
          consensusRound: any(named: 'consensusRound'),
          setIndex: any(named: 'setIndex'),
          submitter: any(named: 'submitter'),
          score: any(named: 'score'),
          lamportCounter: any(named: 'lamportCounter'),
          deviceId: any(named: 'deviceId'),
        ),
      ).thenThrow(
        const PostgrestException(
          message: 'permission denied',
          code: '42501',
        ),
      );

      final store = _InMemoryStore([_row]);
      final flusher = _buildFlusher(remote: remote, store: store);
      addTearDown(flusher.dispose);

      await expectLater(flusher.flushPending(), throwsA(isA<PostgrestException>()));
      expect(store.ack, isEmpty);
      expect(store.errors, isEmpty);
    });
  });
}
