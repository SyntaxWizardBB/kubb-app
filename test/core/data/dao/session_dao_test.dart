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

  test(
    'allCompletedForUser returns only completed sessions for the given user, '
    'ordered by completedAt asc',
    () async {
      await db.playerDao.insert(
        PlayersCompanion(
          id: const Value('p2'),
          name: const Value('Marc'),
          deviceId: const Value('device-p2'),
          createdAt: Value(DateTime.utc(2026, 5, 2)),
        ),
      );
      await db.sessionDao.insert(session('s1', status: 'active'));
      await db.sessionDao.insert(
        session(
          's2',
          status: 'completed',
          completedAt: DateTime.utc(2026, 5, 5),
        ),
      );
      await db.sessionDao.insert(
        session(
          's3',
          status: 'completed',
          completedAt: DateTime.utc(2026, 5, 3),
        ),
      );
      // Session of another player must not leak.
      await db.sessionDao.insert(
        session(
          'other',
          status: 'completed',
          completedAt: DateTime.utc(2026, 5, 4),
          playerId: 'p2',
        ),
      );

      final rows = await db.sessionDao.allCompletedForUser('p1');

      expect(rows.map((s) => s.id), ['s3', 's2']);
    },
  );

  test('deleteAllForUser removes only sessions of that user', () async {
    await db.playerDao.insert(
      PlayersCompanion(
        id: const Value('p2'),
        name: const Value('Marc'),
        deviceId: const Value('device-p2'),
        createdAt: Value(DateTime.utc(2026, 5, 2)),
      ),
    );
    await db.sessionDao.insert(session('s1', status: 'active'));
    await db.sessionDao.insert(
      session(
        's2',
        status: 'completed',
        completedAt: DateTime.utc(2026, 5, 3),
      ),
    );
    await db.sessionDao.insert(
      session(
        'other',
        status: 'completed',
        completedAt: DateTime.utc(2026, 5, 3),
        playerId: 'p2',
      ),
    );

    final removed = await db.sessionDao.deleteAllForUser('p1');

    expect(removed, 2);
    expect(await db.sessionDao.getById('s1'), isNull);
    expect(await db.sessionDao.getById('s2'), isNull);
    expect(await db.sessionDao.getById('other'), isNotNull);
  });

  test(
    'activeForUserInMode returns the active session matching the mode '
    'and ignores other modes',
    () async {
      await db.sessionDao.insert(
        SessionsCompanion(
          id: const Value('sniper-active'),
          playerId: const Value('p1'),
          kind: const Value('sniper'),
          mode: const Value('sniper'),
          distanceMeters: const Value(8),
          status: const Value('active'),
          startedAt: Value(DateTime.utc(2026, 5, 2)),
        ),
      );
      await db.sessionDao.insert(
        SessionsCompanion(
          id: const Value('finisseur-active'),
          playerId: const Value('p1'),
          kind: const Value('finisseur'),
          mode: const Value('finisseur'),
          distanceMeters: const Value(8),
          status: const Value('active'),
          startedAt: Value(DateTime.utc(2026, 5, 2)),
        ),
      );

      final sniper =
          await db.sessionDao.activeForUserInMode('p1', 'sniper');
      final finisseur =
          await db.sessionDao.activeForUserInMode('p1', 'finisseur');
      final ghost = await db.sessionDao.activeForUserInMode('p1', 'ghost');

      expect(sniper?.id, 'sniper-active');
      expect(finisseur?.id, 'finisseur-active');
      expect(ghost, isNull);
    },
  );
}
