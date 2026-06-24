import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/presentation/organizer_dashboard_detail_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _id = TournamentId('t-1');
const _creator = 'u-creator';

TournamentDetail _detail() => const TournamentDetail(
      tournament: TournamentDetailHeader(
        tournamentId: 't-1',
        displayName: 'Sommer-Cup',
        createdByUserId: _creator,
        clubId: null,
        teamSize: 1,
        maxTeamSize: 1,
        minParticipants: 2,
        maxParticipants: 8,
        format: TournamentFormat.roundRobin,
        scoring: TournamentScoring.ekc,
        matchFormatConfig: <String, Object?>{},
        tiebreakerOrder: ['pts'],
        byePoints: null,
        forfeitPoints: null,
        status: TournamentStatus.live,
        publishedAt: null,
        startedAt: null,
        completedAt: null,
      ),
      participants: [],
      matches: [],
      auditTail: [],
    );

TournamentMatchRef _match(
  int n, {
  TournamentMatchStatus status = TournamentMatchStatus.scheduled,
}) =>
    TournamentMatchRef(
      matchId: TournamentMatchId('m-1-$n'),
      tournamentId: _id,
      roundNumber: 1,
      matchNumberInRound: n,
      participantA: TournamentParticipantId('a$n'),
      participantB: TournamentParticipantId('b$n'),
      status: status,
      consensusRound: 0,
      participantADisplayName: 'Team A$n',
      participantBDisplayName: 'Team B$n',
    );

TournamentRoundScheduleRef _schedule() => TournamentRoundScheduleRef(
      tournamentId: _id,
      stageNodeId: null,
      roundNumber: 1,
      phase: 'group',
      status: RoundStatus.running,
      publishedAt: DateTime.utc(2026),
      startsAt: DateTime.utc(2026),
      endsAt: DateTime.utc(2026, 1, 1, 0, 10),
      breakSeconds: 60,
      matchSeconds: 600,
      tiebreakAfterSeconds: null,
      pausedAt: null,
      pausedAccumSeconds: 0,
    );

class _RouteSpy {
  final List<String> pushed = <String>[];
}

class _PushObserver extends NavigatorObserver {
  _PushObserver(this.spy);
  final _RouteSpy spy;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    final name = route.settings.name;
    if (name != null) spy.pushed.add(name);
    super.didPush(route, previousRoute);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required List<TournamentMatchRef> matches,
  _RouteSpy? routeSpy,
}) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final spy = routeSpy ?? _RouteSpy();
  final router = GoRouter(
    initialLocation: '/tournament/t-1/dashboard',
    observers: [_PushObserver(spy)],
    routes: [
      GoRoute(
        path: '/tournament/t-1/dashboard',
        builder: (_, _) =>
            const OrganizerDashboardDetailScreen(tournamentId: _id),
      ),
      GoRoute(
        path: '/tournament/:id/match/:mid/score',
        builder: (_, _) => const Scaffold(body: Text('SCORE')),
      ),
      GoRoute(
        path: '/tournament/:id/match/:mid/override',
        builder: (_, _) => const Scaffold(body: Text('OVERRIDE')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentDetailProvider(_id).overrideWith((_) async => _detail()),
        canAdministerTournamentProvider((
          clubId: null,
          createdBy: _creator,
        )).overrideWithValue(true),
        tournamentMatchListProvider(_id).overrideWith((_) async => matches),
        tournamentRoundScheduleProvider(_id).overrideWith(
          (_) => Stream.value({
            (roundNumber: 1, stageNodeId: null): _schedule(),
          }),
        ),
        tournamentBracketProvider(_id).overrideWith(
          (_) async => throw ArgumentError('no ko matches'),
        ),
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
  testWidgets(
      'W4-T08: every open match shows the "Punkte eintragen" CTA, which opens '
      'the direct-score route', (tester) async {
    final spy = _RouteSpy();
    await _pump(
      tester,
      routeSpy: spy,
      matches: [
        _match(1), // scheduled → open
        _match(2, status: TournamentMatchStatus.awaitingResults), // open
      ],
    );

    expect(find.text('Punkte eintragen'), findsNWidgets(2));

    await tester.ensureVisible(find.text('Punkte eintragen').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Punkte eintragen').first);
    await tester.pumpAndSettle();
    expect(spy.pushed, contains('/tournament/:id/match/:mid/score'));
  });

  testWidgets('W4-T08: a disputed match keeps Override, not the direct CTA',
      (tester) async {
    await _pump(
      tester,
      matches: [_match(1, status: TournamentMatchStatus.disputed)],
    );
    expect(find.text('Punkte eintragen'), findsNothing);
    expect(find.text('Korrigieren'), findsOneWidget);
  });

  testWidgets('W4-T08: a finalized match shows no direct CTA', (tester) async {
    await _pump(
      tester,
      matches: [_match(1, status: TournamentMatchStatus.finalized)],
    );
    expect(find.text('Punkte eintragen'), findsNothing);
  });
}
