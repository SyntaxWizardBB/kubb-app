import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/tournament_conflict_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_conflict_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

class _FakeRemote implements TournamentRemote {
  _FakeRemote(this._detail);
  final TournamentMatchRef _detail;

  @override
  Future<TournamentMatchRef?> getMatch(TournamentMatchId id) async => _detail;

  @override
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id) =>
      const Stream<TournamentMatchRef>.empty();

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

TournamentMatchRef _match({int round = 2}) {
  return TournamentMatchRef(
    matchId: const TournamentMatchId('m-1'),
    tournamentId: const TournamentId('t-1'),
    roundNumber: 1,
    matchNumberInRound: 1,
    participantA: const TournamentParticipantId('alpha1'),
    participantB: const TournamentParticipantId('beta22'),
    status: TournamentMatchStatus.awaitingResults,
    consensusRound: round,
  );
}

TournamentSetScoreProposal _p({
  required String submitter,
  required int set,
  required int kA,
  required int kB,
  required SetWinner winner,
  int round = 2,
}) {
  return TournamentSetScoreProposal(
    matchId: const TournamentMatchId('m-1'),
    consensusRound: round,
    setNumber: set,
    submitterUserId: UserId(submitter),
    score: SetScore(
      basekubbsKnockedByA: kA,
      basekubbsKnockedByB: kB,
      winner: winner,
    ),
  );
}

Future<({GoRouter router})> _pump(
  WidgetTester tester, {
  required TournamentMatchRef match,
  required TournamentConflictSnapshot snapshot,
}) async {
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/tournament/t-1/match/m-1/conflict',
    routes: [
      GoRoute(
        path: '/tournament/:id/match/:matchId/conflict',
        builder: (_, s) => TournamentConflictScreen(
          tournamentId: s.pathParameters['id']!,
          matchId: s.pathParameters['matchId']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId',
        builder: (_, _) => const Scaffold(body: Text('detail-route')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(_FakeRemote(match)),
        tournamentConflictProvider.overrideWith(
          (ref, id) async => snapshot,
        ),
      ],
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
  await tester.pump(const Duration(milliseconds: 16));
  return (router: router);
}

bool _hasDiffBackground(WidgetTester tester) {
  final containers = tester.widgetList<Container>(find.byType(Container));
  for (final c in containers) {
    final d = c.decoration;
    if (d is BoxDecoration && d.color == KubbTokens.miss) return true;
  }
  return false;
}

void main() {
  testWidgets('matching proposals render without diff highlights',
      (tester) async {
    final snap = buildConflictSnapshot([
      _p(submitter: 'a', set: 1, kA: 5, kB: 3, winner: SetWinner.teamA),
      _p(submitter: 'b', set: 1, kA: 5, kB: 3, winner: SetWinner.teamA),
    ]);
    await _pump(tester, match: _match(), snapshot: snap);
    expect(find.text('Eingabe Team A'), findsOneWidget);
    expect(find.text('Eingabe Team B'), findsOneWidget);
    expect(_hasDiffBackground(tester), isFalse);
    expect(find.text('Erneut eintragen'), findsOneWidget);
    expect(find.text('Veranstalter hinzuziehen'), findsOneWidget);
  });

  testWidgets('diverging proposals show diff highlights and both buttons',
      (tester) async {
    final snap = buildConflictSnapshot([
      _p(submitter: 'a', set: 1, kA: 5, kB: 2, winner: SetWinner.teamA),
      _p(submitter: 'b', set: 1, kA: 4, kB: 5, winner: SetWinner.teamB),
    ]);
    await _pump(tester, match: _match(), snapshot: snap);
    expect(_hasDiffBackground(tester), isTrue);
    expect(find.textContaining('Versuch 2 von 3'), findsOneWidget);
    expect(find.text('Erneut eintragen'), findsOneWidget);
    expect(find.text('Veranstalter hinzuziehen'), findsOneWidget);
  });

  testWidgets('consensus round 3 shows last-attempt warning', (tester) async {
    final snap = buildConflictSnapshot([
      _p(submitter: 'a', set: 1, kA: 5, kB: 2, winner: SetWinner.teamA,
          round: 3),
      _p(submitter: 'b', set: 1, kA: 4, kB: 5, winner: SetWinner.teamB,
          round: 3),
    ]);
    await _pump(tester, match: _match(round: 3), snapshot: snap);
    expect(
      find.textContaining('Letzter Versuch'),
      findsOneWidget,
    );
  });

  testWidgets('retry button navigates to match detail route', (tester) async {
    final snap = buildConflictSnapshot([
      _p(submitter: 'a', set: 1, kA: 5, kB: 2, winner: SetWinner.teamA),
      _p(submitter: 'b', set: 1, kA: 4, kB: 5, winner: SetWinner.teamB),
    ]);
    await _pump(tester, match: _match(), snapshot: snap);
    await tester.tap(find.text('Erneut eintragen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('detail-route'), findsOneWidget);
  });
}
