import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/organizer_dashboard_detail_screen.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/schedule_control_bar.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/tournament_forfeit_sheet.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

const _id = TournamentId('t-1');
const _creator = 'u-creator';

/// Records the schedule-control RPCs the control bar dispatches through the
/// actions facade, plus the KO-phase RPC the seeding controller fires (so the
/// auto-seeding handover can be asserted end-to-end against the REAL
/// controller, not a stub).
class _SpyRemote extends FakeTournamentRemote {
  _SpyRemote() : super(initialUser: const UserId('u1'));

  final List<String> calls = <String>[];

  /// The configs passed to `startKoPhase` (one per real RPC dispatch). Empty
  /// when the controller no-ops (e.g. unprimed config==null guard).
  final List<KoPhaseConfig> startKoConfigs = <KoPhaseConfig>[];

  @override
  Future<void> pauseTournament(TournamentId id) async => calls.add('pause');
  @override
  Future<void> resumeTournament(TournamentId id) async => calls.add('resume');
  @override
  Future<void> skipScheduleForward(TournamentId id) async =>
      calls.add('skipForward');
  @override
  Future<void> skipScheduleBackward(TournamentId id) async =>
      calls.add('skipBack');
  @override
  Future<void> startTournament(TournamentId id) async => calls.add('start');

  // Records the KO-phase RPC without requiring the tournament to be registered
  // in the fake's store — the assertion is purely "did the existing mechanic
  // reach the remote with a non-null config" (which only happens once the
  // dashboard has primed the controller via seed(...)).
  @override
  Future<void> startKoPhase(TournamentId id, KoPhaseConfig config) async {
    calls.add('startKoPhase');
    startKoConfigs.add(config);
  }

  // The auto-seeding handover derives the seed order from the standings, which
  // reads these two. Returning empties keeps the standings resolvable for an
  // unregistered fixture tournament.
  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
    TournamentId id,
  ) async =>
      const <TournamentMatchRef>[];
  @override
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async => null;
}

TournamentDetail _detail({
  String? clubId,
  TournamentStatus status = TournamentStatus.live,
  TournamentFormat format = TournamentFormat.swiss,
  Map<String, Object?> setup = const <String, Object?>{},
}) =>
    TournamentDetail(
      tournament: TournamentDetailHeader(
        tournamentId: 't-1',
        displayName: 'Sommer-Cup',
        createdByUserId: _creator,
        clubId: clubId,
        teamSize: 1,
        maxTeamSize: 1,
        minParticipants: 2,
        maxParticipants: 8,
        format: format,
        scoring: TournamentScoring.ekc,
        matchFormatConfig: const <String, Object?>{},
        tiebreakerOrder: const ['pts'],
        byePoints: null,
        forfeitPoints: null,
        status: status,
        publishedAt: null,
        startedAt: null,
        completedAt: null,
        setup: setup,
      ),
      participants: const [],
      matches: const [],
      auditTail: const [],
    );

TournamentMatchRef _match(
  int round,
  int n, {
  TournamentMatchStatus status = TournamentMatchStatus.scheduled,
}) =>
    TournamentMatchRef(
      matchId: TournamentMatchId('m-$round-$n'),
      tournamentId: _id,
      roundNumber: round,
      matchNumberInRound: n,
      participantA: TournamentParticipantId('a$n'),
      participantB: TournamentParticipantId('b$n'),
      status: status,
      consensusRound: 0,
      participantADisplayName: 'Team A$n',
      participantBDisplayName: 'Team B$n',
    );

TournamentRoundScheduleRef _schedule(
  RoundStatus status, {
  DateTime? pausedAt,
}) =>
    TournamentRoundScheduleRef(
      tournamentId: _id,
      stageNodeId: null,
      roundNumber: 1,
      phase: 'group',
      status: status,
      publishedAt: DateTime.utc(2026),
      startsAt: DateTime.utc(2026),
      endsAt: DateTime.utc(2026, 1, 1, 0, 10),
      breakSeconds: 60,
      matchSeconds: 600,
      tiebreakAfterSeconds: null,
      pausedAt: pausedAt,
      pausedAccumSeconds: 0,
    );

/// Spy router: records every pushed location so the B3 link tests can assert
/// the contextual actions navigate to the EXISTING override / seeding routes.
class _RouteSpy {
  final List<String> pushed = <String>[];
}

Future<void> _pump(
  WidgetTester tester, {
  required bool canAdminister,
  TournamentRemote? remote,
  List<TournamentMatchRef> matches = const [],
  TournamentRoundScheduleRef? schedule,
  TournamentDetail? detail,
  Bracket? bracket,
  _RouteSpy? routeSpy,
}) async {
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
      // Destination stubs so the spy router can resolve the contextual links.
      GoRoute(
        path: '/tournament/:id/match/:mid/override',
        builder: (_, _) => const Scaffold(body: Text('OVERRIDE')),
      ),
      GoRoute(
        path: '/tournament/:id/seeding',
        builder: (_, _) => const Scaffold(body: Text('SEEDING')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentDetailProvider(_id)
            .overrideWith((_) async => detail ?? _detail()),
        canAdministerTournamentProvider((
          clubId: null,
          createdBy: _creator,
        )).overrideWithValue(canAdminister),
        tournamentMatchListProvider(_id).overrideWith((_) async => matches),
        tournamentRoundScheduleProvider(_id).overrideWith(
          (_) => Stream.value(
            schedule == null
                ? const {}
                : {
                    (roundNumber: 1, stageNodeId: null): schedule,
                  },
          ),
        ),
        // Bracket: by default the group phase throws (no KO rows yet) →
        // "no bracket". A provided bracket models the KO phase already running.
        tournamentBracketProvider(_id).overrideWith(
          (_) async => bracket ?? (throw ArgumentError('no ko matches')),
        ),
        if (remote != null) tournamentRemoteProvider.overrideWithValue(remote),
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

/// Captures pushed routes by mirroring GoRouter's location into the spy on
/// every push (covers both `context.push` and `context.go`).
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

void main() {
  // ─── Existing B4 behaviour (must stay green) ──────────────────────────

  testWidgets('renders round/match list with disputed highlight',
      (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      matches: [
        _match(1, 1),
        _match(1, 2, status: TournamentMatchStatus.disputed),
        _match(2, 3),
      ],
      schedule: _schedule(RoundStatus.running),
    );

    expect(find.byType(ScheduleControlBar), findsOneWidget);
    expect(find.text('Runde 1'), findsOneWidget);
    expect(find.text('Team A1  vs  Team B1'), findsOneWidget);
    // The lower rounds sit below the new B3 escalation/KO sections — scroll
    // them into the lazy list to assert they still render.
    await tester.scrollUntilVisible(find.text('Team A3  vs  Team B3'), 200);
    expect(find.text('Runde 2'), findsOneWidget);
    expect(find.text('Team A3  vs  Team B3'), findsOneWidget);
  });

  testWidgets('control bar pause action dispatches pause', (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      matches: [_match(1, 1)],
      schedule: _schedule(RoundStatus.running),
    );

    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(spy.calls, contains('pause'));
  });

  testWidgets('control bar resume action dispatches resume (paused)',
      (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      schedule: _schedule(RoundStatus.running, pausedAt: DateTime.utc(2026)),
    );

    await tester.tap(find.text('Fortsetzen'));
    await tester.pump();
    expect(spy.calls, contains('resume'));
  });

  testWidgets('skip-back action dispatches skipBack', (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      schedule: _schedule(RoundStatus.running),
    );

    await tester.tap(find.text('Neu aufrufen'));
    await tester.pump();
    expect(spy.calls, contains('skipBack'));
  });

  testWidgets('skip-forward requires a hold (a tap alone does not fire)',
      (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      schedule: _schedule(RoundStatus.running),
    );

    final shortTap =
        await tester.startGesture(tester.getCenter(find.text('Vorspulen')));
    await tester.pump(const Duration(milliseconds: 100));
    await shortTap.up();
    await tester.pump();
    expect(spy.calls, isNot(contains('skipForward')));

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('Vorspulen')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(spy.calls, contains('skipForward'));
  });

  testWidgets('gate: authorized shows action UI', (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      schedule: _schedule(RoundStatus.running),
    );
    expect(find.byType(ScheduleControlBar), findsOneWidget);
    expect(find.byType(KubbEmptyState), findsNothing);
  });

  testWidgets('gate: unauthorized shows KubbEmptyState, no controls',
      (tester) async {
    await _pump(tester, canAdminister: false);
    expect(find.byType(KubbEmptyState), findsOneWidget);
    expect(find.byType(ScheduleControlBar), findsNothing);
  });

  // ─── B3 contextual intervention links ─────────────────────────────────

  testWidgets('DOD-03: disputed match links to the existing override route',
      (tester) async {
    final spy = _RouteSpy();
    await _pump(
      tester,
      canAdminister: true,
      routeSpy: spy,
      matches: [_match(1, 1, status: TournamentMatchStatus.disputed)],
      schedule: _schedule(RoundStatus.running),
    );

    expect(find.text('Korrigieren'), findsOneWidget);
    await tester.tap(find.text('Korrigieren'));
    await tester.pumpAndSettle();

    expect(spy.pushed, contains('/tournament/:id/match/:mid/override'));
  });

  testWidgets('DOD-03: non-disputed match shows NO override CTA',
      (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      matches: [_match(1, 1)], // scheduled
      schedule: _schedule(RoundStatus.running),
    );
    expect(find.text('Korrigieren'), findsNothing);
  });

  testWidgets('DOD-04: open match opens the existing forfeit sheet',
      (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      matches: [_match(1, 1)], // scheduled → open
      schedule: _schedule(RoundStatus.running),
    );

    expect(find.text('Forfait'), findsOneWidget);
    await tester.tap(find.text('Forfait'));
    await tester.pumpAndSettle();

    // The EXISTING sheet surfaces — no new dialog class is introduced.
    expect(find.byType(TournamentForfeitSheet), findsOneWidget);
  });

  testWidgets('DOD-04: finalized match shows neither forfeit nor override CTA',
      (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      matches: [_match(1, 1, status: TournamentMatchStatus.finalized)],
      schedule: _schedule(RoundStatus.running),
    );
    expect(find.text('Forfait'), findsNothing);
    expect(find.text('Korrigieren'), findsNothing);
  });

  testWidgets(
      'DOD-05: KO handover (manual seeding, no bracket) routes to seeding',
      (tester) async {
    final spy = _RouteSpy();
    await _pump(
      tester,
      canAdminister: true,
      routeSpy: spy,
      detail: _detail(
        setup: const {
          'ko_config': {'seeding_mode': 'manual'},
        },
      ),
      schedule: _schedule(RoundStatus.running),
    );

    expect(find.text('KO-Phase starten'), findsOneWidget);
    await tester.tap(find.text('KO-Phase starten'));
    await tester.pumpAndSettle();

    expect(spy.pushed, contains('/tournament/:id/seeding'));
  });

  testWidgets(
      'DOD-05: KO handover (auto seeding) fires the real startKoPhase RPC',
      (tester) async {
    // Uses the REAL TournamentSeedingController (no stub) plus a SpyRemote, so
    // this exercises the production path: the dashboard must PRIME the
    // controller (seed(...) → config != null) before startKoPhase() can reach
    // the remote. A stubbed controller would mask the config==null guard.
    final remote = _SpyRemote();
    final spy = _RouteSpy();
    await _pump(
      tester,
      canAdminister: true,
      routeSpy: spy,
      remote: remote,
      detail: _detail(), // live + no ko_config → auto seeding
      schedule: _schedule(RoundStatus.running),
    );

    await tester.tap(find.text('KO-Phase starten'));
    await tester.pumpAndSettle();

    // The existing startKoPhase mechanic actually dispatched the RPC with a
    // non-null config — proving the controller was primed, not a silent no-op.
    expect(remote.calls, contains('startKoPhase'));
    expect(remote.startKoConfigs, hasLength(1));
    // No detour to the seeding editor for the auto case.
    expect(spy.pushed, isNot(contains('/tournament/:id/seeding')));
  });

  testWidgets('DOD-05: with a bracket already built, KO CTA is hidden',
      (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      detail: _detail(),
      bracket: const SingleEliminationBracket(rounds: [
        BracketRound(number: 1, pairings: []),
      ]),
      schedule: _schedule(RoundStatus.running),
    );
    expect(find.text('KO-Phase starten'), findsNothing);
  });

  testWidgets('DOD-07: escalation badges reflect disputed + open counts',
      (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      matches: [
        _match(1, 1), // scheduled → open
        _match(1, 2, status: TournamentMatchStatus.awaitingResults), // open
        _match(1, 3, status: TournamentMatchStatus.disputed), // disputed
        _match(2, 4, status: TournamentMatchStatus.finalized), // neither
      ],
      schedule: _schedule(RoundStatus.running),
    );

    // Badges live near the top of the list and are derived from the counts.
    expect(find.text('1 strittig'), findsOneWidget);
    expect(find.text('2 offen'), findsOneWidget);
    // The associated interventions are reachable in the (scrollable) list —
    // scroll the disputed override + a forfeit CTA into view to confirm.
    await tester.scrollUntilVisible(find.text('Korrigieren'), 200);
    expect(find.text('Korrigieren'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Forfait').first, 200);
    expect(find.text('Forfait'), findsWidgets);
  });

  testWidgets('DOD-07: no escalations shows the quiet hint, no badges',
      (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      matches: [_match(1, 1, status: TournamentMatchStatus.finalized)],
      schedule: _schedule(RoundStatus.running),
    );
    expect(find.text('Keine offenen Eingriffe'), findsOneWidget);
    // No count badges rendered.
    expect(find.textContaining('strittig'), findsNothing);
    expect(find.textContaining(RegExp(r'\d+ offen')), findsNothing);
  });
}
