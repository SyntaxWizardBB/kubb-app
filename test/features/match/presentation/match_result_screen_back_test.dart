// Widget test for W5.1-D BH-A-03: the result screen is entered via
// `context.go`, so the navigator has nothing to pop back to. Without an
// explicit leading slot the `KubbAppBar.automaticallyImplyLeading` path
// renders no back affordance and the user is trapped. We now wire a
// `BackButton` that routes home so the back gesture is always live.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_result_screen.dart';

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
    participants: const [],
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
    initialLocation: '/match/result/m-1',
    routes: [
      GoRoute(
        path: '/match/result/:id',
        builder: (_, state) =>
            MatchResultScreen(matchId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/training', builder: (_, _) => const Scaffold(body: Text('home'))),
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
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'BH-A-03: result screen exposes a functional back button that routes home',
    (tester) async {
      await _pump(tester);

      // BackButton rendered as KubbAppBar leading slot.
      final back = find.byType(BackButton);
      expect(back, findsOneWidget);

      await tester.tap(back);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('home'), findsOneWidget);
    },
  );
}
