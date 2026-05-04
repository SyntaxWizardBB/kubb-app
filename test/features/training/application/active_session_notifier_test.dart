import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/features/training/application/active_session_notifier.dart';

import '../../../_helpers/sqlite_open.dart';

class _FakeAppSettingsNotifier extends AppSettingsNotifier {
  _FakeAppSettingsNotifier(this._initial);

  final AppSettings _initial;

  @override
  Future<AppSettings> build() async => _initial;
}

Future<void> _seedPlayer(AppDatabase db, String id) {
  return db.playerDao.insert(
    PlayersCompanion(
      id: Value(id),
      name: const Value('Lukas'),
      deviceId: Value('device-$id'),
      createdAt: Value(DateTime.utc(2026, 5, 2)),
    ),
  );
}

ProviderContainer _container({
  required AppDatabase db,
  AppSettings settings = const AppSettings(),
}) {
  return ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      appSettingsProvider.overrideWith(() => _FakeAppSettingsNotifier(settings)),
    ],
  );
}

void main() {
  const playerId = 'p1';
  late AppDatabase db;
  late ProviderContainer container;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() async {
    db = await openTestDatabase();
    await _seedPlayer(db, playerId);
    container = _container(db: db);
    addTearDown(container.dispose);
  });

  tearDown(() async {
    await db.close();
  });

  test('startSession exposes a fresh state with zero counts', () async {
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.startSession(playerId: playerId, distance: 8);

    final state = container.read(activeSessionProvider).requireValue;
    expect(state, isNotNull);
    expect(state!.distance, 8.0);
    expect(state.hits, 0);
    expect(state.misses, 0);
    expect(state.helis, 0);
  });

  test('recordHit appends a hit event and increments the count', () async {
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.startSession(playerId: playerId, distance: 8);
    await notifier.recordHit();

    final state = container.read(activeSessionProvider).requireValue!;
    expect(state.hits, 1);
    expect(state.misses, 0);

    final events = await db.sessionEventDao.forSession(state.sessionId);
    expect(events.where((e) => e.kind == 'hit'), hasLength(1));
  });

  test('three recordMiss calls produce three miss events', () async {
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.startSession(playerId: playerId, distance: 6);
    await notifier.recordMiss();
    await notifier.recordMiss();
    await notifier.recordMiss();

    final state = container.read(activeSessionProvider).requireValue!;
    expect(state.misses, 3);

    final events = await db.sessionEventDao.forSession(state.sessionId);
    expect(events.where((e) => e.kind == 'miss'), hasLength(3));
  });

  test('undoLast soft-deletes the most recent event of that kind', () async {
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.startSession(playerId: playerId, distance: 8);
    await notifier.recordHit();
    await notifier.undoLast('hit');

    final state = container.read(activeSessionProvider).requireValue!;
    expect(state.hits, 0);

    final events = await db.sessionEventDao.forSession(state.sessionId);
    expect(events, hasLength(1));
    expect(events.single.correctedAt, isNotNull);
  });

  test('recordHeli increments helis when heliTracking is on', () async {
    container.dispose();
    container = _container(db: db);
    addTearDown(container.dispose);

    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.startSession(playerId: playerId, distance: 8);
    await notifier.recordHeli();

    final state = container.read(activeSessionProvider).requireValue!;
    expect(state.helis, 1);
  });

  test('complete marks the session completed and clears the state', () async {
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.startSession(playerId: playerId, distance: 8);
    final id = container.read(activeSessionProvider).requireValue!.sessionId;
    await notifier.complete();

    expect(container.read(activeSessionProvider).requireValue, isNull);
    final stored = await db.sessionDao.getById(id);
    expect(stored?.status, 'completed');
    expect(stored?.completedAt, isNotNull);
  });

  test('abortAndDelete removes session row and cascades events', () async {
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.startSession(playerId: playerId, distance: 8);
    await notifier.recordHit();
    final id = container.read(activeSessionProvider).requireValue!.sessionId;
    await notifier.abortAndDelete();

    expect(container.read(activeSessionProvider).requireValue, isNull);
    expect(await db.sessionDao.getById(id), isNull);
    expect(await db.sessionEventDao.forSession(id), isEmpty);
  });

  test('resumeFromCrash rehydrates counts and ignores corrected events',
      () async {
    const sessionId = 'session-restored';
    await db.sessionDao.insert(
      SessionsCompanion(
        id: const Value(sessionId),
        playerId: const Value(playerId),
        kind: const Value('sniper'),
        distanceMeters: const Value(8),
        status: const Value('active'),
        startedAt: Value(DateTime.utc(2026, 5, 2, 10)),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await db.sessionEventDao.insert(
        SessionEventsCompanion(
          id: Value('hit-$i'),
          sessionId: const Value(sessionId),
          kind: const Value('hit'),
          createdAt: Value(DateTime.utc(2026, 5, 2, 10, 0, i)),
        ),
      );
    }
    for (var i = 0; i < 2; i++) {
      await db.sessionEventDao.insert(
        SessionEventsCompanion(
          id: Value('miss-$i'),
          sessionId: const Value(sessionId),
          kind: const Value('miss'),
          createdAt: Value(DateTime.utc(2026, 5, 2, 10, 1, i)),
        ),
      );
    }
    await db.sessionEventDao.insert(
      SessionEventsCompanion(
        id: const Value('hit-corrected'),
        sessionId: const Value(sessionId),
        kind: const Value('hit'),
        createdAt: Value(DateTime.utc(2026, 5, 2, 10, 2)),
        correctedAt: Value(DateTime.utc(2026, 5, 2, 10, 3)),
      ),
    );

    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.resumeFromCrash(sessionId);

    final state = container.read(activeSessionProvider).requireValue!;
    expect(state.sessionId, sessionId);
    expect(state.hits, 5);
    expect(state.misses, 2);
    expect(state.helis, 0);
  });

  test('recordHit without an active session is a stable no-op', () async {
    final notifier = container.read(activeSessionProvider.notifier);
    // No startSession call. Either the notifier silently ignores the tap or
    // surfaces it as an AsyncError — both are acceptable as long as no event
    // row leaks into the store.
    await notifier.recordHit().catchError((Object _) {});
    final allEvents = await db.select(db.sessionEvents).get();
    expect(allEvents, isEmpty);
    expect(container.read(activeSessionProvider).value, isNull);
  });
}
