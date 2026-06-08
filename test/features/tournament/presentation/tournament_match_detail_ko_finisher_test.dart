import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_shootout_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_match_detail_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../_helpers/sqlite_open.dart';

const _tournamentId = TournamentId('t-1');
const _matchId = TournamentMatchId('m-1');

/// Fake remote that serves a single KO match snapshot and captures the
/// proposed set scores so the tests can assert the resolved set winner.
class _FakeRemote implements TournamentRemote {
  _FakeRemote(this._match);
  final TournamentMatchRef _match;
  ({TournamentMatchId matchId, int round, List<SetScore> scores})? lastCall;

  @override
  Future<TournamentMatchRef?> getMatch(TournamentMatchId id) async => _match;

  @override
  Future<void> proposeSetScores({
    required TournamentMatchId matchId,
    required int consensusRound,
    required List<SetScore> setScores,
  }) async {
    lastCall = (matchId: matchId, round: consensusRound, scores: setScores);
  }

  @override
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id) =>
      const Stream<TournamentMatchRef>.empty();

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

TournamentDetail _detail({
  required String koTiebreakMethod,
  int basekubbsPerSide = 5,
}) {
  return TournamentDetail(
    tournament: TournamentDetailHeader(
      tournamentId: 't-1',
      displayName: 'KO-Cup',
      createdByUserId: 'u-creator',
      clubId: null,
      teamSize: 1,
      maxTeamSize: 1,
      minParticipants: 2,
      maxParticipants: 8,
      format: TournamentFormat.singleElimination,
      scoring: TournamentScoring.ekc,
      matchFormatConfig: <String, Object?>{
        'sets_to_win': 2,
        'max_sets': 3,
        'basekubbs_per_side': basekubbsPerSide,
      },
      tiebreakerOrder: const <String>['pts'],
      byePoints: null,
      forfeitPoints: null,
      status: TournamentStatus.live,
      publishedAt: null,
      startedAt: null,
      completedAt: null,
      setup: <String, Object?>{'ko_tiebreak_method': koTiebreakMethod},
    ),
    participants: const [],
    matches: const [],
    auditTail: const [],
  );
}

TournamentMatchRef _koMatch() => const TournamentMatchRef(
      matchId: _matchId,
      tournamentId: _tournamentId,
      roundNumber: 1,
      matchNumberInRound: 1,
      participantA: TournamentParticipantId('alpha1'),
      participantB: TournamentParticipantId('beta22'),
      status: TournamentMatchStatus.awaitingResults,
      consensusRound: 1,
      participantADisplayName: 'Alice',
      participantBDisplayName: 'Bob',
      phase: MatchPhase.ko,
    );

Future<_FakeRemote> _pump(
  WidgetTester tester, {
  required TournamentMatchRef match,
  required TournamentDetail detail,
  List<PendingShootout> pendingShootouts = const [],
}) async {
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = _FakeRemote(match);
  final database = await openTestDatabase();
  addTearDown(database.close);
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
        path: '/tournament/:id/shootout/:rank',
        builder: (_, _) => const Scaffold(body: Text('shootout-screen')),
      ),
      GoRoute(
        path: '/tournament/:id/matches',
        builder: (_, _) => const Scaffold(body: Text('matches')),
      ),
      GoRoute(
        path: '/tournament/:id/standings',
        builder: (_, _) => const Scaffold(body: Text('standings')),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId/conflict',
        builder: (_, _) => const Scaffold(body: Text('conflict-screen')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(fake),
        appDatabaseProvider.overrideWithValue(database),
        currentUserIdProvider.overrideWithValue('u-other'),
        tournamentDetailProvider(_tournamentId).overrideWith((_) async => detail),
        pendingShootoutsProvider(_tournamentId)
            .overrideWith((_) async => pendingShootouts),
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
  await tester.pump(const Duration(milliseconds: 16));
  return fake;
}

void main() {
  setUpAll(registerLinuxSqliteOverride);

  testWidgets('F1: KO king-less set shows the finisher prompt and blocks submit',
      (tester) async {
    await _pump(
      tester,
      match: _koMatch(),
      detail: _detail(koTiebreakMethod: 'classic_kingtoss_removal'),
    );
    // The default set has no king selected; in the KO phase that surfaces
    // the finisher prompt.
    expect(find.text('Wer hat den Finisher gewonnen?'), findsOneWidget);
    // Submit is blocked while the finisher is unresolved.
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Einreichen'),
    );
    expect(submit.onPressed, isNull);
  });

  testWidgets(
      'F2: classic variant prompts with real names and sets the chosen winner',
      (tester) async {
    final fake = await _pump(
      tester,
      match: _koMatch(),
      detail: _detail(koTiebreakMethod: 'classic_kingtoss_removal'),
    );
    // Real participant names, never literal A/B.
    expect(find.widgetWithText(InkWell, 'Alice'), findsWidgets);
    expect(find.widgetWithText(InkWell, 'Bob'), findsWidgets);
    // Choose Alice (Team A) as the finisher winner — target the finisher
    // KubbButton specifically (the set-input stepper/king-toggle now also
    // carry the real name 'Alice', so a bare find.text would be ambiguous).
    await tester.tap(find.widgetWithText(KubbButton, 'Alice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // Submit becomes enabled and proposes Team A as the set winner.
    await tester.tap(find.text('Einreichen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.lastCall, isNotNull);
    expect(fake.lastCall!.scores.first.winner, SetWinner.teamA);
    // F4: the set is decisive via the finisher (KingHitBy of A), not zeroed.
    expect(
      fake.lastCall!.scores.first.kingOutcome,
      const KingHitBy(TournamentParticipantId('alpha1')),
    );
  });

  testWidgets('F4: finisher winner ignores kubb counts (no auto-kubb fallback)',
      (tester) async {
    final fake = await _pump(
      tester,
      match: _koMatch(),
      detail: _detail(koTiebreakMethod: 'classic_kingtoss_removal'),
    );
    // Give Team B more kubbs, then resolve the finisher for Team A. The
    // winner must follow the finisher (A), not the kubb majority (B).
    final plusB = find.byIcon(LucideIcons.plus).at(1);
    for (var i = 0; i < 3; i++) {
      await tester.tap(plusB);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(KubbButton, 'Alice'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.text('Einreichen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.lastCall!.scores.first.winner, SetWinner.teamA);
    expect(fake.lastCall!.scores.first.basekubbsKnockedByB, 3);
  });

  testWidgets(
      'F3: mighty-finisher variant offers the shoot-out shortcut and routes to it',
      (tester) async {
    await _pump(
      tester,
      match: _koMatch(),
      detail: _detail(koTiebreakMethod: 'mighty_finisher_shootout'),
      pendingShootouts: [
        PendingShootout(
          shootoutId: 's-1',
          tournamentId: _tournamentId,
          startRank: 0,
          status: ShootoutStatus.pending,
          tiedParticipants: const [],
          orderedWinners: const [],
        ),
      ],
    );
    // The shoot-out shortcut is offered for the mighty-finisher method.
    expect(find.text('Shoot-out öffnen'), findsOneWidget);
    await tester.tap(find.text('Shoot-out öffnen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    // Delegates to the existing shoot-out screen rather than re-implementing.
    expect(find.text('shootout-screen'), findsOneWidget);
  });

  testWidgets(
      'F3: mighty-finisher two-way choice also feeds the canonical winner',
      (tester) async {
    final fake = await _pump(
      tester,
      match: _koMatch(),
      detail: _detail(koTiebreakMethod: 'mighty_finisher_shootout'),
    );
    await tester.tap(find.widgetWithText(KubbButton, 'Bob'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.tap(find.text('Einreichen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.lastCall!.scores.first.winner, SetWinner.teamB);
  });

  testWidgets('B1: the base-kubb stepper cap uses the config value (6)',
      (tester) async {
    await _pump(
      tester,
      match: _koMatch(),
      detail: _detail(
        koTiebreakMethod: 'classic_kingtoss_removal',
        basekubbsPerSide: 6,
      ),
    );
    // Verify the input cap is 6: tapping plus 7 times reaches 6 (the 7th
    // tap is a no-op because the stepper is capped at the config max).
    final plusA = find.byIcon(LucideIcons.plus).first;
    for (var i = 0; i < 7; i++) {
      await tester.tap(plusA);
      await tester.pump();
    }
    expect(find.text('6'), findsWidgets);
  });

  testWidgets(
      'B2: king-side needs the config max (6), not the literal 5, to submit',
      (tester) async {
    final fake = await _pump(
      tester,
      match: _koMatch(),
      detail: _detail(
        koTiebreakMethod: 'classic_kingtoss_removal',
        basekubbsPerSide: 6,
      ),
    );
    // Drive Team A's base-kubb count up to 5 (one below the config max).
    final plusA = find.byIcon(LucideIcons.plus).first;
    for (var i = 0; i < 5; i++) {
      await tester.tap(plusA);
      await tester.pump();
    }
    // Select the side-A king toggle (the king-fell-by-A option), not the
    // finisher KubbButton. M1: the toggle now carries the real name 'Alice'
    // (stepper label is the first 'Alice', the king toggle the second; the
    // finisher KubbButton is the third). This exercises the
    // king==teamA && basekubbsA != max branch.
    await tester.tap(find.text('Alice').at(1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // With 5 < config-max 6, king-needs-max validation blocks submit.
    var submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Einreichen'),
    );
    expect(submit.onPressed, isNull,
        reason: 'king side at 5 must fail when config max is 6');
    // Bump to 6 (the config max); the king-needs-max check now passes.
    await tester.tap(plusA);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Einreichen'),
    );
    expect(submit.onPressed, isNotNull,
        reason: 'king side at the config max of 6 must pass');
    await tester.tap(find.text('Einreichen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.lastCall, isNotNull);
    expect(fake.lastCall!.scores.first.basekubbsKnockedByA, 6);
    expect(fake.lastCall!.scores.first.winner, SetWinner.teamA);
  });
}
