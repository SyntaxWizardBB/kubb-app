import 'package:flutter/material.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';

enum ThemeChoice {
  light,
  dark,
  highContrast;

  ThemeMode toThemeMode() => switch (this) {
        ThemeChoice.light || ThemeChoice.highContrast => ThemeMode.light,
        ThemeChoice.dark => ThemeMode.dark,
      };

  ThemeData themeData() => switch (this) {
        ThemeChoice.light => KubbTheme.light(),
        ThemeChoice.dark => KubbTheme.dark(),
        ThemeChoice.highContrast => KubbTheme.highContrast(),
      };
}
