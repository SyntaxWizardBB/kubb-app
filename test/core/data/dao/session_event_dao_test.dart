import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() async {
    db = await openTestDatabase();
    await db.playerDao.insert(
      PlayersCompanion(
        id: const Value('p1'),
        name: const Value('Lukas'),
        deviceId: const Value('device-p1'),
        createdAt: Value(DateTime.utc(2026, 5, 2)),
      ),
    );
    await db.sessionDao.insert(
      SessionsCompanion(
        id: const Value('s1'),
        playerId: const Value('p1'),
        kind: const Value('sniper'),
        distanceMeters: const Value(8),
        status: const Value('active'),
        startedAt: Value(DateTime.utc(2026, 5, 2)),
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertEvent(
    String id,
    String kind, {
    required int minute,
    String sessionId = 's1',
  }) {
    return db.sessionEventDao.insert(
      SessionEventsCompanion(
        id: Value(id),
        sessionId: Value(sessionId),
        kind: Value(kind),
        createdAt: Value(DateTime.utc(2026, 5, 2, 12, minute)),
      ),
    );
  }

  test('forSession returns inserted events ordered by createdAt asc', () async {
    await insertEvent('e1', 'hit', minute: 0);

    final rows = await db.sessionEventDao.forSession('s1');

    expect(rows, hasLength(1));
    expect(rows.first.kind, 'hit');
  });

  test('latestNonDeletedOfKind skips corrected and returns most recent',
      () async {
    await insertEvent('e1', 'hit', minute: 0);
    await insertEvent('e2', 'hit', minute: 1);
    await insertEvent('e3', 'hit', minute: 2);
    await db.sessionEventDao.markCorrected('e2', DateTime.utc(2026, 5, 3));

    final row = await db.sessionEventDao.latestNonDeletedOfKind('s1', 'hit');

    expect(row?.id, 'e3');
  });

  test('countByKind respects the excludeCorrected flag', () async {
    await insertEvent('e1', 'hit', minute: 0);
    await insertEvent('e2', 'hit', minute: 1);
    await insertEvent('e3', 'hit', minute: 2);
    await db.sessionEventDao.markCorrected('e2', DateTime.utc(2026, 5, 3));

    final excluded = await db.sessionEventDao.countByKind('s1', 'hit');
    final included = await db.sessionEventDao
        .countByKind('s1', 'hit', excludeCorrected: false);

    expect(excluded, 2);
    expect(included, 3);
  });

  test('deleting the parent session cascades to its events', () async {
    await insertEvent('e1', 'hit', minute: 0);
    await insertEvent('e2', 'miss', minute: 1);

    await db.sessionDao.deleteById('s1');

    final remaining = await db.sessionEventDao.forSession('s1');
    expect(remaining, isEmpty);
  });
}
