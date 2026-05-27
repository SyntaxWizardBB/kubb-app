import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/application/outbox_gc_task.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/dao/score_submission_outbox_dao.dart';

import '../../_helpers/sqlite_open.dart';

/// Acceptance tests for TASK-M4.3-T13 (Outbox-GC-Task).
///
/// Three scenarios from `tasks.md` §M4.3-T13:
///   1. ack'd row >30d → deleted.
///   2. ack'd row <30d → kept.
///   3. pending row of any age → kept.
void main() {
  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;
  late ScoreSubmissionOutboxDao dao;

  final now = DateTime.utc(2026, 5, 27, 12);
  DateTime nowFn() => now;

  setUp(() async {
    db = await openTestDatabase();
    dao = db.scoreSubmissionOutboxDao;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> seed({
    required String suffix,
    required int counter,
    required DateTime queuedAt,
    DateTime? acknowledgedAt,
  }) {
    return dao.insert(
      ScoreSubmissionOutboxCompanion.insert(
        matchId: 'match-$suffix',
        consensusRound: 1,
        setIndex: 0,
        submitterUserId: 'user-1',
        lamportCounter: counter,
        lamportDeviceId: 'device-A',
        scoreJson: '{"basekubbs_a":5,"basekubbs_b":0,"winner":"A"}',
        queuedAt: queuedAt,
        acknowledgedAt: Value(acknowledgedAt),
      ),
    );
  }

  test('deletes ack-rows older than the retention window, keeps the rest',
      () async {
    final oldAck = await seed(
      suffix: 'old',
      counter: 1,
      queuedAt: now.subtract(const Duration(days: 40)),
      acknowledgedAt: now.subtract(const Duration(days: 35)),
    );
    final youngAck = await seed(
      suffix: 'young',
      counter: 2,
      queuedAt: now.subtract(const Duration(days: 5)),
      acknowledgedAt: now.subtract(const Duration(days: 5)),
    );
    final pending = await seed(
      suffix: 'pending',
      counter: 3,
      queuedAt: now.subtract(const Duration(days: 90)),
    );

    final removed = await OutboxGcTask(dao, now: nowFn).run();

    expect(removed, 1);
    final remaining =
        await db.select(db.scoreSubmissionOutbox).get();
    final remainingIds = remaining.map((r) => r.id).toSet();
    expect(remainingIds, contains(youngAck));
    expect(remainingIds, contains(pending));
    expect(remainingIds, isNot(contains(oldAck)));
  });

  test('is idempotent — a second run after a successful GC removes nothing',
      () async {
    await seed(
      suffix: 'old',
      counter: 1,
      queuedAt: now.subtract(const Duration(days: 40)),
      acknowledgedAt: now.subtract(const Duration(days: 35)),
    );

    final task = OutboxGcTask(dao, now: nowFn);
    await task.run();
    final secondPass = await task.run();
    expect(secondPass, 0);
  });
}
