import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(_openConnection());
  ref.onDispose(db.close);
  return db;
});

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'kubb.db'));
    return NativeDatabase.createInBackground(file);
  });
}
