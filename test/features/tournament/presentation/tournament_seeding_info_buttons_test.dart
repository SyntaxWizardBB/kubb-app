import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_bottom_sheet.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_seeding_screen.dart';
import 'package:kubb_app/features/tournament/presentation/widgets/info_icon_button.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _tournamentId = TournamentId('t-1');

class _FakeRemote implements TournamentRemote {
  @override
  Future<List<TournamentParticipantId>> autoseedFromElo(
    TournamentId tournamentId,
  ) async =>
      const <TournamentParticipantId>[];

  @override
  Future<void> setSeeding({
    required TournamentId tournamentId,
    required Map<TournamentParticipantId, int> seeds,
  }) async {}

  @override
  Future<void> startKoPhase(
    TournamentId tournamentId,
    KoPhaseConfig config,
  ) async {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

List<ParticipantStats> _standings() => const <ParticipantStats>[
      ParticipantStats(
        participantId: 'alpha1',
        totalPoints: 6,
        wins: 3,
        kubbsScored: 30,
        kubbsConceded: 10,
        opponentIds: <String>[],
        opponentTotalPointsLookup: <String, int>{},
        headToHeadLookup: <String, int>{},
      ),
      ParticipantStats(
        participantId: 'beta22',
        totalPoints: 4,
        wins: 2,
        kubbsScored: 20,
        kubbsConceded: 15,
        opponentIds: <String>[],
        opponentTotalPointsLookup: <String, int>{},
        headToHeadLookup: <String, int>{},
      ),
    ];

TournamentDetail _detail() => const TournamentDetail(
      tournament: TournamentDetailHeader(
        tournamentId: 't-1',
        displayName: 'Sommer-Cup',
        createdByUserId: 'u-creator',
        clubId: null,
        teamSize: 1,
        maxTeamSize: 1,
        minParticipants: 2,
        maxParticipants: 8,
        format: TournamentFormat.roundRobinThenKo,
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
      participants: <TournamentParticipant>[],
      matches: <TournamentMatchRef>[],
      auditTail: <TournamentAuditEvent>[],
    );

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/tournament/t-1/seeding',
    routes: <RouteBase>[
      GoRoute(
        path: '/tournament/:id/seeding',
        builder: (_, s) =>
            TournamentSeedingScreen(tournamentId: s.pathParameters['id']!),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(_FakeRemote()),
        tournamentStandingsProvider(_tournamentId)
            .overrideWith((_) async => _standings()),
        tournamentDetailProvider(_tournamentId)
            .overrideWith((_) async => _detail()),
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
}

void main() {
  testWidgets('one head info affordance, not one per action button',
      (tester) async {
    await _pump(tester);

    // The per-button glyphs are gone; a single info affordance sits at the
    // screen head next to the eyebrow.
    expect(find.byType(InfoIconButton), findsOneWidget);
  });

  testWidgets('head info opens a sheet explaining the seeding screen',
      (tester) async {
    await _pump(tester);

    await tester.tap(find.byType(InfoIconButton));
    await tester.pumpAndSettle();

    final sheet = find.widgetWithText(KubbBottomSheet, 'Setzliste');
    expect(sheet, findsOneWidget);
    expect(
      find.descendant(
        of: sheet,
        matching: find.textContaining('Erst nach dem Speichern'),
      ),
      findsOneWidget,
    );
  });
}
