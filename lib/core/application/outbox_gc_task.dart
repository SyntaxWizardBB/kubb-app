import 'package:kubb_app/core/data/dao/score_submission_outbox_dao.dart';

/// Bounds the score-submission outbox at app start per TASK-M4.3-T13.
///
/// Acceptance criteria from `tasks.md` §M4.3-T13:
///   * Acknowledged rows older than 30 days are deleted.
///   * Acknowledged rows younger than 30 days are kept.
///   * Pending rows (regardless of age) are kept.
///
/// The DAO's [ScoreSubmissionOutboxDao.deleteOlderThan] already filters
/// on `acknowledged_at IS NOT NULL`, so this task is a thin scheduling
/// wrapper that computes the cutoff and is safe to invoke repeatedly
/// (idempotent — running twice in a row simply finds nothing the second
/// time).
class OutboxGcTask {
  OutboxGcTask(this._dao, {DateTime Function() now = DateTime.now})
      : _now = now;

  final ScoreSubmissionOutboxDao _dao;
  final DateTime Function() _now;

  /// Deletes acknowledged outbox rows whose `acknowledgedAt` is strictly
  /// older than `now - [retainFor]`. Returns the number of rows removed.
  Future<int> run({Duration retainFor = const Duration(days: 30)}) {
    final cutoff = _now().subtract(retainFor);
    return _dao.deleteOlderThan(cutoff);
  }
}
