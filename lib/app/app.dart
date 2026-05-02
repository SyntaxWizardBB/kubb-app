import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/app/router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

/// Temporary stub — replaced by AppSettingsNotifier in M3-T4.
final themeChoiceProvider = Provider<ThemeChoice>((ref) => ThemeChoice.light);

class KubbApp extends ConsumerWidget {
  const KubbApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(themeChoiceProvider);
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      routerConfig: appRouter,
      theme: choice.themeData(),
      darkTheme: KubbTheme.dark(),
      themeMode: choice.toThemeMode(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
    );
  }
}
