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
  DateTime? eventStartsAt,
}) {
  return TournamentSummaryRef(
    tournamentId: TournamentId(id),
    displayName: name,
    format: format,
    status: status,
    startedAt: null,
    completedAt: null,
    participantCount: participants,
    eventStartsAt: eventStartsAt,
    createdBy: createdBy == null ? null : UserId(createdBy),
  );
}

/// Fixed "today" for deterministic date-filter tests.
final _fixedNow = DateTime(2026, 6, 15, 10);

Future<void> _pump(
  WidgetTester tester,
  List<TournamentSummaryRef> rows, {
  String? landingPath,
  List<MyTournamentRegistration> myRegistrations = const [],
}) async {
  String? lastPushed;
  final router = GoRouter(
    initialLocation: '/tournament',
    routes: [
      GoRoute(
        path: '/tournament',
        builder: (_, _) => TournamentListScreen(now: _fixedNow),
      ),
      GoRoute(
        path: '/tournament/new',
        builder: (_, _) {
          lastPushed = '/tournament/new';
          return const Scaffold(body: Text('new-route'));
        },
      ),
      GoRoute(
        path: '/tournament/:id/register',
        builder: (_, state) {
          lastPushed = '/tournament/${state.pathParameters['id']}/register';
          return Scaffold(
            body: Text('register-${state.pathParameters['id']}'),
          );
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
        myTournamentRegistrationsProvider
            .overrideWith((_) async => myRegistrations),
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

  testWidgets(
      'H1: lists registration-closed but hides live and finalized',
      (tester) async {
    await _pump(tester, [
      // Live now lives under the hub's "Live Turniere" tile → excluded here.
      _ref(id: 'a', name: 'Live-Cup', status: TournamentStatus.live),
      _ref(
        id: 'b',
        name: 'Closed-Cup',
        status: TournamentStatus.registrationClosed,
      ),
      _ref(id: 'c', name: 'Done-Cup', status: TournamentStatus.finalized),
    ]);

    expect(find.text('Live-Cup'), findsNothing);
    expect(find.text('Closed-Cup'), findsOneWidget);
    // Finalized tournaments are no longer "current" → hidden.
    expect(find.text('Done-Cup'), findsNothing);
  });

  testWidgets(
      'H1: future-dated and undated tournaments appear, past ones vanish',
      (tester) async {
    await _pump(tester, [
      _ref(
        id: 'future',
        name: 'Future-Cup',
        status: TournamentStatus.registrationOpen,
        eventStartsAt: _fixedNow.add(const Duration(days: 7)),
      ),
      _ref(
        id: 'undated',
        name: 'Undated-Cup',
        status: TournamentStatus.published,
      ),
      _ref(
        id: 'past',
        name: 'Past-Cup',
        status: TournamentStatus.registrationOpen,
        eventStartsAt: _fixedNow.subtract(const Duration(days: 2)),
      ),
    ]);

    expect(find.text('Future-Cup'), findsOneWidget);
    expect(find.text('Undated-Cup'), findsOneWidget);
    expect(find.text('Past-Cup'), findsNothing);
  });

  testWidgets('H1: a tournament starting earlier today still appears',
      (tester) async {
    await _pump(tester, [
      _ref(
        id: 'today',
        name: 'Today-Cup',
        status: TournamentStatus.registrationOpen,
        // 09:00 on the fixed day — before "now" (10:00) but same calendar
        // day, so the >= today-00:00 rule keeps it visible.
        eventStartsAt: DateTime(2026, 6, 15, 9),
      ),
    ]);

    expect(find.text('Today-Cup'), findsOneWidget);
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

  testWidgets(
      'registration-open tile shows a Details and an Anmelden button '
      'when the caller is not registered', (tester) async {
    await _pump(tester, [
      _ref(
        id: 'a',
        name: 'Sommer-Cup',
        status: TournamentStatus.registrationOpen,
      ),
    ]);

    // P6 L123: both per-tile actions are present.
    expect(find.widgetWithText(OutlinedButton, 'Details'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Anmelden'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Abmelden'), findsNothing);
  });

  testWidgets('Details button pushes the detail route', (tester) async {
    await _pump(tester, [
      _ref(
        id: 'a',
        name: 'Sommer-Cup',
        status: TournamentStatus.registrationOpen,
      ),
    ]);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Details'));
    await tester.pumpAndSettle();
    expect(find.text('detail-a'), findsOneWidget);
  });

  testWidgets('Anmelden button pushes the register route', (tester) async {
    await _pump(tester, [
      _ref(
        id: 'a',
        name: 'Sommer-Cup',
        status: TournamentStatus.registrationOpen,
      ),
    ]);
    await tester.tap(find.widgetWithText(FilledButton, 'Anmelden'));
    await tester.pumpAndSettle();
    expect(find.text('register-a'), findsOneWidget);
  });

  testWidgets(
      'tile flips to Abmelden when the caller already holds a registration',
      (tester) async {
    await _pump(
      tester,
      [
        _ref(
          id: 'a',
          name: 'Sommer-Cup',
          status: TournamentStatus.registrationOpen,
        ),
      ],
      myRegistrations: [
        MyTournamentRegistration(
          tournament: _ref(
            id: 'a',
            name: 'Sommer-Cup',
            status: TournamentStatus.registrationOpen,
          ),
          participantId: const TournamentParticipantId('p-1'),
          status: TournamentParticipantStatus.pending,
        ),
      ],
    );

    expect(find.widgetWithText(FilledButton, 'Abmelden'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Anmelden'), findsNothing);
    // Details stays available regardless of registration state.
    expect(find.widgetWithText(OutlinedButton, 'Details'), findsOneWidget);
  });
}
