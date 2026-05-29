import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/achievements/data/achievements_repository.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/training/application/active_session_notifier.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../_helpers/sqlite_open.dart';

/// W4-T2 session-complete pathway: `markCompleted` fires the badge
/// listener with a cumulative `BadgeSessionSummary`, and matching
/// triggers land in the achievements repository.
void main() {
  const playerId = 'p1';

  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;
  late InMemoryAchievementsRepository repo;
  late ProviderContainer container;

  setUp(() async {
    db = await openTestDatabase();
    await db.playerDao.insert(
      PlayersCompanion(
        id: const Value(playerId),
        name: const Value('Lukas'),
        deviceId: const Value('device-$playerId'),
        createdAt: Value(DateTime.utc(2026, 5)),
      ),
    );
    repo = InMemoryAchievementsRepository();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        achievementsRepositoryProvider.overrideWithValue(repo),
        currentUserIdProvider.overrideWith((_) => playerId),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(repo.dispose);
  });

  tearDown(() async {
    await db.close();
  });

  test('100th sniper hit unlocks hits_100 on session complete', () async {
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.startSession(playerId: playerId, distance: 8);
    for (var i = 0; i < 100; i++) {
      await notifier.recordHit();
    }
    await notifier.complete();

    final unlocks = await repo.listUnlocksFor(const UserId(playerId));
    expect(unlocks.map((u) => u.badgeId), contains('hits_100'));
  });

  test('session below the threshold persists no unlocks', () async {
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.startSession(playerId: playerId, distance: 8);
    await notifier.recordHit();
    await notifier.complete();

    final unlocks = await repo.listUnlocksFor(const UserId(playerId));
    expect(unlocks, isEmpty);
  });

  test('cumulative hits across two sessions trip hits_100', () async {
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.startSession(playerId: playerId, distance: 8);
    for (var i = 0; i < 60; i++) {
      await notifier.recordHit();
    }
    await notifier.complete();

    await notifier.startSession(playerId: playerId, distance: 8);
    for (var i = 0; i < 40; i++) {
      await notifier.recordHit();
    }
    await notifier.complete();

    final unlocks = await repo.listUnlocksFor(const UserId(playerId));
    expect(unlocks.map((u) => u.badgeId), contains('hits_100'));
  });

  test('re-completing into already-unlocked state does not duplicate row',
      () async {
    final notifier = container.read(activeSessionProvider.notifier);
    await notifier.startSession(playerId: playerId, distance: 8);
    for (var i = 0; i < 100; i++) {
      await notifier.recordHit();
    }
    await notifier.complete();

    await notifier.startSession(playerId: playerId, distance: 8);
    await notifier.recordHit();
    await notifier.complete();

    final unlocks = await repo.listUnlocksFor(const UserId(playerId));
    expect(
      unlocks.where((u) => u.badgeId == 'hits_100'),
      hasLength(1),
    );
  });
}
