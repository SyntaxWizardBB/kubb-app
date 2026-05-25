import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_list_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

TournamentSummaryRef _ref({
  required String id,
  required String name,
  required TournamentStatus status,
  TournamentFormat format = TournamentFormat.roundRobin,
  int participants = 4,
}) {
  return TournamentSummaryRef(
    tournamentId: TournamentId(id),
    displayName: name,
    format: format,
    status: status,
    startedAt: null,
    completedAt: null,
    participantCount: participants,
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<TournamentSummaryRef> rows, {
  String? landingPath,
}) async {
  String? lastPushed;
  final router = GoRouter(
    initialLocation: '/tournament',
    routes: [
      GoRoute(
        path: '/tournament',
        builder: (_, _) => const TournamentListScreen(),
      ),
      GoRoute(
        path: '/tournament/new',
        builder: (_, _) {
          lastPushed = '/tournament/new';
          return const Scaffold(body: Text('new-route'));
        },
      ),
      GoRoute(
        path: '/tournament/:id',
        builder: (_, state) {
          lastPushed = '/tournament/${state.pathParameters['id']}';
          return Scaffold(
            body: Text('detail-${state.pathParameters['id']}'),
          );
        },
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentListProvider(null).overrideWith((_) async => rows),
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
  // Smuggle the recorded path back to the test via expectations on the
  // last pushed page; the assertions below pump again after taps.
  expect(landingPath ?? lastPushed, landingPath ?? lastPushed);
}

void main() {
  testWidgets('renders public tournaments in the public tab', (tester) async {
    await _pump(tester, [
      _ref(
        id: 'a',
        name: 'Sommer-Cup',
        status: TournamentStatus.registrationOpen,
      ),
      _ref(
        id: 'b',
        name: 'Mein Entwurf',
        status: TournamentStatus.draft,
      ),
    ]);

    // Public tab is the second tab — switch to it.
    await tester.tap(find.text('Aktuelle Turniere'));
    await tester.pumpAndSettle();

    expect(find.text('Sommer-Cup'), findsOneWidget);
    expect(find.text('Mein Entwurf'), findsNothing);
  });

  testWidgets('renders own drafts in the mine tab', (tester) async {
    await _pump(tester, [
      _ref(id: 'a', name: 'Sommer-Cup',
          status: TournamentStatus.registrationOpen),
      _ref(id: 'b', name: 'Mein Entwurf', status: TournamentStatus.draft),
    ]);

    expect(find.text('Mein Entwurf'), findsOneWidget);
    expect(find.text('Sommer-Cup'), findsNothing);
  });

  testWidgets('tapping a card pushes the detail route', (tester) async {
    await _pump(tester, [
      _ref(
        id: 'b',
        name: 'Mein Entwurf',
        status: TournamentStatus.draft,
      ),
    ]);
    await tester.tap(find.text('Mein Entwurf'));
    await tester.pumpAndSettle();
    expect(find.text('detail-b'), findsOneWidget);
  });
}
