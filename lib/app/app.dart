import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/app/bootstrap.dart';
import 'package:kubb_app/app/realtime_lifecycle_controller.dart';
import 'package:kubb_app/app/router.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/theme_choice.dart';
import 'package:kubb_app/core/ui/widgets/kubb_offline_banner.dart';
import 'package:kubb_app/features/notifications/application/push_notifications_provider.dart';
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
    // Single production lifecycle path (FC-9 / ADR-0029 battery regime).
    // EVERY AppLifecycleState is routed into the RealtimeLifecycleController,
    // which owns the whole foreground/background sequence:
    //   - resumed  → re-sign FIRST (forceReSignWireSession), THEN resume the
    //                keypair refresher, THEN reconnect exactly the keys that
    //                were live at the last pause (avoids the Auth-Storm of a
    //                reconnect-before-resign).
    //   - paused   → after a 5 s debounce: snapshot + disconnectAll (zero
    //                sockets, zero timers) + pause the refresher.
    //   - detached → immediate teardown (no debounce).
    //   - inactive → no-op (transient OS overlay).
    // The re-sign and refresher-pause logic that used to live here as a
    // standalone onResume handler now flows through the controller's seams.
    _lifecycleListener = AppLifecycleListener(
      onStateChange: _onLifecycleStateChange,
    );
  }

  void _onLifecycleStateChange(AppLifecycleState state) {
    // The controller is null only when the wired adapter does not expose the
    // lifecycle mixin (e.g. a minimal test fake) — then there is nothing to
    // manage and we deliberately skip.
    final controller = ref.read(realtimeLifecycleControllerProvider);
    controller?.onLifecycleState(state);
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
        // Keep the FCM token lifecycle alive for the app's lifetime
        // (register on login / refresh, unregister on sign-out).
        ref.watch(pushNotificationsProvider);
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
