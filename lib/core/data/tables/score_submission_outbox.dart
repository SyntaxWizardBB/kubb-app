import 'package:drift/drift.dart';

/// Outbox for score submissions awaiting RPC acknowledgement.
///
/// Each row represents a single set-score submission that has been queued
/// locally and must be flushed via the score submission RPC. Rows persist
/// across app restarts so that submissions survive offline periods and
/// crashes; the flusher marks them acknowledged or stamps an error code on
/// failure. The UNIQUE-Index across the submission identity columns
/// prevents duplicate enqueues for the same logical event.
@DataClassName('ScoreSubmissionOutboxRow')
class ScoreSubmissionOutbox extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get matchId => text()();
  IntColumn get consensusRound => integer()();
  IntColumn get setIndex => integer()();
  TextColumn get submitterUserId => text()();
  IntColumn get lamportCounter => integer()();
  TextColumn get lamportDeviceId => text()();
  TextColumn get scoreJson => text()();
  DateTimeColumn get queuedAt => dateTime()();
  DateTimeColumn get acknowledgedAt => dateTime().nullable()();
  TextColumn get lastErrorCode => text().nullable()();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
        {
          matchId,
          consensusRound,
          setIndex,
          submitterUserId,
          lamportCounter,
          lamportDeviceId,
        },
      ];
}
