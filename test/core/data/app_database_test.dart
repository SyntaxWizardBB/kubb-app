import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';

import '../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('schemaVersion is 7', () {
    expect(db.schemaVersion, 7);
  });

  test('players table has avatarColor column after migration', () async {
    final rows = await db
        .customSelect("PRAGMA table_info('players')")
        .get();
    final cols = rows.map((r) => r.read<String>('name')).toSet();
    expect(cols, contains('avatar_color'));
  });

  test('all expected tables exist after migration', () async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='table' "
          "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%'",
        )
        .get();
    final names = rows.map((r) => r.read<String>('name')).toSet();

    expect(names, containsAll(<String>{
      'players',
      'sessions',
      'session_events',
      'app_settings_table',
      'finisseur_stick_events',
      'cached_auth_session',
      'tournament_score_drafts',
      'inbox_messages',
    }));
  });

  test('all expected indices exist after migration', () async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'",
        )
        .get();
    final names = rows.map((r) => r.read<String>('name')).toSet();

    expect(names, containsAll(<String>{
      'idx_sessions_status_completed',
      'idx_session_events_session_corrected',
      'idx_finisseur_stick_session_index',
    }));
  });

  test('sessions table has mode column with default sniper', () async {
    final rows = await db
        .customSelect("PRAGMA table_info('sessions')")
        .get();
    final cols = rows.map((r) => r.read<String>('name')).toSet();
    expect(cols, containsAll(<String>{'mode', 'fin_field', 'fin_base'}));
  });
}
