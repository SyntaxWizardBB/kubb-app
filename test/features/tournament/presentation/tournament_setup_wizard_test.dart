import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_setup_wizard.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

class _FakeTournamentRemote implements TournamentRemote {
  String? createdDisplayName;
  int? createdSetsToWin;
  TournamentFormat? createdFormat;
  int callCount = 0;
  bool failNext = false;

  @override
  Future<TournamentId> createTournament({
    required String displayName,
    required int teamSize,
    required int minParticipants,
    required int maxParticipants,
    required TournamentFormat format,
    required Map<String, Object?> matchFormatConfig,
    required List<String> tiebreakerOrder,
  }) async {
    callCount += 1;
    if (failNext) {
      failNext = false;
      throw StateError('boom');
    }
    createdDisplayName = displayName;
    createdSetsToWin = matchFormatConfig['sets_to_win'] as int?;
    createdFormat = format;
    return const TournamentId('t-fake-1');
  }

  @override
  Future<List<TournamentSummaryRef>> listTournaments({
    TournamentStatus? statusFilter,
    int limit = 50,
  }) async =>
      const <TournamentSummaryRef>[];

  @override
  Future<TournamentSummaryRef?> getTournament(TournamentId id) async => null;

  @override
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async => null;

  @override
  Future<void> publish(TournamentId id) async {}

  @override
  Future<void> openRegistration(TournamentId id) async {}

  @override
  Future<void> closeRegistration(TournamentId id) async {}

  @override
  Future<void> startTournament(TournamentId id) async {}

  @override
  Future<void> finalizeTournament(TournamentId id) async {}

  @override
  Future<void> abortTournament(TournamentId id) async {}

  @override
  Future<TournamentParticipantId> registerSingle(TournamentId id) async =>
      const TournamentParticipantId('p-1');

  @override
  Future<void> withdrawRegistration(TournamentParticipantId participantId) async {}

  @override
  Future<void> confirmRegistration(TournamentParticipantId participantId) async {}

  @override
  Future<void> rejectRegistration(TournamentParticipantId participantId) async {}

  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
          TournamentId id) async =>
      const <TournamentMatchRef>[];

  @override
  Future<TournamentMatchRef?> getMatch(TournamentMatchId id) async => null;

  @override
  Future<void> proposeSetScores({
    required TournamentMatchId matchId,
    required int consensusRound,
    required List<SetScore> setScores,
  }) async {}

  @override
  Future<void> organizerOverride({
    required TournamentMatchId matchId,
    required List<SetScore> finalSetScores,
    required String reason,
  }) async {}

  @override
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id) =>
      const Stream<TournamentMatchRef>.empty();

  @override
  Future<void> setSeeding({
    required TournamentId tournamentId,
    required Map<TournamentParticipantId, int> seeds,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> startKoPhase(TournamentId tournamentId, KoPhaseConfig config) {
    throw UnimplementedError();
  }

  @override
  Future<void> overrideKoPairing({
    required TournamentMatchId matchId,
    required TournamentParticipantId participantA,
    required TournamentParticipantId participantB,
    required String reason,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<Bracket> getBracket(TournamentId tournamentId) {
    throw UnimplementedError();
  }

  @override
  Future<TournamentParticipantId> registerTeam({
    required TournamentId tournamentId,
    required TeamId teamId,
    required List<RosterSlotInput> roster,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> replaceRosterSlot({
    required TournamentParticipantId participantId,
    required int slotIndex,
    required RosterSlotInput newOccupant,
    String? reason,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<RosterSlot>> getRoster(TournamentParticipantId participantId) {
    throw UnimplementedError();
  }

  @override
  Future<void> startPoolPhase(
    TournamentId tournamentId,
    PoolPhaseConfig config,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<PoolGroupStandings>> getPoolStandings(TournamentId id) {
    throw UnimplementedError();
  }

  @override
  Future<void> resolveCrossPoolTie(
    TournamentId tournamentId,
    List<TournamentParticipantId> orderedParticipants,
  ) {
    throw UnimplementedError();
  }
}

/// Controller variant that starts the draft in a hybrid format so the
/// dynamic step list exposes the league + KO-config steps (T13 acceptance
/// 1 — `_totalSteps = 6` for `round_robin_then_ko`).
class _KoSeededController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => const TournamentConfigDraft(
        format: TournamentFormat.roundRobinThenKo,
      );
}

Future<_FakeTournamentRemote> _pumpWizard(
  WidgetTester tester, {
  List<Object> extraOverrides = const <Object>[],
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fake = _FakeTournamentRemote();
  final router = GoRouter(
    initialLocation: TournamentRoutes.newTournament,
    routes: [
      GoRoute(
        path: TournamentRoutes.newTournament,
        builder: (_, _) => const TournamentSetupWizard(),
      ),
      GoRoute(
        path: '${TournamentRoutes.list}/:id',
        builder: (_, state) => Scaffold(
          body: Text('detail:${state.pathParameters['id']}'),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Object>[
        tournamentRemoteProvider.overrideWithValue(fake),
        ...extraOverrides,
      ].cast(),
      child: MaterialApp.router(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('de'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _typeName(WidgetTester tester, String name) async {
  await tester.enterText(find.byType(TextField), name);
  await tester.pumpAndSettle();
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lands on step 1 with progress "Schritt 1 von 4"',
      (tester) async {
    await _pumpWizard(tester);
    expect(find.text('Schritt 1 von 4'), findsOneWidget);
    expect(find.text('STAMMDATEN'), findsOneWidget);
  });

  testWidgets('next is disabled until a valid name is entered',
      (tester) async {
    await _pumpWizard(tester);
    final next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Weiter'),
    );
    expect(next.onPressed, isNull);

    await _typeName(tester, 'Cup 2026');
    final next2 = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Weiter'),
    );
    expect(next2.onPressed, isNotNull);
  });

  testWidgets('steps through all four screens and updates progress label',
      (tester) async {
    await _pumpWizard(tester);
    await _typeName(tester, 'Cup 2026');

    await _tapNext(tester); // -> step 2
    expect(find.text('Schritt 2 von 4'), findsOneWidget);
    expect(find.text('TEILNEHMER'), findsOneWidget);

    await _tapNext(tester); // -> step 3
    expect(find.text('Schritt 3 von 4'), findsOneWidget);
    expect(find.text('FORMAT'), findsOneWidget);

    await _tapNext(tester); // -> step 4
    expect(find.text('Schritt 4 von 4'), findsOneWidget);
    expect(find.text('ÜBERSICHT'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Turnier anlegen'),
        findsOneWidget);
  });

  testWidgets(
      'round_robin_then_ko unlocks league + ko steps for a total of 6 (T13)',
      (tester) async {
    await _pumpWizard(
      tester,
      extraOverrides: [
        tournamentConfigControllerProvider
            .overrideWith(_KoSeededController.new),
      ],
    );
    expect(find.text('Schritt 1 von 6'), findsOneWidget);

    await _typeName(tester, 'KO Cup');
    await _tapNext(tester); // -> participants
    expect(find.text('Schritt 2 von 6'), findsOneWidget);
    await _tapNext(tester); // -> format
    expect(find.text('Schritt 3 von 6'), findsOneWidget);
    await _tapNext(tester); // -> league (T12)
    expect(find.text('Schritt 4 von 6'), findsOneWidget);
    expect(find.text('LIGA-WERTUNG'), findsOneWidget);
    await _tapNext(tester); // -> ko config (T13)
    expect(find.text('Schritt 5 von 6'), findsOneWidget);
    expect(find.text('KO-KONFIGURATION'), findsOneWidget);
    // Smart default for 8 participants is 4 → preview shows bracket 8,
    // 4 BYEs, but the smarter case is exercised explicitly in the
    // helper-widget test file. Sanity-check the preview is rendered.
    expect(find.textContaining('Bracket-Grösse'), findsOneWidget);
  });

  testWidgets('submit calls createTournament with the configured draft',
      (tester) async {
    final fake = await _pumpWizard(tester);
    await _typeName(tester, 'Cup 2026');
    await _tapNext(tester);
    await _tapNext(tester);
    await _tapNext(tester);

    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await tester.pumpAndSettle();

    expect(fake.callCount, 1);
    expect(fake.createdDisplayName, 'Cup 2026');
    expect(fake.createdSetsToWin, 2);
    expect(fake.createdFormat, TournamentFormat.roundRobin);
    expect(find.text('detail:t-fake-1'), findsOneWidget);
  });
}
