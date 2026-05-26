import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';

class KubbTheme {
  const KubbTheme._();

  /// Font family bundled via `pubspec.yaml` (`assets/fonts/`).
  static const String fontFamily = 'BricolageGrotesque';

  static ThemeData light() => _build(KubbTokens.light, Brightness.light);

  static ThemeData dark() => _build(KubbTokens.dark, Brightness.dark);

  static ThemeData highContrast() =>
      _build(KubbTokens.highContrast, Brightness.light);

  static ThemeData _build(KubbTokens tokens, Brightness brightness) {
    final baseTextTheme = brightness == Brightness.dark
        ? Typography.whiteMountainView
        : Typography.blackMountainView;

    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: tokens.primary,
      onPrimary: tokens.onPrimary,
      secondary: tokens.accent,
      onSecondary: tokens.onAccent,
      error: tokens.danger,
      onError: tokens.onDanger,
      surface: tokens.bgRaised,
      onSurface: tokens.fg,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: tokens.bg,
      textTheme: baseTextTheme
          .apply(
            fontFamily: fontFamily,
            bodyColor: tokens.fg,
            displayColor: tokens.fg,
          ),
      extensions: <ThemeExtension<dynamic>>[tokens],
    );
  }
}
