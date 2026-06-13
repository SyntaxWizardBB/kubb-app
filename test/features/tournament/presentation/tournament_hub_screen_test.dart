import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_mode_card.dart';
import 'package:kubb_app/features/organizer_team/application/organizer_team_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_hub_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

TournamentSummaryRef _ref({
  required String id,
  required String name,
  TournamentStatus status = TournamentStatus.live,
}) {
  return TournamentSummaryRef(
    tournamentId: TournamentId(id),
    displayName: name,
    format: TournamentFormat.roundRobin,
    status: status,
    startedAt: null,
    completedAt: null,
    participantCount: 4,
  );
}

MyTournamentRegistration _reg(
  TournamentSummaryRef t, {
  TournamentParticipantStatus status = TournamentParticipantStatus.approved,
}) =>
    MyTournamentRegistration(
      tournament: t,
      participantId: TournamentParticipantId('p-${t.tournamentId.value}'),
      status: status,
    );

Future<void> _pump(
  WidgetTester tester, {
  List<MyTournamentRegistration> myRegistrations = const [],
}) async {
  final router = GoRouter(
    initialLocation: TournamentRoutes.hub,
    routes: [
      GoRoute(
        path: TournamentRoutes.hub,
        builder: (_, _) => const TournamentHubScreen(),
      ),
      GoRoute(
        path: '/tournament/:id/live',
        builder: (_, state) =>
            Scaffold(body: Text('live-${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: TournamentRoutes.list,
        builder: (_, _) => const Scaffold(body: Text('list-route')),
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
        myTournamentRegistrationsProvider
            .overrideWith((_) async => myRegistrations),
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
  testWidgets('renders the live + upcoming tiles with the new titles',
      (tester) async {
    await _pump(tester);
    expect(find.text('Live Turniere'), findsOneWidget);
    expect(find.text('Künftige Turniere'), findsOneWidget);
    // Old titles are gone.
    expect(find.text('Angemeldete Turniere'), findsNothing);
    expect(find.text('Aktuelle Turniere'), findsNothing);
  });

  testWidgets('upcoming tile pushes the discovery list route', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Künftige Turniere'));
    await tester.pumpAndSettle();
    expect(find.text('list-route'), findsOneWidget);
  });

  testWidgets(
      'live tile with exactly one live tournament pushes the live view',
      (tester) async {
    await _pump(
      tester,
      myRegistrations: [_reg(_ref(id: 'only', name: 'Solo-Live'))],
    );
    await tester.tap(find.text('Live Turniere'));
    await tester.pumpAndSettle();
    expect(find.text('live-only'), findsOneWidget);
  });

  testWidgets(
      'live tile with several live tournaments shows a picker that '
      'routes to the chosen live view', (tester) async {
    await _pump(
      tester,
      myRegistrations: [
        _reg(_ref(id: 'a', name: 'Cup-A')),
        _reg(_ref(id: 'b', name: 'Cup-B')),
      ],
    );
    await tester.tap(find.text('Live Turniere'));
    await tester.pumpAndSettle();

    // Picker lists both live tournaments.
    expect(find.text('Live Turnier wählen'), findsOneWidget);
    expect(find.text('Cup-A'), findsOneWidget);
    expect(find.text('Cup-B'), findsOneWidget);

    await tester.tap(find.text('Cup-B'));
    await tester.pumpAndSettle();
    expect(find.text('live-b'), findsOneWidget);
  });

  testWidgets('live tile with no live tournament shows the empty state',
      (tester) async {
    // A non-live registration must NOT count as live.
    await _pump(
      tester,
      myRegistrations: [
        _reg(_ref(
          id: 'reg',
          name: 'Angemeldet',
          status: TournamentStatus.registrationOpen,
        )),
      ],
    );
    await tester.tap(find.text('Live Turniere'));
    await tester.pumpAndSettle();
    expect(find.text('Kein laufendes Turnier'), findsOneWidget);
  });

  testWidgets(
      'live tile ignores a withdrawn registration of a live tournament',
      (tester) async {
    // Withdrawn from a tournament that later went live: it must NOT be
    // treated as live (no auto-push into the H3 view).
    await _pump(
      tester,
      myRegistrations: [
        _reg(
          _ref(id: 'gone', name: 'Ausgestiegen'),
          status: TournamentParticipantStatus.withdrawn,
        ),
      ],
    );
    await tester.tap(find.text('Live Turniere'));
    await tester.pumpAndSettle();
    expect(find.text('Kein laufendes Turnier'), findsOneWidget);
    expect(find.text('live-gone'), findsNothing);
  });

  testWidgets('ranking tile pushes the ranking route', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('Rangliste'));
    await tester.pumpAndSettle();
    expect(find.text('ranking-route'), findsOneWidget);
  });

  testWidgets('mercenary tile carries a Coming Soon marker', (tester) async {
    await _pump(tester);
    expect(find.text('Coming Soon'), findsOneWidget);
  });

  testWidgets('hub renders exactly eight mode-card tiles', (tester) async {
    await _pump(tester);
    // Live, Upcoming, Past, Mercenary, Rangliste, ELO best-list,
    // Stufen-Graph (ADR-0030 §Editor), Stats.
    expect(find.byType(KubbModeCard), findsNWidgets(8));
  });
}
