import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/app/router.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:logging/logging.dart';

final _bootstrapLog = Logger('Bootstrap');

class KubbApp extends ConsumerWidget {
  const KubbApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(appSettingsProvider);
    final choice = settingsAsync.when(
      data: (s) => s.themeChoice,
      loading: () => ThemeChoice.light,
      error: (_, _) => ThemeChoice.light,
    );
    final boot = ref.watch(appBootstrapProvider);
    return boot.when(
      loading: () => _bootstrapShell(choice, const _SplashScreen()),
      error: (e, st) {
        _bootstrapLog.severe('bootstrap failed', e, st);
        return _bootstrapShell(choice, const _BootstrapErrorScreen());
      },
      data: (_) {
        final router = ref.watch(goRouterProvider);
        return MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          routerConfig: router,
          theme: choice.themeData(),
          darkTheme: KubbTheme.dark(),
          themeMode: choice.toThemeMode(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }

  Widget _bootstrapShell(ThemeChoice choice, Widget home) {
    return MaterialApp(
      home: home,
      theme: choice.themeData(),
      darkTheme: KubbTheme.dark(),
      themeMode: choice.toThemeMode(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen();

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l.bootstrapErrorTitle,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                l.bootstrapErrorBody,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
