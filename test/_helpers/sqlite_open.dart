import 'package:drift/native.dart';
import 'package:kubb_app/core/data/app_database.dart';

/// Builds an in-memory `AppDatabase` with `foreign_keys` enabled so tests
/// can rely on cascade and restrict actions just like production builds.
Future<AppDatabase> openTestDatabase() async {
  final db = AppDatabase(NativeDatabase.memory());
  await db.customStatement('PRAGMA foreign_keys = ON');
  return db;
}
