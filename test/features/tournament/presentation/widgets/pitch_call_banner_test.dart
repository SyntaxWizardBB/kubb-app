// Widget tests for the player-facing pitch-call banner (STAGE B,
// spec "TournierStart").

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/pitch_call_banner.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

const _tid = TournamentId('t-1');
const _myParticipant = TournamentParticipantId('me-1');

TournamentMatchRef _match({
  required String id,
  required int matchNumberInRound,
  TournamentMatchStatus status = TournamentMatchStatus.scheduled,
  TournamentParticipantId? a = _myParticipant,
  TournamentParticipantId? b = const TournamentParticipantId('foe-1'),
  String? aName = 'Ich',
  String? bName = 'Gegner-Team',
}) =>
    TournamentMatchRef(
      matchId: TournamentMatchId(id),
      tournamentId: _tid,
      roundNumber: 1,
      matchNumberInRound: matchNumberInRound,
      participantA: a,
      participantB: b,
      status: status,
      consensusRound: 1,
      participantADisplayName: aName,
      participantBDisplayName: bName,
    );

class _Remote implements TournamentRemote {
  _Remote(this.channel, this._matches, {required this.registered});
  final FakeRealtimeChannel channel;
  final List<TournamentMatchRef> _matches;
  final bool registered;

  @override
  Future<List<MyTournamentRegistration>> listMyRegistrations() async {
    if (!registered) return const [];
    return [
      const MyTournamentRegistration(
        tournament: TournamentSummaryRef(
          tournamentId: _tid,
          displayName: 'Turnier',
          format: TournamentFormat.roundRobin,
          status: TournamentStatus.live,
          startedAt: null,
          completedAt: null,
          participantCount: 4,
        ),
        participantId: _myParticipant,
        status: TournamentParticipantStatus.approved,
      ),
    ];
  }

  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
    TournamentId id,
  ) async =>
      _matches;

  @override
  Stream<TournamentMatchRef> watchTournamentMatches(TournamentId id) =>
      channel
          .subscribe(
            table: 'tournament_matches',
            filterColumn: 'tournament_id',
            filterValue: id.value,
          )
          .map((c) => _matches.firstWhere(
                (m) => m.matchId.value == c.newRow['id'],
              ));

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<void> _pump(
  WidgetTester tester,
  List<TournamentMatchRef> matches, {
  bool registered = true,
}) async {
  final remote = _Remote(FakeRealtimeChannel(), matches, registered: registered);
  final router = GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, _) => const Scaffold(
          body: PitchCallBanner(tournamentId: _tid),
        ),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId',
        builder: (_, _) => const Scaffold(body: Text('match-detail-screen')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [tournamentRemoteProvider.overrideWithValue(remote)],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: KubbTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('shows "Pitch <n>" and opponent for the caller\'s open match',
      (tester) async {
    await _pump(tester, [
      _match(id: 'm-7', matchNumberInRound: 7),
    ]);

    expect(find.byKey(const ValueKey('pitch-call-banner')), findsOneWidget);
    expect(find.text('Dein Platz: Pitch 7 — leg los!'), findsOneWidget);
    expect(find.text('Gegen Gegner-Team'), findsOneWidget);
  });

  testWidgets('opens match detail when the banner action is tapped',
      (tester) async {
    await _pump(tester, [
      _match(id: 'm-7', matchNumberInRound: 7),
    ]);
    await tester.tap(find.text('Spiel öffnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('match-detail-screen'), findsOneWidget);
  });

  testWidgets('prefers an awaiting (in-progress) match over a scheduled one',
      (tester) async {
    await _pump(tester, [
      _match(id: 'm-2', matchNumberInRound: 2),
      _match(
        id: 'm-5',
        matchNumberInRound: 5,
        status: TournamentMatchStatus.awaitingResults,
      ),
    ]);
    expect(find.text('Dein Platz: Pitch 5 — leg los!'), findsOneWidget);
  });

  testWidgets('renders nothing when the caller is not registered',
      (tester) async {
    await _pump(
      tester,
      [_match(id: 'm-1', matchNumberInRound: 1)],
      registered: false,
    );
    expect(find.byKey(const ValueKey('pitch-call-banner')), findsNothing);
  });

  testWidgets('renders nothing when the caller has only finalized matches',
      (tester) async {
    await _pump(tester, [
      _match(
        id: 'm-1',
        matchNumberInRound: 1,
        status: TournamentMatchStatus.finalized,
      ),
    ]);
    expect(find.byKey(const ValueKey('pitch-call-banner')), findsNothing);
  });

  testWidgets('ignores matches the caller is not part of', (tester) async {
    await _pump(tester, [
      _match(
        id: 'm-9',
        matchNumberInRound: 9,
        a: const TournamentParticipantId('other-a'),
        b: const TournamentParticipantId('other-b'),
        aName: 'A',
        bName: 'B',
      ),
    ]);
    expect(find.byKey(const ValueKey('pitch-call-banner')), findsNothing);
  });
}
