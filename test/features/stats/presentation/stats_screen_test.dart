import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/stats/application/stats_aggregate_provider.dart';
import 'package:kubb_app/features/stats/application/stats_filter_notifier.dart';
import 'package:kubb_app/features/stats/data/stats_aggregate.dart';
import 'package:kubb_app/features/stats/presentation/stats_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:lucide_icons/lucide_icons.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required StatsAggregate aggregate,
    FinisseurStatsAggregate? finisseur,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statsAggregateProvider.overrideWith((ref) async => aggregate),
          finisseurStatsAggregateProvider.overrideWith(
            (ref) async => finisseur ?? FinisseurStatsAggregate.empty(),
          ),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const StatsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  StatsAggregate makeAgg({int sessions = 3}) => StatsAggregate(
        totalSessions: sessions,
        totalThrows: sessions * 10,
        hitRatePercent: 64,
        longestHitStreak: 7,
        bestHitRatePercent: 88,
        bestHitRateDistance: 4.5,
        mostThrowsInOneDay: 42,
        trendPoints: List.generate(sessions, (i) => 50 + i * 5),
        sessionRows: List.generate(
          sessions,
          (i) => StatsSessionRow(
            sessionId: 's$i',
            completedAt: DateTime.utc(2026, 5, 2 - i),
            distanceMeters: 8,
            hitRatePercent: 50 + i * 5,
            totalThrows: 10,
          ),
        ),
      );

  testWidgets('shows empty state when aggregate is empty', (tester) async {
    await pump(tester, aggregate: StatsAggregate.empty());

    expect(find.text('Noch keine Sessions'), findsOneWidget);
    // Hero numbers should not appear.
    expect(find.text('0 %'), findsNothing);
  });

  testWidgets('renders aggregate hero, bests and session list when data exists',
      (tester) async {
    await pump(tester, aggregate: makeAgg());

    expect(find.text('64'), findsOneWidget);
    expect(find.text('Längste Serie'.toUpperCase()), findsOneWidget);
    // Best rate row formatted with distance.
    expect(find.textContaining('88 %'), findsWidgets);
    // Session list rows.
    expect(find.text('8.0 m'), findsWidgets);
  });

  testWidgets('changing distance range triggers a recompute', (tester) async {
    final container = ProviderContainer(
      overrides: [
        statsAggregateProvider.overrideWith((ref) async {
          final filter = ref.watch(statsFilterProvider);
          return filter.isDistanceFullRange
              ? makeAgg()
              : StatsAggregate.empty();
        }),
        finisseurStatsAggregateProvider.overrideWith(
          (ref) async => FinisseurStatsAggregate.empty(),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          home: const StatsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Initially: data visible.
    expect(find.text('64'), findsOneWidget);
    expect(find.text('Noch keine Sessions'), findsNothing);

    // Narrow the distance range away from the full default.
    container.read(statsFilterProvider.notifier).setDistanceRange(4, 5);
    await tester.pumpAndSettle();

    expect(find.text('Noch keine Sessions'), findsOneWidget);
  });

  testWidgets('renders sniper and finisseur tabs', (tester) async {
    await pump(tester, aggregate: makeAgg());
    expect(find.text('Sniper'), findsOneWidget);
    expect(find.text('Finisseur'), findsOneWidget);
  });

  testWidgets('switching to finisseur tab shows finisseur metrics',
      (tester) async {
    await pump(
      tester,
      aggregate: makeAgg(),
      finisseur: FinisseurStatsAggregate(
        totalSessions: 4,
        successCount: 3,
        totalSticks: 18,
        missSticks: 2,
        longDubbiesPerSession: 1.25,
        heliCount: 2,
        penaltyCount: 1,
        kingAttempts: 4,
        kingHits: 3,
        successTrendPercent: const [0, 100, 100, 100],
        sessionRows: [
          FinisseurSessionRow(
            sessionId: 'fa',
            completedAt: DateTime.utc(2026, 5, 9),
            field: 7,
            base: 3,
            sticksUsed: 5,
            success: true,
          ),
        ],
      ),
    );

    await tester.tap(find.text('Finisseur'));
    await tester.pumpAndSettle();

    expect(find.text('75 %'), findsWidgets); // success rate
    expect(find.text('Letzte Finisseurs'.toUpperCase()), findsOneWidget);
    expect(find.text('7/3'), findsOneWidget);
  });

  testWidgets('back button routes to home when stats was reached via go',
      (tester) async {
    final router = GoRouter(
      initialLocation: '/stats',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('HOME')),
        ),
        GoRoute(
          path: '/stats',
          builder: (_, _) => const StatsScreen(),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statsAggregateProvider.overrideWith((ref) async => makeAgg()),
          finisseurStatsAggregateProvider.overrideWith(
            (ref) async => FinisseurStatsAggregate.empty(),
          ),
        ],
        child: MaterialApp.router(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('de'),
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Back button must be wired even when canPop() is false (route replace).
    final backFinder = find.byIcon(LucideIcons.arrowLeft);
    expect(backFinder, findsOneWidget);
    await tester.tap(backFinder);
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
  });
}
