import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/settings/data/csv_export_filter.dart';
import 'package:kubb_app/features/settings/data/csv_export_repository.dart';

import '../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;
  late CsvExportRepository repo;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() async {
    db = await openTestDatabase();
    await db.playerDao.insert(
      PlayersCompanion(
        id: const Value('p1'),
        name: const Value('Lukas'),
        deviceId: const Value('device-1'),
        createdAt: Value(DateTime.utc(2026, 5)),
      ),
    );
    repo = CsvExportRepository(
      sessionDao: db.sessionDao,
      eventDao: db.sessionEventDao,
      stickDao: db.finisseurStickEventDao,
    );
  });

  tearDown(() => db.close());

  Future<void> insertSniper(
    String id, {
    required int hits,
    required int misses,
    int helis = 0,
    DateTime? completedAt,
  }) async {
    final ts = completedAt ?? DateTime.utc(2026, 5, 2, 12);
    await db.sessionDao.insert(
      SessionsCompanion(
        id: Value(id),
        playerId: const Value('p1'),
        kind: const Value('sniper'),
        mode: const Value('sniper'),
        distanceMeters: const Value(8),
        throwTarget: const Value(36),
        status: const Value('completed'),
        startedAt: Value(ts),
        completedAt: Value(ts.add(const Duration(minutes: 5))),
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

  Future<void> insertFinisseur(
    String id, {
    required List<int> fieldHits,
    required List<bool> kingHits,
    int field = 7,
    int base = 3,
  }) async {
    final ts = DateTime.utc(2026, 4, 30);
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
        completedAt: Value(ts.add(const Duration(minutes: 4))),
      ),
    );
    for (var i = 0; i < fieldHits.length; i++) {
      await db.finisseurStickEventDao.insert(
        FinisseurStickEventsCompanion(
          id: Value('$id-stick-$i'),
          sessionId: Value(id),
          stickIndex: Value(i),
          fieldKubbsHit: Value(fieldHits[i]),
          eightMHit: const Value(false),
          heliThrow: const Value(false),
          kingHit: i < kingHits.length ? Value(kingHits[i]) : const Value(null),
          createdAt: Value(ts.add(Duration(minutes: i))),
        ),
      );
    }
  }

  test('aggregates sniper hits, misses, helis', () async {
    await insertSniper('s1', hits: 23, misses: 13, helis: 1);
    final rows = await repo.load(
      playerId: 'p1',
      filter: const CsvExportFilter(),
    );
    expect(rows, hasLength(1));
    expect(rows.first.mode, 'sniper');
    expect(rows.first.hits, 23);
    expect(rows.first.misses, 13);
    expect(rows.first.helis, 1);
    expect(rows.first.distanceM, 8);
    expect(rows.first.throwTarget, 36);
  });

  test('aggregates finisseur with sticks_used and king_hit', () async {
    await insertFinisseur(
      'f1',
      fieldHits: [3, 2, 0, 0, 0],
      kingHits: [false, false, false, false, true],
    );
    final rows = await repo.load(
      playerId: 'p1',
      filter: const CsvExportFilter(),
    );
    expect(rows, hasLength(1));
    expect(rows.first.mode, 'finisseur');
    expect(rows.first.sticksUsed, 5);
    expect(rows.first.kingHit, true);
    expect(rows.first.success, true);
    expect(rows.first.finField, 7);
    expect(rows.first.finBase, 3);
  });

  test('filter excludes finisseur when only sniper requested', () async {
    await insertSniper('s1', hits: 1, misses: 0);
    await insertFinisseur('f1', fieldHits: [0], kingHits: [true]);
    final rows = await repo.load(
      playerId: 'p1',
      filter: const CsvExportFilter(includeFinisseur: false),
    );
    expect(rows, hasLength(1));
    expect(rows.first.mode, 'sniper');
  });

  test('returns empty list when filter excludes both modes', () async {
    await insertSniper('s1', hits: 1, misses: 0);
    final rows = await repo.load(
      playerId: 'p1',
      filter: const CsvExportFilter(
        includeSniper: false,
        includeFinisseur: false,
      ),
    );
    expect(rows, isEmpty);
  });

  test('cutoff filters older sessions', () async {
    final old = DateTime.utc(2025, 2);
    final recent = DateTime.utc(2026, 5, 2);
    await insertSniper('old', hits: 1, misses: 0, completedAt: old);
    await insertSniper('new', hits: 5, misses: 1, completedAt: recent);
    final rows = await repo.load(
      playerId: 'p1',
      filter: const CsvExportFilter(range: ExportRange.last30Days),
      now: DateTime.utc(2026, 5, 10),
    );
    expect(rows, hasLength(1));
    expect(rows.first.sessionId, 'new');
  });

  test('count matches load result count', () async {
    await insertSniper('s1', hits: 1, misses: 0);
    await insertSniper('s2', hits: 2, misses: 0);
    final c = await repo.count(
      playerId: 'p1',
      filter: const CsvExportFilter(),
    );
    expect(c, 2);
  });
}
