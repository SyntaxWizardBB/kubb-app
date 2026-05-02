import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';

Future<KubbTokens> _pumpAndReadTokens(
  WidgetTester tester,
  ThemeData theme,
) async {
  late KubbTokens captured;
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) {
          captured = Theme.of(context).extension<KubbTokens>()!;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return captured;
}

void main() {
  group('KubbTheme', () {
    testWidgets('light exposes light tokens', (tester) async {
      final tokens = await _pumpAndReadTokens(tester, KubbTheme.light());
      expect(tokens.primary, const Color(0xFF3a7c2e));
      expect(tokens.bg, const Color(0xFFfbfaf6));
      expect(KubbTheme.light().brightness, Brightness.light);
      expect(ThemeChoice.light.toThemeMode(), ThemeMode.light);
    });

    testWidgets('dark exposes dark tokens', (tester) async {
      final tokens = await _pumpAndReadTokens(tester, KubbTheme.dark());
      expect(tokens.primary, const Color(0xFF569748));
      expect(tokens.bg, const Color(0xFF0c0b07));
      expect(KubbTheme.dark().brightness, Brightness.dark);
      expect(ThemeChoice.dark.toThemeMode(), ThemeMode.dark);
    });

    testWidgets('highContrast exposes HC tokens', (tester) async {
      final tokens =
          await _pumpAndReadTokens(tester, KubbTheme.highContrast());
      expect(tokens.bg, const Color(0xFFFFFFFF));
      expect(tokens.fg, const Color(0xFF000000));
      expect(tokens.primary, const Color(0xFF0F4A08));
      expect(KubbTheme.highContrast().brightness, Brightness.light);
      expect(ThemeChoice.highContrast.toThemeMode(), ThemeMode.light);
    });
  });
}
