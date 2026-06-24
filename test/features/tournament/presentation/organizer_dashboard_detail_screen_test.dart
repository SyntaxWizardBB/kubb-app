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
import 'package:lucide_icons/lucide_icons.dart';

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

  // W4-T25: lifecycle RPCs migrated into the cockpit's _LifecycleSection.
  @override
  Future<void> publish(TournamentId id) async => calls.add('publish');
  @override
  Future<void> closeRegistration(TournamentId id) async =>
      calls.add('closeReg');
  @override
  Future<void> finalizeTournament(TournamentId id) async =>
      calls.add('finalize');
  @override
  Future<void> abortTournament(TournamentId id) async => calls.add('abort');
  @override
  Future<void> reactivateTournament(TournamentId id) async =>
      calls.add('reactivate');

  // Participant moderation (remove) migrated into the cockpit.
  final List<String> removed = <String>[];
  @override
  Future<void> removeParticipant(
    TournamentParticipantId participantId, {
    String? reason,
  }) async {
    removed.add(participantId.value);
  }

  /// Records the signed delta of each adjust-round-time dispatch so a test can
  /// assert the +/- step direction (extend = positive, shorten = negative).
  final List<int> adjustDeltas = <int>[];
  @override
  Future<void> adjustRoundTime(TournamentId id, int deltaSeconds) async {
    calls.add('adjust');
    adjustDeltas.add(deltaSeconds);
  }

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
  TournamentFormat format = TournamentFormat.schoch,
  Map<String, Object?> setup = const <String, Object?>{},
  List<TournamentParticipant> participants = const [],
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
      participants: participants,
      matches: const [],
      auditTail: const [],
    );

TournamentParticipant _participant({
  required String id,
  TournamentParticipantStatus status = TournamentParticipantStatus.approved,
}) =>
    TournamentParticipant(
      participantId: id,
      userId: 'user-$id',
      nickname: null,
      displayName: 'Spieler $id',
      registrationStatus: status,
      seed: null,
      registeredAt: DateTime.utc(2026),
      respondedAt: null,
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

/// A schedule row anchored at `now` so the Restzeit-Formel yields a positive
/// remaining time for the status-line tests (the default [_schedule] anchors
/// at 2026, which always reads as expired).
TournamentRoundScheduleRef _liveSchedule({
  required int matchSeconds,
  bool paused = false,
}) {
  final now = DateTime.now().toUtc();
  return TournamentRoundScheduleRef(
    tournamentId: _id,
    stageNodeId: null,
    roundNumber: 1,
    phase: 'group',
    status: RoundStatus.running,
    publishedAt: now,
    startsAt: now,
    endsAt: now.add(Duration(seconds: matchSeconds)),
    breakSeconds: 60,
    matchSeconds: matchSeconds,
    tiebreakAfterSeconds: null,
    pausedAt: paused ? now : null,
    pausedAccumSeconds: 0,
  );
}

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
    // "Runde 1" now appears twice: once in the control-bar status line and once
    // as the round header in the list.
    expect(find.text('Runde 1'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Team A1  vs  Team B1'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Team A1  vs  Team B1'), findsOneWidget);
    // The lower rounds sit below the new B3 escalation/KO sections — scroll
    // them into the lazy list to assert they still render.
    await tester.scrollUntilVisible(find.text('Team A3  vs  Team B3'), 200, scrollable: find.byType(Scrollable).first);
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

  testWidgets('W4-T16: + step button dispatches extendRound (positive delta)',
      (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      schedule: _schedule(RoundStatus.running),
    );

    await tester.tap(find.byIcon(LucideIcons.plus));
    await tester.pump();
    expect(spy.calls, contains('adjust'));
    expect(spy.adjustDeltas.single, greaterThan(0));
  });

  testWidgets('W4-T16: - step button dispatches shortenRound (negative delta)',
      (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      schedule: _schedule(RoundStatus.running),
    );

    await tester.tap(find.byIcon(LucideIcons.minus));
    await tester.pump();
    expect(spy.calls, contains('adjust'));
    expect(spy.adjustDeltas.single, lessThan(0));
  });

  testWidgets('W4-T16: direct number input dispatches a matching adjust',
      (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      schedule: _schedule(RoundStatus.running),
    );

    await tester.enterText(find.byType(TextField), '90');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(spy.adjustDeltas.single, 90);
  });

  testWidgets('W4-T16: status line shows Runde N and a remaining time',
      (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      schedule: _liveSchedule(matchSeconds: 600),
    );

    // "Runde 1" appears both in the status line and the round header; the
    // status line guarantees at least one.
    expect(find.text('Runde 1'), findsWidgets);
    // Remaining time renders as "Restzeit mm:ss" (a 600s round just started).
    expect(find.textContaining('Restzeit'), findsOneWidget);
  });

  testWidgets('W4-T16: status line shows Pause while the clock is paused',
      (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      schedule: _liveSchedule(matchSeconds: 600, paused: true),
    );
    expect(find.text('Pausiert'), findsWidgets);
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

    await tester.scrollUntilVisible(find.text('Korrigieren'), 200, scrollable: find.byType(Scrollable).first);
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

    // The open row now also carries the W4-T08 "Punkte eintragen" CTA above
    // the forfeit shortcut, so bring the forfeit button into view first.
    await tester.scrollUntilVisible(find.text('Forfait'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Forfait'), findsOneWidget);
    await tester.ensureVisible(find.text('Forfait'));
    await tester.pumpAndSettle();
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
    await tester.scrollUntilVisible(find.text('Korrigieren'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Korrigieren'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Forfait').first,
      200,
      scrollable: find.byType(Scrollable).first,
    );
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

  // ─── M4 #4: Schoch/Swiss next-round pairing CTA (ADR-0039 §3) ──────────

  testWidgets(
      'shows the pair-next-round CTA and submits a client-computed, '
      'stage-scoped pairing when the stage round is complete', (tester) async {
    final stageMatches = _schochStageRound1();
    final spy = _SwissPairSpy(stageMatches);
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      matches: stageMatches,
      schedule: _schedule(RoundStatus.completed),
      detail: _detail(setup: _schochSetup(rounds: 7)),
    );

    final cta = find.text('Nächste Runde paaren');
    await tester.scrollUntilVisible(
      cta,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(cta, findsOneWidget);

    await tester.tap(cta);
    await tester.pumpAndSettle();

    final pair = spy.lastPairStageRound;
    expect(pair, isNotNull, reason: 'the CTA must reach pairStageRound');
    expect(pair!.stageNodeId, _schochNode);
    // The submitted pairing equals what planRound computes locally — the
    // CLIENT did the pairing, not the server.
    expect(pair.pairings, equals(_expectedSchochRound2().pairings));
  });

  testWidgets('hides the CTA while the latest stage round is still open',
      (tester) async {
    final stageMatches = <TournamentMatchRef>[
      ..._schochStageRound1(),
      // A second round is partly open — not pairable yet.
      _stageMatch(2, 1, status: TournamentMatchStatus.awaitingResults),
    ];
    await _pump(
      tester,
      canAdminister: true,
      remote: _SwissPairSpy(stageMatches),
      matches: stageMatches,
      schedule: _schedule(RoundStatus.running),
      detail: _detail(setup: _schochSetup(rounds: 7)),
    );
    expect(find.text('Nächste Runde paaren'), findsNothing);
  });

  testWidgets('hides the CTA once the last configured round is reached',
      (tester) async {
    // R = 1: round 1 complete IS the last round, so no further pairing.
    final stageMatches = _schochStageRound1();
    await _pump(
      tester,
      canAdminister: true,
      remote: _SwissPairSpy(stageMatches),
      matches: stageMatches,
      schedule: _schedule(RoundStatus.completed),
      detail: _detail(setup: _schochSetup(rounds: 1)),
    );
    expect(find.text('Nächste Runde paaren'), findsNothing);
  });

  // ─── W4-T25: lifecycle action block migrated into the cockpit ──────────

  Future<void> seek(WidgetTester tester, Finder f) async {
    await tester.scrollUntilVisible(f, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
  }

  testWidgets('lifecycle: draft shows publish + dispatches it', (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      detail: _detail(status: TournamentStatus.draft),
    );
    await seek(tester, find.text('Veröffentlichen'));
    await tester.tap(find.text('Veröffentlichen'));
    await tester.pumpAndSettle();
    expect(spy.calls, contains('publish'));
  });

  testWidgets('lifecycle: registration_open shows Start + Anmeldung schliessen',
      (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      detail: _detail(status: TournamentStatus.registrationOpen),
    );
    await seek(tester, find.text('Turnier starten'));
    expect(find.text('Anmeldung schliessen'), findsOneWidget);
    await tester.tap(find.text('Turnier starten'));
    await tester.pumpAndSettle();
    expect(spy.calls, contains('start'));
  });

  testWidgets('lifecycle: live shows finalize + dispatches it', (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      detail: _detail(),
      schedule: _schedule(RoundStatus.running),
    );
    await seek(tester, find.text('Turnier abschliessen'));
    await tester.tap(find.text('Turnier abschliessen'));
    await tester.pumpAndSettle();
    expect(spy.calls, contains('finalize'));
  });

  testWidgets('lifecycle: edit + abort available pre-finalize', (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      detail: _detail(status: TournamentStatus.registrationClosed),
    );
    await seek(tester, find.text('Bearbeiten'));
    expect(find.text('Bearbeiten'), findsOneWidget);
    await seek(tester, find.text('Turnier abbrechen'));
    expect(find.text('Turnier abbrechen'), findsOneWidget);
  });

  testWidgets('lifecycle: live manual-seeding shows the seeding CTA',
      (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      detail: _detail(
        setup: const {
          'ko_config': {'seeding_mode': 'manual'},
        },
      ),
    );
    await seek(tester, find.text('Seeding festlegen'));
    expect(find.text('Seeding festlegen'), findsOneWidget);
  });

  testWidgets('lifecycle: aborted shows resume + dispatches reactivate',
      (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      detail: _detail(status: TournamentStatus.aborted),
    );
    await seek(tester, find.text('Fortsetzen'));
    await tester.tap(find.text('Fortsetzen'));
    await tester.pumpAndSettle();
    expect(spy.calls, contains('reactivate'));
  });

  // ─── W4-T25: participant moderation migrated into the cockpit ──────────

  testWidgets('moderation: Entfernen routes to removeParticipant',
      (tester) async {
    final spy = _SpyRemote();
    await _pump(
      tester,
      canAdminister: true,
      remote: spy,
      detail: _detail(
        status: TournamentStatus.registrationOpen,
        participants: [_participant(id: 'p1')],
      ),
    );
    await seek(tester, find.text('Entfernen'));
    await tester.tap(find.text('Entfernen'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Entfernen'),
      ),
    );
    await tester.pumpAndSettle();
    expect(spy.removed, ['p1']);
  });
}

const _schochNode = 'stage-schoch';

Map<String, Object?> _schochSetup({required int rounds}) => <String, Object?>{
      'pool_phase_config': <String, Object?>{'schoch_rounds': rounds},
    };

/// Stage-tagged finished round 1: P1>P2, P3>P4, P5=P6, P7>P8.
List<TournamentMatchRef> _schochStageRound1() => <TournamentMatchRef>[
      _stageMatch(1, 1),
      _stageMatch(1, 2, a: 'P3', b: 'P4', scoreA: 12, scoreB: 11),
      _stageMatch(1, 3, a: 'P5', b: 'P6', scoreA: 9, scoreB: 9),
      _stageMatch(1, 4, a: 'P7', b: 'P8', scoreB: 2),
    ];

TournamentMatchRef _stageMatch(
  int round,
  int n, {
  String a = 'P1',
  String b = 'P2',
  int scoreA = 16,
  int scoreB = 5,
  TournamentMatchStatus status = TournamentMatchStatus.finalized,
}) =>
    TournamentMatchRef(
      matchId: TournamentMatchId('sm-$round-$n'),
      tournamentId: _id,
      roundNumber: round,
      matchNumberInRound: n,
      participantA: TournamentParticipantId(a),
      participantB: TournamentParticipantId(b),
      status: status,
      consensusRound: 1,
      finalScoreA: status == TournamentMatchStatus.finalized ? scoreA : null,
      finalScoreB: status == TournamentMatchStatus.finalized ? scoreB : null,
      stageNodeId: _schochNode,
    );

PlannedRound _expectedSchochRound2() {
  final r1 = _schochStageRound1();
  final roster = <String>[];
  final completed = <MatchResult>[];
  for (final m in r1) {
    final a = m.participantA!.value;
    final b = m.participantB!.value;
    if (!roster.contains(a)) roster.add(a);
    if (!roster.contains(b)) roster.add(b);
    completed.add(
      MatchResult(
        participantA: a,
        participantB: b,
        pointsA: m.finalScoreA!,
        pointsB: m.finalScoreB!,
        roundNumber: m.roundNumber,
      ),
    );
  }
  return const SwissSystemStrategy().planRound(
    participants: roster,
    completedMatches: completed,
    roundNumber: 2,
    tournamentId: _id.value,
  );
}

/// Serves a fixed stage-tagged match list and captures the pairing the CTA
/// submits, so the test can assert the client-computed, stage-scoped payload.
class _SwissPairSpy extends FakeTournamentRemote {
  _SwissPairSpy(this._matches) : super(initialUser: const UserId('u1'));

  final List<TournamentMatchRef> _matches;

  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
    TournamentId id,
  ) async =>
      _matches;
}
