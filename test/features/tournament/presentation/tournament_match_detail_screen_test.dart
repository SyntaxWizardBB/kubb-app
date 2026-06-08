import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_match_detail_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../_helpers/sqlite_open.dart';

class _FakeRemote implements TournamentRemote {
  _FakeRemote(
    this._detail, {
    TournamentMatchRef? afterPropose,
    Stream<TournamentMatchRef>? matchStream,
    TournamentDetail? tournamentDetail,
  })  : _afterPropose = afterPropose,
        _matchStream = matchStream,
        _tournamentDetail = tournamentDetail;

  TournamentMatchRef _detail;
  final TournamentMatchRef? _afterPropose;
  final Stream<TournamentMatchRef>? _matchStream;
  final TournamentDetail? _tournamentDetail;
  ({TournamentMatchId matchId, int round, List<SetScore> scores})? lastCall;

  @override
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async =>
      _tournamentDetail;

  // Allow the test to mutate the snapshot that the next `getMatch`
  // call resolves to — used by the realtime-listen test where the
  // detail-provider gets invalidated by the stream event and re-reads.
  // ignore: use_setters_to_change_properties
  void setDetail(TournamentMatchRef next) => _detail = next;

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
      _matchStream ?? const Stream<TournamentMatchRef>.empty();

  // Unused for these tests.
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

TournamentMatchRef _match({
  TournamentMatchStatus status = TournamentMatchStatus.awaitingResults,
  int consensusRound = 1,
  String? aName = 'Anna',
  String? bName = 'Bodo',
}) {
  return TournamentMatchRef(
    matchId: const TournamentMatchId('m-1'),
    tournamentId: const TournamentId('t-1'),
    roundNumber: 1,
    matchNumberInRound: 1,
    participantA: const TournamentParticipantId('alpha1'),
    participantB: const TournamentParticipantId('beta22'),
    participantADisplayName: aName,
    participantBDisplayName: bName,
    status: status,
    consensusRound: consensusRound,
  );
}

Future<_FakeRemote> _pump(
  WidgetTester tester, {
  required TournamentMatchRef match,
  TournamentMatchRef? afterPropose,
  Stream<TournamentMatchRef>? matchStream,
  AppDatabase? db,
  TournamentDetail? tournamentDetail,
  String? callerUserId,
}) async {
  // Tall viewport so the bottom of the match-detail ListView (with
  // the submit button) is built without scrolling.
  tester.view.physicalSize = const Size(1080, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = _FakeRemote(
    match,
    afterPropose: afterPropose,
    matchStream: matchStream,
    tournamentDetail: tournamentDetail,
  );
  final database = db ?? await openTestDatabase();
  if (db == null) addTearDown(database.close);
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
        appDatabaseProvider.overrideWithValue(database),
        if (callerUserId != null)
          currentUserIdProvider.overrideWithValue(callerUserId),
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
  setUpAll(registerLinuxSqliteOverride);

  testWidgets('renders header, default first-set inputs and submit button',
      (tester) async {
    await _pump(tester, match: _match());
    expect(find.text('Spiel-Eingabe'), findsOneWidget);
    expect(find.text('Satz 1'), findsOneWidget);
    expect(find.text('Einreichen'), findsOneWidget);
    // M1: real names instead of the generic 'Basekubbs Team A'/'Team B'.
    // 'Anna'/'Bodo' each appear twice (stepper label + king-toggle button)
    // and in the versus header — never the generic 'Team A'/'Team B'.
    expect(find.text('Basekubbs Team A'), findsNothing);
    expect(find.text('Basekubbs Team B'), findsNothing);
    expect(find.text('Team A'), findsNothing);
    expect(find.text('Team B'), findsNothing);
    expect(find.textContaining('Anna'), findsWidgets);
    expect(find.textContaining('Bodo'), findsWidgets);
    // Versus header shows the real names.
    expect(find.text('Anna gegen Bodo'), findsOneWidget);
  });

  testWidgets('BYE match shows the real name + Freilos header, no placeholder',
      (tester) async {
    await _pump(
      tester,
      match: const TournamentMatchRef(
        matchId: TournamentMatchId('m-1'),
        tournamentId: TournamentId('t-1'),
        roundNumber: 1,
        matchNumberInRound: 1,
        participantA: TournamentParticipantId('alpha1'),
        participantB: null,
        participantADisplayName: 'Anna',
        status: TournamentMatchStatus.scheduled,
        consensusRound: 1,
      ),
    );
    expect(find.text('Freilos'), findsOneWidget);
    expect(find.text('Team A'), findsNothing);
    expect(find.text('Team B'), findsNothing);
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
    await tester.tap(find.text('Anna').last);
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
    await tester.tap(find.text('Anna').last);
    await tester.pump();
    await tester.tap(find.text('Einreichen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('conflict-screen'), findsOneWidget);
  });

  testWidgets(
      'routes to the conflict screen when realtime flips status to disputed',
      (tester) async {
    // R10-F-13 / MUSS-Fix #2: a realtime event flipping the match to
    // `disputed` while the detail screen is mounted must actively
    // navigate to the conflict screen instead of leaving the user on
    // the (now stale) score-entry view.
    final controller = StreamController<TournamentMatchRef>.broadcast();
    addTearDown(controller.close);
    final disputed =
        _match(status: TournamentMatchStatus.disputed, consensusRound: 2);
    final fake = await _pump(
      tester,
      match: _match(),
      matchStream: controller.stream,
    );
    // Sanity: we start on the detail screen, not the conflict one.
    expect(find.text('conflict-screen'), findsNothing);
    expect(find.text('Einreichen'), findsOneWidget);
    // Flip the snapshot the detail-provider will see on its re-read,
    // then emit a realtime event so the realtime provider invalidates
    // the detail provider.
    fake.setDetail(disputed);
    controller.add(disputed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.text('conflict-screen'), findsOneWidget);
  });

  testWidgets('pre-fills inputs from persisted draft on reopen (DSCORE-20)',
      (tester) async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    // Seed a draft for the round the screen will hydrate.
    await db.tournamentScoreDraftDao.save(
      const TournamentMatchId('m-1'),
      1,
      [
        SetScore(
          basekubbsKnockedByA: 5,
          basekubbsKnockedByB: 3,
          winner: SetWinner.teamA,
        ),
      ],
    );
    await _pump(tester, match: _match(), db: db);
    // The hydration is async; one extra frame for the notifier to flush.
    await tester.pump();
    expect(find.text('5'), findsWidgets);
    expect(find.text('3'), findsWidgets);
  });

  testWidgets('persists every edit to drift (DSCORE-19)', (tester) async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    await _pump(tester, match: _match(), db: db);
    final plus = find.byIcon(LucideIcons.plus).first;
    for (var i = 0; i < 3; i++) {
      await tester.tap(plus);
      await tester.pump();
    }
    // Each tap upserts asynchronously; settle the queue.
    await tester.pump(const Duration(milliseconds: 16));
    final loaded =
        await db.tournamentScoreDraftDao.load(const TournamentMatchId('m-1'), 1);
    expect(loaded, isNotNull);
    expect(loaded!.single.basekubbsKnockedByA, 3);
  });

  testWidgets('clears draft after a successful submit (DSCORE-21)',
      (tester) async {
    final db = await openTestDatabase();
    addTearDown(db.close);
    await _pump(tester, match: _match(), db: db);
    final plus = find.byIcon(LucideIcons.plus).first;
    for (var i = 0; i < 5; i++) {
      await tester.tap(plus);
      await tester.pump();
    }
    await tester.tap(find.text('Anna').last);
    await tester.pump();
    await tester.tap(find.text('Einreichen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final remaining =
        await db.tournamentScoreDraftDao.load(const TournamentMatchId('m-1'), 1);
    expect(remaining, isNull);
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

  // O1: the live-dashboard was removed; the organizer forfeit entry must
  // still be reachable from the match-detail screen. Creator + live
  // tournament + open match => the "Forfeit erklären" action is present.
  testWidgets('organizer (creator) sees the forfeit action on a live match',
      (tester) async {
    await _pump(
      tester,
      match: _match(),
      callerUserId: 'creator-1',
      tournamentDetail: _liveDetailOwnedBy('creator-1'),
    );
    expect(find.text('Forfeit erklären'), findsOneWidget);
  });

  testWidgets('non-creator does not see the forfeit action', (tester) async {
    await _pump(
      tester,
      match: _match(),
      callerUserId: 'someone-else',
      tournamentDetail: _liveDetailOwnedBy('creator-1'),
    );
    expect(find.text('Forfeit erklären'), findsNothing);
  });
}

/// Minimal [TournamentDetail] whose header is `live` and was created by
/// [creatorUserId] — enough to flip `canForfeit` in the match-detail
/// screen (creator + live + both sides present).
TournamentDetail _liveDetailOwnedBy(String creatorUserId) => TournamentDetail(
      tournament: TournamentDetailHeader(
        tournamentId: 't-1',
        displayName: 'Test-Turnier',
        createdByUserId: creatorUserId,
        clubId: null,
        teamSize: 1,
        maxTeamSize: 1,
        minParticipants: 2,
        maxParticipants: 8,
        format: TournamentFormat.swiss,
        scoring: TournamentScoring.ekc,
        matchFormatConfig: const <String, Object?>{},
        tiebreakerOrder: const <String>[],
        byePoints: null,
        forfeitPoints: null,
        status: TournamentStatus.live,
        publishedAt: null,
        startedAt: null,
        completedAt: null,
      ),
      participants: const <TournamentParticipant>[],
      matches: const <TournamentMatchRef>[],
      auditTail: const <TournamentAuditEvent>[],
    );
