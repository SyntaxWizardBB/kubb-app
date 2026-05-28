import 'dart:async';
import 'dart:io';

import 'package:kubb_domain/kubb_domain.dart';

/// Lifecycle status of the score-submission outbox flusher. Surfaced to
/// the UI as a banner ("ausstehend …", "synchronisiere …") and used by
/// the property-tests in `test/core/application/outbox_flusher_test.dart`
/// to assert flow transitions. See M4.3 architecture §3.4.
enum OutboxFlushStatus {
  /// Flusher is idle — no pending work or it has just finished.
  idle,

  /// A flush pass is currently iterating over pending rows.
  flushing,

  /// Connectivity reports offline; pending work is held until online.
  paused,

  /// The last flush pass raised a non-transient error (e.g. a
  /// `STALE_CONSENSUS_ROUND` conflict). The offending row carries
  /// `lastErrorCode`; UI must surface the conflict.
  error,
}

/// One pending entry of the score-submission outbox. Mirrors
/// `ScoreSubmissionOutboxRow` from `lib/core/data/tables/`
/// (TASK-M4.3-T1), but keeps the flusher contract independent of the
/// drift-generated type so tests can build rows without spinning up a
/// database.
class OutboxRow {
  const OutboxRow({
    required this.id,
    required this.matchId,
    required this.consensusRound,
    required this.setIndex,
    required this.submitterUserId,
    required this.score,
    required this.lamportCounter,
    required this.lamportDeviceId,
    required this.queuedAt,
    this.firstAttemptAt,
    this.lastAttemptAt,
    this.attemptCount = 0,
    this.lastErrorCode,
    this.acknowledgedAt,
  });

  final String id;
  final TournamentMatchId matchId;
  final int consensusRound;
  final int setIndex;
  final UserId submitterUserId;
  final SetScore score;
  final int lamportCounter;
  final String lamportDeviceId;
  final DateTime queuedAt;
  final DateTime? firstAttemptAt;
  final DateTime? lastAttemptAt;
  final int attemptCount;
  final String? lastErrorCode;
  final DateTime? acknowledgedAt;
}

/// Minimal port over the drift DAO from TASK-M4.3-T1. Defined here so
/// the property-tests can swap in an in-memory fake without depending
/// on the wave-7 drift artefacts.
abstract interface class OutboxStore {
  Future<List<OutboxRow>> pending();
  Future<void> markAcknowledged(String rowId, DateTime at);
  Future<void> markError(String rowId, String errorCode, DateTime at);
  Future<void> markAttempt(String rowId, DateTime at);
}

/// Subset of `TournamentRemote` that the flusher actually consumes.
/// Defined here (instead of importing `TournamentRemote` directly) so
/// the wave-7 stub does not have to bring the full port into the core
/// layer; TASK-M4.3-T6 adds the corresponding method to the real port.
// Single-member interface is intentional — this is a structural port
// over a future wave-8 method on `TournamentRemote`.
// ignore: one_member_abstracts
abstract interface class ScoreLamportSubmitter {
  Future<TournamentMatchRef> proposeSetScoreWithLamport({
    required TournamentMatchId matchId,
    required int consensusRound,
    required int setIndex,
    required UserId submitter,
    required SetScore score,
    required int lamportCounter,
    required String deviceId,
  });
}

/// Subset of `ConnectivityService` (TASK-M4.3-T9) consumed by the
/// flusher. Tests provide a `FakeConnectivityService` locally.
abstract interface class ConnectivityProbe {
  bool get isOnline;
  Stream<bool> get onlineStream;
}

/// Cross-cutting outbox flusher per M4.3 architecture §3.4.
///
/// Contract (defined by TASK-M4.3-T5 property-tests, implemented by
/// TASK-M4.3-T7):
/// * [flushPending] drains rows where `acknowledgedAt IS NULL`,
///   ordered by `queuedAt ASC`, calling
///   [ScoreLamportSubmitter.proposeSetScoreWithLamport] per row.
/// * Transient network errors (`SocketException`) trigger a retry with
///   exponential backoff and a hard cap.
/// * `STALE_CONSENSUS_ROUND` from the server marks the row with
///   `lastErrorCode`, skips further retries, and surfaces as an
///   [OutboxFlushStatus.error] event on [statusStream].
/// * On success the row is updated with `acknowledgedAt = now()`.
/// * [onConnectivityChange] pauses the flusher when offline and
///   resumes (with a single flush pass) on online.
abstract class OutboxFlusher {
  Future<void> flushPending();

  // The single-bool callback shape mirrors the wave-8 connectivity
  // listener contract from TASK-M4.3-T9 — kept positional for symmetry
  // with `Connectivity().onConnectivityChanged` consumers.
  // ignore: avoid_positional_boolean_parameters
  Future<void> onConnectivityChange(bool online);

  Stream<OutboxFlushStatus> get statusStream;
}

/// Sentinel error code stamped on outbox rows whose server-side
/// consensus round drifted past the locally queued submission.
const String kStaleConsensusRoundCode = 'STALE_CONSENSUS_ROUND';

/// Submitter-side classification of a transient failure: the network
/// hiccupped or the RPC timed out; the row stays pending and the
/// flusher counts an attempt + backs off. Adapter implementations
/// rethrow this in place of raw `SocketException`/`TimeoutException`
/// so callers can rely on a stable, port-level taxonomy instead of
/// branching on `dart:io` types (TASK-W1-T1 / R17-F-01).
class TransientSubmitException implements Exception {
  const TransientSubmitException({required this.reason, this.cause});

  /// Stable token, e.g. `network_socket` or `rpc_timeout`. Never the
  /// `runtimeType.toString()` of the underlying error — see R17-F-01.
  final String reason;

  /// Original failure, kept for logging/debugging. Not part of the
  /// classification surface.
  final Object? cause;

  @override
  String toString() => 'TransientSubmitException($reason)';
}

/// Submitter-side classification of a terminal failure: the server
/// rejected the proposal with a known conflict token (lamport
/// regression, override pending, stale consensus, etc.). The row is
/// stamped with [reason] via [OutboxStore.markError] and not retried.
class TerminalSubmitException implements Exception {
  const TerminalSubmitException({required this.reason, this.cause});

  /// Stable token surfaced to the UI / outbox row, e.g.
  /// `STALE_CONSENSUS_ROUND`, `lamport_regression`, `override_pending`,
  /// or `conflict_*`. Stable across releases so downstream consumers
  /// can switch on it.
  final String reason;

  final Object? cause;

  @override
  String toString() => 'TerminalSubmitException($reason)';
}

/// Concrete flusher implementation per TASK-M4.3-T7.
///
/// Drains the outbox sequentially, retries [SocketException] with
/// capped exponential backoff, and terminates a row on a
/// `STALE_CONSENSUS_ROUND` conflict by stamping `lastErrorCode`.
/// Subscribes to [ConnectivityProbe.onlineStream] in the constructor so
/// offline → online transitions trigger a fresh flush pass.
class OutboxFlusherImpl implements OutboxFlusher {
  OutboxFlusherImpl({
    required OutboxStore store,
    required ScoreLamportSubmitter submitter,
    required ConnectivityProbe connectivity,
    DateTime Function() now = DateTime.now,
    List<Duration> backoffSchedule = _defaultBackoff,
    Duration backoffCap = const Duration(seconds: 30),
    int maxRetries = 4,
  })  : _store = store,
        _submitter = submitter,
        _connectivity = connectivity,
        _now = now,
        _backoffSchedule = backoffSchedule,
        _backoffCap = backoffCap,
        _maxRetries = maxRetries,
        _paused = !connectivity.isOnline {
    _onlineSub = connectivity.onlineStream.listen(
      (online) => unawaited(onConnectivityChange(online)),
    );
  }

  static const List<Duration> _defaultBackoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  final OutboxStore _store;
  final ScoreLamportSubmitter _submitter;
  final ConnectivityProbe _connectivity;
  final DateTime Function() _now;
  final List<Duration> _backoffSchedule;
  final Duration _backoffCap;
  final int _maxRetries;

  final StreamController<OutboxFlushStatus> _statusController =
      StreamController<OutboxFlushStatus>.broadcast();
  late final StreamSubscription<bool> _onlineSub;

  bool _paused;
  bool _flushing = false;
  OutboxFlushStatus _lastStatus = OutboxFlushStatus.idle;

  @override
  Stream<OutboxFlushStatus> get statusStream async* {
    yield _lastStatus;
    yield* _statusController.stream;
  }

  void _emitStatus(OutboxFlushStatus status) {
    _lastStatus = status;
    _statusController.add(status);
  }

  @override
  Future<void> flushPending() async {
    if (_paused || _flushing) {
      return;
    }
    _flushing = true;
    _emitStatus(OutboxFlushStatus.flushing);
    var sawError = false;
    try {
      final rows = await _store.pending();
      for (final row in rows) {
        if (_paused) break;
        final outcome = await _processRow(row);
        if (outcome == _RowOutcome.conflict) {
          sawError = true;
        }
      }
    } finally {
      _flushing = false;
      _emitStatus(
        sawError ? OutboxFlushStatus.error : OutboxFlushStatus.idle,
      );
    }
  }

  Future<_RowOutcome> _processRow(OutboxRow row) async {
    var attempt = 0;
    while (true) {
      try {
        await _store.markAttempt(row.id, _now());
        await _submitter.proposeSetScoreWithLamport(
          matchId: row.matchId,
          consensusRound: row.consensusRound,
          setIndex: row.setIndex,
          submitter: row.submitterUserId,
          score: row.score,
          lamportCounter: row.lamportCounter,
          deviceId: row.lamportDeviceId,
        );
        await _store.markAcknowledged(row.id, _now());
        return _RowOutcome.acknowledged;
      } on SocketException {
        if (!_connectivity.isOnline || attempt >= _maxRetries) {
          return _RowOutcome.givenUp;
        }
        await Future<void>.delayed(_backoffFor(attempt));
        attempt += 1;
        if (_paused) return _RowOutcome.givenUp;
      } on TransientSubmitException {
        // Adapter-mapped transient failure (network/timeout). Same
        // retry semantics as a raw `SocketException` — the previous
        // `markAttempt` above already recorded the attempt.
        if (!_connectivity.isOnline || attempt >= _maxRetries) {
          return _RowOutcome.givenUp;
        }
        await Future<void>.delayed(_backoffFor(attempt));
        attempt += 1;
        if (_paused) return _RowOutcome.givenUp;
      } on TerminalSubmitException catch (e) {
        // Adapter-mapped terminal failure (lamport regression, override
        // pending, stale consensus, …). Stamp the reason token on the
        // row and stop retrying.
        await _store.markError(row.id, e.reason, _now());
        return _RowOutcome.conflict;
      } on Exception catch (e) {
        final code = _conflictCode(e);
        if (code == kStaleConsensusRoundCode) {
          await _store.markError(row.id, code!, _now());
          return _RowOutcome.conflict;
        }
        rethrow;
      }
    }
  }

  Duration _backoffFor(int attempt) {
    if (attempt < _backoffSchedule.length) {
      return _backoffSchedule[attempt];
    }
    return _backoffCap;
  }

  /// Duck-typed extractor for the conflict code carried by the wave-8
  /// `TournamentScoreConflictException` (TASK-M4.3-T6). Kept structural
  /// so the flusher does not have to import the domain exception while
  /// T6 is still in flight.
  String? _conflictCode(Object error) {
    if (error.runtimeType.toString() != 'TournamentScoreConflictException') {
      return null;
    }
    final dynamic value = (error as dynamic).code;
    if (value is String) return value;
    return null;
  }

  @override
  Future<void> onConnectivityChange(bool online) async {
    _paused = !online;
    if (!online) {
      _emitStatus(OutboxFlushStatus.paused);
      return;
    }
    await flushPending();
  }

  /// Releases the connectivity subscription and the status stream.
  /// Wired from the Riverpod provider's `onDispose` hook.
  Future<void> dispose() async {
    await _onlineSub.cancel();
    await _statusController.close();
  }
}

enum _RowOutcome { acknowledged, conflict, givenUp }
