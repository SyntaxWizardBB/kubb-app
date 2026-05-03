import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/stats/application/stats_aggregate_provider.dart';
import 'package:kubb_app/features/stats/application/stats_filter_notifier.dart';
import 'package:kubb_app/features/stats/data/stats_aggregate.dart';
import 'package:kubb_app/features/stats/presentation/stats_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required StatsAggregate aggregate,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          statsAggregateProvider.overrideWith((ref) async => aggregate),
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

  testWidgets('changing distance filter triggers a recompute', (tester) async {
    final container = ProviderContainer(
      overrides: [
        statsAggregateProvider.overrideWith((ref) async {
          final filter = ref.watch(statsFilterProvider);
          return filter.distanceMeters == null
              ? makeAgg()
              : StatsAggregate.empty();
        }),
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

    // Mutate the filter — pick the 4.0 m chip.
    container.read(statsFilterProvider.notifier).setDistance(4);
    await tester.pumpAndSettle();

    expect(find.text('Noch keine Sessions'), findsOneWidget);
  });
}
