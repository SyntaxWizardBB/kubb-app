import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';

import '../../../_helpers/sqlite_open.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;

  setUpAll(registerLinuxSqliteOverride);

  setUp(() async {
    db = await openTestDatabase();
    container = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  test('build returns defaults when the database is empty', () async {
    final settings = await container.read(appSettingsProvider.future);

    expect(settings, const AppSettings());
  });

  test('setTheme updates state and persists to the database', () async {
    await container.read(appSettingsProvider.future);

    await container.read(appSettingsProvider.notifier).setTheme(
          ThemeChoice.dark,
        );

    final state = container.read(appSettingsProvider).requireValue;
    expect(state.themeChoice, ThemeChoice.dark);
    expect(await db.appSettingsDao.get('theme'), 'dark');
  });

  test('setHeliTracking flips the flag and persists the string value',
      () async {
    await container.read(appSettingsProvider.future);

    await container
        .read(appSettingsProvider.notifier)
        .setHeliTracking(value: false);

    final state = container.read(appSettingsProvider).requireValue;
    expect(state.heliTracking, false);
    expect(await db.appSettingsDao.get('heliTracking'), 'false');
  });

  test('setLongDubbieTracking persists the new key', () async {
    await container.read(appSettingsProvider.future);

    await container
        .read(appSettingsProvider.notifier)
        .setLongDubbieTracking(value: false);

    final state = container.read(appSettingsProvider).requireValue;
    expect(state.longDubbieTracking, isFalse);
    expect(await db.appSettingsDao.get('longDubbieTracking'), 'false');
  });

  test('setPenaltyKubbTracking persists the new key', () async {
    await container.read(appSettingsProvider.future);

    await container
        .read(appSettingsProvider.notifier)
        .setPenaltyKubbTracking(value: false);

    final state = container.read(appSettingsProvider).requireValue;
    expect(state.penaltyKubbTracking, isFalse);
    expect(await db.appSettingsDao.get('penaltyKubbTracking'), 'false');
  });

  test('setKingThrowTracking persists the new key', () async {
    await container.read(appSettingsProvider.future);

    await container
        .read(appSettingsProvider.notifier)
        .setKingThrowTracking(value: false);

    final state = container.read(appSettingsProvider).requireValue;
    expect(state.kingThrowTracking, isFalse);
    expect(await db.appSettingsDao.get('kingThrowTracking'), 'false');
  });

  test('a fresh container rehydrates the persisted theme', () async {
    await container.read(appSettingsProvider.future);
    await container.read(appSettingsProvider.notifier).setTheme(
          ThemeChoice.dark,
        );
    container.dispose();

    final next = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(next.dispose);

    final reloaded = await next.read(appSettingsProvider.future);
    expect(reloaded.themeChoice, ThemeChoice.dark);
  });
}
