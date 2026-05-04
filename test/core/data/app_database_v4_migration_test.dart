import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';

import '../../_helpers/sqlite_open.dart';

/// Tests the v3 → v4 upgrade path. The strategy: open a v4 database,
/// roll it back to a v3-shaped state by dropping the new table and
/// resetting `user_version`, seed it with sample v3 data, then drive
/// the v4 migrator and assert the additive change applied without
/// touching pre-existing rows.
void main() {
  setUpAll(registerLinuxSqliteOverride);

  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> rollbackToV3() async {
    await db.customStatement('DROP TABLE IF EXISTS cached_auth_session');
    await db.customStatement('PRAGMA user_version = 3');
  }

  Future<void> seedV3SampleData() async {
    await db.customStatement(
      "INSERT INTO players (id, name, device_id, avatar_color, created_at) "
      "VALUES ('p1', 'Test Player', 'device-1', '#FF0000', 0)",
    );
    await db.customStatement(
      "INSERT INTO sessions (id, player_id, kind, mode, distance_meters, "
      "throw_target, status, started_at) VALUES "
      "('s1', 'p1', 'sniper', 'sniper', 8.0, 50, 'completed', 0)",
    );
    await db.customStatement(
      "INSERT INTO sessions (id, player_id, kind, mode, distance_meters, "
      "throw_target, status, started_at) VALUES "
      "('s2', 'p1', 'finisseur', 'finisseur', 8.0, NULL, 'completed', 0)",
    );
    await db.customStatement(
      "INSERT INTO session_events (id, session_id, kind, created_at) "
      "VALUES ('e1', 's1', 'hit', 0)",
    );
  }

  test('v3 → v4 migration creates cached_auth_session table', () async {
    await rollbackToV3();
    await seedV3SampleData();

    // Confirm we are in the v3-shaped state.
    final preTables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name='cached_auth_session'",
        )
        .get();
    expect(preTables, isEmpty);

    // Drive the additive migration step.
    await db.createMigrator().createTable(db.cachedAuthSession);

    final postTables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name='cached_auth_session'",
        )
        .get();
    expect(postTables.length, 1);
  });

  test('v3 → v4 migration leaves existing v3 data untouched', () async {
    await rollbackToV3();
    await seedV3SampleData();

    await db.createMigrator().createTable(db.cachedAuthSession);

    final players = await db.customSelect('SELECT id FROM players').get();
    final sessions = await db.customSelect('SELECT id FROM sessions').get();
    final events =
        await db.customSelect('SELECT id FROM session_events').get();

    expect(players.map((r) => r.read<String>('id')).toSet(), {'p1'});
    expect(
      sessions.map((r) => r.read<String>('id')).toSet(),
      {'s1', 's2'},
    );
    expect(events.map((r) => r.read<String>('id')).toSet(), {'e1'});
  });

  test('cached_auth_session enforces single-row constraint via default id',
      () async {
    final now = DateTime.now().toUtc();
    await db.into(db.cachedAuthSession).insert(
          CachedAuthSessionCompanion.insert(
            userId: 'user-1',
            kind: 'keypair',
            displayName: 'Lukas',
            avatarColor: const Value('#FF8800'),
            expiresAt: now.add(const Duration(hours: 1)),
            refreshAfter: now.add(const Duration(minutes: 50)),
            createdAt: now,
            updatedAt: now,
          ),
        );

    // Inserting again without specifying id reuses the default 'singleton'
    // and must therefore conflict on the primary key.
    await expectLater(
      db.into(db.cachedAuthSession).insert(
            CachedAuthSessionCompanion.insert(
              userId: 'user-2',
              kind: 'oauth_google',
              displayName: 'Other',
              expiresAt: now.add(const Duration(hours: 1)),
              refreshAfter: now.add(const Duration(minutes: 50)),
              createdAt: now,
              updatedAt: now,
            ),
          ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('cached_auth_session round-trip preserves all columns', () async {
    final now = DateTime.now().toUtc();
    await db.into(db.cachedAuthSession).insert(
          CachedAuthSessionCompanion.insert(
            userId: 'user-1',
            kind: 'oauth_apple',
            displayName: 'Lukas',
            avatarColor: const Value('#3366FF'),
            expiresAt: now.add(const Duration(hours: 1)),
            refreshAfter: now.add(const Duration(minutes: 50)),
            createdAt: now,
            updatedAt: now,
          ),
        );

    final rows = await db.select(db.cachedAuthSession).get();
    expect(rows.length, 1);
    expect(rows.first.id, 'singleton');
    expect(rows.first.userId, 'user-1');
    expect(rows.first.kind, 'oauth_apple');
    expect(rows.first.displayName, 'Lukas');
    expect(rows.first.avatarColor, '#3366FF');
  });
}
