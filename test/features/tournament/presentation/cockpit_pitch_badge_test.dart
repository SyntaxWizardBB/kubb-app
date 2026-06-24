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

TournamentMatchRef _match(int n, {int? pitch}) => TournamentMatchRef(
      matchId: TournamentMatchId('m-1-$n'),
      tournamentId: _id,
      roundNumber: 1,
      matchNumberInRound: n,
      participantA: TournamentParticipantId('a$n'),
      participantB: TournamentParticipantId('b$n'),
      status: TournamentMatchStatus.scheduled,
      consensusRound: 0,
      participantADisplayName: 'Team A$n',
      participantBDisplayName: 'Team B$n',
      pitchNumber: pitch,
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

Future<void> _pump(
  WidgetTester tester, {
  required List<TournamentMatchRef> matches,
}) async {
  final router = GoRouter(
    initialLocation: '/tournament/t-1/dashboard',
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
  testWidgets('W4-T04: a pitch-assigned match shows its pitch badge',
      (tester) async {
    await _pump(tester, matches: [_match(1, pitch: 7)]);
    await tester.scrollUntilVisible(
      find.text('Pitch 7'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Pitch 7'), findsOneWidget);
  });

  testWidgets('W4-T04: a match with no pitch shows no badge', (tester) async {
    await _pump(tester, matches: [_match(1)]);
    expect(find.textContaining('Pitch'), findsNothing);
  });
}
