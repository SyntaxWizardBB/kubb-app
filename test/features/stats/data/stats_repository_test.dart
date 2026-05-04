import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/stats/data/stats_filter.dart';
import 'package:kubb_app/features/stats/data/stats_repository.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;
  late StatsRepository repo;

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
    repo = StatsRepository(
      sessionDao: db.sessionDao,
      eventDao: db.sessionEventDao,
      finisseurDao: db.finisseurStickEventDao,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> insertSession(
    String id, {
    required int hits,
    required int misses,
    int helis = 0,
    double distance = 8,
    DateTime? completedAt,
  }) async {
    final ts = completedAt ?? DateTime.utc(2026, 5, 2, 12);
    await db.sessionDao.insert(
      SessionsCompanion(
        id: Value(id),
        playerId: const Value('p1'),
        kind: const Value('sniper'),
        distanceMeters: Value(distance),
        status: const Value('completed'),
        startedAt: Value(ts),
        completedAt: Value(ts),
      ),
    );
    Future<void> add(String kind, int n) async {
      for (var i = 0; i < n; i++) {
        await db.sessionEventDao.insert(
          SessionEventsCompanion(
            id: Value('$id-$kind-$i'),
            sessionId: Value(id),
            kind: Value(kind),
            createdAt: Value(ts.add(Duration(seconds: i))),
          ),
        );
      }
    }

    await add('hit', hits);
    await add('miss', misses);
    await add('heli', helis);
  }

  test('returns empty aggregate when no sessions exist', () async {
    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(),
      heliTracking: true,
    );
    expect(agg.isEmpty, isTrue);
    expect(agg.totalSessions, 0);
    expect(agg.trendPoints, isEmpty);
  });

  test('aggregates totals and overall hit-rate across sessions', () async {
    await insertSession(
      's1',
      hits: 7,
      misses: 3,
      completedAt: DateTime.utc(2026, 5, 2, 10),
    );
    await insertSession(
      's2',
      hits: 5,
      misses: 5,
      completedAt: DateTime.utc(2026, 5, 2, 14),
    );

    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(),
      heliTracking: true,
    );

    expect(agg.totalSessions, 2);
    expect(agg.totalThrows, 20);
    expect(agg.hitRatePercent, 60); // (7+5) / (10+10) = 60%
    expect(agg.trendPoints, [70, 50]);
  });

  test('computes longest hit streak within a single session', () async {
    // 3 hits, miss, 4 hits, miss → longest = 4
    await db.sessionDao.insert(
      SessionsCompanion(
        id: const Value('s1'),
        playerId: const Value('p1'),
        kind: const Value('sniper'),
        distanceMeters: const Value(8),
        status: const Value('completed'),
        startedAt: Value(DateTime.utc(2026, 5, 2)),
        completedAt: Value(DateTime.utc(2026, 5, 2)),
      ),
    );
    final kinds = ['hit', 'hit', 'hit', 'miss', 'hit', 'hit', 'hit', 'hit', 'miss'];
    for (var i = 0; i < kinds.length; i++) {
      await db.sessionEventDao.insert(
        SessionEventsCompanion(
          id: Value('e$i'),
          sessionId: const Value('s1'),
          kind: Value(kinds[i]),
          createdAt: Value(DateTime.utc(2026, 5, 2).add(Duration(seconds: i))),
        ),
      );
    }

    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(),
      heliTracking: true,
    );

    expect(agg.longestHitStreak, 4);
  });

  test('distance filter narrows aggregate', () async {
    await insertSession('s1', hits: 6, misses: 4);
    await insertSession('s2', hits: 9, misses: 1, distance: 4);

    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(distanceMeters: 8),
      heliTracking: true,
    );

    expect(agg.totalSessions, 1);
    expect(agg.hitRatePercent, 60);
  });

  test('date range filter respects last7Days cutoff', () async {
    final now = DateTime.utc(2026, 5, 10);
    await insertSession(
      's-old',
      hits: 9,
      misses: 1,
      completedAt: now.subtract(const Duration(days: 30)),
    );
    await insertSession(
      's-new',
      hits: 5,
      misses: 5,
      completedAt: now.subtract(const Duration(days: 2)),
    );

    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(dateRange: StatsDateRange.last7Days),
      heliTracking: true,
      now: now,
    );

    expect(agg.totalSessions, 1);
    expect(agg.hitRatePercent, 50);
  });

  test('totalThrows ignores helis when heliTracking is off', () async {
    await insertSession('s1', hits: 5, misses: 5, helis: 3);

    final on = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(),
      heliTracking: true,
    );
    final off = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(),
      heliTracking: false,
    );

    expect(on.totalThrows, 13);
    expect(off.totalThrows, 10);
    // hit-rate must not change.
    expect(on.hitRatePercent, off.hitRatePercent);
  });

  test('best hit-rate picks the strongest session and reports its distance',
      () async {
    await insertSession('s1', hits: 6, misses: 4, distance: 6);
    await insertSession('s2', hits: 9, misses: 1, distance: 4.5);
    await insertSession('s3', hits: 7, misses: 3);

    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(),
      heliTracking: true,
    );

    expect(agg.bestHitRatePercent, 90);
    expect(agg.bestHitRateDistance, 4.5);
  });

  test('mostThrowsInOneDay groups sessions on the same UTC day', () async {
    final dayA = DateTime.utc(2026, 5, 2, 10);
    final dayB = DateTime.utc(2026, 5, 3, 10);
    await insertSession('a1', hits: 5, misses: 5, completedAt: dayA);
    await insertSession('a2', hits: 8, misses: 2, completedAt: dayA);
    await insertSession('b1', hits: 3, misses: 7, completedAt: dayB);

    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(),
      heliTracking: true,
    );

    expect(agg.mostThrowsInOneDay, 20); // dayA: 10 + 10
  });

  Future<void> insertFinisseur({
    required String id,
    required int field,
    required int base,
    required List<({int fieldHits, bool eight, bool heli, bool? king, int p2})>
        sticks,
    DateTime? completedAt,
  }) async {
    final ts = completedAt ?? DateTime.utc(2026, 5, 5);
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
          heliThrow: Value(s.heli),
          kingHit: switch (s.king) {
            final bool v => Value(v),
            _ => const Value.absent(),
          },
          penaltyHits2: Value(s.p2),
          createdAt: Value(ts.add(Duration(seconds: i))),
        ),
      );
    }
  }

  test('finisseur aggregate is empty without finisseur sessions', () async {
    final agg = await repo.computeFinisseurAggregate(playerId: 'p1');
    expect(agg.isEmpty, isTrue);
  });

  test('finisseur aggregate counts successes, sticks and long dubbies',
      () async {
    await insertFinisseur(
      id: 'f-success',
      field: 2,
      base: 1,
      // Stick 0 knocks down a field plus base in one throw (long dubbie),
      // stick 1 knocks down the remaining field, king lands.
      sticks: [
        (fieldHits: 1, eight: true, heli: false, king: null, p2: 0),
        (fieldHits: 1, eight: false, heli: false, king: true, p2: 0),
      ],
    );
    await insertFinisseur(
      id: 'f-fail',
      field: 1,
      base: 1,
      sticks: [
        (fieldHits: 0, eight: false, heli: true, king: null, p2: 0),
      ],
    );

    final agg = await repo.computeFinisseurAggregate(playerId: 'p1');

    expect(agg.totalSessions, 2);
    expect(agg.successCount, 1);
    expect(agg.successRatePercent, 50);
    expect(agg.totalSticks, 3);
    expect(agg.heliCount, 1);
    expect(agg.longDubbiesPerSession, closeTo(0.5, 0.0001));
    expect(agg.kingAttempts, 1);
    expect(agg.kingHits, 1);
    expect(agg.kingHitRatePercent, 100);
  });

  test('finisseur aggregate exposes session rows newest-first', () async {
    await insertFinisseur(
      id: 'f-old',
      field: 1,
      base: 0,
      sticks: const [
        (fieldHits: 1, eight: false, heli: false, king: null, p2: 1),
      ],
      completedAt: DateTime.utc(2026, 5),
    );
    await insertFinisseur(
      id: 'f-new',
      field: 1,
      base: 0,
      sticks: [
        (fieldHits: 1, eight: false, heli: false, king: null, p2: 0),
      ],
      completedAt: DateTime.utc(2026, 5, 10),
    );

    final agg = await repo.computeFinisseurAggregate(playerId: 'p1');

    expect(agg.sessionRows.first.sessionId, 'f-new');
    expect(agg.sessionRows.last.sessionId, 'f-old');
  });

  test('sessionRows are most-recent-first and capped to 20', () async {
    for (var i = 0; i < 25; i++) {
      await insertSession(
        's$i',
        hits: 5,
        misses: 5,
        completedAt: DateTime.utc(2026, 5).add(Duration(hours: i)),
      );
    }

    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(),
      heliTracking: true,
    );

    expect(agg.sessionRows, hasLength(20));
    expect(agg.sessionRows.first.sessionId, 's24');
  });
}
