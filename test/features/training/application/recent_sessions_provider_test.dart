import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/features/player/application/display_profile_provider.dart';
import 'package:kubb_app/features/training/application/recent_sessions_provider.dart';

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

  Future<ProviderContainer> makeContainer({
    required bool heliTracking,
  }) async {
    if (!heliTracking) {
      await db.appSettingsDao.save('heliTracking', 'false');
    }
    final container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        displayProfileProvider.overrideWithValue(
          const DisplayProfile(userId: 'p1', displayName: 'Lukas'),
        ),
      ],
    );
    await container.read(appSettingsProvider.future);
    return container;
  }

  Future<void> insertCompleted(
    String id, {
    required int hits,
    required int misses,
    int helis = 0,
    double distance = 8,
  }) async {
    await db.sessionDao.insert(
      SessionsCompanion(
        id: Value(id),
        playerId: const Value('p1'),
        kind: const Value('sniper'),
        distanceMeters: Value(distance),
        status: const Value('completed'),
        startedAt: Value(DateTime.now().toUtc()),
        completedAt: Value(DateTime.now().toUtc()),
      ),
    );
    Future<void> add(String kind, int count) async {
      for (var i = 0; i < count; i++) {
        await db.sessionEventDao.insert(
          SessionEventsCompanion(
            id: Value('$id-$kind-$i'),
            sessionId: Value(id),
            kind: Value(kind),
            createdAt: Value(DateTime.now().toUtc()),
          ),
        );
      }
    }

    await add('hit', hits);
    await add('miss', misses);
    await add('heli', helis);
  }

  Future<List<RecentSessionView>> waitForData(
    ProviderContainer container, {
    bool Function(List<RecentSessionView>)? until,
  }) async {
    final completer = Completer<List<RecentSessionView>>();
    final sub = container.listen<AsyncValue<List<RecentSessionView>>>(
      recentSessionsProvider,
      (_, next) {
        final value = next.value;
        if (value == null) return;
        if (until != null && !until(value)) return;
        if (!completer.isCompleted) completer.complete(value);
      },
      fireImmediately: true,
    );
    addTearDown(sub.close);
    return completer.future.timeout(const Duration(seconds: 5));
  }

  test('emits empty list when no sessions exist', () async {
    final container = await makeContainer(heliTracking: true);
    addTearDown(container.dispose);

    final result = await waitForData(container);
    expect(result, isEmpty);
  });

  test('computes hit-rate from non-corrected hits and misses', () async {
    await insertCompleted('s1', hits: 7, misses: 3);
    final container = await makeContainer(heliTracking: true);
    addTearDown(container.dispose);

    final result =
        await waitForData(container, until: (list) => list.isNotEmpty);

    expect(result, hasLength(1));
    expect(result.single.hitRatePercent, 70);
    expect(result.single.modeTag, 'Sniper');
  });

  Future<void> insertFinisseurCompleted(
    String id, {
    required int field,
    required int base,
    required List<({int fieldHits, bool eight, bool? king})> sticks,
  }) async {
    final ts = DateTime.now().toUtc();
    await db.sessionDao.insert(
      SessionsCompanion(
        id: Value(id),
        playerId: const Value('p1'),
        kind: const Value('finisseur'),
        mode: const Value('finisseur'),
        distanceMeters: const Value(8),
        finField: Value(field),
        finBase: Value(base),
        status: const Value('completed'),
        startedAt: Value(ts),
        completedAt: Value(ts),
      ),
    );
    for (var i = 0; i < sticks.length; i++) {
      final s = sticks[i];
      await db.finisseurStickEventDao.insert(
        FinisseurStickEventsCompanion(
          id: Value('$id-stk-$i'),
          sessionId: Value(id),
          stickIndex: Value(i),
          fieldKubbsHit: Value(s.fieldHits),
          eightMHit: Value(s.eight),
          heliThrow: const Value(false),
          kingHit: switch (s.king) {
            final bool v => Value(v),
            _ => const Value.absent(),
          },
          createdAt: Value(ts.add(Duration(seconds: i))),
        ),
      );
    }
  }

  test('finisseur view exposes binaryWin instead of a hit-rate', () async {
    await insertFinisseurCompleted(
      'fwin',
      field: 1,
      base: 1,
      sticks: const [
        (fieldHits: 1, eight: true, king: true),
      ],
    );
    final container = await makeContainer(heliTracking: true);
    addTearDown(container.dispose);

    final result =
        await waitForData(container, until: (list) => list.isNotEmpty);

    expect(result.single.modeTag, 'Finisseur');
    expect(result.single.binaryWin, isTrue);
    expect(result.single.hitRatePercent, isNull);
  });

  test('subtitle ignores helis in throw count when heliTracking is off',
      () async {
    await insertCompleted('s1', hits: 5, misses: 5, helis: 2);
    final container = await makeContainer(heliTracking: false);
    addTearDown(container.dispose);

    final result =
        await waitForData(container, until: (list) => list.isNotEmpty);

    // Heli reduces the rate (5 / (5+5+2) ≈ 42).
    expect(result.single.hitRatePercent, 42);
    expect(result.single.subtitle, contains('10 Würfe'));
    expect(result.single.subtitle, contains('8.0 m'));
  });
}
