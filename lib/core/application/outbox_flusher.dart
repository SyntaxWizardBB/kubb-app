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

/// Wave-7 stub implementation. Every entrypoint throws
/// [UnimplementedError]; TASK-M4.3-T7 (wave 8) replaces this class with
/// the real flusher and turns the property-tests green.
class OutboxFlusherStub implements OutboxFlusher {
  OutboxFlusherStub({
    required OutboxStore store,
    required ScoreLamportSubmitter submitter,
    required ConnectivityProbe connectivity,
  })  : _store = store,
        _submitter = submitter,
        _connectivity = connectivity;

  // Fields are wired but unused — the stub exists only to pin down the
  // constructor surface so the wave-8 impl (TASK-M4.3-T7) can drop in
  // without breaking call sites or test setUp blocks.
  // ignore: unused_field
  final OutboxStore _store;
  // Reserved for wave-8 impl; see comment on _store.
  // ignore: unused_field
  final ScoreLamportSubmitter _submitter;
  // Reserved for wave-8 impl; see comment on _store.
  // ignore: unused_field
  final ConnectivityProbe _connectivity;

  @override
  Future<void> flushPending() =>
      throw UnimplementedError('OutboxFlusher.flushPending — see TASK-M4.3-T7');

  @override
  Future<void> onConnectivityChange(bool online) => throw UnimplementedError(
        'OutboxFlusher.onConnectivityChange — see TASK-M4.3-T7',
      );

  @override
  Stream<OutboxFlushStatus> get statusStream => throw UnimplementedError(
        'OutboxFlusher.statusStream — see TASK-M4.3-T7',
      );
}
