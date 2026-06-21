import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/application/tournament_seeding_controller.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_seeding_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _tournamentId = TournamentId('t-1');
const _alpha = TournamentParticipantId('alpha1');
const _beta = TournamentParticipantId('beta22');
const _gamma = TournamentParticipantId('gamma3');

class _FakeRemote implements TournamentRemote {
  ({TournamentId id, Map<TournamentParticipantId, int> seeds})? setSeedingCall;
  ({TournamentId id, KoPhaseConfig config})? startKoCall;
  TournamentId? autoseedCall;

  /// Order [autoseedFromElo] returns — defaults to the reversed standings
  /// so a test can assert the screen reflects the server-side result.
  List<TournamentParticipantId> autoseedResult =
      const <TournamentParticipantId>[_gamma, _beta, _alpha];

  @override
  Future<List<TournamentParticipantId>> autoseedFromElo(
    TournamentId tournamentId,
  ) async {
    autoseedCall = tournamentId;
    return autoseedResult;
  }

  @override
  Future<void> setSeeding({
    required TournamentId tournamentId,
    required Map<TournamentParticipantId, int> seeds,
  }) async {
    setSeedingCall = (id: tournamentId, seeds: seeds);
  }

  @override
  Future<void> startKoPhase(
    TournamentId tournamentId,
    KoPhaseConfig config,
  ) async {
    startKoCall = (id: tournamentId, config: config);
  }

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
      ParticipantStats(
        participantId: 'gamma3',
        totalPoints: 2,
        wins: 1,
        kubbsScored: 10,
        kubbsConceded: 20,
        opponentIds: <String>[],
        opponentTotalPointsLookup: <String, int>{},
        headToHeadLookup: <String, int>{},
      ),
    ];

TournamentDetail _detail() {
  return const TournamentDetail(
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
}

Future<(_FakeRemote, GoRouter)> _pump(
  WidgetTester tester, {
  List<ParticipantStats>? standings,
}) async {
  tester.view.physicalSize = const Size(1080, 3200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = _FakeRemote();
  final router = GoRouter(
    initialLocation: '/tournament/t-1/seeding',
    routes: <RouteBase>[
      GoRoute(
        path: '/tournament/:id/seeding',
        builder: (_, s) =>
            TournamentSeedingScreen(tournamentId: s.pathParameters['id']!),
      ),
      GoRoute(
        path: '/tournament/:id/bracket',
        builder: (_, _) => const Scaffold(body: Text('bracket-screen')),
      ),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(fake),
        tournamentStandingsProvider(_tournamentId)
            .overrideWith((_) async => standings ?? _standings()),
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
  // Resolve futures + post-frame seed callback.
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
  return (fake, router);
}

void main() {
  testWidgets('renders auto-seed order from the standings provider',
      (tester) async {
    await _pump(tester);
    final positions = <int>[
      for (final t in tester.widgetList<Text>(find.textContaining('Position ')))
        int.tryParse(t.data!.split(' ').last) ?? 0,
    ];
    expect(positions, <int>[1, 2, 3]);
    // Participant labels rendered (their ids — wired to the row count).
    expect(find.text('alpha1'), findsOneWidget);
    expect(find.text('beta22'), findsOneWidget);
    expect(find.text('gamma3'), findsOneWidget);
  });

  testWidgets(
      'restore button reverts manual reorder back to auto baseline',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(_FakeRemote()),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container
        .read(tournamentSeedingControllerProvider(_tournamentId).notifier);
    final config = KoPhaseConfig(qualifierCount: 3, participantCount: 3);
    notifier
      ..seed(
        auto: const <TournamentParticipantId>[_alpha, _beta, _gamma],
        config: config,
      )
      ..reorder(0, 3); // alpha → end
    var state =
        container.read(tournamentSeedingControllerProvider(_tournamentId));
    expect(state.order, <TournamentParticipantId>[_beta, _gamma, _alpha]);
    expect(state.isDirty, isTrue);
    notifier.restoreAuto();
    state = container.read(tournamentSeedingControllerProvider(_tournamentId));
    expect(state.order, <TournamentParticipantId>[_alpha, _beta, _gamma]);
    expect(state.isDirty, isFalse);
  });

  testWidgets('save button calls setSeeding with 1-based positions',
      (tester) async {
    final (fake, _) = await _pump(tester);
    await tester.tap(find.text('Seeding speichern'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(fake.setSeedingCall, isNotNull);
    expect(fake.setSeedingCall!.id, _tournamentId);
    expect(fake.setSeedingCall!.seeds, <TournamentParticipantId, int>{
      _alpha: 1,
      _beta: 2,
      _gamma: 3,
    });
  });

  testWidgets(
      'KO start triggers startKoPhase and navigates to bracket on success',
      (tester) async {
    final (fake, router) = await _pump(tester);
    await tester.tap(find.text('KO starten'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(fake.startKoCall, isNotNull);
    expect(fake.startKoCall!.id, _tournamentId);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/tournament/t-1/bracket',
    );
    expect(find.text('bracket-screen'), findsOneWidget);
  });

  testWidgets(
      'auto-seed button calls autoseedFromElo and reflects the returned order',
      (tester) async {
    final (fake, _) = await _pump(tester);

    // Baseline: standings order alpha, beta, gamma (top → bottom).
    expect(
      tester.getCenter(find.text('alpha1')).dy <
          tester.getCenter(find.text('gamma3')).dy,
      isTrue,
    );

    await tester.tap(find.text('Aus ELO-Wertung'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    // The RPC was invoked for this tournament.
    expect(fake.autoseedCall, _tournamentId);

    // The screen now reflects the returned order: gamma, beta, alpha
    // (top → bottom) — the reverse of the standings baseline.
    expect(
      tester.getCenter(find.text('gamma3')).dy <
          tester.getCenter(find.text('beta22')).dy,
      isTrue,
    );
    expect(
      tester.getCenter(find.text('beta22')).dy <
          tester.getCenter(find.text('alpha1')).dy,
      isTrue,
    );
  });

  testWidgets('empty standings surface the empty placeholder',
      (tester) async {
    await _pump(tester, standings: <ParticipantStats>[]);
    expect(find.text('Noch keine qualifizierten Teilnehmer.'), findsOneWidget);
    expect(find.text('KO starten'), findsNothing);
  });

  // CF6-08(c): the seeding screen is reachable through the *new* GoRoute
  // addressed via the TournamentRoutes.seeding(id) helper — i.e. the same
  // path constant registered in lib/app/router.dart. We build a router that
  // starts away from seeding, navigate via go(TournamentRoutes.seeding(id)),
  // and assert the screen renders for the parsed tournamentId.
  testWidgets('reachable via TournamentRoutes.seeding(id) GoRoute',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final fake = _FakeRemote();
    // Route path is '/tournament/:id/seeding'; seedingBase + the param
    // segment must compose to exactly that, which TournamentRoutes.seeding
    // guarantees ('$seedingBase/$id/seeding').
    final router = GoRouter(
      initialLocation: '/home',
      routes: <RouteBase>[
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('home-screen')),
        ),
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
          tournamentRemoteProvider.overrideWithValue(fake),
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
    expect(find.text('home-screen'), findsOneWidget);

    // Navigate through the new route via the TournamentRoutes helper.
    expect(TournamentRoutes.seeding('t-1'), '/tournament/t-1/seeding');
    router.go(TournamentRoutes.seeding('t-1'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(TournamentSeedingScreen), findsOneWidget);
    expect(
      tester
          .widget<TournamentSeedingScreen>(find.byType(TournamentSeedingScreen))
          .tournamentId,
      't-1',
    );
    // The seeding editor's primary action confirms it rendered.
    expect(find.text('Seeding speichern'), findsOneWidget);
  });
}
