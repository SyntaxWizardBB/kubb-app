import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/app/router.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';
import 'package:kubb_app/core/ui/widgets/kubb_offline_banner.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:logging/logging.dart';

final _bootstrapLog = Logger('Bootstrap');

class _AppConfig {
  const _AppConfig({
    required this.theme,
    required this.darkTheme,
    required this.themeMode,
  });

  final ThemeData theme;
  final ThemeData darkTheme;
  final ThemeMode themeMode;
}

_AppConfig _resolveConfig(WidgetRef ref) {
  final choice = ref.watch(appSettingsProvider).maybeWhen(
        data: (s) => s.themeChoice,
        orElse: () => ThemeChoice.light,
      );
  return _AppConfig(
    theme: choice.themeData(),
    darkTheme: KubbTheme.dark(),
    themeMode: choice.toThemeMode(),
  );
}

class KubbApp extends ConsumerStatefulWidget {
  const KubbApp({super.key});

  @override
  ConsumerState<KubbApp> createState() => _KubbAppState();
}

class _KubbAppState extends ConsumerState<KubbApp> {
  AppLifecycleListener? _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // Proactive keypair re-sign on foreground. The Phase-1 keypair JWT
    // has a fixed lifetime and no refresh token (ADR-0010); the
    // KeypairSessionRefresher timer is paused while the app is
    // backgrounded, so a token that expires during suspension stays
    // stale on resume and the first authenticated RPC (e.g. "Meine
    // Teams") fails with PGRST303. Re-signing on resume re-mints the
    // wire session before the user navigates anywhere. `force: true`
    // bypasses the `wireAccessToken != null` short-circuit because a
    // stale-but-present token would otherwise be treated as live.
    _lifecycleListener = AppLifecycleListener(
      onResume: () {
        unawaited(_reSignOnResume());
      },
    );
  }

  Future<void> _reSignOnResume() async {
    try {
      await ref.read(forceReSignWireSessionProvider)();
    } on Object catch (e, st) {
      // Best-effort: a failed re-sign must not crash the app. The
      // per-RPC guard in TeamRepository remains the safety net.
      _bootstrapLog.warning('resume re-sign failed', e, st);
    }
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final config = _resolveConfig(ref);
    final boot = ref.watch(appBootstrapProvider);
    return boot.when(
      loading: () => _bootstrapShell(config, const _SplashScreen()),
      error: (e, st) {
        _bootstrapLog.severe('bootstrap failed', e, st);
        return _bootstrapShell(config, const _BootstrapErrorScreen());
      },
      data: (_) {
        final router = ref.watch(goRouterProvider);
        return MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
          routerConfig: router,
          theme: config.theme,
          darkTheme: config.darkTheme,
          themeMode: config.themeMode,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          debugShowCheckedModeBanner: false,
          builder: (context, child) => Column(
            children: [
              const KubbOfflineBanner(),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
        );
      },
    );
  }

  Widget _bootstrapShell(_AppConfig config, Widget home) {
    return MaterialApp(
      home: home,
      theme: config.theme,
      darkTheme: config.darkTheme,
      themeMode: config.themeMode,
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
