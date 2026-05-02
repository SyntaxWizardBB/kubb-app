import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/tables/app_settings_table.dart';

part 'app_settings_dao.g.dart';

@DriftAccessor(tables: [AppSettingsTable])
class AppSettingsDao extends DatabaseAccessor<AppDatabase>
    with _$AppSettingsDaoMixin {
  AppSettingsDao(super.attachedDatabase);

  Future<Map<String, String>> load() async {
    final rows = await select(appSettingsTable).get();
    return {for (final row in rows) row.key: row.value};
  }

  Future<void> save(String key, String value) {
    return into(appSettingsTable).insertOnConflictUpdate(
      AppSettingsTableCompanion(key: Value(key), value: Value(value)),
    );
  }

  Future<String?> get(String key) async {
    final row = await (select(appSettingsTable)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }
}
