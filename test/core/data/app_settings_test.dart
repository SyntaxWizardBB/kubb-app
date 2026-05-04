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
      expect(settings.longDubbieTracking, isTrue);
      expect(settings.penaltyKubbTracking, isTrue);
      expect(settings.kingThrowTracking, isTrue);
      expect(settings.allowContinueBeyondSticks, isTrue);
    });

    test('fromMap with empty map returns defaults', () {
      final settings = AppSettings.fromMap(const {});
      expect(settings, const AppSettings());
    });

    test('fromMap parses all keys', () {
      final settings = AppSettings.fromMap(const {
        'theme': 'dark',
        'heliTracking': 'false',
        'vibration': 'false',
        'sniperEyeToggleHidden': 'true',
        'longDubbieTracking': 'false',
        'penaltyKubbTracking': 'false',
        'kingThrowTracking': 'false',
        'allowContinueBeyondSticks': 'false',
      });
      expect(settings.themeChoice, ThemeChoice.dark);
      expect(settings.heliTracking, isFalse);
      expect(settings.vibration, isFalse);
      expect(settings.sniperEyeToggleHidden, isTrue);
      expect(settings.longDubbieTracking, isFalse);
      expect(settings.penaltyKubbTracking, isFalse);
      expect(settings.kingThrowTracking, isFalse);
      expect(settings.allowContinueBeyondSticks, isFalse);
    });

    test('fromMap falls back to light on unknown theme', () {
      final settings = AppSettings.fromMap(const {'theme': 'neon'});
      expect(settings.themeChoice, ThemeChoice.light);
    });

    test('missing finisseur tracking keys default to true', () {
      // Older databases never wrote these keys — make sure existing users
      // still see the new toggles enabled instead of silently disabled.
      final settings = AppSettings.fromMap(const {'theme': 'dark'});
      expect(settings.longDubbieTracking, isTrue);
      expect(settings.penaltyKubbTracking, isTrue);
      expect(settings.kingThrowTracking, isTrue);
      expect(settings.allowContinueBeyondSticks, isTrue);
    });

    test('round-trip via toMap and fromMap is identity-preserving', () {
      const original = AppSettings(
        themeChoice: ThemeChoice.highContrast,
        heliTracking: false,
        sniperEyeToggleHidden: true,
        longDubbieTracking: false,
        penaltyKubbTracking: false,
        kingThrowTracking: false,
        allowContinueBeyondSticks: false,
      );
      final restored = AppSettings.fromMap(original.toMap());
      expect(restored, original);
    });
  });
}
