import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/match/application/match_providers.dart';
import 'package:kubb_app/features/match/data/match_models.dart';
import 'package:kubb_app/features/match/presentation/match_finished_screen.dart';

MatchDetail _detail({
  MatchStatus status = MatchStatus.finalized,
  String? winner = 'A',
  int? scoreA = 6,
  int? scoreB = 3,
}) {
  final started = DateTime.utc(2026, 5, 24, 10);
  return MatchDetail(
    match: MatchDetailHeader(
      matchId: 'm-1',
      createdByUserId: null,
      format: MatchFormat.bo3,
      scoring: MatchScoring.wins,
      status: status,
      startedAt: started,
      completedAt: started.add(const Duration(hours: 1)),
      currentRound: 1,
      settings: const <String, dynamic>{},
      winnerTeamId: winner,
      finalScoreA: scoreA,
      finalScoreB: scoreB,
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

Future<void> _pump(WidgetTester tester, MatchDetail detail) async {
  final router = GoRouter(
    initialLocation: '/match/finished/m-1',
    routes: [
      GoRoute(
        path: '/match/finished/:id',
        builder: (_, state) =>
            MatchFinishedScreen(matchId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('home'))),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        matchDetailProvider('m-1').overrideWith((_) async => detail),
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
  testWidgets('finalized match shows winning team and final score',
      (tester) async {
    await _pump(tester, _detail());

    // Verdict is rendered as an uppercased eyebrow inside the meadow
    // hero card — see _ScoreHeroCard in match_finished_screen.dart.
    expect(find.text('SIEGER: TEAM A'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Neues Match'), findsOneWidget);
    expect(find.text('Zurück zur Übersicht'), findsOneWidget);
  });

  testWidgets('voided match shows the abort headline and no winner',
      (tester) async {
    await _pump(
      tester,
      _detail(status: MatchStatus.voided, winner: null, scoreA: null, scoreB: null),
    );

    expect(find.text('MATCH ABGEBROCHEN'), findsOneWidget);
    expect(find.textContaining('SIEGER'), findsNothing);
  });
}
