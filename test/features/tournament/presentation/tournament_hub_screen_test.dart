import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_mode_card.dart';
import 'package:kubb_app/features/club/application/club_providers.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_hub_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';

Future<void> _pump(WidgetTester tester) async {
  final router = GoRouter(
    initialLocation: TournamentRoutes.hub,
    routes: [
      GoRoute(
        path: TournamentRoutes.hub,
        builder: (_, _) => const TournamentHubScreen(),
      ),
      GoRoute(
        path: TournamentRoutes.pastTournaments,
        builder: (_, _) => const Scaffold(body: Text('past-route')),
      ),
      GoRoute(
        path: TournamentRoutes.mercenaryMarket,
        builder: (_, _) => const Scaffold(body: Text('mercenary-route')),
      ),
      GoRoute(
        path: TournamentRoutes.ranking,
        builder: (_, _) => const Scaffold(body: Text('ranking-route')),
      ),
      GoRoute(
        path: TournamentRoutes.eloLeaderboard,
        builder: (_, _) => const Scaffold(body: Text('elo-route')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        canPublishTournamentProvider.overrideWith((_) async => false),
      ],
      child: MaterialApp.router(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the two new tiles in order before the stats tile',
      (tester) async {
    await _pump(tester);

    final past = find.text('Vergangene Turniere');
    final mercenary = find.text('Söldnermarkt');
    final stats = find.text('Turnierstatistik');

    expect(past, findsOneWidget);
    expect(mercenary, findsOneWidget);
    expect(stats, findsOneWidget);

    // Vertical order: past tile sits above the mercenary tile, which
    // sits above the stats tile.
    final pastY = tester.getTopLeft(past).dy;
    final mercenaryY = tester.getTopLeft(mercenary).dy;
    final statsY = tester.getTopLeft(stats).dy;
    expect(pastY, lessThan(mercenaryY));
    expect(mercenaryY, lessThan(statsY));
  });

  testWidgets(
      'ranking tile sits between the mercenary and the stats tile',
      (tester) async {
    await _pump(tester);

    final mercenary = find.text('Söldnermarkt');
    final ranking = find.text('Rangliste');
    final stats = find.text('Turnierstatistik');

    expect(mercenary, findsOneWidget);
    expect(ranking, findsOneWidget);
    expect(stats, findsOneWidget);

    // P8-Hub-B2: Söldnermarkt -> Rangliste -> Statistik.
    final mercenaryY = tester.getTopLeft(mercenary).dy;
    final rankingY = tester.getTopLeft(ranking).dy;
    final statsY = tester.getTopLeft(stats).dy;
    expect(mercenaryY, lessThan(rankingY));
    expect(rankingY, lessThan(statsY));
  });

  testWidgets('ranking tile pushes the ranking route', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Rangliste'));
    await tester.pumpAndSettle();
    expect(find.text('ranking-route'), findsOneWidget);
  });

  testWidgets('elo best-list tile sits between the ranking and the stats tile',
      (tester) async {
    await _pump(tester);

    final ranking = find.text('Rangliste');
    final elo = find.text('ELO-Bestenliste');
    final stats = find.text('Turnierstatistik');

    expect(ranking, findsOneWidget);
    expect(elo, findsOneWidget);
    expect(stats, findsOneWidget);

    // ELO_RATINGS §7: Rangliste -> ELO-Bestenliste -> Statistik.
    final rankingY = tester.getTopLeft(ranking).dy;
    final eloY = tester.getTopLeft(elo).dy;
    final statsY = tester.getTopLeft(stats).dy;
    expect(rankingY, lessThan(eloY));
    expect(eloY, lessThan(statsY));
  });

  testWidgets('elo best-list tile pushes the elo route', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('ELO-Bestenliste'));
    await tester.pumpAndSettle();
    expect(find.text('elo-route'), findsOneWidget);
  });

  testWidgets('mercenary tile carries a Coming Soon marker', (tester) async {
    await _pump(tester);
    expect(find.text('Coming Soon'), findsOneWidget);
  });

  testWidgets('past tile pushes the past-tournaments route', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Vergangene Turniere'));
    await tester.pumpAndSettle();
    expect(find.text('past-route'), findsOneWidget);
  });

  testWidgets('mercenary tile pushes the mercenary route', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Söldnermarkt'));
    await tester.pumpAndSettle();
    expect(find.text('mercenary-route'), findsOneWidget);
  });

  testWidgets('hub renders exactly seven mode-card tiles', (tester) async {
    await _pump(tester);
    // Registrations, Browse, Past, Mercenary, Rangliste, ELO best-list, Stats.
    expect(find.byType(KubbModeCard), findsNWidgets(7));
  });
}
