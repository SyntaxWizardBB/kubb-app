import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/inbox_bell_action.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/inbox/application/inbox_controller.dart';
import 'package:kubb_app/features/tournament/application/realtime_catchup_provider.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart'
    hide tournamentPoolStandingsProvider;
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/presentation/bracket/bracket_canvas.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_live_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_pool_standings_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _tid = TournamentId('t-1');

TournamentMatchRef _match(
  String id, {
  required TournamentMatchStatus status,
  String a = 'me',
  String b = 'rival',
  int round = 1,
  int number = 1,
  MatchPhase phase = MatchPhase.group,
  String? groupLabel,
}) {
  return TournamentMatchRef(
    matchId: TournamentMatchId(id),
    tournamentId: _tid,
    roundNumber: round,
    matchNumberInRound: number,
    participantA: TournamentParticipantId(a),
    participantB: TournamentParticipantId(b),
    status: status,
    consensusRound: 0,
    participantADisplayName: 'A-$a',
    participantBDisplayName: 'B-$b',
    phase: phase,
    groupLabel: groupLabel,
  );
}

TournamentDetail _detail(TournamentFormat format) => TournamentDetail(
      tournament: TournamentDetailHeader(
        tournamentId: 't-1',
        displayName: 'Sommer-Cup',
        createdByUserId: 'u-creator',
        clubId: null,
        teamSize: 1,
        maxTeamSize: 1,
        minParticipants: 2,
        maxParticipants: 8,
        format: format,
        scoring: TournamentScoring.ekc,
        matchFormatConfig: const <String, Object?>{},
        tiebreakerOrder: const <String>[],
        byePoints: 0,
        forfeitPoints: 0,
        status: TournamentStatus.live,
        publishedAt: null,
        startedAt: null,
        completedAt: null,
        setup: const <String, Object?>{
          'pool_phase_config': <String, Object?>{'qualifiers_per_group': 2},
        },
      ),
      participants: <TournamentParticipant>[
        _participant('me', 'Ich'),
        _participant('rival', 'Gegner'),
      ],
      matches: const <TournamentMatchRef>[],
      auditTail: const <TournamentAuditEvent>[],
    );

TournamentParticipant _participant(String id, String name) =>
    TournamentParticipant(
      participantId: id,
      userId: null,
      nickname: null,
      displayName: name,
      registrationStatus: TournamentParticipantStatus.approved,
      seed: null,
      registeredAt: DateTime.utc(2026),
      respondedAt: null,
    );

TournamentSummaryRef _summary() => const TournamentSummaryRef(
      tournamentId: _tid,
      displayName: 'Sommer-Cup',
      format: TournamentFormat.roundRobin,
      status: TournamentStatus.live,
      startedAt: null,
      completedAt: null,
      participantCount: 4,
    );

MyTournamentRegistration _reg(String participantId) =>
    MyTournamentRegistration(
      tournament: _summary(),
      participantId: TournamentParticipantId(participantId),
      status: TournamentParticipantStatus.approved,
    );

ParticipantStats _stat(String id) => ParticipantStats(
      participantId: id,
      totalPoints: 9,
      wins: 3,
      kubbsScored: 12,
      kubbsConceded: 5,
      opponentIds: const <String>[],
      opponentTotalPointsLookup: const <String, int>{},
      headToHeadLookup: const <String, int>{},
    );

BracketPairing _pair(String a, String b) => (
      (seed: 1, participantId: a, isBye: false),
      (seed: 2, participantId: b, isBye: false),
    );

Future<void> _pump(
  WidgetTester tester, {
  required TournamentFormat format,
  required List<TournamentMatchRef> matches,
  List<ParticipantStats> standings = const <ParticipantStats>[],
  List<PoolGroupStandings> pool = const <PoolGroupStandings>[],
  Bracket bracket = const SingleEliminationBracket(rounds: <BracketRound>[]),
  int unread = 0,
}) async {
  final router = GoRouter(
    initialLocation: TournamentRoutes.live('t-1'),
    routes: [
      GoRoute(
        path: '/tournament/:id/live',
        builder: (_, s) => TournamentLiveScreen(
          tournamentId: s.pathParameters['id']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id',
        builder: (_, _) => const Scaffold(body: Text('DETAIL')),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId',
        builder: (_, _) => const Scaffold(body: Text('MATCH')),
      ),
      GoRoute(
        path: '/inbox',
        builder: (_, _) => const Scaffold(body: Text('INBOX')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWith((_) => 'me'),
        inboxUnreadCountProvider.overrideWith((_) => unread),
        myTournamentRegistrationsProvider.overrideWith((_) async => [_reg('me')]),
        tournamentMatchListProvider(_tid).overrideWith((_) async => matches),
        tournamentStandingsProvider(_tid).overrideWith((_) async => standings),
        tournamentPoolStandingsProvider(_tid).overrideWith((_) async => pool),
        tournamentBracketProvider(_tid).overrideWith((_) async => bracket),
        tournamentDetailProvider(_tid).overrideWith((_) async => _detail(format)),
        tournamentMatchListRealtimeProvider(_tid).overrideWith(
          (_) => const Stream<TournamentMatchRef>.empty(),
        ),
        tournamentStandingsRealtimeProvider(_tid).overrideWith(
          (_) => const Stream<TournamentMatchRef>.empty(),
        ),
        realtimeCatchupProvider(_tid).overrideWith((_) {}),
        realtimeFallbackProvider(_tid)
            .overrideWith((_) => Stream<bool>.value(false)),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: KubbTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Rangliste stays flat for a round-robin tournament',
      (tester) async {
    await _pump(
      tester,
      format: TournamentFormat.roundRobin,
      matches: [_match('m1', status: TournamentMatchStatus.scheduled)],
      standings: [_stat('me')],
    );

    await tester.tap(find.text('Rangliste'));
    await tester.pumpAndSettle();

    // Flat standings table renders the caller row; no grouped pool tiles.
    expect(find.text('Ich'), findsOneWidget);
    expect(find.byType(TournamentPoolStandingsView), findsNothing);
  });

  testWidgets('Rangliste groups by pool for a group-phase tournament',
      (tester) async {
    await _pump(
      tester,
      format: TournamentFormat.roundRobinThenKo,
      matches: [
        _match('m1',
            status: TournamentMatchStatus.scheduled, groupLabel: 'A'),
      ],
      pool: [
        PoolGroupStandings('Gruppe A', [_stat('me')]),
        PoolGroupStandings('Gruppe B', [_stat('rival')]),
      ],
    );

    await tester.tap(find.text('Rangliste'));
    await tester.pumpAndSettle();

    expect(find.byType(TournamentPoolStandingsView), findsOneWidget);
    expect(find.text('Gruppe A'), findsWidgets);
    expect(find.text('Gruppe B'), findsWidgets);
  });

  testWidgets('Übersicht shows the round list while still in group phase',
      (tester) async {
    await _pump(
      tester,
      format: TournamentFormat.roundRobinThenKo,
      matches: [
        _match('m1',
            status: TournamentMatchStatus.scheduled, groupLabel: 'A'),
      ],
    );

    await tester.tap(find.text('Übersicht'));
    await tester.pumpAndSettle();

    // No bracket canvas yet; the group-labelled round header is visible.
    expect(find.byType(BracketCanvas), findsNothing);
    expect(find.text('Gruppe A · Runde 1'), findsOneWidget);
  });

  testWidgets('Übersicht swaps to the bracket once the KO phase is active',
      (tester) async {
    await _pump(
      tester,
      format: TournamentFormat.roundRobinThenKo,
      matches: [
        _match('m1', status: TournamentMatchStatus.finalized, groupLabel: 'A'),
        _match('ko1',
            status: TournamentMatchStatus.scheduled,
            round: 2,
            phase: MatchPhase.ko),
      ],
      bracket: SingleEliminationBracket(
        rounds: [
          BracketRound(number: 1, pairings: [_pair('me', 'rival')]),
        ],
      ),
    );

    await tester.tap(find.text('Übersicht'));
    await tester.pumpAndSettle();

    expect(find.byType(BracketCanvas), findsOneWidget);
  });

  testWidgets('the Postfach bell is present on the live view', (tester) async {
    await _pump(
      tester,
      format: TournamentFormat.roundRobin,
      matches: [_match('m1', status: TournamentMatchStatus.scheduled)],
      unread: 3,
    );

    expect(find.byType(InboxBellAction), findsOneWidget);
    await tester.tap(find.byType(InboxBellAction));
    await tester.pumpAndSettle();
    expect(find.text('INBOX'), findsOneWidget);
  });
}
