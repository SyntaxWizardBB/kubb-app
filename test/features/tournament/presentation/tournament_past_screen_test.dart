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
  WidgetTester tester, {
  List<TournamentSummaryRef> finalized = const [],
  List<TournamentSummaryRef> aborted = const [],
}) async {
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
            .overrideWith((_) async => finalized),
        tournamentListProvider(TournamentStatus.aborted)
            .overrideWith((_) async => aborted),
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
  testWidgets('lists finalized and aborted, hides the live/open/draft states',
      (tester) async {
    await _pump(
      tester,
      finalized: [
        _ref(id: 'a', name: 'Done-Cup', status: TournamentStatus.finalized),
        _ref(id: 'b', name: 'Live-Cup', status: TournamentStatus.live),
        _ref(id: 'c', name: 'Open-Cup',
            status: TournamentStatus.registrationOpen),
      ],
      aborted: [
        _ref(id: 'e', name: 'Aborted-Cup', status: TournamentStatus.aborted),
        _ref(id: 'd', name: 'Draft-Cup', status: TournamentStatus.draft),
      ],
    );

    expect(find.text('Done-Cup'), findsOneWidget);
    expect(find.text('Aborted-Cup'), findsOneWidget);
    // Slices are guarded client-side, so a mis-tagged row is dropped.
    expect(find.text('Live-Cup'), findsNothing);
    expect(find.text('Open-Cup'), findsNothing);
    expect(find.text('Draft-Cup'), findsNothing);
  });

  testWidgets('tapping a card pushes the detail route', (tester) async {
    await _pump(
      tester,
      finalized: [
        _ref(id: 'a', name: 'Done-Cup', status: TournamentStatus.finalized),
      ],
    );
    await tester.tap(find.text('Done-Cup'));
    await tester.pumpAndSettle();
    expect(find.text('detail-a'), findsOneWidget);
  });

  testWidgets('shows the empty state when nothing is finished', (tester) async {
    await _pump(tester);
    expect(find.byType(KubbEmptyState), findsOneWidget);
    expect(find.text('Noch keine vergangenen Turniere'), findsOneWidget);
  });
}
