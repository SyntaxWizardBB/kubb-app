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
    // Trend is cumulative: session 1 → 7/10 = 70%, session 2 → 12/20 = 60%.
    expect(agg.trendPoints, [70, 60]);
  });

  test('sniper trend is cumulative hit-rate over sessions', () async {
    // Three sessions: 8/10, 4/10, 6/10. Cumulative: 80, 60, 60.
    await insertSession(
      's1',
      hits: 8,
      misses: 2,
      completedAt: DateTime.utc(2026, 5, 2, 9),
    );
    await insertSession(
      's2',
      hits: 4,
      misses: 6,
      completedAt: DateTime.utc(2026, 5, 2, 10),
    );
    await insertSession(
      's3',
      hits: 6,
      misses: 4,
      completedAt: DateTime.utc(2026, 5, 2, 11),
    );

    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(),
      heliTracking: true,
    );

    expect(agg.trendPoints, [80, 60, 60]);
  });

  test('sniper trend with single session is its own hit-rate', () async {
    await insertSession('only', hits: 7, misses: 3);

    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(),
      heliTracking: true,
    );

    expect(agg.trendPoints, [70]);
  });

  test('sniper trend counts helis as misses in the running denominator',
      () async {
    // Session 1: 5 hits, 5 misses, 0 helis → 50%.
    // Session 2: 5 hits, 0 misses, 5 helis → cumulative 10/20 = 50%.
    await insertSession(
      's1',
      hits: 5,
      misses: 5,
      completedAt: DateTime.utc(2026, 5, 2, 9),
    );
    await insertSession(
      's2',
      hits: 5,
      misses: 0,
      helis: 5,
      completedAt: DateTime.utc(2026, 5, 2, 10),
    );

    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(),
      heliTracking: true,
    );

    expect(agg.trendPoints, [50, 50]);
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

  test('distance range narrows aggregate', () async {
    await insertSession('s1', hits: 6, misses: 4);
    await insertSession('s2', hits: 9, misses: 1, distance: 4);

    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(distanceMin: 7.5),
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

  test('helis leave both throw count and rate when heliTracking is off',
      () async {
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
    // With heli tracking on, helis count as a miss in the rate denominator.
    // With it off, helis leave the quota too, so the rate climbs.
    expect(on.hitRatePercent, 38); // 5 / (5 + 5 + 3) ≈ 38.46%
    expect(off.hitRatePercent, 50); // 5 / (5 + 5)
  });

  test('heli reduces hit-rate even with helis = 0 keeping the old result',
      () async {
    await insertSession('s1', hits: 5, misses: 5);
    final agg = await repo.computeAggregate(
      playerId: 'p1',
      filter: const StatsFilter(),
      heliTracking: true,
    );
    expect(agg.hitRatePercent, 50);
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

  test('finisseur range narrows aggregate by field plus base', () async {
    await insertFinisseur(
      id: 'f73',
      field: 7,
      base: 3,
      sticks: const [(fieldHits: 1, eight: false, heli: false, king: null, p2: 0)],
    );
    await insertFinisseur(
      id: 'f55',
      field: 5,
      base: 5,
      sticks: const [(fieldHits: 1, eight: false, heli: false, king: null, p2: 0)],
    );

    final agg = await repo.computeFinisseurAggregate(
      playerId: 'p1',
      filter: const StatsFilter(
        finFieldMin: 7,
        finBaseMax: 3,
      ),
    );

    expect(agg.totalSessions, 1);
    expect(agg.sessionRows.single.field, 7);
  });

  test('finisseur aggregate counts heli-only and full-dud sticks as misses',
      () async {
    await insertFinisseur(
      id: 'f-misses',
      field: 3,
      base: 1,
      sticks: const [
        // hit stick: scores a field kubb
        (fieldHits: 1, eight: false, heli: false, king: null, p2: 0),
        // miss stick: heli only
        (fieldHits: 0, eight: false, heli: true, king: null, p2: 0),
        // miss stick: dud, no inputs
        (fieldHits: 0, eight: false, heli: false, king: null, p2: 0),
      ],
    );

    final agg = await repo.computeFinisseurAggregate(playerId: 'p1');

    expect(agg.totalSticks, 3);
    expect(agg.missSticks, 2);
    expect(agg.stickHitRatePercent, 33); // 1 / 3
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

  test('finisseur aggregate marks sessions over six sticks as failures',
      () async {
    // Player cleared everything but it took seven sticks (continued past
    // regulation) — the aggregate must still record this as a loss.
    await insertFinisseur(
      id: 'f-over',
      field: 1,
      base: 1,
      sticks: const [
        (fieldHits: 0, eight: false, heli: false, king: null, p2: 0),
        (fieldHits: 0, eight: false, heli: false, king: null, p2: 0),
        (fieldHits: 0, eight: false, heli: false, king: null, p2: 0),
        (fieldHits: 0, eight: false, heli: false, king: null, p2: 0),
        (fieldHits: 0, eight: false, heli: false, king: null, p2: 0),
        (fieldHits: 1, eight: true, heli: false, king: null, p2: 0),
        (fieldHits: 0, eight: false, heli: false, king: true, p2: 0),
      ],
    );

    final agg = await repo.computeFinisseurAggregate(playerId: 'p1');

    expect(agg.totalSessions, 1);
    expect(agg.successCount, 0);
    expect(agg.totalSticks, 7);
    expect(agg.sessionRows.single.success, isFalse);
    expect(agg.sessionRows.single.sticksUsed, 7);
  });

  test('finisseur trend is cumulative success rate over sessions', () async {
    // Outcomes [Win, Lost, Win] → [100, 50, 67].
    Future<void> add(String id, {required bool win, required int hour}) {
      final ts = DateTime.utc(2026, 5, 5, hour);
      return insertFinisseur(
        id: id,
        field: 1,
        base: 0,
        sticks: [
          (fieldHits: win ? 1 : 0, eight: false, heli: false, king: null, p2: 0),
        ],
        completedAt: ts,
      );
    }

    await add('f1', win: true, hour: 9);
    await add('f2', win: false, hour: 10);
    await add('f3', win: true, hour: 11);

    final agg = await repo.computeFinisseurAggregate(playerId: 'p1');

    expect(agg.successTrendPercent, [100, 50, 67]);
  });

  test('finisseur trend with single win is [100]', () async {
    await insertFinisseur(
      id: 'f-only',
      field: 1,
      base: 0,
      sticks: const [
        (fieldHits: 1, eight: false, heli: false, king: null, p2: 0),
      ],
    );

    final agg = await repo.computeFinisseurAggregate(playerId: 'p1');

    expect(agg.successTrendPercent, [100]);
  });

  test('finisseur trend with single loss is [0]', () async {
    await insertFinisseur(
      id: 'f-loss',
      field: 1,
      base: 0,
      sticks: const [
        (fieldHits: 0, eight: false, heli: false, king: null, p2: 0),
      ],
    );

    final agg = await repo.computeFinisseurAggregate(playerId: 'p1');

    expect(agg.successTrendPercent, [0]);
  });

  test('finisseur trend with no sessions is empty', () async {
    final agg = await repo.computeFinisseurAggregate(playerId: 'p1');

    expect(agg.successTrendPercent, isEmpty);
  });

  test('finisseur trend over five mixed sessions tracks running average',
      () async {
    // Outcomes [Win, Win, Lost, Win, Lost] → [100, 100, 67, 75, 60].
    final outcomes = [true, true, false, true, false];
    for (var i = 0; i < outcomes.length; i++) {
      await insertFinisseur(
        id: 'fmix-$i',
        field: 1,
        base: 0,
        sticks: [
          (
            fieldHits: outcomes[i] ? 1 : 0,
            eight: false,
            heli: false,
            king: null,
            p2: 0,
          ),
        ],
        completedAt: DateTime.utc(2026, 5, 6, 8 + i),
      );
    }

    final agg = await repo.computeFinisseurAggregate(playerId: 'p1');

    expect(agg.successTrendPercent, [100, 100, 67, 75, 60]);
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
