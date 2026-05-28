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
  // W5.1-A added a MatchStageIndicator above the body, shrinking the
  // available ListView viewport. Lift the surface to keep the secondary
  // action row (`Zurück zur Übersicht`) in the build tree.
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
    // Score "6" / "3" also appears inside the half-set mock cards once
    // W5.1-C added the Halbsatz-Verlauf — match the 80px big-number text
    // by walking the rich-text size to keep the assertion hero-specific.
    final bigText = find.byWidgetPredicate(
      (w) => w is Text && w.style?.fontSize == 80 && w.data == '6',
    );
    expect(bigText, findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.style?.fontSize == 80 && w.data == '3',
      ),
      findsOneWidget,
    );
    // ListView lazily builds offstage rows once W5.1-C added stats/sections
    // — `skipOffstage: false` keeps the secondary Action-Row asserted.
    expect(find.text('Neues Match', skipOffstage: false), findsOneWidget);
    expect(find.text('Zurück zur Übersicht', skipOffstage: false), findsOneWidget);
    // Hero meta line — mock figures for now until backend exposes the
    // duration / throw count / ELO delta (BH-C-03 follow-up).
    expect(find.text('9:42 min · 28 Würfe · ELO +18'), findsOneWidget);
    // W5.1-C sections present (skipOffstage: false for items below fold).
    expect(find.text('Halbsatz-Verlauf', skipOffstage: false), findsOneWidget);
    expect(find.text('Statistik · du vs. Gegner', skipOffstage: false), findsOneWidget);
    expect(find.text('Revanche', skipOffstage: false), findsOneWidget);
    expect(find.text('Match teilen', skipOffstage: false), findsOneWidget);
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
