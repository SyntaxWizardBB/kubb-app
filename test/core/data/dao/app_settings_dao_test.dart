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

  test('roundtrips a saved value through get', () async {
    await db.appSettingsDao.save('theme', 'dark');

    expect(await db.appSettingsDao.get('theme'), 'dark');
  });

  test('save overwrites the value of an existing key', () async {
    await db.appSettingsDao.save('theme', 'dark');
    await db.appSettingsDao.save('theme', 'light');

    expect(await db.appSettingsDao.get('theme'), 'light');
  });

  test('load returns every stored key as a map', () async {
    await db.appSettingsDao.save('theme', 'dark');
    await db.appSettingsDao.save('heliTracking', 'true');
    await db.appSettingsDao.save('vibration', 'false');
    await db.appSettingsDao.save('eyeHidden', 'true');

    final map = await db.appSettingsDao.load();

    expect(map, {
      'theme': 'dark',
      'heliTracking': 'true',
      'vibration': 'false',
      'eyeHidden': 'true',
    });
  });
}
