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
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> pump(
    WidgetTester tester, {
    AuthSession session = const AuthSession.keypair(
      userId: 'p1',
      displayName: 'Lukas',
    ),
  }) async {
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
        GoRoute(path: '/onboarding', builder: (_, _) => const Placeholder()),
        GoRoute(path: '/profile', builder: (_, _) => const Placeholder()),
        GoRoute(path: '/stats', builder: (_, _) => const Placeholder()),
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
        GoRoute(
          path: '/legal/privacy',
          builder: (_, _) => const Scaffold(
            body: Center(child: Text('Privacy Policy Stub')),
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          authControllerProvider.overrideWith(
            () => _StubAuthController(session),
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

  testWidgets('renders account section and the data + app sections', (tester) async {
    await pump(tester);

    expect(find.text('Lukas'), findsOneWidget);
    expect(find.text('Konto'), findsOneWidget);
    expect(find.text('Daten'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('Sessions zurücksetzen'), findsOneWidget);
    expect(find.text('CSV-Export'), findsOneWidget);
  });

  testWidgets('cancel on reset confirm leaves sessions intact', (tester) async {
    await db.sessionDao.insert(
      SessionsCompanion(
        id: const Value('s1'),
        playerId: const Value('p1'),
        kind: const Value('sniper'),
        mode: const Value('sniper'),
        distanceMeters: const Value(8),
        status: const Value('completed'),
        startedAt: Value(DateTime.utc(2026, 5, 2)),
        completedAt: Value(DateTime.utc(2026, 5, 2)),
      ),
    );

    await pump(tester);
    await tester.tap(find.text('Sessions zurücksetzen'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Sessions löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pump();
    await tester.pump();

    final remaining = await db.sessionDao.allCompletedForUser('p1');
    expect(remaining, hasLength(1));
  });

  testWidgets(
      'renders account section for OAuth-Google session (composition smoke)',
      (tester) async {
    await pump(
      tester,
      session: const AuthSession.oauth(
        userId: 'p1',
        displayName: 'Lukas',
        provider: AuthProvider.google,
      ),
    );

    expect(find.text('Konto'), findsOneWidget);
    expect(find.text('Google'), findsWidgets);
    expect(find.text('Daten'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('Sessions zurücksetzen'), findsOneWidget);
  });

  testWidgets('privacy section shows synced-data copy and link to /legal/privacy',
      (tester) async {
    await pump(tester);

    await tester.scrollUntilVisible(
      find.text('Datenschutzerklärung öffnen'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Supabase-Backend in der EU synchronisiert'),
      findsOneWidget,
    );
    expect(find.text('Datenschutzerklärung öffnen'), findsOneWidget);

    await tester.tap(find.text('Datenschutzerklärung öffnen'));
    await tester.pumpAndSettle();

    expect(find.text('Privacy Policy Stub'), findsOneWidget);
  });

  testWidgets('confirm on reset deletes all sessions', (tester) async {
    await db.sessionDao.insert(
      SessionsCompanion(
        id: const Value('s1'),
        playerId: const Value('p1'),
        kind: const Value('sniper'),
        mode: const Value('sniper'),
        distanceMeters: const Value(8),
        status: const Value('completed'),
        startedAt: Value(DateTime.utc(2026, 5, 2)),
        completedAt: Value(DateTime.utc(2026, 5, 2)),
      ),
    );

    await pump(tester);
    await tester.tap(find.text('Sessions zurücksetzen'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Löschen'));
    await tester.pump();
    await tester.pump();

    final remaining = await db.sessionDao.allCompletedForUser('p1');
    expect(remaining, isEmpty);
  });
}
