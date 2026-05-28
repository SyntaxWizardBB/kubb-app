import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';
import 'package:kubb_app/features/training/data/finisseur_repository.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;
  late FinisseurRepository repo;

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
    repo = FinisseurRepository(
      sessionDao: db.sessionDao,
      stickDao: db.finisseurStickEventDao,
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('startFinisseur persists active session with mode finisseur', () async {
    final s = await repo.startFinisseur(playerId: 'p1', field: 7, base: 3);

    final stored = await db.sessionDao.getById(s.id);
    expect(stored, isNotNull);
    expect(stored!.mode, 'finisseur');
    expect(stored.finField, 7);
    expect(stored.finBase, 3);
    expect(stored.status, 'active');
  });

  test('startFinisseur replaces a previous active finisseur session',
      () async {
    final first = await repo.startFinisseur(playerId: 'p1', field: 5, base: 5);
    final second = await repo.startFinisseur(playerId: 'p1', field: 7, base: 3);

    expect(await db.sessionDao.getById(first.id), isNull);
    final active = await repo.loadActiveOrNull(playerId: 'p1');
    expect(active?.id, second.id);
  });

  test('startFinisseur leaves an active sniper session untouched', () async {
    const sniperId = 'sn-1';
    await db.sessionDao.insert(
      SessionsCompanion(
        id: const Value(sniperId),
        playerId: const Value('p1'),
        kind: const Value('sniper'),
        mode: const Value('sniper'),
        distanceMeters: const Value(8),
        status: const Value('active'),
        startedAt: Value(DateTime.utc(2026, 5, 2)),
      ),
    );

    await repo.startFinisseur(playerId: 'p1', field: 7, base: 3);

    expect(await db.sessionDao.getById(sniperId), isNotNull);
  });

  test('recordStick stores rich payload and is readable back', () async {
    final s = await repo.startFinisseur(playerId: 'p1', field: 7, base: 3);
    await repo.recordStick(
      sessionId: s.id,
      stickIndex: 0,
      result: const StickResult(fieldHits: 2, penalty1: 1),
    );
    await repo.recordStick(
      sessionId: s.id,
      stickIndex: 1,
      result: const StickResult(heli: true),
    );

    final events = await repo.loadStickEvents(s.id);
    expect(events, hasLength(2));
    expect(events[0].fieldKubbsHit, 2);
    expect(events[0].penaltyHits1, 1);
    expect(events[1].heliThrow, isTrue);
  });

  test('recordStick persists king detail when present', () async {
    final s = await repo.startFinisseur(playerId: 'p1', field: 7, base: 3);
    await repo.recordStick(
      sessionId: s.id,
      stickIndex: 5,
      result: const StickResult(
        king: KingResult(hit: true, position: KingPosition.unten),
      ),
    );
    final events = await repo.loadStickEvents(s.id);
    expect(events.single.kingHit, isTrue);
    expect(events.single.kingPosition, 'unten');
  });

  test('markCompleted flips status and stamps completedAt', () async {
    final s = await repo.startFinisseur(playerId: 'p1', field: 7, base: 3);
    await repo.markCompleted(sessionId: s.id);

    final stored = await db.sessionDao.getById(s.id);
    expect(stored?.status, 'completed');
    expect(stored?.completedAt, isNotNull);
  });

  test('discard cascades to stick events', () async {
    final s = await repo.startFinisseur(playerId: 'p1', field: 7, base: 3);
    await repo.recordStick(
      sessionId: s.id,
      stickIndex: 0,
      result: const StickResult(fieldHits: 1),
    );

    await repo.discard(sessionId: s.id);

    expect(await db.sessionDao.getById(s.id), isNull);
    expect(await repo.loadStickEvents(s.id), isEmpty);
  });

  test('recordStick at the same index upserts instead of throwing', () async {
    // Race-safety follow-up (W2-T8, refs R5-F-01..02): the unique index
    // on (session_id, stick_index) is still in place, but recordStick now
    // upserts so a retry, crash-resume, or a second tap that slipped past
    // the notifier mutex replaces the existing row instead of crashing.
    final s = await repo.startFinisseur(playerId: 'p1', field: 7, base: 3);
    await repo.recordStick(
      sessionId: s.id,
      stickIndex: 0,
      result: const StickResult(fieldHits: 1),
    );
    await repo.recordStick(
      sessionId: s.id,
      stickIndex: 0,
      result: const StickResult(fieldHits: 2),
    );

    final events = await repo.loadStickEvents(s.id);
    expect(events, hasLength(1));
    expect(events.single.stickIndex, 0);
    expect(events.single.fieldKubbsHit, 2);
  });
}
