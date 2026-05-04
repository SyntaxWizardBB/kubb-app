import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/stats/application/stats_aggregate_provider.dart';
import 'package:kubb_app/features/stats/application/stats_filter_notifier.dart';
import 'package:kubb_app/features/stats/data/stats_aggregate.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;
  late Player player;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() async {
    db = await openTestDatabase();
    await db.playerDao.insert(
      PlayersCompanion(
        id: const Value('p1'),
        name: const Value('Lukas'),
        deviceId: const Value('device-p1'),
        createdAt: Value(DateTime.utc(2026, 5)),
      ),
    );
    player = (await db.playerDao.getById('p1'))!;
  });

  tearDown(() async {
    await db.close();
  });

  Future<ProviderContainer> makeContainer() async {
    final controller = StreamController<Player?>();
    addTearDown(controller.close);
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        currentProfileProvider.overrideWith((ref) => controller.stream),
      ],
    );
    await container.read(appSettingsProvider.future);
    controller.add(player);
    return container;
  }

  Future<void> insertSession(String id, {required int hits, required int misses}) async {
    final ts = DateTime.utc(2026, 5, 2, 10, int.parse(id.replaceAll(RegExp('[^0-9]'), '')));
    await db.sessionDao.insert(
      SessionsCompanion(
        id: Value(id),
        playerId: const Value('p1'),
        kind: const Value('sniper'),
        distanceMeters: const Value(8),
        status: const Value('completed'),
        startedAt: Value(ts),
        completedAt: Value(ts),
      ),
    );
    for (var i = 0; i < hits; i++) {
      await db.sessionEventDao.insert(
        SessionEventsCompanion(
          id: Value('$id-h$i'),
          sessionId: Value(id),
          kind: const Value('hit'),
          createdAt: Value(ts.add(Duration(seconds: i))),
        ),
      );
    }
    for (var i = 0; i < misses; i++) {
      await db.sessionEventDao.insert(
        SessionEventsCompanion(
          id: Value('$id-m$i'),
          sessionId: Value(id),
          kind: const Value('miss'),
          createdAt: Value(ts.add(Duration(seconds: 100 + i))),
        ),
      );
    }
  }

  Future<StatsAggregate> waitForAggregate(ProviderContainer container) {
    final completer = Completer<StatsAggregate>();
    final sub = container.listen<AsyncValue<StatsAggregate>>(
      statsAggregateProvider,
      (_, next) {
        next.whenData((value) {
          if (!completer.isCompleted) completer.complete(value);
        });
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);
    return completer.future.timeout(const Duration(seconds: 5));
  }

  test('emits empty aggregate when player has no sessions', () async {
    final container = await makeContainer();
    addTearDown(container.dispose);

    final agg = await waitForAggregate(container);
    expect(agg.isEmpty, isTrue);
  });

  test('recomputes when distance filter changes', () async {
    await insertSession('s1', hits: 8, misses: 2);
    final container = await makeContainer();
    addTearDown(container.dispose);

    final firstFuture = waitForAggregate(container);
    final first = await firstFuture;
    expect(first.totalSessions, 1);

    final completer = Completer<StatsAggregate>();
    final sub = container.listen<AsyncValue<StatsAggregate>>(
      statsAggregateProvider,
      (prev, next) {
        next.whenData((value) {
          if (value.totalSessions == 0 && !completer.isCompleted) {
            completer.complete(value);
          }
        });
      },
    );
    addTearDown(sub.close);

    container.read(statsFilterProvider.notifier).setDistanceRange(4, 4.5);
    final filtered = await completer.future.timeout(const Duration(seconds: 5));
    expect(filtered.totalSessions, 0);
  });
}
