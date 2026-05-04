import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';

const _keyTheme = 'theme';
const _keyHeliTracking = 'heliTracking';
const _keyVibration = 'vibration';
const _keyEyeHidden = 'sniperEyeToggleHidden';
const _keyLongDubbie = 'longDubbieTracking';
const _keyPenaltyKubb = 'penaltyKubbTracking';
const _keyKingThrow = 'kingThrowTracking';

class AppSettingsNotifier extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() async {
    final db = ref.watch(appDatabaseProvider);
    final kv = await db.appSettingsDao.load();
    return AppSettings.fromMap(kv);
  }

  Future<void> setTheme(ThemeChoice choice) async {
    await _update(
      (prev) => prev.copyWith(themeChoice: choice),
      _keyTheme,
      choice.name,
    );
  }

  Future<void> setHeliTracking({required bool value}) async {
    await _update(
      (prev) => prev.copyWith(heliTracking: value),
      _keyHeliTracking,
      value.toString(),
    );
  }

  Future<void> setVibration({required bool value}) async {
    await _update(
      (prev) => prev.copyWith(vibration: value),
      _keyVibration,
      value.toString(),
    );
  }

  Future<void> setEyeHidden({required bool value}) async {
    await _update(
      (prev) => prev.copyWith(sniperEyeToggleHidden: value),
      _keyEyeHidden,
      value.toString(),
    );
  }

  Future<void> setLongDubbieTracking({required bool value}) async {
    await _update(
      (prev) => prev.copyWith(longDubbieTracking: value),
      _keyLongDubbie,
      value.toString(),
    );
  }

  Future<void> setPenaltyKubbTracking({required bool value}) async {
    await _update(
      (prev) => prev.copyWith(penaltyKubbTracking: value),
      _keyPenaltyKubb,
      value.toString(),
    );
  }

  Future<void> setKingThrowTracking({required bool value}) async {
    await _update(
      (prev) => prev.copyWith(kingThrowTracking: value),
      _keyKingThrow,
      value.toString(),
    );
  }

  Future<void> _update(
    AppSettings Function(AppSettings prev) mutate,
    String key,
    String value,
  ) async {
    final prev = state.value;
    if (prev == null) return;
    state = AsyncData(mutate(prev));
    try {
      final db = ref.read(appDatabaseProvider);
      await db.appSettingsDao.save(key, value);
    } on Object catch (e, st) {
      state = AsyncData(prev);
      state = AsyncError(e, st);
    }
  }
}

final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsNotifier, AppSettings>(
  AppSettingsNotifier.new,
);
