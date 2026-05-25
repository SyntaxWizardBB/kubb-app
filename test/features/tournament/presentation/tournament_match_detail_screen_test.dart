import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_match_detail_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

class _FakeRemote implements TournamentRemote {
  _FakeRemote(this._detail, {TournamentMatchRef? afterPropose})
      : _afterPropose = afterPropose;

  TournamentMatchRef _detail;
  final TournamentMatchRef? _afterPropose;
  ({TournamentMatchId matchId, int round, List<SetScore> scores})? lastCall;

  @override
  Future<TournamentMatchRef?> getMatch(TournamentMatchId id) async => _detail;

  @override
  Future<void> proposeSetScores({
    required TournamentMatchId matchId,
    required int consensusRound,
    required List<SetScore> setScores,
  }) async {
    lastCall = (matchId: matchId, round: consensusRound, scores: setScores);
    if (_afterPropose != null) _detail = _afterPropose;
  }

  @override
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id) =>
      const Stream<TournamentMatchRef>.empty();

  // Unused for these tests.
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

TournamentMatchRef _match({
  TournamentMatchStatus status = TournamentMatchStatus.awaitingResults,
  int consensusRound = 1,
}) {
  return TournamentMatchRef(
    matchId: const TournamentMatchId('m-1'),
    tournamentId: const TournamentId('t-1'),
    roundNumber: 1,
    matchNumberInRound: 1,
    participantA: const TournamentParticipantId('alpha1'),
    participantB: const TournamentParticipantId('beta22'),
    status: status,
    consensusRound: consensusRound,
  );
}

Future<_FakeRemote> _pump(
  WidgetTester tester, {
  required TournamentMatchRef match,
  TournamentMatchRef? afterPropose,
}) async {
  // Tall viewport so the bottom of the match-detail ListView (with
  // the submit button) is built without scrolling.
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = _FakeRemote(match, afterPropose: afterPropose);
  final router = GoRouter(
    initialLocation: '/tournament/t-1/match/m-1',
    routes: [
      GoRoute(
        path: '/tournament/:id/match/:matchId',
        builder: (_, s) => TournamentMatchDetailScreen(
          tournamentId: s.pathParameters['id']!,
          matchId: s.pathParameters['matchId']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId/conflict',
        builder: (_, _) => const Scaffold(body: Text('conflict-screen')),
      ),
      GoRoute(
        path: '/tournament/:id/matches',
        builder: (_, _) => const Scaffold(body: Text('matches')),
      ),
      GoRoute(
        path: '/tournament/:id/standings',
        builder: (_, _) => const Scaffold(body: Text('standings')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(fake),
      ],
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: KubbTheme.light(),
        routerConfig: router,
      ),
    ),
  );
  // FutureProvider resolves on the microtask queue. Don't use
  // pumpAndSettle — the 5s polling timer would block it forever.
  await tester.pump(); // initial build, kicks the future
  await tester.pump(); // future completes, data state populates
  await tester.pump(const Duration(milliseconds: 16));
  await tester.pump(const Duration(milliseconds: 16));
  return fake;
}

void main() {
  testWidgets('renders header, default first-set inputs and submit button',
      (tester) async {
    await _pump(tester, match: _match());
    expect(find.text('Spiel-Eingabe'), findsOneWidget);
    expect(find.text('Satz 1'), findsOneWidget);
    expect(find.text('Einreichen'), findsOneWidget);
    expect(find.text('Basekubbs Team A'), findsOneWidget);
    expect(find.text('Basekubbs Team B'), findsOneWidget);
  });

  testWidgets('consensus banner appears only on retry rounds',
      (tester) async {
    await _pump(tester, match: _match(consensusRound: 2));
    expect(find.textContaining('Versuch 2 von 3'), findsOneWidget);
  });

  testWidgets('submit posts the current draft to the remote', (tester) async {
    final fake = await _pump(tester, match: _match());
    // Set 1: tap Team-A plus 5 times to reach max, then choose Team A as king.
    final plus = find.byIcon(LucideIcons.plus).first;
    for (var i = 0; i < 5; i++) {
      await tester.tap(plus);
      await tester.pump();
    }
    await tester.tap(find.text('Team A'));
    await tester.pump();
    // Submit.
    await tester.tap(find.text('Einreichen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.lastCall, isNotNull);
    expect(fake.lastCall!.round, 1);
    expect(fake.lastCall!.scores.length, 1);
    expect(fake.lastCall!.scores.first.basekubbsKnockedByA, 5);
    expect(fake.lastCall!.scores.first.winner, SetWinner.teamA);
  });

  testWidgets('pushes the conflict screen when consensus round bumps',
      (tester) async {
    await _pump(
      tester,
      match: _match(),
      afterPropose: _match(consensusRound: 2),
    );
    final plus = find.byIcon(LucideIcons.plus).first;
    for (var i = 0; i < 5; i++) {
      await tester.tap(plus);
      await tester.pump();
    }
    await tester.tap(find.text('Team A'));
    await tester.pump();
    await tester.tap(find.text('Einreichen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('conflict-screen'), findsOneWidget);
  });

  testWidgets('finalized match shows read-only notice and hides submit',
      (tester) async {
    await _pump(
      tester,
      match: _match(status: TournamentMatchStatus.finalized),
    );
    expect(find.text('Einreichen'), findsNothing);
    expect(
      find.textContaining('Dieses Spiel ist bereits abgeschlossen'),
      findsOneWidget,
    );
  });
}
