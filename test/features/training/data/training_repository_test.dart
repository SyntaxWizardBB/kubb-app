import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/training/data/training_repository.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;
  late TrainingRepository repo;

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
    repo = TrainingRepository(
      sessionDao: db.sessionDao,
      eventDao: db.sessionEventDao,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('startSession persists an active row', () async {
    final s = await repo.startSession(playerId: 'p1', distance: 8);

    final stored = await db.sessionDao.getById(s.id);
    expect(stored, isNotNull);
    expect(stored!.status, 'active');
    expect(stored.distanceMeters, 8.0);
    expect(stored.kind, 'sniper');
  });

  test('startSession discards a previous active session (hard delete)',
      () async {
    final first = await repo.startSession(playerId: 'p1', distance: 8);
    final second = await repo.startSession(playerId: 'p1', distance: 6);

    final firstStored = await db.sessionDao.getById(first.id);
    final activeNow = await db.sessionDao.activeForUser('p1');

    expect(firstStored, isNull);
    expect(activeNow?.id, second.id);
  });

  test('appendEvent inserts rows that the DAO can read back', () async {
    final s = await repo.startSession(playerId: 'p1', distance: 8);

    await repo.appendEvent(sessionId: s.id, kind: 'hit');
    await repo.appendEvent(sessionId: s.id, kind: 'hit');
    await repo.appendEvent(sessionId: s.id, kind: 'hit');

    final hits = await db.sessionEventDao.countByKind(s.id, 'hit');
    expect(hits, 3);
  });

  test('softDeleteLastEvent flags exactly one event of the requested kind',
      () async {
    final s = await repo.startSession(playerId: 'p1', distance: 8);
    await repo.appendEvent(sessionId: s.id, kind: 'hit');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.appendEvent(sessionId: s.id, kind: 'hit');

    await repo.softDeleteLastEvent(sessionId: s.id, kind: 'hit');

    final events = await db.sessionEventDao.forSession(s.id);
    final corrected = events.where((e) => e.correctedAt != null).toList();
    final remaining = events.where((e) => e.correctedAt == null).toList();
    expect(corrected, hasLength(1));
    expect(remaining, hasLength(1));
  });

  test('markCompleted sets status to completed', () async {
    final s = await repo.startSession(playerId: 'p1', distance: 8);

    await repo.markCompleted(sessionId: s.id);

    final stored = await db.sessionDao.getById(s.id);
    expect(stored?.status, 'completed');
    expect(stored?.completedAt, isNotNull);
  });

  test('discard hard-deletes the session and cascades to events', () async {
    final s = await repo.startSession(playerId: 'p1', distance: 8);
    await repo.appendEvent(sessionId: s.id, kind: 'hit');
    await repo.appendEvent(sessionId: s.id, kind: 'miss');

    await repo.discard(sessionId: s.id);

    expect(await db.sessionDao.getById(s.id), isNull);
    expect(await db.sessionEventDao.forSession(s.id), isEmpty);
  });

  test('watchActiveSession emits null after discard', () async {
    final s = await repo.startSession(playerId: 'p1', distance: 8);
    final stream = repo.watchActiveSession(playerId: 'p1');

    expect(await stream.first, isNotNull);

    await repo.discard(sessionId: s.id);

    expect(await stream.first, isNull);
  });
}
