import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_override_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:lucide_icons/lucide_icons.dart';

const _creator = 'u-creator';
const _tournamentId = TournamentId('t-1');
const _matchId = TournamentMatchId('m-1');

class _FakeRemote implements TournamentRemote {
  _FakeRemote(this._match);
  final TournamentMatchRef _match;
  ({TournamentMatchId id, List<SetScore> scores, String reason})? lastCall;

  @override
  Future<TournamentMatchRef?> getMatch(TournamentMatchId id) async => _match;

  @override
  Future<void> organizerOverride({
    required TournamentMatchId matchId,
    required List<SetScore> finalSetScores,
    required String reason,
  }) async {
    lastCall = (id: matchId, scores: finalSetScores, reason: reason);
  }

  @override
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id) =>
      const Stream<TournamentMatchRef>.empty();

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

TournamentDetail _detail() {
  return const TournamentDetail(
    tournament: TournamentDetailHeader(
      tournamentId: 't-1',
      displayName: 'Sommer-Cup',
      createdByUserId: _creator,
      clubId: null,
      teamSize: 1,
      maxTeamSize: 1,
      minParticipants: 2,
      maxParticipants: 8,
      format: TournamentFormat.roundRobin,
      scoring: TournamentScoring.ekc,
      matchFormatConfig: <String, Object?>{
        'sets_to_win': 2,
        'max_sets': 3,
        'basekubbs_per_side': 5,
      },
      tiebreakerOrder: <String>['pts'],
      byePoints: null,
      forfeitPoints: null,
      status: TournamentStatus.live,
      publishedAt: null,
      startedAt: null,
      completedAt: null,
    ),
    participants: [],
    matches: [],
    auditTail: [],
  );
}

TournamentMatchRef _match({
  TournamentMatchStatus status = TournamentMatchStatus.disputed,
}) =>
    TournamentMatchRef(
      matchId: _matchId,
      tournamentId: _tournamentId,
      roundNumber: 1,
      matchNumberInRound: 1,
      participantA: const TournamentParticipantId('alpha1'),
      participantB: const TournamentParticipantId('beta22'),
      participantADisplayName: 'Anna',
      participantBDisplayName: 'Bodo',
      status: status,
      consensusRound: 3,
    );

Future<_FakeRemote> _pump(
  WidgetTester tester, {
  required TournamentMatchRef match,
  required String? callerUserId,
  bool direct = false,
}) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = _FakeRemote(match);
  final initial = direct
      ? '/tournament/t-1/match/m-1/score'
      : '/tournament/t-1/match/m-1/override';
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(
        path: '/tournament/:id/match/:matchId/override',
        builder: (_, s) => TournamentOverrideScreen(
          tournamentId: s.pathParameters['id']!,
          matchId: s.pathParameters['matchId']!,
        ),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId/score',
        builder: (_, s) => TournamentOverrideScreen(
          tournamentId: s.pathParameters['id']!,
          matchId: s.pathParameters['matchId']!,
          direct: true,
        ),
      ),
      GoRoute(
        path: '/tournament/:id/match/:matchId',
        builder: (_, _) => const Scaffold(body: Text('match-detail')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(fake),
        tournamentDetailProvider(_tournamentId)
            .overrideWith((_) async => _detail()),
        currentUserIdProvider.overrideWithValue(callerUserId),
      ],
      child: MaterialApp.router(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  return fake;
}

void main() {
  testWidgets('non-creator sees the not-authorized gate banner',
      (tester) async {
    await _pump(tester, match: _match(), callerUserId: 'u-other');
    expect(find.text('Nicht autorisiert'), findsOneWidget);
    expect(find.text('Entscheidung speichern'), findsNothing);
  });

  testWidgets('T1: a non-terminal match (awaiting_results) renders the form',
      (tester) async {
    await _pump(
      tester,
      match: _match(status: TournamentMatchStatus.awaitingResults),
      callerUserId: _creator,
    );
    // No gate — the organizer can override a non-disputed match now.
    expect(find.textContaining('übersteuert werden'), findsNothing);
    expect(find.text('Entscheidung speichern'), findsOneWidget);
  });

  testWidgets('a terminal match (finalized) surfaces the gate message',
      (tester) async {
    await _pump(
      tester,
      match: _match(status: TournamentMatchStatus.finalized),
      callerUserId: _creator,
    );
    expect(
      find.textContaining('nicht mehr übersteuert werden'),
      findsOneWidget,
    );
    expect(find.text('Entscheidung speichern'), findsNothing);
  });

  testWidgets('submit is disabled until score is decisive and reason set',
      (tester) async {
    await _pump(tester, match: _match(), callerUserId: _creator);
    // Submit button rendered but disabled (no taps to scores or reason).
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNull);
    expect(find.textContaining('Score muss eindeutig'), findsOneWidget);
    expect(find.textContaining('Begründung ist erforderlich'), findsOneWidget);
  });

  testWidgets('valid input submits to the remote and navigates back',
      (tester) async {
    final fake = await _pump(tester, match: _match(), callerUserId: _creator);
    // Team A scores 5 basekubbs in set 1 → king.
    final plus = find.byIcon(LucideIcons.plus);
    for (var i = 0; i < 5; i++) {
      await tester.tap(plus.first);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(InkWell, 'Anna').first);
    await tester.pump();
    // Add a second set, also won by A.
    await tester.tap(find.text('Satz +'));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.tap(plus.first);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(InkWell, 'Anna').first);
    await tester.pump();
    // Enter reason.
    await tester.enterText(find.byType(TextField), 'Schiedsrichter');
    await tester.pump();
    // Submit.
    await tester.tap(find.text('Entscheidung speichern'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.lastCall, isNotNull);
    expect(fake.lastCall!.reason, 'Schiedsrichter');
    expect(fake.lastCall!.scores, hasLength(2));
  });

  // ─── W4-T07: direct score-entry mode ──────────────────────────────────

  testWidgets('direct mode reads "Punkte eintragen" and hides the reason field',
      (tester) async {
    await _pump(
      tester,
      match: _match(status: TournamentMatchStatus.scheduled),
      callerUserId: _creator,
      direct: true,
    );
    // Title + submit button both say "Punkte eintragen"; no reason field, no
    // dispute eyebrow, no proposals review.
    expect(find.text('Punkte eintragen'), findsWidgets);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Begründung'), findsNothing);
    expect(find.text('Strittiges Match'), findsNothing);
    expect(find.text('Bisherige Eingaben'), findsNothing);
  });

  testWidgets('direct mode submits with NO mandatory reason', (tester) async {
    final fake = await _pump(
      tester,
      match: _match(status: TournamentMatchStatus.scheduled),
      callerUserId: _creator,
      direct: true,
    );
    final plus = find.byIcon(LucideIcons.plus);
    for (var i = 0; i < 5; i++) {
      await tester.tap(plus.first);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(InkWell, 'Anna').first);
    await tester.pump();
    await tester.tap(find.text('Satz +'));
    await tester.pump();
    for (var i = 0; i < 5; i++) {
      await tester.tap(plus.first);
      await tester.pump();
    }
    await tester.tap(find.widgetWithText(InkWell, 'Anna').first);
    await tester.pump();
    // No reason entered — the direct path must still submit once decisive.
    final btn = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(btn.onPressed, isNotNull,
        reason: 'direct submit enables on a decisive score without a reason');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.lastCall, isNotNull);
    expect(fake.lastCall!.reason, isEmpty);
    expect(fake.lastCall!.scores, hasLength(2));
  });
}
