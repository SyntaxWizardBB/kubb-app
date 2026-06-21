import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_binary_choice.dart';
import 'package:kubb_app/core/ui/widgets/kubb_button.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/stage_graph_templates_repository.dart'
    show
        StageGraphTemplate,
        StageGraphTemplatesRepository,
        TemplateVisibility,
        stageGraphTemplatesProvider,
        stageGraphTemplatesRepositoryProvider;
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_builder_screen.dart';
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

  // V2-B2: when set, updateTournament throws this instead of succeeding,
  // simulating the server's typed live-edit rejections.
  Exception? throwOnUpdate;

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
    if (throwOnUpdate != null) {
      throw throwOnUpdate!;
    }
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

  // Invite-only Spaßturnier capture.
  final List<({TournamentId tournamentId, UserId userId})> sentInvites =
      <({TournamentId tournamentId, UserId userId})>[];

  @override
  Future<void> inviteUser(TournamentId tournamentId, UserId userId) async =>
      sentInvites.add((tournamentId: tournamentId, userId: userId));

  @override
  Future<void> respondInvitation(
    String invitationId, {
    required bool accept,
  }) async {}

  @override
  Future<void> revokeInvitation(String invitationId) async {}

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
  Future<void> reactivateTournament(TournamentId id) async {}

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
  Future<void> checkinParticipant(TournamentParticipantId participantId) async {}

  @override
  Future<void> undoCheckin(TournamentParticipantId participantId) async {}

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
  Stream<TournamentParticipant> watchTournamentParticipants(
    TournamentId tournamentId,
  ) =>
      const Stream<TournamentParticipant>.empty();

  @override
  Stream<BracketAdvanceEvent> watchBracketAdvances(TournamentId tournamentId) =>
      const Stream<BracketAdvanceEvent>.empty();

  @override
  Future<DateTime> fetchServerNow() async => DateTime.now().toUtc();

  @override
  Stream<TournamentRoundScheduleRef> watchRoundSchedule(
    TournamentId tournamentId,
  ) =>
      const Stream<TournamentRoundScheduleRef>.empty();

  @override
  Future<List<TournamentAdminCardRef>> listAdministrableTournaments() =>
      throw UnimplementedError();

  @override
  Future<void> pauseTournament(TournamentId id) => throw UnimplementedError();

  @override
  Future<void> resumeTournament(TournamentId id) => throw UnimplementedError();

  @override
  Future<void> skipScheduleForward(TournamentId id) =>
      throw UnimplementedError();

  @override
  Future<void> skipScheduleBackward(TournamentId id) =>
      throw UnimplementedError();

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
          format: TournamentFormat.schochThenKo,
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
          format: TournamentFormat.schochThenKo,
          vorrundeType: VorrundeType.schoch,
          koType: KoType.consolation,
        ),
      );
}

/// W5/K26: a Schoch-seeded draft that PASSES every per-step gate (so the
/// wizard can reach the summary) but FAILS `validate()` — `setsToWin` is out
/// of the 1..4 range, which no step gate checks but the final validator does.
/// Used to assert the summary surfaces the validation issues (ERR-1) and the
/// "Anlegen" button stays disabled (ERR-3).
class _InvalidDraftSeededController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => _withStammdaten(
        const TournamentConfigDraft(
          format: TournamentFormat.schochThenKo,
          vorrundeType: VorrundeType.schoch,
          setsToWin: 9,
        ),
      );
}

/// Spaßturnier draft that already has invite-only ON and one invitee, so a
/// submit must fan the invite out through `inviteUser` after create. Stays a
/// Spaßturnier (no club) so the invite-only toggle is eligible.
class _InviteSeededController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => _withStammdaten(
        super.build().copyWith(
          inviteOnly: true,
          invitedUsers: const <InvitedUser>[
            InvitedUser(userId: 'u-guest-1', nickname: 'Gast Eins'),
          ],
        ),
      );
}

/// P2.2: a Schoch-seeded draft already switched into the stage-graph format
/// mode, so the wizard renders the embedded builder (not the classic Vorrunde
/// × KO section) and skips the koConfig step.
class _StageGraphSeededController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => _withStammdaten(
        const TournamentConfigDraft(
          format: TournamentFormat.schochThenKo,
          vorrundeType: VorrundeType.schoch,
          formatMode: TournamentFormatMode.stageGraph,
        ),
      );
}

/// P5.1 (§8): a stage-graph-mode draft in TEMPLATE mode — `appliedTemplateId`
/// is set but `stageGraph` is null (the template is applied server-side on
/// create), so the summary must resolve the graph from the live builder and
/// show the template name instead of 0/0.
class _StageGraphTemplateController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => _withStammdaten(
        const TournamentConfigDraft(
          format: TournamentFormat.schochThenKo,
          vorrundeType: VorrundeType.schoch,
          formatMode: TournamentFormatMode.stageGraph,
          appliedTemplateId: 'tpl-kubbmaister',
        ),
      );
}

/// P2.3: overrides [stageGraphBuilderProvider] with a fresh controller seeded
/// from [graph] but keeping the controller's DEFAULT field size, so a pitch
/// seed (if any) is observable instead of a hardcoded value.
Object _stageGraphDefaultFieldSizeOverride(StageGraph graph) =>
    stageGraphBuilderProvider.overrideWith(
      () => StageGraphBuilderController(graph),
    );

/// P2.2 fixtures: a valid non-empty single-pool graph (no findings) and the
/// empty graph, used to drive the stage-graph format-step gate.
StageGraph get _p2ValidGraph => StageGraph(
      nodes: <StageNode>[
        StageNode(
          id: 'groups',
          type: StageNodeType.groupPhase,
          seeding: StageSeedingSource.asRouted,
          config: const <String, Object?>{'groupCount': 2, 'qualifierCount': 2},
        ),
      ],
      edges: const <StageEdge>[],
    );

/// Overrides [stageGraphBuilderProvider] with a controller seeded from [graph]
/// (and a generous field size so capacity findings don't fire). Returned as
/// `Object` so it slots into the `_pumpWizard` `extraOverrides` (`List<Object>`
/// .cast()) without depending on the riverpod `Override` type being exported.
Object _stageGraphOverride(StageGraph graph) =>
    stageGraphBuilderProvider.overrideWith(
      () => StageGraphBuilderController(graph, 8),
    );

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
  Exception? throwOnUpdate,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final fake = _FakeTournamentRemote()..throwOnUpdate = throwOnUpdate;
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
    expect(find.text('Gruppierungsstrategie'), findsOneWidget);

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
    expect(fake.createdFormat, TournamentFormat.schochThenKo);
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

  testWidgets('K21/K22: KO matchup + tiebreak are binary-choice cards, not '
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
    // ADR-0033 P1.2: both axes are now shared KubbBinaryChoice cards.
    expect(find.byType(KubbBinaryChoice<KoMatchup>), findsOneWidget);
    expect(find.byType(KubbBinaryChoice<KoTiebreakMethod>), findsOneWidget);

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
      'invite-only toggle shows for a Spaßturnier and hides once a club is host',
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
    // Spaßturnier (no club): the invite-only toggle is offered.
    expect(find.byKey(const Key('wizardInviteOnlyToggle')), findsOneWidget);

    // Pick a club → the tournament is no longer a Spaßturnier → toggle gone.
    await tester.tap(find.byKey(const Key('wizardClubPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kubb Club Aarau').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wizardInviteOnlyToggle')), findsNothing);
  });

  testWidgets('toggling invite-only on reveals the player search field',
      (tester) async {
    await _pumpWizard(tester);
    await _typeName(tester, 'Cup');
    expect(find.byKey(const Key('wizardInviteSearchField')), findsNothing);

    // Only the inner Switch of _ToggleRow is interactive, so tap that.
    final toggleSwitch = find.descendant(
      of: find.byKey(const Key('wizardInviteOnlyToggle')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(toggleSwitch);
    await tester.pumpAndSettle();
    await tester.tap(toggleSwitch);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('wizardInviteSearchField')), findsOneWidget);
  });

  testWidgets('submitting an invite-only draft fans invites out via inviteUser',
      (tester) async {
    final fake = await _pumpWizard(
      tester,
      controllerOverride: _InviteSeededController.new,
    );
    await _typeName(tester, 'Geheim-Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary

    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await tester.pumpAndSettle();

    // Create happened, then the seeded invitee was sent to the new tournament.
    expect(fake.callCount, 1);
    expect(fake.sentInvites, hasLength(1));
    expect(fake.sentInvites.single.userId.value, 'u-guest-1');
    expect(fake.sentInvites.single.tournamentId.value, 't-fake-1');
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

  testWidgets(
      'selecting an organizing club flows organizer_team_id into the create call',
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

    expect(fake.createdSetup?['organizer_team_id'], 'c-1');
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

  testWidgets(
      'V2-B2: a live edit rejected with StructureLockedException shows the '
      'clear German structure-lock message (not the raw error)', (tester) async {
    const editId = TournamentId('t-edit-locked');
    final initial =
        _withStammdaten(const TournamentConfigDraft(displayName: 'Alt-Name'));
    final fake = await _pumpEditWizard(
      tester,
      editId: editId,
      initialDraft: initial,
      throwOnUpdate: const StructureLockedException('Phase laeuft bereits'),
    );

    await _typeName(tester, 'Neuer-Name');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary

    await tester.tap(
      find.widgetWithText(FilledButton, 'Änderungen speichern'),
    );
    await tester.pumpAndSettle();

    // The save was attempted, navigation did NOT happen, and the rule-specific
    // German message is shown instead of the generic raw-error snackbar.
    expect(fake.updateCallCount, 1);
    expect(find.text('detail:t-edit-locked'), findsNothing);
    expect(
      find.textContaining('Strukturänderung nicht möglich'),
      findsOneWidget,
    );
    // The raw exception toString must NOT leak through the generic snackbar.
    expect(find.textContaining('StructureLockedException'), findsNothing);
  });

  testWidgets(
      'V2-B2: an edit rejected with TournamentLockedException shows the '
      'finished/aborted message', (tester) async {
    const editId = TournamentId('t-edit-final');
    final initial =
        _withStammdaten(const TournamentConfigDraft(displayName: 'Alt-Name'));
    final fake = await _pumpEditWizard(
      tester,
      editId: editId,
      initialDraft: initial,
      throwOnUpdate: const TournamentLockedException('finalized'),
    );

    await _typeName(tester, 'Neuer-Name');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary

    await tester.tap(
      find.widgetWithText(FilledButton, 'Änderungen speichern'),
    );
    await tester.pumpAndSettle();

    expect(fake.updateCallCount, 1);
    expect(find.text('detail:t-edit-final'), findsNothing);
    expect(
      find.textContaining('Turnier ist abgeschlossen oder abgebrochen'),
      findsOneWidget,
    );
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

  testWidgets('K06: the opening-rule switch is present and default-on (2-4-6)',
      (tester) async {
    await _pumpWizard(tester);
    // ADR-0033 P1.2: the opening rule is now a default-on KubbLabeledSwitch
    // (ON => '2-4-6', OFF => 'free').
    final switchFinder = find.descendant(
      of: find.byKey(const Key('wizardOpeningRule')),
      matching: find.byType(Switch),
    );
    expect(switchFinder, findsOneWidget);
    // Default shows the switch ON (== 2-4-6).
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    // Toggling it off selects the "free" opening rule.
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switchFinder).value, isFalse);
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
    expect(find.text('Gruppierungsstrategie'), findsOneWidget);
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
    expect(find.text('Gruppierungsstrategie'), findsNothing);
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

  // ---- W5: summary step (K26 + error marking) ----

  testWidgets(
      'K26: summary groups every step and shows representative fields from '
      'all of them', (tester) async {
    await _pumpWizard(tester);
    // Use a name without a year so K01 appends the event year (2026).
    await _typeName(tester, 'Sommercup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary
    expect(find.text('Übersicht'), findsOneWidget);

    // Section headings for all four wizard steps.
    expect(find.text('Stammdaten'), findsOneWidget);
    expect(find.text('Teilnehmer'), findsOneWidget);
    expect(find.text('Vorrunde'), findsWidgets);
    expect(find.text('K.-o.'), findsOneWidget);

    // K26-1: name with the auto-appended year + Spasstournier + scoring.
    expect(find.text('Sommercup 2026'), findsOneWidget);
    expect(find.text('Spasstournier – ohne Wertung'), findsWidgets);
    expect(find.text('EKC'), findsWidgets);

    // K26-3: prelim format (group phase = default) is rendered.
    expect(find.text('Gruppenphase'), findsWidgets);

    // K26-4: KO type (default single-out).
    expect(find.text('Single-Out'), findsWidgets);
  });

  testWidgets('K26-4: consolation summary shows the Trostturnier name',
      (tester) async {
    await _pumpWizard(
      tester,
      controllerOverride: _ConsolationSeededController.new,
    );
    await _typeName(tester, 'Herzcup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    // K18: consolation name is required — fill it so we can reach the summary.
    await tester.enterText(
      find.byKey(const Key('wizardConsolationNameField')),
      'Sieger der Herzen',
    );
    await tester.pumpAndSettle();
    await _tapNext(tester); // -> summary

    expect(find.text('Übersicht'), findsOneWidget);
    expect(find.text('Trostturnier'), findsWidgets);
    expect(find.text('Sieger der Herzen'), findsOneWidget);
  });

  testWidgets(
      'ERR-1/ERR-3: invalid draft shows the issue list and disables Anlegen',
      (tester) async {
    await _pumpWizard(
      tester,
      controllerOverride: _InvalidDraftSeededController.new,
    );
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary
    expect(find.text('Übersicht'), findsOneWidget);

    // ERR-1: the prominent issue box + the concrete validation issue render.
    expect(find.byKey(const Key('wizardSummaryErrorBox')), findsOneWidget);
    expect(find.text('Turnier kann nicht angelegt werden'), findsOneWidget);
    expect(
      find.text('Sätze zum Sieg muss zwischen 1 und 4 liegen.'),
      findsOneWidget,
    );

    // ERR-3: the create button is disabled while the draft is invalid.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Turnier anlegen'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets(
      'ERR-2/ERR-3: valid draft shows no issue list and enables Anlegen',
      (tester) async {
    await _pumpWizard(tester);
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary
    expect(find.text('Übersicht'), findsOneWidget);

    // ERR-2: no error box / no error title for a valid draft.
    expect(find.byKey(const Key('wizardSummaryErrorBox')), findsNothing);
    expect(find.text('Turnier kann nicht angelegt werden'), findsNothing);

    // ERR-3: the create button is enabled.
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Turnier anlegen'),
    );
    expect(button.onPressed, isNotNull);
  });

  testWidgets(
      'K26-5: unset optional fields render the "—" placeholder in the summary',
      (tester) async {
    // The default seed leaves PDFs, contact and info texts empty → "—" /
    // "Nein" placeholders, and a free tournament → "Gratis".
    await _pumpWizard(tester);
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary

    // Placeholder for empty optional fields (contact + info texts).
    expect(find.text('—'), findsWidgets);
    // No entry fee → "Gratis"; PDFs not uploaded → "Nein".
    expect(find.text('Gratis'), findsOneWidget);
    expect(find.text('Nein'), findsWidgets);
  });

  testWidgets(
      'K26-1: a chosen club is shown by its resolved name (not the field '
      'label) in the summary', (tester) async {
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
    await _typeName(tester, 'Vereins-Cup');

    // Pick the organizing club + a required league category (K29).
    await tester.tap(find.byKey(const Key('wizardClubPicker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kubb Club Aarau').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Liga A'));
    await tester.pumpAndSettle();

    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary
    expect(find.text('Übersicht'), findsOneWidget);

    // The summary value is the resolved club name, NOT the field label
    // "Ausrichtendes Veranstalterteam" (which only appears once, as the row
    // label).
    expect(find.text('Kubb Club Aarau'), findsOneWidget);
    expect(find.text('Ausrichtendes Veranstalterteam'), findsOneWidget);
  });

  testWidgets(
      'K26-4: the KO per-round rules render a short best-of form, not just a '
      'count', (tester) async {
    await _pumpWizard(tester);
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary
    expect(find.text('Übersicht'), findsOneWidget);

    // The per-round value is a short "R<n>: Bo<maxSets>" form (round 1 always
    // present once a KO bracket exists), NOT a bare count.
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && (w.data?.startsWith('R1: Bo') ?? false),
      ),
      findsOneWidget,
    );
    // And it is NOT the old "<n> Runden konfiguriert" count string.
    expect(find.textContaining('Runden konfiguriert'), findsNothing);
  });

  group('prelim scoring fields in the format step', () {
    testWidgets(
        'the Vorrunde step exposes only "Max. Sätze", no separate '
        'sets-to-win input', (tester) async {
      await _pumpWizard(
        tester,
        controllerOverride: _SchochSeededController.new,
      );
      await _typeName(tester, 'Cup');
      await _tapNext(tester); // -> participants
      await _tapNext(tester); // -> Vorrunde (format step)
      expect(find.text('Schritt 3 von 5'), findsOneWidget);

      expect(find.text('Sätze zum Sieg (Vorrunde)'), findsNothing);
      expect(find.text('Sätze zum Sieg'), findsNothing);
      expect(find.text('Max. Sätze'), findsOneWidget);
    });

    testWidgets(
        'the prelim still emits a sets_to_win in the payload from the draft '
        'default', (tester) async {
      final fake = await _pumpWizard(
        tester,
        controllerOverride: _SchochSeededController.new,
      );
      await _typeName(tester, 'Cup');
      await _tapNext(tester); // -> participants
      await _tapNext(tester); // -> Vorrunde (format step)
      await _tapNext(tester); // -> KO config
      await _tapNext(tester); // -> summary
      await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
      await tester.pumpAndSettle();

      expect(fake.callCount, 1);
      // No prelim input exists, so the payload carries the draft default.
      expect(fake.createdSetsToWin, 2);
    });
  });

  group('P2.2 format-mode fork (stage graph)', () {
    /// Walks name -> participants -> format step (step 3) for a stage-graph
    /// flow (4 visible steps: name, participants, format, summary — koConfig
    /// is skipped).
    Future<void> walkToFormat(WidgetTester tester) async {
      await _typeName(tester, 'Graph Cup');
      await _tapNext(tester); // -> participants
      await _tapNext(tester); // -> format (Vorrunde)
    }

    testWidgets(
        'format step opens with the KubbBinaryChoice mode fork offering '
        'Klassisch / Stufen-Graph / Vorlage wählen (DOD-01)', (tester) async {
      await _pumpWizard(
        tester,
        controllerOverride: _SchochSeededController.new,
        extraOverrides: <Object>[_stageGraphOverride(_p2ValidGraph)],
      );
      await walkToFormat(tester);

      // The primary mode fork is a KubbBinaryChoice.
      expect(find.byType(KubbBinaryChoice<TournamentFormatMode>),
          findsOneWidget);
      // The three semantic paths are visible (classic + the two stage-graph
      // sub-affordances build/template).
      expect(find.text('Klassisch'), findsOneWidget);
      expect(find.text('Stufen-Graph'), findsWidgets);
    });

    testWidgets(
        'switching to stage-graph hides the classic Vorrunde/KO part and '
        'shows the embedded builder (DOD-04)', (tester) async {
      await _pumpWizard(
        tester,
        controllerOverride: _SchochSeededController.new,
        extraOverrides: <Object>[_stageGraphOverride(_p2ValidGraph)],
      );
      await walkToFormat(tester);

      // Classic mode first: the KO-system selector is present.
      expect(find.text('K.-o.-System'), findsOneWidget);
      expect(find.byKey(const Key('wizardStageGraphBuilder')), findsNothing);

      // Tap the stage-graph mode option.
      await tester.tap(find.text('Stufen-Graph').first);
      await tester.pumpAndSettle();

      // Classic KO-system selector is gone; the embedded builder is mounted.
      expect(find.text('K.-o.-System'), findsNothing);
      expect(find.byKey(const Key('wizardStageGraphBuilder')), findsOneWidget);
      // P2.3: the embedded body is the SHARED StageGraphBuilderBody (embedded),
      // the same widget the standalone editor screen renders.
      expect(
        find.byType(StageGraphBuilderBody),
        findsOneWidget,
      );
      // DOD-04 substance: the hosted body is the real INTERACTIVE builder, not
      // a read-only placeholder — it exposes add-node / add-edge affordances
      // (the standalone editor's tooltips, since it is the same body).
      expect(find.byTooltip('Stufe hinzufügen'), findsOneWidget);
      expect(find.byTooltip('Kante hinzufügen'), findsOneWidget);
      // The source sub-choice is also a shared KubbBinaryChoice.
      expect(find.byKey(const Key('wizardStageGraphSource')), findsOneWidget);
      // Default sub-affordance is "build", so no template bar yet.
      expect(
        find.byKey(const Key('wizardStageGraphTemplateBar')),
        findsNothing,
      );

      // Picking "Vorlage wählen" surfaces the template bar.
      await tester.tap(find.text('Vorlage wählen'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('wizardStageGraphTemplateBar')),
        findsOneWidget,
      );
    });

    testWidgets(
        'the embedded builder authors a node inline: empty graph -> add-node '
        'dialog -> node appears and the step frees Weiter (DOD-04)',
        (tester) async {
      // Start in stage-graph mode with a truly EMPTY graph so the inline
      // builder shows its empty-state CTA and the step gate is closed.
      await _pumpWizard(
        tester,
        controllerOverride: _StageGraphSeededController.new,
        extraOverrides: <Object>[
          _stageGraphOverride(
            StageGraph(nodes: const <StageNode>[], edges: const <StageEdge>[]),
          ),
        ],
      );
      await _typeName(tester, 'Graph Cup');
      await _tapNext(tester); // -> participants
      await _tapNext(tester); // -> format
      expect(find.text('Schritt 3 von 4'), findsOneWidget);

      // Empty graph: the format step gate ("Weiter") is closed and the
      // shared body's empty-state CTA ("Stufe hinzufügen") is offered.
      final blocked = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Weiter'),
      );
      expect(blocked.onPressed, isNull);
      final addNodeCta = find.widgetWithText(KubbButton, 'Stufe hinzufügen');
      expect(addNodeCta, findsOneWidget);

      // Author a pool stage inline via the SHARED add-node dialog.
      await tester.ensureVisible(addNodeCta);
      await tester.tap(addNodeCta);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stageGraphNodeIdField')),
        'groups',
      );
      await tester.tap(find.text('Bestätigen'));
      await tester.pumpAndSettle();

      // The authored node now shows in the inline node list (real builder,
      // not a placeholder), and the format step frees "Weiter".
      expect(find.text('groups'), findsOneWidget);
      final freed = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Weiter'),
      );
      expect(freed.onPressed, isNotNull);
    });

    testWidgets(
        '_visibleSteps skips koConfig in stage-graph mode, keeps it in classic '
        '(DOD-06)', (tester) async {
      // Stage-graph seeded: 4-step flow (no KO-config step).
      await _pumpWizard(
        tester,
        controllerOverride: _StageGraphSeededController.new,
        extraOverrides: <Object>[_stageGraphOverride(_p2ValidGraph)],
      );
      expect(find.text('Schritt 1 von 4'), findsOneWidget);

      await _typeName(tester, 'Graph Cup');
      await _tapNext(tester); // -> participants
      expect(find.text('Schritt 2 von 4'), findsOneWidget);
      await _tapNext(tester); // -> format
      expect(find.text('Schritt 3 von 4'), findsOneWidget);
      await _tapNext(tester); // -> summary (koConfig skipped)
      expect(find.text('Schritt 4 von 4'), findsOneWidget);
      expect(find.text('Übersicht'), findsOneWidget);
      // The KO-config step never appears in this flow.
      expect(find.text('KO-Konfiguration'), findsNothing);
    });

    testWidgets(
        'format-step validity in stage-graph mode: empty graph blocks Weiter, '
        'a valid non-empty graph frees it (DOD-07)', (tester) async {
      // Empty graph first -> the format step gate is closed.
      await _pumpWizard(
        tester,
        controllerOverride: _StageGraphSeededController.new,
        extraOverrides: <Object>[
          _stageGraphOverride(
            StageGraph(nodes: const <StageNode>[], edges: const <StageEdge>[]),
          ),
        ],
      );
      await _typeName(tester, 'Graph Cup');
      await _tapNext(tester); // -> participants
      await _tapNext(tester); // -> format
      expect(find.text('Schritt 3 von 4'), findsOneWidget);

      // The format step gate ("Weiter") is closed for the empty graph (the
      // gate requires a non-empty, error-free graph).
      final blocked = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Weiter'),
      );
      expect(blocked.onPressed, isNull);
    });

    testWidgets(
        'valid non-empty graph frees Weiter on the stage-graph format step '
        '(DOD-07)', (tester) async {
      await _pumpWizard(
        tester,
        controllerOverride: _StageGraphSeededController.new,
        extraOverrides: <Object>[_stageGraphOverride(_p2ValidGraph)],
      );
      await _typeName(tester, 'Graph Cup');
      await _tapNext(tester); // -> participants
      await _tapNext(tester); // -> format
      expect(find.text('Schritt 3 von 4'), findsOneWidget);

      expect(find.text('Spielbar'), findsOneWidget);
      final freed = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Weiter'),
      );
      expect(freed.onPressed, isNotNull);
    });

    testWidgets('the old jump-button key is gone (DOD-08)', (tester) async {
      await _pumpWizard(
        tester,
        controllerOverride: _StageGraphSeededController.new,
        extraOverrides: <Object>[_stageGraphOverride(_p2ValidGraph)],
      );
      await _typeName(tester, 'Graph Cup');
      await _tapNext(tester); // -> participants
      await _tapNext(tester); // -> format
      expect(find.byKey(const Key('wizardStageGraphEntry')), findsNothing);
    });

    // ---- P2.3: extracted body reuse, single provider, seed + onChange -------

    testWidgets(
        'P2.3: the embedded builder root capacity is seeded from '
        'maxParticipants and has no separate field-size input (P2_3-05)',
        (tester) async {
      // The seeded draft carries the default maxParticipants (8). The embedded
      // builder starts from the controller DEFAULT field size (4) so the seed
      // to 8 is observable.
      await _pumpWizard(
        tester,
        controllerOverride: _StageGraphSeededController.new,
        extraOverrides: <Object>[
          _stageGraphDefaultFieldSizeOverride(_p2ValidGraph),
        ],
      );
      await _typeName(tester, 'Graph Cup');
      await _tapNext(tester); // -> participants
      await _tapNext(tester); // -> format
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TournamentSetupWizard)),
      );
      final draft = container.read(tournamentConfigControllerProvider);
      // The builder capacity tracks maxParticipants, not the pitch count.
      expect(
        container.read(stageGraphBuilderProvider).fieldSize,
        draft.maxParticipants,
      );

      // The embedded builder no longer shows a field-size input — the capacity
      // is derived, not entered a second time.
      expect(find.text('Anzahl Felder'), findsNothing);
      expect(find.text('Feldgröße'), findsNothing);
    });

    testWidgets(
        'P2.3: a mutation in the EMBEDDED builder writes the same '
        'stageGraphBuilderProvider AND is mirrored into the draft via '
        'setStageGraph (P2_3-06 / P2_3-07)', (tester) async {
      await _pumpWizard(
        tester,
        controllerOverride: _StageGraphSeededController.new,
        extraOverrides: <Object>[
          _stageGraphOverride(
            StageGraph(nodes: const <StageNode>[], edges: const <StageEdge>[]),
          ),
        ],
      );
      await _typeName(tester, 'Graph Cup');
      await _tapNext(tester); // -> participants
      await _tapNext(tester); // -> format
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TournamentSetupWizard)),
      );

      // Author a node inline through the SHARED body empty-state CTA.
      final addNodeCta = find.widgetWithText(KubbButton, 'Stufe hinzufügen');
      await tester.ensureVisible(addNodeCta);
      await tester.tap(addNodeCta);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stageGraphNodeIdField')),
        'groups',
      );
      await tester.tap(find.text('Bestätigen'));
      await tester.pumpAndSettle();

      // The embedded mutation hit the ONE builder provider...
      final builderGraph = container.read(stageGraphBuilderProvider).graph;
      expect(builderGraph.nodes.map((n) => n.id), contains('groups'));

      // ...and is mirrored into the draft via setStageGraph (single source):
      // draft.stageGraph == builder graph.
      final draftGraph =
          container.read(tournamentConfigControllerProvider).stageGraph;
      expect(draftGraph, isNotNull);
      expect(draftGraph, builderGraph);
    });

    testWidgets(
        'P2.3: the classic path never calls setStageGraph (draft.stageGraph '
        'stays null) (P2_3-06)', (tester) async {
      // Stay in the classic mode (default). Even with a non-empty builder graph
      // override present, the classic path must not mirror it into the draft.
      await _pumpWizard(
        tester,
        extraOverrides: <Object>[_stageGraphOverride(_p2ValidGraph)],
      );
      await _typeName(tester, 'Graph Cup');
      await _tapNext(tester); // -> participants
      await _tapNext(tester); // -> format
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TournamentSetupWizard)),
      );
      expect(
        container.read(tournamentConfigControllerProvider).formatMode,
        TournamentFormatMode.classic,
      );
      expect(
        container.read(tournamentConfigControllerProvider).stageGraph,
        isNull,
      );
    });
  });

  // ---- P5.1 (§8): the summary renders the FULL stage-graph ------------------
  group('P5.1 stage-graph summary (§8)', () {
    // A valid two-stage graph: pool 'groups' (with config) -> single-elim 'cup'
    // via TopK(2). Valid so the format-step gate lets us reach the summary.
    StageGraph graph() => StageGraph(
          nodes: <StageNode>[
            StageNode(
              id: 'groups',
              type: StageNodeType.groupPhase,
              seeding: StageSeedingSource.asRouted,
              config: const <String, Object?>{
                'groupCount': 2,
                'qualifierCount': 2,
              },
            ),
            StageNode(
              id: 'cup',
              type: StageNodeType.singleElim,
              seeding: StageSeedingSource.asRouted,
            ),
          ],
          edges: const <StageEdge>[
            StageEdge(fromNodeId: 'groups', toNodeId: 'cup', selector: TopK(2)),
          ],
        );

    Future<void> walkToSummary(WidgetTester tester) async {
      await _typeName(tester, 'Graph Cup');
      await _tapNext(tester); // -> participants
      await _tapNext(tester); // -> format
      await _tapNext(tester); // -> summary
    }

    testWidgets('built-graph mode lists every node + edge, not just counts',
        (tester) async {
      await _pumpWizard(
        tester,
        controllerOverride: _StageGraphSeededController.new,
        extraOverrides: <Object>[_stageGraphOverride(graph())],
      );
      await walkToSummary(tester);

      // Nodes: id + type label + per-stage config (no silent omission, §8/H2).
      expect(find.text('groups'), findsOneWidget);
      expect(find.text('cup'), findsOneWidget);
      expect(find.textContaining('Qualifikanten: 2'), findsOneWidget);
      // Edge: topology + selector — not reduced to a bare count.
      expect(find.text('groups → cup'), findsOneWidget);
      expect(find.textContaining('Top 2'), findsOneWidget);
      // The old count-only rows must be gone.
      expect(find.text('Knoten'), findsNothing);
    });

    testWidgets('template mode shows the template name + resolved graph (no 0/0)',
        (tester) async {
      final g = graph();
      await _pumpWizard(
        tester,
        controllerOverride: _StageGraphTemplateController.new,
        extraOverrides: <Object>[
          _stageGraphOverride(g),
          stageGraphTemplatesProvider.overrideWith(
            (ref) async => <StageGraphTemplate>[
              StageGraphTemplate(
                id: 'tpl-kubbmaister',
                name: 'KubbMAIster Cup',
                description: null,
                visibility: TemplateVisibility.public,
                graph: g,
                isSystem: true,
              ),
            ],
          ),
        ],
      );
      await walkToSummary(tester);

      // The chosen template's NAME is surfaced...
      expect(find.text('KubbMAIster Cup'), findsOneWidget);
      // ...and the graph is resolved from the live builder (the old bug showed
      // 0/0 because draft.stageGraph is null until the server applies it).
      expect(find.text('groups'), findsOneWidget);
      expect(find.text('groups → cup'), findsOneWidget);
    });
  });

  group('#8 stage-graph template save + bind in the wizard', () {
    StageGraph graph() => StageGraph(
          nodes: <StageNode>[
            StageNode(
              id: 'groups',
              type: StageNodeType.groupPhase,
              seeding: StageSeedingSource.asRouted,
              config: const <String, Object?>{
                'groupCount': 2,
                'qualifierCount': 2,
              },
            ),
            StageNode(
              id: 'cup',
              type: StageNodeType.singleElim,
              seeding: StageSeedingSource.asRouted,
            ),
          ],
          edges: const <StageEdge>[
            StageEdge(fromNodeId: 'groups', toNodeId: 'cup', selector: TopK(2)),
          ],
        );

    /// A draft already in stage-graph mode with a club set, so a club-scoped
    /// save forwards the club id. A club tournament is league-relevant, so the
    /// Stammdaten step also needs a league category to pass its gate.
    TournamentConfigController seededWithClub() => _SeededFn(
          () => _withStammdaten(
            const TournamentConfigDraft(
              format: TournamentFormat.schochThenKo,
              vorrundeType: VorrundeType.schoch,
              formatMode: TournamentFormatMode.stageGraph,
              clubId: 'club-7',
              leagueCategories: <LeagueCategory>[LeagueCategory.a],
              pitchPlan: PitchPlan(
                mode: PitchMode.range,
                rangeFrom: 1,
                rangeTo: 4,
              ),
            ),
          ),
        );

    Future<void> openTemplateSource(WidgetTester tester) async {
      await _typeName(tester, 'Graph Cup');
      await _tapNext(tester); // -> participants
      await _tapNext(tester); // -> format (stage-graph mode)
      // Switch the graph source to the template variant so the bar shows. The
      // option title "Vorlage wählen" also labels the template picker below, so
      // target the source option inside its keyed binary-choice widget.
      final sourceOption = find.descendant(
        of: find.byKey(const Key('wizardStageGraphSource')),
        matching: find.text('Vorlage wählen'),
      );
      await tester.ensureVisible(sourceOption);
      await tester.pumpAndSettle();
      await tester.tap(sourceOption);
      await tester.pumpAndSettle();
    }

    testWidgets('save button is hidden for an empty graph, shown for a filled '
        'one', (tester) async {
      await _pumpWizard(
        tester,
        controllerOverride: _StageGraphSeededController.new,
        extraOverrides: <Object>[
          _stageGraphOverride(
            StageGraph(nodes: const <StageNode>[], edges: const <StageEdge>[]),
          ),
          stageGraphTemplatesProvider.overrideWith(
            (_) async => const <StageGraphTemplate>[],
          ),
        ],
      );
      await openTemplateSource(tester);
      final saveBtn = find.byKey(const Key('wizardStageGraphTemplateSave'));
      expect(saveBtn, findsOneWidget);
      expect(
        tester.widget<KubbButton>(saveBtn).onPressed,
        isNull,
      );
    });

    testWidgets('saving forwards name + visibility + clubId and invalidates the '
        'list', (tester) async {
      final repo = _CapturingTemplatesRepo();
      await _pumpWizard(
        tester,
        controllerOverride: seededWithClub,
        extraOverrides: <Object>[
          _stageGraphOverride(graph()),
          stageGraphTemplatesRepositoryProvider.overrideWithValue(repo),
          stageGraphTemplatesProvider.overrideWith(
            (_) async => const <StageGraphTemplate>[],
          ),
        ],
      );
      await openTemplateSource(tester);

      await tester.tap(find.byKey(const Key('wizardStageGraphTemplateSave')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stageGraphTemplateNameField')),
        'Mein Verein Cup',
      );
      // Pick the club visibility.
      await tester.tap(
        find.byKey(const Key('stageGraphTemplateVisibilityField')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verein/Organisation').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bestätigen'));
      await tester.pumpAndSettle();

      expect(repo.saved, hasLength(1));
      final call = repo.saved.single;
      expect(call.name, 'Mein Verein Cup');
      expect(call.visibility, TemplateVisibility.club);
      expect(call.clubId, 'club-7');
      // #11: the draft's pitch plan rides along into the saved template.
      expect(
        call.pitchPlan,
        const PitchPlan(mode: PitchMode.range, rangeFrom: 1, rangeTo: 4),
      );
      expect(find.text('Vorlage gespeichert.'), findsOneWidget);
    });

    testWidgets('a missing club disables the club visibility option',
        (tester) async {
      await _pumpWizard(
        tester,
        // Default seed is a Spaßturnier (clubId == null) in stage-graph mode.
        controllerOverride: _StageGraphSeededController.new,
        extraOverrides: <Object>[
          _stageGraphOverride(graph()),
          stageGraphTemplatesProvider.overrideWith(
            (_) async => const <StageGraphTemplate>[],
          ),
        ],
      );
      await openTemplateSource(tester);
      await tester.tap(find.byKey(const Key('wizardStageGraphTemplateSave')));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('muss ein Veranstalter gewaehlt sein'),
        findsOneWidget,
      );
    });

    testWidgets('applying a template binds appliedTemplateId; editing the graph '
        'clears it again', (tester) async {
      await _pumpWizard(
        tester,
        controllerOverride: () => _SeededFn(
          () => _withStammdaten(
            const TournamentConfigDraft(
              format: TournamentFormat.schochThenKo,
              vorrundeType: VorrundeType.schoch,
              formatMode: TournamentFormatMode.stageGraph,
            ),
          ),
        ),
        extraOverrides: <Object>[
          _stageGraphOverride(
            StageGraph(nodes: const <StageNode>[], edges: const <StageEdge>[]),
          ),
          stageGraphTemplatesProvider.overrideWith(
            (_) async => <StageGraphTemplate>[
              StageGraphTemplate(
                id: 'tpl-x',
                name: 'Vorlage X',
                description: null,
                visibility: TemplateVisibility.public,
                graph: graph(),
                isSystem: true,
                // #11: this template carries a pitch plan; applying restores it.
                pitchPlan: const PitchPlan(
                  mode: PitchMode.range,
                  rangeFrom: 2,
                  rangeTo: 5,
                ),
              ),
            ],
          ),
        ],
      );
      await openTemplateSource(tester);

      // Pick + apply the template.
      await tester.tap(
        find.byKey(const Key('wizardStageGraphTemplatePicker')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vorlage X').last);
      await tester.pumpAndSettle();
      // The embedded builder body hosts its own template bar too, so scope the
      // apply tap to the wizard's bar.
      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('wizardStageGraphTemplateBar')),
          matching: find.text('Anwenden'),
        ),
      );
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(TournamentSetupWizard)),
      );
      expect(
        container.read(tournamentConfigControllerProvider).appliedTemplateId,
        'tpl-x',
      );
      // The applied template's pitch plan landed in the draft.
      expect(
        container.read(tournamentConfigControllerProvider).pitchPlan,
        const PitchPlan(mode: PitchMode.range, rangeFrom: 2, rangeTo: 5),
      );

      // A manual graph edit (drop a node) must clear the binding.
      container.read(stageGraphBuilderProvider.notifier).removeNode('cup');
      await tester.pumpAndSettle();

      expect(
        container.read(tournamentConfigControllerProvider).appliedTemplateId,
        isNull,
      );
    });
  });
}

/// Builds a controller from a draft factory, so a test can seed an arbitrary
/// starting draft without a dedicated subclass.
class _SeededFn extends TournamentConfigController {
  _SeededFn(this._seed);

  final TournamentConfigDraft Function() _seed;

  @override
  TournamentConfigDraft build() => _seed();
}

/// Captured `saveTemplate` call for the wizard save assertions.
class _SavedCall {
  const _SavedCall({
    required this.name,
    required this.visibility,
    required this.clubId,
    required this.pitchPlan,
  });

  final String name;
  final TemplateVisibility visibility;
  final String? clubId;
  final PitchPlan? pitchPlan;
}

/// Repository fake over the public test seam that records every save and never
/// touches Supabase.
class _CapturingTemplatesRepo extends StageGraphTemplatesRepository {
  _CapturingTemplatesRepo()
      : super.withSeams(
          select: (_) async => const <dynamic>[],
          rpc: (_, _) async => 'new-id',
        );

  final List<_SavedCall> saved = <_SavedCall>[];

  @override
  Future<String> saveTemplate({
    required String name,
    required TemplateVisibility visibility,
    required StageGraph graph,
    String? description,
    String? clubId,
    PitchPlan? pitchPlan,
  }) async {
    saved.add(
      _SavedCall(
        name: name,
        visibility: visibility,
        clubId: clubId,
        pitchPlan: pitchPlan,
      ),
    );
    return 'new-id';
  }
}
