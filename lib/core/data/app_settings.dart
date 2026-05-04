import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';

part 'app_settings.freezed.dart';

const _keyTheme = 'theme';
const _keyHeliTracking = 'heliTracking';
const _keyVibration = 'vibration';
const _keyEyeHidden = 'sniperEyeToggleHidden';
const _keyLongDubbie = 'longDubbieTracking';
const _keyPenaltyKubb = 'penaltyKubbTracking';
const _keyKingThrow = 'kingThrowTracking';

@freezed
abstract class AppSettings with _$AppSettings {
  const factory AppSettings({
    @Default(ThemeChoice.light) ThemeChoice themeChoice,
    @Default(true) bool heliTracking,
    @Default(true) bool vibration,
    @Default(false) bool sniperEyeToggleHidden,
    @Default(true) bool longDubbieTracking,
    @Default(true) bool penaltyKubbTracking,
    @Default(true) bool kingThrowTracking,
  }) = _AppSettings;

  const AppSettings._();

  // factory naming would clash with the freezed default constructor;
  // a static helper keeps the call-site explicit (`AppSettings.fromMap(...)`).
  // ignore: prefer_constructors_over_static_methods
  static AppSettings fromMap(Map<String, String> kv) {
    return AppSettings(
      themeChoice: _parseTheme(kv[_keyTheme]),
      heliTracking: _parseBool(kv[_keyHeliTracking], defaultValue: true),
      vibration: _parseBool(kv[_keyVibration], defaultValue: true),
      sniperEyeToggleHidden:
          _parseBool(kv[_keyEyeHidden], defaultValue: false),
      longDubbieTracking:
          _parseBool(kv[_keyLongDubbie], defaultValue: true),
      penaltyKubbTracking:
          _parseBool(kv[_keyPenaltyKubb], defaultValue: true),
      kingThrowTracking:
          _parseBool(kv[_keyKingThrow], defaultValue: true),
    );
  }

  Map<String, String> toMap() => {
        _keyTheme: themeChoice.name,
        _keyHeliTracking: heliTracking.toString(),
        _keyVibration: vibration.toString(),
        _keyEyeHidden: sniperEyeToggleHidden.toString(),
        _keyLongDubbie: longDubbieTracking.toString(),
        _keyPenaltyKubb: penaltyKubbTracking.toString(),
        _keyKingThrow: kingThrowTracking.toString(),
      };
}

ThemeChoice _parseTheme(String? raw) {
  if (raw == null) return ThemeChoice.light;
  for (final choice in ThemeChoice.values) {
    if (choice.name == raw) return choice;
  }
  return ThemeChoice.light;
}

bool _parseBool(String? raw, {required bool defaultValue}) {
  if (raw == 'true') return true;
  if (raw == 'false') return false;
  return defaultValue;
}
