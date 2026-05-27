// Widget tests for TASK-M4.2-T7 (Live-Dashboard).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_live_dashboard_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

const _tid = TournamentId('t-live');

TournamentMatchRef _m(String id, int n, TournamentMatchStatus s) =>
    TournamentMatchRef(
      matchId: TournamentMatchId(id),
      tournamentId: _tid,
      roundNumber: 1,
      matchNumberInRound: n,
      participantA: const TournamentParticipantId('p-a'),
      participantB: const TournamentParticipantId('p-b'),
      status: s,
      consensusRound: 1,
    );

class _Remote implements TournamentRemote {
  _Remote(this.channel, this._list);
  final FakeRealtimeChannel channel;
  List<TournamentMatchRef> _list;
  void replace(TournamentMatchRef u) =>
      _list = [for (final m in _list) m.matchId == u.matchId ? u : m];

  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
    TournamentId id,
  ) async =>
      _list;

  @override
  Stream<TournamentMatchRef> watchTournamentMatches(TournamentId id) =>
      channel
          .subscribe(
            table: 'tournament_matches',
            filterColumn: 'tournament_id',
            filterValue: id.value,
          )
          .map((c) => _list.firstWhere(
                (m) => m.matchId.value == c.newRow['id'],
              ));

  @override
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id) =>
      const Stream.empty();
  @override
  Stream<BracketAdvanceEvent> watchBracketAdvances(TournamentId id) =>
      const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

Future<_Remote> _pump(
  WidgetTester tester,
  List<TournamentMatchRef> matches,
) async {
  final remote = _Remote(FakeRealtimeChannel(), matches);
  final router = GoRouter(
    initialLocation: '/live',
    routes: [
      GoRoute(
        path: '/live',
        builder: (_, _) =>
            TournamentLiveDashboardScreen(tournamentId: _tid.value),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId',
        builder: (_, _) => const Scaffold(body: Text('match-detail')),
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
  return remote;
}

Color _borderOf(WidgetTester tester, String id) {
  final c = tester.widget<Container>(find.byKey(ValueKey('live-card-$id')));
  return ((c.decoration! as BoxDecoration).border! as Border).top.color;
}

void main() {
  final fourMatches = [
    _m('m-1', 1, TournamentMatchStatus.scheduled),
    _m('m-2', 2, TournamentMatchStatus.awaitingResults),
    _m('m-3', 3, TournamentMatchStatus.finalized),
    _m('m-4', 4, TournamentMatchStatus.disputed),
  ];

  testWidgets('renders one card per match (4 mocks)', (tester) async {
    await _pump(tester, fourMatches);
    for (final id in const ['m-1', 'm-2', 'm-3', 'm-4']) {
      expect(find.byKey(ValueKey('live-card-$id')), findsOneWidget);
    }
  });

  testWidgets('status colour matches scheduled/awaiting/finalized/disputed',
      (tester) async {
    await _pump(tester, fourMatches);
    expect(_borderOf(tester, 'm-1'), KubbTokens.stone400);
    expect(_borderOf(tester, 'm-2'), KubbTokens.wood400);
    expect(_borderOf(tester, 'm-3'), KubbTokens.meadow500);
    expect(_borderOf(tester, 'm-4'), KubbTokens.miss);
  });

  testWidgets('tap card → navigates to match detail', (tester) async {
    await _pump(tester, [_m('m-1', 1, TournamentMatchStatus.scheduled)]);
    await tester.tap(find.byKey(const ValueKey('live-card-m-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('match-detail'), findsOneWidget);
  });

  testWidgets('realtime emit flips card status', (tester) async {
    final remote = await _pump(
      tester,
      [_m('m-1', 1, TournamentMatchStatus.scheduled)],
    );
    expect(_borderOf(tester, 'm-1'), KubbTokens.stone400);
    remote.replace(_m('m-1', 1, TournamentMatchStatus.disputed));
    remote.channel.emit(
      fakeRealtimeChannelKey(
        table: 'tournament_matches',
        filterColumn: 'tournament_id',
        filterValue: _tid.value,
      ),
      RealtimeChange(
        eventType: RealtimeEventType.update,
        table: 'tournament_matches',
        rowId: 'm-1',
        newRow: const {'id': 'm-1'},
        oldRow: const {'id': 'm-1'},
        receivedAt: DateTime.utc(2026, 5, 27),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_borderOf(tester, 'm-1'), KubbTokens.miss);
  });
}
