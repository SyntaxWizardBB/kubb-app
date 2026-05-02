import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:sqlite3/open.dart';

void main() {
  late AppDatabase db;

  setUpAll(() {
    if (Platform.isLinux) {
      open.overrideFor(
        OperatingSystem.linux,
        () => DynamicLibrary.open('libsqlite3.so.0'),
      );
    }
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('schemaVersion is 1', () {
    expect(db.schemaVersion, 1);
  });

  test('all four tables exist after migration', () async {
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
    }));
  });

  test('both expected indices exist after migration', () async {
    final rows = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'",
        )
        .get();
    final names = rows.map((r) => r.read<String>('name')).toSet();

    expect(names, containsAll(<String>{
      'idx_sessions_status_completed',
      'idx_session_events_session_corrected',
    }));
  });
}
