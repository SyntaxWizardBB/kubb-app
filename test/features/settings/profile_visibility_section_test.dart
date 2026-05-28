// Sprint-C W2-T2: Widget-Tests fuer die Profile-Visibility-Section
// im Settings-Screen. Deckt den Picker-Tap- und Save-Flow plus die
// Provider-Invalidation nach dem Save ab.
//
// Refs: R20-F-02 (FR-AUTH-5, DSGVO Art. 25), R20-F-10 (FR-SOCIAL-4).

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
import 'package:kubb_app/features/auth/application/cloud_profile_provider.dart';
import 'package:kubb_app/features/settings/presentation/settings_screen.dart';
import 'package:kubb_app/features/settings/presentation/widgets/profile_visibility_section.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../_helpers/sqlite_open.dart';
import '../../fixtures/auth/fake_cloud_profile_repository.dart';

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
  late FakeCloudProfileRepository fakeProfileRepo;

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
    fakeProfileRepo = FakeCloudProfileRepository();
    // Seed the profile row so the picker has a concrete tier to render.
    await fakeProfileRepo.ensureProfile(
      userId: 'p1',
      nickname: 'Lukas',
    );
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
          builder: (_, _) => const Scaffold(body: Placeholder()),
        ),
        GoRoute(
          path: '/legal/imprint',
          builder: (_, _) => const Scaffold(body: Placeholder()),
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
          cloudProfileRepositoryProvider.overrideWithValue(fakeProfileRepo),
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

  testWidgets('renders the friends-only tier as the default subtitle',
      (tester) async {
    await pump(tester);

    expect(find.byKey(ProfileVisibilitySection.rowKey), findsOneWidget);
    expect(find.text('Profil-Sichtbarkeit'), findsOneWidget);
    // Friends-only ist der Privacy-Floor: neue Accounts starten hier.
    expect(find.text('Nur Freunde'), findsOneWidget);
  });

  testWidgets(
    'tapping the row opens the picker and saving public writes through',
    (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(ProfileVisibilitySection.rowKey));
      await tester.pumpAndSettle();

      // Picker zeigt alle drei Tiers.
      expect(
        find.byKey(ProfileVisibilitySection.optionKey(ProfileVisibility.public)),
        findsOneWidget,
      );
      expect(
        find.byKey(ProfileVisibilitySection.optionKey(
          ProfileVisibility.friendsOnly,
        )),
        findsOneWidget,
      );
      expect(
        find.byKey(ProfileVisibilitySection.optionKey(ProfileVisibility.private)),
        findsOneWidget,
      );

      // Public auswaehlen und auf Save-Flow + Snackbar warten.
      await tester.tap(
        find.byKey(ProfileVisibilitySection.optionKey(ProfileVisibility.public)),
      );
      await tester.pumpAndSettle();

      // Repo wurde mit dem neuen Tier aufgerufen.
      expect(fakeProfileRepo.updateCount, 1);
      final saved = await fakeProfileRepo.getProfile(userId: 'p1');
      expect(saved?.visibility, ProfileVisibility.public);

      // Snackbar bestaetigt die Speicherung.
      expect(find.text('Sichtbarkeit gespeichert'), findsOneWidget);

      // Nach der Provider-Invalidation reflektiert die Row den neuen Tier
      // ohne Neustart.
      expect(find.text('Öffentlich'), findsOneWidget);
    },
  );

  testWidgets('selecting the current tier is a no-op (no repo write)',
      (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(ProfileVisibilitySection.rowKey));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(ProfileVisibilitySection.optionKey(
        ProfileVisibility.friendsOnly,
      )),
    );
    await tester.pumpAndSettle();

    expect(fakeProfileRepo.updateCount, 0);
    // No snackbar surfaced because nothing actually changed.
    expect(find.text('Sichtbarkeit gespeichert'), findsNothing);
  });
}
