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
  });

  tearDown(() async {
    await db.close();
  });

  SessionsCompanion session(
    String id, {
    required String status,
    DateTime? completedAt,
    String playerId = 'p1',
  }) {
    return SessionsCompanion(
      id: Value(id),
      playerId: Value(playerId),
      kind: const Value('sniper'),
      distanceMeters: const Value(8),
      status: Value(status),
      startedAt: Value(DateTime.utc(2026, 5, 2)),
      completedAt: completedAt == null
          ? const Value.absent()
          : Value(completedAt),
    );
  }

  test('returns inserted session by id', () async {
    await db.sessionDao.insert(session('s1', status: 'active'));

    final row = await db.sessionDao.getById('s1');

    expect(row, isNotNull);
    expect(row!.status, 'active');
  });

  test('activeForUser returns only the active session', () async {
    await db.sessionDao.insert(session('s1', status: 'active'));
    await db.sessionDao.insert(
      session(
        's2',
        status: 'completed',
        completedAt: DateTime.utc(2026, 5, 3),
      ),
    );

    final row = await db.sessionDao.activeForUser('p1');

    expect(row?.id, 's1');
  });

  test('watchRecentCompleted streams up to limit ordered by completedAt desc',
      () async {
    for (var i = 0; i < 4; i++) {
      await db.sessionDao.insert(
        session(
          's$i',
          status: 'completed',
          completedAt: DateTime.utc(2026, 5, i + 2),
        ),
      );
    }

    final first = await db.sessionDao.watchRecentCompleted(userId: 'p1').first;

    expect(first.map((s) => s.id), ['s3', 's2', 's1']);
  });

  test('insert with unknown playerId fails on FK constraint', () async {
    await expectLater(
      db.sessionDao.insert(
        session('s1', status: 'active', playerId: 'ghost'),
      ),
      throwsA(isA<Exception>()),
    );
  });
}
