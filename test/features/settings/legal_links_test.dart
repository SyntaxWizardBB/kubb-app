import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_controller.dart';
import 'package:kubb_app/features/auth/application/auth_session.dart';
import 'package:kubb_app/features/legal/presentation/imprint_screen.dart';
import 'package:kubb_app/features/legal/presentation/privacy_policy_screen.dart';
import 'package:kubb_app/features/settings/presentation/settings_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../_helpers/sqlite_open.dart';

class _StubAuthController extends AuthController {
  _StubAuthController(this._initial);
  final AuthSession _initial;

  @override
  Future<AuthSession> build() async => _initial;

  @override
  Future<void> signOut() async {
    state = const AsyncData(AuthSession.signedOut());
  }
}

void main() {
  late AppDatabase db;

  setUpAll(() {
    registerLinuxSqliteOverride();
    GoogleFonts.config.allowRuntimeFetching = false;
    TestWidgetsFlutterBinding.ensureInitialized();
    PackageInfo.setMockInitialValues(
      appName: 'kubb_app',
      packageName: 'app.kubb',
      version: '0.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() async {
    db = await openTestDatabase();
    await db.playerDao.insert(
      PlayersCompanion(
        id: const Value('p1'),
        name: const Value('Lukas'),
        deviceId: const Value('device-abc-123'),
        createdAt: Value(DateTime.utc(2026, 5)),
      ),
    );
    // Asset-Override fuer beide Legal-Screens, damit der Tap-Pfad nicht
    // am realen rootBundle-Lookup haengt.
    PrivacyPolicyScreen.loaderOverride =
        () async => '# Datenschutzerklärung\n\nFake.';
    ImprintScreen.loaderOverride = () async => '# Impressum\n\nFake.';
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (_, _) => const SettingsScreen(),
        ),
        GoRoute(path: '/profile', builder: (_, _) => const Placeholder()),
        GoRoute(path: '/stats', builder: (_, _) => const Placeholder()),
        GoRoute(
          path: '/legal/privacy',
          builder: (_, _) => const PrivacyPolicyScreen(),
        ),
        GoRoute(
          path: '/legal/imprint',
          builder: (_, _) => const ImprintScreen(),
        ),
        GoRoute(
          path: '/sign-in/account-link',
          builder: (_, _) => const Placeholder(),
        ),
        GoRoute(
          path: '/sign-in/passphrase-change',
          builder: (_, _) => const Placeholder(),
        ),
        GoRoute(
          path: '/sign-in/delete',
          builder: (_, _) => const Placeholder(),
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authControllerProvider.overrideWith(
            () => _StubAuthController(
              const AuthSession.keypair(userId: 'p1', displayName: 'Lukas'),
            ),
          ),
        ],
        child: MaterialApp.router(
          theme: KubbTheme.light(),
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('settings App-Section listet Datenschutz und Impressum',
      (tester) async {
    await pump(tester);

    expect(find.text('Datenschutz'), findsWidgets);
    expect(find.text('Impressum'), findsOneWidget);
  });

  testWidgets('Tap auf Impressum oeffnet Impressum-Screen', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Impressum'));
    await tester.pumpAndSettle();

    // Heading des Impressum-Screens ist sichtbar.
    expect(find.text('Impressum'), findsWidgets);
    // Loader-Override liefert „Fake.“ — also rendert der MarkdownBody.
    expect(find.text('Fake.'), findsOneWidget);
  });

  testWidgets('Tap auf Datenschutz oeffnet Privacy-Policy-Screen',
      (tester) async {
    await pump(tester);

    // Mehrere "Datenschutz"-Treffer existieren (Header-Block + neue Row).
    // Die letzte ist die tappable Row direkt ueber der Version-Zeile.
    await tester.tap(find.text('Datenschutz').last);
    await tester.pumpAndSettle();

    expect(find.text('Datenschutzerklärung'), findsWidgets);
    expect(find.text('Fake.'), findsOneWidget);
  });
}
