import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/tables/score_submission_outbox.dart';

part 'score_submission_outbox_dao.g.dart';

@DriftAccessor(tables: [ScoreSubmissionOutbox])
class ScoreSubmissionOutboxDao extends DatabaseAccessor<AppDatabase>
    with _$ScoreSubmissionOutboxDaoMixin {
  ScoreSubmissionOutboxDao(super.attachedDatabase);

  /// Enqueue a new submission row. The UNIQUE-Index on the identity columns
  /// guards against duplicate enqueues for the same logical event.
  Future<int> insert(ScoreSubmissionOutboxCompanion companion) {
    return into(scoreSubmissionOutbox).insert(companion);
  }

  /// Returns all rows that have not been acknowledged yet, ordered by
  /// `queuedAt` ascending so the flusher processes them in enqueue order.
  Future<List<ScoreSubmissionOutboxRow>> pending() {
    return (select(scoreSubmissionOutbox)
          ..where((t) => t.acknowledgedAt.isNull())
          ..orderBy([(t) => OrderingTerm.asc(t.queuedAt)]))
        .get();
  }

  /// Marks the row with [id] as acknowledged at `DateTime.now()` and clears
  /// any previous error code.
  Future<int> markAcknowledged(int id) {
    return (update(scoreSubmissionOutbox)..where((t) => t.id.equals(id))).write(
      ScoreSubmissionOutboxCompanion(
        acknowledgedAt: Value(DateTime.now()),
        lastErrorCode: const Value(null),
      ),
    );
  }

  /// Records an error [code] for the row with [id] and increments
  /// `retryCount` by one.
  Future<int> markError(int id, String code) {
    return customUpdate(
      'UPDATE score_submission_outbox '
      'SET last_error_code = ?, retry_count = retry_count + 1 '
      'WHERE id = ?',
      variables: [Variable<String>(code), Variable<int>(id)],
      updates: {scoreSubmissionOutbox},
      updateKind: UpdateKind.update,
    );
  }

  /// Deletes acknowledged rows whose `acknowledgedAt` is strictly older than
  /// [date]. Used by the outbox GC to bound table size.
  Future<int> deleteOlderThan(DateTime date) {
    return (delete(scoreSubmissionOutbox)
          ..where(
            (t) =>
                t.acknowledgedAt.isNotNull() &
                t.acknowledgedAt.isSmallerThanValue(date),
          ))
        .go();
  }

  /// Returns the maximum `lamport_counter` previously written for the
  /// `(matchId, lamportDeviceId)` pair, or `0` when the outbox has no
  /// row yet for that pair. Used by the lamport-clock-hydration provider
  /// (TASK-M4.3-T8) to seed the per-match clock so the next local tick
  /// always emits a counter strictly greater than any value still queued
  /// from a previous app session.
  Future<int> maxCounterFor(String matchId, String deviceId) async {
    final row = await customSelect(
      'SELECT COALESCE(MAX(lamport_counter), 0) AS max_counter '
      'FROM score_submission_outbox '
      'WHERE match_id = ?1 AND lamport_device_id = ?2',
      variables: [Variable<String>(matchId), Variable<String>(deviceId)],
      readsFrom: {scoreSubmissionOutbox},
    ).getSingle();
    return row.read<int>('max_counter');
  }
}
