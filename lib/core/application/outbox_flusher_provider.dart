import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/application/outbox_flusher.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_provider.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_service.dart';
import 'package:kubb_app/core/data/dao/score_submission_outbox_dao.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// DI seam for [ScoreSubmissionOutboxDao]. Tests override this provider
/// with an in-memory DAO when exercising the flusher end-to-end.
final scoreSubmissionOutboxDaoProvider = Provider<ScoreSubmissionOutboxDao>(
  (ref) => ref.watch(appDatabaseProvider).scoreSubmissionOutboxDao,
);

/// Singleton [OutboxFlusher] per M4.3 architecture §3.4. Hydrated once
/// at app start so connectivity transitions and queued submissions
/// share a single flush state.
///
/// Per TASK-M4.3-T7 acceptance criteria the provider:
///   * Wires the drift DAO (TASK-M4.3-T1) behind an [OutboxStore]
///     adapter,
///   * Wraps `TournamentRemote.proposeSetScoreWithLamport` (TASK-M4.3-T6)
///     behind a [ScoreLamportSubmitter] adapter,
///   * Subscribes to [ConnectivityProbe.onlineStream] (TASK-M4.3-T9) so
///     offline → online transitions trigger a flush pass.
final outboxFlusherProvider = Provider<OutboxFlusher>((ref) {
  final dao = ref.watch(scoreSubmissionOutboxDaoProvider);
  final remote = ref.watch(tournamentRemoteProvider);
  final connectivity = ref.watch(connectivityServiceProvider);
  final flusher = OutboxFlusherImpl(
    store: _DriftOutboxStore(dao),
    submitter: _RemoteScoreLamportSubmitter(remote),
    connectivity: _ConnectivityProbeAdapter(connectivity),
  );
  ref.onDispose(flusher.dispose);
  return flusher;
});

/// Adapter from the wave-7 drift DAO to the [OutboxStore] port. The
/// scoreJson column round-trips through [SetScore] here so the flusher
/// stays agnostic of the storage representation.
class _DriftOutboxStore implements OutboxStore {
  _DriftOutboxStore(this._dao);

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
  Future<void> markError(String rowId, String errorCode, DateTime at) async {
    await _dao.markError(int.parse(rowId), errorCode);
  }

  @override
  Future<void> markAttempt(String rowId, DateTime at) async {
    // `retry_count` is incremented inside `markError`; a stand-alone
    // attempt timestamp column is not part of the wave-7 schema. The
    // flusher's port still expects this hook, so we keep it as a no-op
    // until TASK-M4.3-T13 (GC) adds an `attemptedAt` column.
  }
}

OutboxRow _fromDriftRow(ScoreSubmissionOutboxRow row) {
  return OutboxRow(
    id: row.id.toString(),
    matchId: TournamentMatchId(row.matchId),
    consensusRound: row.consensusRound,
    setIndex: row.setIndex,
    submitterUserId: UserId(row.submitterUserId),
    score: _decodeSetScore(row.scoreJson),
    lamportCounter: row.lamportCounter,
    lamportDeviceId: row.lamportDeviceId,
    queuedAt: row.queuedAt,
    attemptCount: row.retryCount,
    lastErrorCode: row.lastErrorCode,
    acknowledgedAt: row.acknowledgedAt,
  );
}

SetScore _decodeSetScore(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final winnerLabel = json['winner'] as String;
  return SetScore(
    basekubbsKnockedByA: (json['basekubbs_a'] ?? json['basekubbsKnockedByA'])
        as int,
    basekubbsKnockedByB: (json['basekubbs_b'] ?? json['basekubbsKnockedByB'])
        as int,
    winner: winnerLabel == 'A' || winnerLabel == 'teamA'
        ? SetWinner.teamA
        : SetWinner.teamB,
  );
}

/// Adapter from [TournamentRemote] to the [ScoreLamportSubmitter] port.
/// Delegates to the wave-8 `proposeSetScoreWithLamport` method added in
/// TASK-M4.3-T6. Until that port method lands this adapter raises
/// [UnimplementedError]; the provider itself stays compileable so
/// downstream wiring (TASK-M4.3-T10) can already reference it.
class _RemoteScoreLamportSubmitter implements ScoreLamportSubmitter {
  _RemoteScoreLamportSubmitter(this._remote);

  // Held for the wave-8 swap (TASK-M4.3-T6); the adapter delegates to
  // `_remote.proposeSetScoreWithLamport(...)` once the port method ships.
  // ignore: unused_field
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
    throw UnimplementedError(
      'TournamentRemote.proposeSetScoreWithLamport — see TASK-M4.3-T6',
    );
  }
}

/// Adapter from the production [ConnectivityService] to the flusher's
/// minimal [ConnectivityProbe] port.
class _ConnectivityProbeAdapter implements ConnectivityProbe {
  _ConnectivityProbeAdapter(this._service);

  final ConnectivityService _service;

  @override
  bool get isOnline => _service.isOnline;

  @override
  Stream<bool> get onlineStream => _service.onlineStream;
}
