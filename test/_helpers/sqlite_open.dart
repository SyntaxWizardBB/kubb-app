import 'dart:ffi';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:sqlite3/open.dart';

bool _registered = false;

/// Registers a Linux-specific SQLite resolver so tests can run with the
/// system `libsqlite3.so.0` instead of the package-bundled binary.
/// No-op on other platforms or when called more than once.
void registerLinuxSqliteOverride() {
  if (_registered || !Platform.isLinux) {
    return;
  }
  open.overrideFor(
    OperatingSystem.linux,
    () => DynamicLibrary.open('libsqlite3.so.0'),
  );
  _registered = true;
}

/// Builds an in-memory `AppDatabase` with `foreign_keys` enabled so tests
/// can rely on cascade and restrict actions just like production builds.
Future<AppDatabase> openTestDatabase() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.customStatement('PRAGMA foreign_keys = ON');
  return db;
}
