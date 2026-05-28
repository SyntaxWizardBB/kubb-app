import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/application/outbox_flusher.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_provider.dart';
import 'package:kubb_app/core/data/connectivity/connectivity_service.dart';
import 'package:kubb_app/core/data/dao/score_submission_outbox_dao.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

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

/// Test seam: returns the production [ScoreLamportSubmitter] adapter
/// wired to [remote]. Lets unit-tests in
/// `test/core/application/outbox_flusher_provider_test.dart` exercise
/// the file-private adapter without exposing the class itself.
@visibleForTesting
ScoreLamportSubmitter buildScoreLamportSubmitterForTest(
  TournamentRemote remote,
) =>
    _RemoteScoreLamportSubmitter(remote);

/// Adapter from [TournamentRemote] to the [ScoreLamportSubmitter] port.
/// Delegates to `TournamentRemote.proposeSetScoreWithLamport` (TASK-M4.3-T6)
/// and classifies infrastructure failures into the stable
/// [TransientSubmitException] / [TerminalSubmitException] taxonomy so the
/// flusher can drive retry vs. terminal-conflict logic without depending
/// on `dart:io` or PostgREST internals (TASK-W1-T1, R17-F-01).
///
/// Type bridge: the outbox row carries the local [UserId] of the
/// submitter, while the remote port speaks [TournamentParticipantId]
/// (R17-B-01). The server's RPC sources the effective submitter from
/// `auth.uid()`, so the parameter is routing/idempotency information
/// only — we forward the same opaque token across the boundary.
class _RemoteScoreLamportSubmitter implements ScoreLamportSubmitter {
  _RemoteScoreLamportSubmitter(this._remote);

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
  }) async {
    try {
      return await _remote.proposeSetScoreWithLamport(
        matchId: matchId,
        consensusRound: consensusRound,
        setIndex: setIndex,
        // R17-B-01 bridge: the remote port expects a participant id but
        // the RPC keys the submitter via `auth.uid()`. Forwarding the
        // user-scoped token keeps the wire payload stable; the
        // participant context is recovered server-side.
        submitter: TournamentParticipantId(submitter.value),
        score: score,
        lamportCounter: lamportCounter,
        deviceId: deviceId,
      );
    } on SocketException catch (e) {
      throw TransientSubmitException(reason: 'network_socket', cause: e);
    } on TimeoutException catch (e) {
      throw TransientSubmitException(reason: 'rpc_timeout', cause: e);
    } on TournamentScoreConflictException catch (e) {
      // The repository already mapped a HINT-tagged PostgREST error to
      // the domain conflict type (e.g. `STALE_CONSENSUS_ROUND`). Lift
      // it into the submitter taxonomy so the flusher sees a uniform
      // terminal contract.
      throw TerminalSubmitException(reason: e.code, cause: e);
    } on PostgrestException catch (e) {
      final reason = _terminalReasonFor(e);
      if (reason != null) {
        throw TerminalSubmitException(reason: reason, cause: e);
      }
      rethrow;
    }
  }

  /// Classifies a [PostgrestException] into a stable reason token.
  ///
  /// Order of precedence:
  ///   1. `e.hint` — set explicitly by the server via
  ///      `RAISE EXCEPTION USING HINT = '<TOKEN>'`. This is the
  ///      contract for `STALE_CONSENSUS_ROUND` and forthcoming
  ///      conflict tokens (`lamport_regression`, `override_pending`,
  ///      `conflict_*`).
  ///   2. `e.code` — when the hint is absent we accept the same
  ///      token vocabulary via SQLSTATE-adjacent fields some
  ///      PostgREST builds populate (defensive, future-proof).
  ///
  /// Returns `null` for unclassified errors so the caller can rethrow
  /// the original exception unchanged. Never returns
  /// `runtimeType.toString()` — reason codes are part of the public
  /// contract and must be stable.
  String? _terminalReasonFor(PostgrestException e) {
    const knownTokens = <String>{
      'STALE_CONSENSUS_ROUND',
      'lamport_regression',
      'override_pending',
    };
    String? candidate;
    final hint = e.hint;
    if (hint != null && hint.isNotEmpty) {
      candidate = hint;
    } else {
      final code = e.code;
      if (code != null && code.isNotEmpty) {
        candidate = code;
      }
    }
    if (candidate == null) return null;
    if (knownTokens.contains(candidate)) return candidate;
    if (candidate.startsWith('conflict_')) return candidate;
    return null;
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
