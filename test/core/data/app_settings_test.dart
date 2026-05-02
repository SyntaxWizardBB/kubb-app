import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/app_settings.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';

void main() {
  group('AppSettings', () {
    test('default constructor uses documented defaults', () {
      const settings = AppSettings();
      expect(settings.themeChoice, ThemeChoice.light);
      expect(settings.heliTracking, isTrue);
      expect(settings.vibration, isTrue);
      expect(settings.sniperEyeToggleHidden, isFalse);
    });

    test('fromMap with empty map returns defaults', () {
      final settings = AppSettings.fromMap(const {});
      expect(settings, const AppSettings());
    });

    test('fromMap parses all four keys', () {
      final settings = AppSettings.fromMap(const {
        'theme': 'dark',
        'heliTracking': 'false',
        'vibration': 'false',
        'sniperEyeToggleHidden': 'true',
      });
      expect(settings.themeChoice, ThemeChoice.dark);
      expect(settings.heliTracking, isFalse);
      expect(settings.vibration, isFalse);
      expect(settings.sniperEyeToggleHidden, isTrue);
    });

    test('fromMap falls back to light on unknown theme', () {
      final settings = AppSettings.fromMap(const {'theme': 'neon'});
      expect(settings.themeChoice, ThemeChoice.light);
    });

    test('round-trip via toMap and fromMap is identity-preserving', () {
      const original = AppSettings(
        themeChoice: ThemeChoice.highContrast,
        heliTracking: false,
        sniperEyeToggleHidden: true,
      );
      final restored = AppSettings.fromMap(original.toMap());
      expect(restored, original);
    });
  });
}
