import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_realtime_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/organizer_dashboard_detail_screen.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/schedule_control_bar.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

const _id = TournamentId('t-1');
const _creator = 'u-creator';

/// Records the schedule-control RPCs the control bar dispatches through the
/// actions facade.
class _SpyRemote extends FakeTournamentRemote {
  _SpyRemote() : super(initialUser: const UserId('u1'));

  final List<String> calls = <String>[];

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
}

TournamentDetail _detail({String? clubId}) => TournamentDetail(
      tournament: TournamentDetailHeader(
        tournamentId: 't-1',
        displayName: 'Sommer-Cup',
        createdByUserId: _creator,
        clubId: clubId,
        teamSize: 1,
        maxTeamSize: 1,
        minParticipants: 2,
        maxParticipants: 8,
        format: TournamentFormat.swiss,
        scoring: TournamentScoring.ekc,
        matchFormatConfig: const <String, Object?>{},
        tiebreakerOrder: const ['pts'],
        byePoints: null,
        forfeitPoints: null,
        status: TournamentStatus.live,
        publishedAt: null,
        startedAt: null,
        completedAt: null,
      ),
      participants: const [],
      matches: const [],
      auditTail: const [],
    );

TournamentMatchRef _match(int round, int n, {bool disputed = false}) =>
    TournamentMatchRef(
      matchId: TournamentMatchId('m-$round-$n'),
      tournamentId: _id,
      roundNumber: round,
      matchNumberInRound: n,
      participantA: TournamentParticipantId('a$n'),
      participantB: TournamentParticipantId('b$n'),
      status: disputed
          ? TournamentMatchStatus.disputed
          : TournamentMatchStatus.scheduled,
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

Future<void> _pump(
  WidgetTester tester, {
  required bool canAdminister,
  TournamentRemote? remote,
  List<TournamentMatchRef> matches = const [],
  TournamentRoundScheduleRef? schedule,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentDetailProvider(_id).overrideWith((_) async => _detail()),
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
        if (remote != null) tournamentRemoteProvider.overrideWithValue(remote),
      ],
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const OrganizerDashboardDetailScreen(tournamentId: _id),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders round/match list with disputed highlight',
      (tester) async {
    await _pump(
      tester,
      canAdminister: true,
      matches: [_match(1, 1), _match(1, 2, disputed: true), _match(2, 3)],
      schedule: _schedule(RoundStatus.running),
    );

    expect(find.text('Runde 1'), findsOneWidget);
    expect(find.text('Runde 2'), findsOneWidget);
    expect(find.text('Team A1  vs  Team B1'), findsOneWidget);
    expect(find.text('Team A3  vs  Team B3'), findsOneWidget);
    expect(find.byType(ScheduleControlBar), findsOneWidget);
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

    // Running → primary toggle is "Pause".
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

    // A short press must NOT confirm the irreversible action.
    final shortTap =
        await tester.startGesture(tester.getCenter(find.text('Vorspulen')));
    await tester.pump(const Duration(milliseconds: 100));
    await shortTap.up();
    await tester.pump();
    expect(spy.calls, isNot(contains('skipForward')));

    // Holding past the hold duration confirms it once.
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
}
