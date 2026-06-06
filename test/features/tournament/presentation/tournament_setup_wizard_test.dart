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
  int? createdTeamSize;
  Map<String, Object?>? createdSetup;
  int callCount = 0;
  bool failNext = false;

  // P7 edit-after-publish capture.
  TournamentId? updatedId;
  String? updatedDisplayName;
  Map<String, Object?>? updatedSetup;
  int updateCallCount = 0;

  @override
  Future<TournamentId> createTournament({
    required String displayName,
    required int teamSize,
    required int minParticipants,
    required int maxParticipants,
    required TournamentFormat format,
    required Map<String, Object?> matchFormatConfig,
    required List<String> tiebreakerOrder,
    Map<String, Object?> setup = const <String, Object?>{},
  }) async {
    callCount += 1;
    if (failNext) {
      failNext = false;
      throw StateError('boom');
    }
    createdDisplayName = displayName;
    createdSetsToWin = matchFormatConfig['sets_to_win'] as int?;
    createdFormat = format;
    createdTeamSize = teamSize;
    createdSetup = setup;
    return const TournamentId('t-fake-1');
  }

  @override
  Future<void> updateTournament({
    required TournamentId id,
    required String displayName,
    required int teamSize,
    required int minParticipants,
    required int maxParticipants,
    required TournamentFormat format,
    required Map<String, Object?> matchFormatConfig,
    required List<String> tiebreakerOrder,
    Map<String, Object?> setup = const <String, Object?>{},
  }) async {
    updateCallCount += 1;
    if (failNext) {
      failNext = false;
      throw StateError('boom');
    }
    updatedId = id;
    updatedDisplayName = displayName;
    updatedSetup = setup;
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
  Future<List<MyTournamentRegistration>> listMyRegistrations() async =>
      const <MyTournamentRegistration>[];

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
  Future<void> declareForfeit({
    required TournamentMatchId matchId,
    required ForfeitAbsentSide absentSide,
    required String reason,
  }) async {}

  @override
  Future<TournamentMatchRef> proposeSetScoreWithLamport({
    required TournamentMatchId matchId,
    required int consensusRound,
    required int setIndex,
    required TournamentParticipantId submitter,
    required SetScore score,
    required int lamportCounter,
    required String deviceId,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<TournamentMatchRef> watchMatch(TournamentMatchId id) =>
      const Stream<TournamentMatchRef>.empty();

  @override
  Stream<TournamentMatchRef> watchTournamentMatches(TournamentId tournamentId) =>
      const Stream<TournamentMatchRef>.empty();

  @override
  Stream<BracketAdvanceEvent> watchBracketAdvances(TournamentId tournamentId) =>
      const Stream<BracketAdvanceEvent>.empty();

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
  Future<List<TournamentParticipantId>> autoseedFromElo(
    TournamentId tournamentId,
  ) {
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

  @override
  Future<List<PendingShootout>> listPendingShootouts(
    TournamentId tournamentId,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> reportShootoutWinners({
    required String shootoutId,
    required List<TournamentParticipantId> orderedWinners,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> confirmShootout({
    required String shootoutId,
    required List<TournamentParticipantId> orderedWinners,
  }) {
    throw UnimplementedError();
  }
}

/// Required Stammdaten fields (W1 / K03, K30-K33) merged onto a draft so
/// navigation-focused tests can advance past the (now stricter) step 1
/// without driving every date picker. Spasstournier (no club) so no league
/// category is required (K29).
TournamentConfigDraft _withStammdaten(TournamentConfigDraft d) {
  final start = DateTime(2026, 8, 1, 10);
  return d.copyWith(
    clubChoiceMade: true,
    location: 'Esp',
    venueAddress: 'Sportplatz Esp, Fislisbach',
    eventStartsAt: start,
    registrationClosesAt: start.subtract(const Duration(days: 7)),
    checkinUntil: start.subtract(const Duration(minutes: 30)),
  );
}

/// Default controller for [_pumpWizard]: a group-phase draft with the
/// required Stammdaten pre-filled so the wizard can walk past step 1.
class _StammdatenSeededController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => _withStammdaten(super.build());
}

/// Controller variant that starts the draft on a Schoch Vorrunde so the
/// group-phase (pool) step is hidden — yielding the minimal 5-step flow
/// (name, Vorrunde, KO-config, summary; every tournament has a KO stage).
class _SchochSeededController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => _withStammdaten(
        const TournamentConfigDraft(
          format: TournamentFormat.swissThenKo,
          vorrundeType: VorrundeType.schoch,
        ),
      );
}

/// Controller variant seeded as Trostturnier (consolation) on a Schoch
/// Vorrunde, used to assert the Model-B config inputs surface.
class _ConsolationSeededController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => _withStammdaten(
        const TournamentConfigDraft(
          format: TournamentFormat.swissThenKo,
          vorrundeType: VorrundeType.schoch,
          koType: KoType.consolation,
        ),
      );
}

Future<_FakeTournamentRemote> _pumpWizard(
  WidgetTester tester, {
  List<Object> extraOverrides = const <Object>[],
  TournamentConfigController Function()? controllerOverride,
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
        path: '${TournamentRoutes.detail}/:id',
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
        // Default: a draft with the required Stammdaten pre-filled (W1) so
        // navigation tests can advance past step 1. A test may swap in its
        // own controller via [controllerOverride] (e.g. Schoch/consolation
        // seeds); those seeds also include the Stammdaten via [_withStammdaten].
        tournamentConfigControllerProvider.overrideWith(
          controllerOverride ?? _StammdatenSeededController.new,
        ),
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

/// Pumps the wizard in EDIT mode for [editId], pre-seeded from
/// [initialDraft]. Mirrors [_pumpWizard] but constructs the wizard with
/// the P7 edit parameters so submit routes through `updateTournament`.
Future<_FakeTournamentRemote> _pumpEditWizard(
  WidgetTester tester, {
  required TournamentId editId,
  required TournamentConfigDraft initialDraft,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fake = _FakeTournamentRemote();
  final router = GoRouter(
    initialLocation: TournamentRoutes.edit(editId.value),
    routes: [
      GoRoute(
        path: '/tournament/:id/edit',
        builder: (_, _) => TournamentSetupWizard(editId: editId),
      ),
      GoRoute(
        path: '${TournamentRoutes.detail}/:id',
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
        tournamentConfigControllerProvider.overrideWith(
          () => TournamentConfigController(initialDraft),
        ),
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
  await tester.enterText(find.byKey(const Key('wizardNameField')), name);
  await tester.pumpAndSettle();
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lands on step 1, step name is the bold app-bar title (DOD-04)',
      (tester) async {
    await _pumpWizard(tester);
    // K25: the separate group-phase step is gone — group config now lives in
    // the Vorrunde step, so every flow has 5 visible steps.
    expect(find.text('Schritt 1 von 5'), findsOneWidget);
    // Title hierarchy: step name as the (mixed-case) title; "Neues Turnier"
    // as the uppercased eyebrow above it.
    expect(find.text('Stammdaten'), findsOneWidget);
    expect(find.text('NEUES TURNIER'), findsOneWidget);
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

  testWidgets(
      'group-phase flow walks name → Teilnehmer → Vorrunde → KO → Übersicht'
      ' (K25: no separate group-phase step)', (tester) async {
    final fake = await _pumpWizard(tester);
    await _typeName(tester, 'Cup 2026');

    await _tapNext(tester); // -> participants
    expect(find.text('Schritt 2 von 5'), findsOneWidget);
    expect(find.text('Teilnehmer'), findsOneWidget);

    await _tapNext(tester); // -> Vorrunde (renamed from "Format")
    expect(find.text('Schritt 3 von 5'), findsOneWidget);
    expect(find.text('Vorrunde'), findsWidgets);
    // K12: group count + grouping strategy are configured inline here.
    expect(find.text('Anzahl Gruppen'), findsOneWidget);
    expect(find.text('Grouping-Strategie'), findsOneWidget);

    await _tapNext(tester); // -> KO config (no separate group-phase step)
    expect(find.text('Schritt 4 von 5'), findsOneWidget);
    expect(find.text('KO-Konfiguration'), findsOneWidget);

    await _tapNext(tester); // -> summary
    expect(find.text('Schritt 5 von 5'), findsOneWidget);
    expect(find.text('Übersicht'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await tester.pumpAndSettle();
    expect(fake.callCount, 1);
    expect(fake.createdFormat, TournamentFormat.roundRobinThenKo);
    // K25: a valid pool_phase_config is still produced from the inline inputs.
    final pool =
        fake.createdSetup?['pool_phase_config'] as Map<String, Object?>?;
    expect(pool, isNotNull);
    expect(pool?['group_count'], 4);
    // Default 8 participants → KO smart-default 4 qualifiers → bracket size 4;
    // 4 / 4 groups → 1 qualifier per group (derived, not an input).
    expect(pool?['qualifiers_per_group'], 1);
  });

  testWidgets(
      'Schoch Vorrunde hides the group-phase step → 5-step flow with KO',
      (tester) async {
    final fake = await _pumpWizard(
      tester,
      controllerOverride: _SchochSeededController.new,
    );
    expect(find.text('Schritt 1 von 5'), findsOneWidget);

    await _typeName(tester, 'Schoch Cup');
    await _tapNext(tester); // -> participants
    expect(find.text('Schritt 2 von 5'), findsOneWidget);
    await _tapNext(tester); // -> Vorrunde
    expect(find.text('Schritt 3 von 5'), findsOneWidget);
    // The shared Schoch/Swiss rounds slider surfaces for the Schoch axis.
    expect(find.byType(Slider), findsOneWidget);
    await _tapNext(tester); // -> KO config (no group-phase step)
    expect(find.text('Schritt 4 von 5'), findsOneWidget);
    expect(find.text('KO-Konfiguration'), findsOneWidget);
    await _tapNext(tester); // -> summary
    expect(find.text('Schritt 5 von 5'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await tester.pumpAndSettle();
    expect(fake.createdFormat, TournamentFormat.swissThenKo);
    // Schoch auto-fills a single-pool pool_phase_config (group_count == 1, all
    // participants in one pool) even though the pool-config step is hidden, so
    // tournament_start no longer fails with "pool_phase_config required for
    // hybrid format".
    final pool =
        fake.createdSetup?['pool_phase_config'] as Map<String, Object?>?;
    expect(pool, isNotNull);
    expect(pool?['group_count'], 1);
    expect(pool?['strategy'], 'seeded');
    // qualifiers_per_group tracks the KO qualifier count chosen in the KO step.
    expect(pool?['qualifiers_per_group'], isNotNull);
  });

  testWidgets('no "Kein K.-o." option remains; three KO choices are offered',
      (tester) async {
    await _pumpWizard(tester);
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde

    expect(find.text('Kein K.-o.'), findsNothing);
    expect(find.text('Single-Out'), findsOneWidget);
    expect(find.text('Double-Elimination'), findsOneWidget);
    expect(find.text('Trostturnier'), findsOneWidget);
  });

  testWidgets(
      'K15: Model-B config is NEVER in the format step — even for Trostturnier',
      (tester) async {
    await _pumpWizard(
      tester,
      controllerOverride: _SchochSeededController.new,
    );
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde (format step)
    expect(
      find.byKey(const Key('wizardConsolationKoSection')),
      findsNothing,
    );

    // Picking Trostturnier in the format step must NOT reveal the Model-B
    // section here anymore (K15: it lives in the KO step).
    await tester.tap(find.text('Trostturnier'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('wizardConsolationKoSection')),
      findsNothing,
    );
  });

  testWidgets(
      'K15/K16/K18: Model-B section (chips + required name) renders in the KO '
      'step for the Trostturnier KO type', (tester) async {
    await _pumpWizard(
      tester,
      controllerOverride: _ConsolationSeededController.new,
    );
    await _typeName(tester, 'Trost Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde (format step)
    // Not here (K15).
    expect(
      find.byKey(const Key('wizardConsolationKoSection')),
      findsNothing,
    );
    await _tapNext(tester); // -> KO config
    // The whole Model-B section is in the KO step.
    expect(
      find.byKey(const Key('wizardConsolationKoSection')),
      findsOneWidget,
    );
    // K16: direct starters are chips, not a free text field.
    expect(
      find.byKey(const Key('wizardConsolationDirectCountChips')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('wizardConsolationDirectCountField')),
      findsNothing,
    );
    // K18: the required name field is present.
    expect(
      find.byKey(const Key('wizardConsolationNameField')),
      findsOneWidget,
    );
  });

  testWidgets('K18: KO step "Weiter" stays disabled until the Trostturnier '
      'name is filled', (tester) async {
    await _pumpWizard(
      tester,
      controllerOverride: _ConsolationSeededController.new,
    );
    await _typeName(tester, 'Trost Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config

    final blocked = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Weiter'),
    );
    expect(blocked.onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('wizardConsolationNameField')),
      'Bâton Rouille',
    );
    await tester.pumpAndSettle();
    final enabled = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Weiter'),
    );
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('K16/K18: Trostturnier name + direct-count chip flow into the '
      'create payload', (tester) async {
    final fake = await _pumpWizard(
      tester,
      controllerOverride: _ConsolationSeededController.new,
    );
    await _typeName(tester, 'Trost Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config

    // Pick a 16-bracket so the direct-starter chips include 4 and 8 (K16).
    await tester.tap(find.widgetWithText(InkWell, '16').first);
    await tester.pumpAndSettle();

    // K16: tap the "4" direct-starter chip (scoped to the chip Wrap so it does
    // not collide with the KO-size "4" chip).
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('wizardConsolationDirectCountChips')),
        matching: find.text('4'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('wizardConsolationNameField')),
      'Bâton Rouille',
    );
    await tester.pumpAndSettle();

    await _tapNext(tester); // -> summary
    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await tester.pumpAndSettle();

    expect(fake.createdSetup?['ko_type'], 'consolation');
    expect(fake.createdSetup?['consolation_name'], 'Bâton Rouille');
    expect(fake.createdSetup?['consolation_direct_count'], 4);
  });

  testWidgets('K21/K22: KO matchup + tiebreak are radio buttons, not '
      'SegmentedButtons, and are selectable', (tester) async {
    final fake = await _pumpWizard(
      tester,
      controllerOverride: _SchochSeededController.new,
    );
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config

    // No SegmentedButton for either axis anymore (K21/K22).
    expect(find.byType(SegmentedButton<KoMatchup>), findsNothing);
    expect(find.byType(SegmentedButton<KoTiebreakMethod>), findsNothing);
    // Radios are rendered for both axes.
    expect(find.byType(RadioListTile<KoMatchup>), findsNWidgets(2));
    expect(find.byType(RadioListTile<KoTiebreakMethod>), findsNWidgets(2));

    // Selecting the "1. vs 2." matchup updates the draft.
    await tester.tap(find.text('1. vs 2.'));
    await tester.pumpAndSettle();
    // Selecting the "Mighty-Finisher" tiebreak updates the draft.
    await tester.tap(find.text('Mighty-Finisher'));
    await tester.pumpAndSettle();

    await _tapNext(tester); // -> summary
    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await tester.pumpAndSettle();

    expect(fake.createdSetup?['ko_matchup'], 'one_vs_two');
    expect(fake.createdSetup?['ko_tiebreak_method'], 'mighty_finisher_shootout');
  });

  testWidgets('submit calls createTournament with the configured draft',
      (tester) async {
    final fake = await _pumpWizard(tester);
    await _typeName(tester, 'Cup 2026');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary

    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await tester.pumpAndSettle();

    expect(fake.callCount, 1);
    expect(fake.createdDisplayName, 'Cup 2026');
    // Every tournament has a KO stage now → hybrid round-robin-then-KO.
    expect(fake.createdFormat, TournamentFormat.roundRobinThenKo);
    expect(find.text('detail:t-fake-1'), findsOneWidget);
  });

  testWidgets(
      'league chips only show once a club is chosen as host (DOD-09)',
      (tester) async {
    await _pumpWizard(
      tester,
      extraOverrides: <Object>[
        manageableClubsProvider.overrideWith(
          (_) async => const <ManageableClub>[
            (id: 'c-1', name: 'Kubb Club Aarau'),
          ],
        ),
      ],
    );
    await _typeName(tester, 'Cup');
    // Personal tournament (no club): no league chips.
    expect(find.text('Liga A'), findsNothing);

    // Pick a club → league chips appear.
    await tester.tap(find.byKey(const Key('wizardClubPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kubb Club Aarau').last);
    await tester.pumpAndSettle();
    expect(find.text('Liga A'), findsOneWidget);
  });

  testWidgets(
      'Stammdaten league + scoring choices flow into the setup payload',
      (tester) async {
    final fake = await _pumpWizard(
      tester,
      extraOverrides: <Object>[
        manageableClubsProvider.overrideWith(
          (_) async => const <ManageableClub>[
            (id: 'c-1', name: 'Kubb Club Aarau'),
          ],
        ),
      ],
    );
    await _typeName(tester, 'Bâton dOr');
    // A club must be chosen for the league chips to surface (DOD-09).
    await tester.tap(find.byKey(const Key('wizardClubPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kubb Club Aarau').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liga A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Klassisch'));
    await tester.pumpAndSettle();

    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary

    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await tester.pumpAndSettle();

    expect(fake.createdSetup?['scoring'], 'classic');
    expect(fake.createdSetup?['league_categories'], contains('A'));
  });

  testWidgets(
      'club picker lists only the clubs the caller may manage, plus the '
      'no-club option', (tester) async {
    await _pumpWizard(
      tester,
      extraOverrides: <Object>[
        manageableClubsProvider.overrideWith(
          (_) async => const <ManageableClub>[
            (id: 'c-1', name: 'Kubb Club Aarau'),
            (id: 'c-2', name: 'Kubb Club Bern'),
          ],
        ),
      ],
    );

    // Open the dropdown; both manageable clubs and the no-club option show.
    await tester.tap(find.byKey(const Key('wizardClubPicker')));
    await tester.pumpAndSettle();

    expect(find.text('Kubb Club Aarau'), findsWidgets);
    expect(find.text('Kubb Club Bern'), findsWidgets);
    // K02: the no-club option is now the Spasstournier label.
    expect(find.text('Spasstournier – ohne Wertung'), findsWidgets);
    // A club the caller does NOT manage is never offered.
    expect(find.text('Kubb Club Zürich'), findsNothing);
  });

  testWidgets('selecting an organizing club flows club_id into the create call',
      (tester) async {
    final fake = await _pumpWizard(
      tester,
      extraOverrides: <Object>[
        manageableClubsProvider.overrideWith(
          (_) async => const <ManageableClub>[
            (id: 'c-1', name: 'Kubb Club Aarau'),
          ],
        ),
      ],
    );
    await _typeName(tester, 'Vereins-Cup');

    await tester.tap(find.byKey(const Key('wizardClubPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kubb Club Aarau').last);
    await tester.pumpAndSettle();
    // K29: a club tournament requires at least one league category.
    await tester.tap(find.text('Liga A'));
    await tester.pumpAndSettle();

    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary

    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await tester.pumpAndSettle();

    expect(fake.createdSetup?['club_id'], 'c-1');
  });

  testWidgets('team size and pitch range flow into the create call',
      (tester) async {
    final fake = await _pumpWizard(tester);
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants

    // Team-size is the first numeric field on the participants step; type 2.
    await tester.enterText(find.byType(TextField).first, '2');
    await tester.pumpAndSettle();

    await _tapNext(tester); // -> Vorrunde

    // Range mode is the default; target the pitch von/bis fields by key.
    await tester.enterText(
      find.byKey(const Key('wizardPitchRangeFromField')),
      '10',
    );
    await tester.enterText(
      find.byKey(const Key('wizardPitchRangeToField')),
      '20',
    );
    await tester.pumpAndSettle();

    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary
    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await tester.pumpAndSettle();

    expect(fake.createdTeamSize, 2);
    final pitch = fake.createdSetup?['pitch_plan'] as Map<String, Object?>?;
    expect(pitch, isNotNull);
    expect(pitch!['mode'], 'range');
    expect(pitch['range_from'], 10);
    expect(pitch['range_to'], 20);
  });

  testWidgets('edit mode pre-fills the name and submits via updateTournament',
      (tester) async {
    const editId = TournamentId('t-edit-1');
    final initial =
        _withStammdaten(const TournamentConfigDraft(displayName: 'Alt-Name'));
    final fake = await _pumpEditWizard(
      tester,
      editId: editId,
      initialDraft: initial,
    );

    // EDIT mode: the eyebrow (uppercased) reflects editing, the step name is
    // the title, and the name field is pre-filled from the initial draft.
    expect(find.text('TURNIER BEARBEITEN'), findsOneWidget);
    expect(find.text('Alt-Name'), findsOneWidget);

    // Change the name, then walk to the summary and save (group-phase flow).
    await _typeName(tester, 'Neuer-Name');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary

    await tester.tap(
      find.widgetWithText(FilledButton, 'Änderungen speichern'),
    );
    await tester.pumpAndSettle();

    // create must NOT be called; update must carry the changed name + id.
    expect(fake.callCount, 0);
    expect(fake.updateCallCount, 1);
    expect(fake.updatedId, editId);
    // K01: the year (from eventStartsAt = 2026) is auto-appended on submit.
    expect(fake.updatedDisplayName, 'Neuer-Name 2026');
    expect(fake.updatedSetup, isNotNull);
    expect(find.text('detail:t-edit-1'), findsOneWidget);
  });

  // ---- W1 wizard-rework Stammdaten UI ----

  testWidgets('K01: a helper text explains the auto-appended year',
      (tester) async {
    await _pumpWizard(tester);
    expect(
      find.text('Die Jahreszahl wird automatisch angehängt (z.B. 2026).'),
      findsOneWidget,
    );
  });

  testWidgets('K02: the no-club option is labelled "Spasstournier – ohne '
      'Wertung"', (tester) async {
    await _pumpWizard(tester);
    // Default seed = Spasstournier (no club), so the label shows as the
    // selected value of the picker.
    expect(find.text('Spasstournier – ohne Wertung'), findsWidgets);
  });

  testWidgets('K03: Weiter stays disabled until the club choice is made',
      (tester) async {
    // Fresh draft (no Stammdaten seed): even with a valid name, the club
    // choice is unmade, so the step is invalid.
    await _pumpWizard(
      tester,
      controllerOverride: TournamentConfigController.new,
    );
    await _typeName(tester, 'Cup');
    final next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Weiter'),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets('K05: the Diggy toggle is ON for a fresh draft', (tester) async {
    await _pumpWizard(tester);
    final diggySwitch = tester.widget<Switch>(
      find.descendant(
        of: find.ancestor(
          of: find.text('Diggy-Regel'),
          matching: find.byType(Row),
        ),
        matching: find.byType(Switch),
      ),
    );
    expect(diggySwitch.value, isTrue);
  });

  testWidgets('K06: the opening-rule selector is present and selectable',
      (tester) async {
    await _pumpWizard(tester);
    final segmented = find.byKey(const Key('wizardOpeningRule'));
    expect(segmented, findsOneWidget);
    // Default shows 2-4-6 selected.
    final button = tester.widget<SegmentedButton<String>>(segmented);
    expect(button.selected, <String>{'2-4-6'});
    // Picking "Frei" updates the rule variants.
    await tester.tap(find.text('Frei'));
    await tester.pumpAndSettle();
    final updated = tester.widget<SegmentedButton<String>>(segmented);
    expect(updated.selected, <String>{'free'});
  });

  testWidgets('K07: the participant info fields allow up to 5 lines',
      (tester) async {
    await _pumpWizard(tester);
    // The info fields are built into the step regardless of scroll position.
    final infoFields = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((f) => f.maxLines == 5)
        .toList();
    // The four info free-text fields (food/travel/accommodation/weather).
    expect(infoFields.length, greaterThanOrEqualTo(4));
    for (final f in infoFields) {
      expect(f.minLines, 3);
    }
  });

  // ---- W3: K12 group config in the Vorrunde step ----

  testWidgets(
      'K12: the group-phase shows group count (default 4) + strategy inline; '
      'Schoch hides them', (tester) async {
    // Group phase (default seed): walk to the Vorrunde step.
    await _pumpWizard(tester);
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    expect(find.text('Anzahl Gruppen'), findsOneWidget);
    expect(find.text('Grouping-Strategie'), findsOneWidget);
    // The inline group-count field defaults to 4.
    final groupCount = tester.widget<TextField>(
      find.byKey(const Key('wizardGroupCountField')),
    );
    expect(groupCount.controller?.text, '4');
    // The qualifier-per-group is read-only (no editable qualifier input here).
    expect(find.text('Qualifier pro Gruppe'), findsOneWidget);
  });

  testWidgets('K12: Schoch hides the group-count + strategy inputs',
      (tester) async {
    await _pumpWizard(
      tester,
      controllerOverride: _SchochSeededController.new,
    );
    await _typeName(tester, 'Schoch Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    expect(find.byKey(const Key('wizardGroupCountField')), findsNothing);
    expect(find.text('Grouping-Strategie'), findsNothing);
  });

  testWidgets('K12: picking the Random strategy reveals the seed field',
      (tester) async {
    await _pumpWizard(tester);
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    // The seed field is hidden for the default (snake) strategy.
    expect(find.byKey(const Key('wizardGroupRandomSeedField')), findsNothing);
    await tester.tap(find.byKey(const Key('wizardGroupStrategyField')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Random (deterministisch)').last);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('wizardGroupRandomSeedField')),
      findsOneWidget,
    );
  });

  testWidgets(
      'K12: a group count that does not divide the KO size blocks the KO step',
      (tester) async {
    await _pumpWizard(tester);
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    // KO smart-default = 4 (8 participants). Type 3 → 4 % 3 != 0.
    await tester.enterText(
      find.byKey(const Key('wizardGroupCountField')),
      '3',
    );
    await tester.pumpAndSettle();
    await _tapNext(tester); // -> KO config
    // The divisibility gate lives on the KO step (the KO size is final there):
    // Weiter is disabled until the group count divides the KO bracket size.
    final next = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Weiter'),
    );
    expect(next.onPressed, isNull);
  });

  testWidgets(
      'K23/K24: per-group pitch assignment shows in the pitch context for the '
      'group phase with pitches, absent for Schoch', (tester) async {
    // Group phase + a pitch range → the per-group assignment surfaces.
    await _pumpWizard(tester);
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await tester.enterText(
      find.byKey(const Key('wizardPitchRangeFromField')),
      '1',
    );
    await tester.enterText(
      find.byKey(const Key('wizardPitchRangeToField')),
      '3',
    );
    await tester.pumpAndSettle();
    expect(find.text('Pitch-Zuteilung pro Gruppe'), findsOneWidget);
    expect(find.text('Gruppe A'), findsOneWidget);
  });

  testWidgets('K23/K24: no per-group pitch assignment for the Schoch Vorrunde',
      (tester) async {
    await _pumpWizard(
      tester,
      controllerOverride: _SchochSeededController.new,
    );
    await _typeName(tester, 'Schoch Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await tester.enterText(
      find.byKey(const Key('wizardPitchRangeFromField')),
      '1',
    );
    await tester.enterText(
      find.byKey(const Key('wizardPitchRangeToField')),
      '3',
    );
    await tester.pumpAndSettle();
    expect(find.text('Pitch-Zuteilung pro Gruppe'), findsNothing);
  });
}
