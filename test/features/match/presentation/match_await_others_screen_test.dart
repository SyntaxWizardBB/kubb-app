// Widget tests for the await-others screen polish (W5.1-D):
//
// * BH-A-02 / BH-B-02: the "Erneut benachrichtigen" CTA is not wired to
//   a backend mutation yet. Tapping it must surface a stub SnackBar so
//   the user gets feedback instead of a silent dead button.
// * BH-A-04: the AppBar back button used to route to the lobby, which
//   the lobby's status-listener then immediately bounced back to the
//   await screen. The back button must leave the match flow (route to
//   `/`) so the user can escape.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_await_others_screen.dart';

MatchDetail _detail() {
  final started = DateTime.utc(2026, 5, 24, 10);
  return MatchDetail(
    match: MatchDetailHeader(
      matchId: 'm-1',
      createdByUserId: null,
      format: MatchFormat.bo3,
      scoring: MatchScoring.wins,
      status: MatchStatus.awaitingResults,
      startedAt: started,
      completedAt: null,
      currentRound: 1,
      settings: const <String, dynamic>{},
    ),
    teams: const [
      MatchTeam(teamId: 'A', displayName: null),
      MatchTeam(teamId: 'B', displayName: null),
    ],
    participants: [
      MatchParticipant(
        participantId: 'p-1',
        teamId: 'A',
        kind: MatchParticipantKind.inApp,
        userId: 'user-me',
        nickname: 'Marc',
        invitationStatus: MatchInvitationStatus.accepted,
        joinedAt: started,
        respondedAt: started,
      ),
      MatchParticipant(
        participantId: 'p-2',
        teamId: 'B',
        kind: MatchParticipantKind.inApp,
        userId: 'user-other',
        nickname: 'Vinz',
        invitationStatus: MatchInvitationStatus.accepted,
        joinedAt: started,
        respondedAt: started,
      ),
    ],
    ownProposal: null,
    auditTail: const [],
  );
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/match/await-others/m-1',
    routes: [
      GoRoute(
        path: '/match/await-others/:id',
        builder: (_, state) =>
            MatchAwaitOthersScreen(matchId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/match/lobby/:id',
        builder: (_, state) => Scaffold(
          body: Text('lobby ${state.pathParameters['id']}'),
        ),
      ),
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchDetailProvider('m-1').overrideWith((_) async => _detail()),
        matchPollingProvider('m-1').overrideWith((_) {}),
      ],
      child: MaterialApp.router(
        theme: KubbTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  // The "Warten auf andere Spieler" screen renders a permanent
  // CircularProgressIndicator, so `pumpAndSettle` would time out.
  // A couple of frames is enough to flush the FutureProvider resolution
  // and lay out the body.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // BH-A-02 / BH-B-02: re-notify is a stub until W5-T4 wires the
  // push-notification mutation. Tapping must surface a SnackBar
  // explaining the deferred status instead of being a silent no-op.
  testWidgets(
    'BH-A-02/B-02: tapping "Erneut benachrichtigen" shows a stub SnackBar',
    (tester) async {
      await _pump(tester);

      final notify = find.widgetWithText(KubbButton, 'Erneut benachrichtigen');
      expect(notify, findsOneWidget);

      await tester.tap(notify);
      await tester.pump();

      expect(
        find.text('Benachrichtigung folgt in einem späteren Update'),
        findsOneWidget,
      );
    },
  );

  // BH-A-04: the back button used to route to the lobby, where the
  // status-listener (`awaiting_results` → result screen) would bounce
  // the user right back. The new behaviour is to leave the match flow.
  testWidgets(
    'BH-A-04: AppBar back button routes home instead of back to the lobby',
    (tester) async {
      await _pump(tester);

      // The BackButton is the leading slot of the KubbAppBar.
      final back = find.byType(BackButton);
      expect(back, findsOneWidget);

      await tester.tap(back);
      // The destination home route is a plain text placeholder, but the
      // source route's polling Timer (stubbed) plus pending animations
      // can keep pumpAndSettle spinning. A handful of pumps is enough
      // to drive the go_router redirect to completion.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // We landed on the home placeholder, not the lobby.
      expect(find.text('home'), findsOneWidget);
      expect(find.textContaining('lobby'), findsNothing);
    },
  );
}
