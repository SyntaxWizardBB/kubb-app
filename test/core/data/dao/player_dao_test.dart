import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() async {
    db = await openTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  PlayersCompanion player(String id, String name, {DateTime? createdAt}) {
    return PlayersCompanion(
      id: Value(id),
      name: Value(name),
      deviceId: Value('device-$id'),
      createdAt: Value(createdAt ?? DateTime.utc(2026, 5, 2)),
    );
  }

  test('returns inserted player by id', () async {
    await db.playerDao.insert(player('p1', 'Lukas'));

    final row = await db.playerDao.getById('p1');

    expect(row, isNotNull);
    expect(row!.name, 'Lukas');
    expect(row.deviceId, 'device-p1');
  });

  test('all returns players ordered by createdAt asc', () async {
    await db.playerDao.insert(
      player('p2', 'Bea', createdAt: DateTime.utc(2026, 5, 3)),
    );
    await db.playerDao.insert(
      player('p1', 'Anna', createdAt: DateTime.utc(2026, 5, 2)),
    );

    final rows = await db.playerDao.all();

    expect(rows.map((p) => p.id), ['p1', 'p2']);
  });

  test('returns null when player id is unknown', () async {
    final row = await db.playerDao.getById('missing');
    expect(row, isNull);
  });
}
