// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'score_submission_outbox_dao.dart';

// ignore_for_file: type=lint
mixin _$ScoreSubmissionOutboxDaoMixin on DatabaseAccessor<AppDatabase> {
  $ScoreSubmissionOutboxTable get scoreSubmissionOutbox =>
      attachedDatabase.scoreSubmissionOutbox;
  ScoreSubmissionOutboxDaoManager get managers =>
      ScoreSubmissionOutboxDaoManager(this);
}

class ScoreSubmissionOutboxDaoManager {
  final _$ScoreSubmissionOutboxDaoMixin _db;
  ScoreSubmissionOutboxDaoManager(this._db);
  $$ScoreSubmissionOutboxTableTableManager get scoreSubmissionOutbox =>
      $$ScoreSubmissionOutboxTableTableManager(
        _db.attachedDatabase,
        _db.scoreSubmissionOutbox,
      );
}
