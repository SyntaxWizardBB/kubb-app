import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/realtime_catchup_provider.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_live_screen.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _tid = TournamentId('t-1');

// ---------------------------------------------------------------------------
// Builders
// ---------------------------------------------------------------------------

TournamentMatchRef _match(
  String id, {
  required TournamentMatchStatus status,
  String? a = 'me',
  String? b = 'rival',
  int round = 1,
  int number = 1,
}) {
  return TournamentMatchRef(
    matchId: TournamentMatchId(id),
    tournamentId: _tid,
    roundNumber: round,
    matchNumberInRound: number,
    participantA: a == null ? null : TournamentParticipantId(a),
    participantB: b == null ? null : TournamentParticipantId(b),
    status: status,
    consensusRound: 0,
    participantADisplayName: a == null ? null : 'A-$a',
    participantBDisplayName: b == null ? null : 'B-$b',
  );
}

TournamentSummaryRef _summary() => const TournamentSummaryRef(
      tournamentId: _tid,
      displayName: 'Sommer-Cup',
      format: TournamentFormat.roundRobin,
      status: TournamentStatus.live,
      startedAt: null,
      completedAt: null,
      participantCount: 4,
    );

MyTournamentRegistration _reg(String participantId) => MyTournamentRegistration(
      tournament: _summary(),
      participantId: TournamentParticipantId(participantId),
      status: TournamentParticipantStatus.approved,
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

TournamentDetail _detail() => TournamentDetail(
      tournament: const TournamentDetailHeader(
        tournamentId: 't-1',
        displayName: 'Sommer-Cup',
        createdByUserId: 'u-creator',
        clubId: null,
        teamSize: 1,
        maxTeamSize: 1,
        minParticipants: 2,
        maxParticipants: 8,
        format: TournamentFormat.roundRobin,
        scoring: TournamentScoring.ekc,
        matchFormatConfig: <String, Object?>{},
        tiebreakerOrder: <String>[],
        byePoints: 0,
        forfeitPoints: 0,
        status: TournamentStatus.live,
        publishedAt: null,
        startedAt: null,
        completedAt: null,
      ),
      participants: <TournamentParticipant>[
        _participant('me', 'Ich'),
        _participant('rival', 'Gegner'),
      ],
      matches: const <TournamentMatchRef>[],
      auditTail: const <TournamentAuditEvent>[],
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

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

Future<GoRouter> _pump(
  WidgetTester tester, {
  required List<TournamentMatchRef> matches,
  required List<MyTournamentRegistration> regs,
  List<ParticipantStats> standings = const <ParticipantStats>[],
  String me = 'me',
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
        builder: (_, _) => const Scaffold(body: Text('DETAIL-SCREEN')),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId',
        builder: (_, s) => Scaffold(
          body: Text('MATCH-${s.pathParameters['matchId']}'),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUserIdProvider.overrideWith((_) => me),
        myTournamentRegistrationsProvider.overrideWith((_) async => regs),
        tournamentMatchListProvider(_tid).overrideWith((_) async => matches),
        tournamentStandingsProvider(_tid)
            .overrideWith((_) async => standings),
        tournamentDetailProvider(_tid).overrideWith((_) async => _detail()),
        // Keep the realtime/fallback wiring inert (no network) — the
        // reused match-list and standings views watch these.
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
  return router;
}

void main() {
  testWidgets('AC13a: default tab is "Mein Match" and shows the caller match',
      (tester) async {
    await _pump(
      tester,
      regs: [_reg('me')],
      matches: [_match('m1', status: TournamentMatchStatus.scheduled)],
    );

    expect(find.text('Mein Match'), findsOneWidget);
    expect(find.text('Übersicht'), findsOneWidget);
    expect(find.text('Rangliste'), findsOneWidget);

    // The screen owns its own TabController; assert the default index via
    // the TabBar's attached controller.
    final bar = tester.widget<TabBar>(find.byType(TabBar));
    expect(bar.controller!.index, 0);

    // The caller's own opponent label is visible on the default tab.
    expect(find.text('B-rival'), findsOneWidget);
  });

  testWidgets('AC13b: "Turnier-Infos" action navigates to the detail route',
      (tester) async {
    await _pump(
      tester,
      regs: [_reg('me')],
      matches: [_match('m1', status: TournamentMatchStatus.scheduled)],
    );

    await tester.tap(find.byTooltip('Turnier-Infos'));
    await tester.pumpAndSettle();

    expect(find.text('DETAIL-SCREEN'), findsOneWidget);
  });

  testWidgets('AC6: tapping a "Mein Match" row opens the match-detail route',
      (tester) async {
    await _pump(
      tester,
      regs: [_reg('me')],
      matches: [_match('m1', status: TournamentMatchStatus.awaitingResults)],
    );

    await tester.tap(find.text('B-rival'));
    await tester.pumpAndSettle();

    expect(find.text('MATCH-m1'), findsOneWidget);
  });

  testWidgets('AC14: all three tabs render their respective content',
      (tester) async {
    await _pump(
      tester,
      regs: [_reg('me')],
      matches: [
        _match('m1', status: TournamentMatchStatus.scheduled),
        _match('m2',
            status: TournamentMatchStatus.finalized, a: 'x', b: 'y', number: 2),
      ],
      standings: [_stat('me')],
    );

    // Tab 0 — my match.
    expect(find.text('B-rival'), findsOneWidget);

    // Tab 1 — Übersicht: full match list grouped by round.
    await tester.tap(find.text('Übersicht'));
    await tester.pumpAndSettle();
    // Both matches (own + foreign) appear in the full overview list.
    expect(find.text('B-rival'), findsOneWidget);
    expect(find.text('B-y'), findsOneWidget);

    // Tab 2 — Rangliste: standings table renders the caller row.
    await tester.tap(find.text('Rangliste'));
    await tester.pumpAndSettle();
    expect(find.text('Ich'), findsOneWidget);
  });

  testWidgets('AC15a: empty state "Kein aktuelles Match" when no open match',
      (tester) async {
    await _pump(
      tester,
      regs: [_reg('me')],
      matches: [
        // Own match but terminal -> excluded.
        _match('m1', status: TournamentMatchStatus.finalized),
      ],
    );

    expect(find.text('Kein aktuelles Match'), findsOneWidget);
    expect(find.text('B-rival'), findsNothing);
  });

  testWidgets(
      'AC15b: "Mein Match" shows only own non-terminal matches '
      '(foreign + terminal excluded; disputed included)', (tester) async {
    await _pump(
      tester,
      regs: [_reg('me')],
      matches: [
        // Own, scheduled -> shown.
        _match('m-open', status: TournamentMatchStatus.scheduled),
        // Own, disputed -> shown (Plan A3 non-terminal set).
        _match('m-disp', status: TournamentMatchStatus.disputed, number: 2),
        // Own, finalized -> excluded (terminal).
        _match('m-fin', status: TournamentMatchStatus.finalized, number: 3),
        // Foreign, scheduled -> excluded (caller not involved).
        _match('m-foreign',
            status: TournamentMatchStatus.scheduled,
            a: 'x',
            b: 'y',
            number: 4),
      ],
    );

    // The two non-terminal own matches each render the opponent label.
    expect(find.text('B-rival'), findsNWidgets(2));
    // The foreign match's opponent label never appears on this tab.
    expect(find.text('B-y'), findsNothing);
    expect(find.text('Kein aktuelles Match'), findsNothing);
  });
}
