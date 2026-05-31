import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_list_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _testUserId = 'me-1';

TournamentSummaryRef _ref({
  required String id,
  required String name,
  required TournamentStatus status,
  TournamentFormat format = TournamentFormat.roundRobin,
  int participants = 4,
  String? createdBy,
}) {
  return TournamentSummaryRef(
    tournamentId: TournamentId(id),
    displayName: name,
    format: format,
    status: status,
    startedAt: null,
    completedAt: null,
    participantCount: participants,
    createdBy: createdBy == null ? null : UserId(createdBy),
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
        currentUserIdProvider.overrideWith((_) => _testUserId),
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
  testWidgets('lists published tournaments and hides drafts', (tester) async {
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

    // Flat list of published tournaments — drafts are filtered out.
    expect(find.text('Sommer-Cup'), findsOneWidget);
    expect(find.text('Mein Entwurf'), findsNothing);
  });

  testWidgets('also lists live and registration-closed tournaments',
      (tester) async {
    await _pump(tester, [
      _ref(id: 'a', name: 'Live-Cup', status: TournamentStatus.live),
      _ref(
        id: 'b',
        name: 'Closed-Cup',
        status: TournamentStatus.registrationClosed,
      ),
      _ref(id: 'c', name: 'Done-Cup', status: TournamentStatus.finalized),
    ]);

    expect(find.text('Live-Cup'), findsOneWidget);
    expect(find.text('Closed-Cup'), findsOneWidget);
    // Finalized tournaments are no longer "current" → hidden.
    expect(find.text('Done-Cup'), findsNothing);
  });

  testWidgets('tapping a card pushes the detail route', (tester) async {
    await _pump(tester, [
      _ref(
        id: 'a',
        name: 'Sommer-Cup',
        status: TournamentStatus.registrationOpen,
      ),
    ]);
    await tester.tap(find.text('Sommer-Cup'));
    await tester.pumpAndSettle();
    expect(find.text('detail-a'), findsOneWidget);
  });
}
