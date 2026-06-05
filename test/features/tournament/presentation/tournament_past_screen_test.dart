import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_past_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

TournamentSummaryRef _ref({
  required String id,
  required String name,
  required TournamentStatus status,
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

Future<void> _pump(
  WidgetTester tester,
  List<TournamentSummaryRef> rows,
) async {
  final router = GoRouter(
    initialLocation: '/tournament/past',
    routes: [
      GoRoute(
        path: '/tournament/past',
        builder: (_, _) => const TournamentPastScreen(),
      ),
      GoRoute(
        path: '/tournament/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail-${state.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentListProvider(TournamentStatus.finalized)
            .overrideWith((_) async => rows),
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
  testWidgets('shows only finalized tournaments and hides other states',
      (tester) async {
    await _pump(tester, [
      _ref(id: 'a', name: 'Done-Cup', status: TournamentStatus.finalized),
      _ref(id: 'b', name: 'Live-Cup', status: TournamentStatus.live),
      _ref(id: 'c', name: 'Open-Cup', status: TournamentStatus.registrationOpen),
      _ref(id: 'd', name: 'Draft-Cup', status: TournamentStatus.draft),
      _ref(id: 'e', name: 'Aborted-Cup', status: TournamentStatus.aborted),
    ]);

    expect(find.text('Done-Cup'), findsOneWidget);
    expect(find.text('Live-Cup'), findsNothing);
    expect(find.text('Open-Cup'), findsNothing);
    expect(find.text('Draft-Cup'), findsNothing);
    expect(find.text('Aborted-Cup'), findsNothing);
  });

  testWidgets('tapping a finalized card pushes the detail route',
      (tester) async {
    await _pump(tester, [
      _ref(id: 'a', name: 'Done-Cup', status: TournamentStatus.finalized),
    ]);
    await tester.tap(find.text('Done-Cup'));
    await tester.pumpAndSettle();
    expect(find.text('detail-a'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no finalized tournaments',
      (tester) async {
    await _pump(tester, const []);
    expect(find.byType(KubbEmptyState), findsOneWidget);
    expect(find.text('Noch keine vergangenen Turniere'), findsOneWidget);
  });
}
