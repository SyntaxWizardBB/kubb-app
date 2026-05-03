import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/settings/presentation/settings_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../_helpers/sqlite_open.dart';

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

  Future<void> pump(WidgetTester tester) async {
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
      ],
    );
    final player = Player(
      id: 'p1',
      name: 'Lukas',
      deviceId: 'device-abc-123',
      createdAt: DateTime.utc(2026, 5),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          currentProfileProvider.overrideWith((ref) => Stream.value(player)),
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
    await tester.pump();
  }

  testWidgets('renders profile header and three sections', (tester) async {
    await pump(tester);
    await tester.pump();

    expect(find.text('Lukas'), findsOneWidget);
    expect(find.textContaining('device-abc-123'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Daten'), findsOneWidget);
    expect(find.text('App'), findsOneWidget);
    expect(find.text('Profil löschen'), findsOneWidget);
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
    await tester.pump();
    await tester.tap(find.text('Sessions zurücksetzen'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Sessions löschen?'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pump();
    await tester.pump();

    final remaining = await db.sessionDao.allCompletedForPlayer('p1');
    expect(remaining, hasLength(1));
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
    await tester.pump();
    await tester.tap(find.text('Sessions zurücksetzen'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Löschen'));
    await tester.pump();
    await tester.pump();

    final remaining = await db.sessionDao.allCompletedForPlayer('p1');
    expect(remaining, isEmpty);
  });

  testWidgets('confirm on profile delete removes player', (tester) async {
    await pump(tester);
    await tester.pump();
    await tester.tap(find.text('Profil löschen'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Profil löschen?'), findsOneWidget);
    await tester.tap(find.text('Löschen'));
    await tester.pump();
    await tester.pump();

    final players = await db.playerDao.all();
    expect(players, isEmpty);
  });
}
