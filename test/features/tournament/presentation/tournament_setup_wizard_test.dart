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
}

/// Controller variant that starts the draft on a Schoch Vorrunde so the
/// group-phase (pool) step is hidden — yielding the minimal 5-step flow
/// (name, Vorrunde, KO-config, summary; every tournament has a KO stage).
class _SchochSeededController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => const TournamentConfigDraft(
        format: TournamentFormat.swissThenKo,
        vorrundeType: VorrundeType.schoch,
      );
}

/// Controller variant seeded as Trostturnier (consolation) on a Schoch
/// Vorrunde, used to assert the Model-B config inputs surface.
class _ConsolationSeededController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => const TournamentConfigDraft(
        format: TournamentFormat.swissThenKo,
        vorrundeType: VorrundeType.schoch,
        koType: KoType.consolation,
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
    // Default flow (group phase + single-out KO): 6 visible steps.
    expect(find.text('Schritt 1 von 6'), findsOneWidget);
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
      'group-phase flow walks name → Teilnehmer → Vorrunde → KO → Gruppenphase'
      ' → Übersicht (KO before group phase, DOD-13)', (tester) async {
    final fake = await _pumpWizard(tester);
    await _typeName(tester, 'Cup 2026');

    await _tapNext(tester); // -> participants
    expect(find.text('Schritt 2 von 6'), findsOneWidget);
    expect(find.text('Teilnehmer'), findsOneWidget);

    await _tapNext(tester); // -> Vorrunde (renamed from "Format")
    expect(find.text('Schritt 3 von 6'), findsOneWidget);
    expect(find.text('Vorrunde'), findsWidgets);

    await _tapNext(tester); // -> KO config (precedes the group phase)
    expect(find.text('Schritt 4 von 6'), findsOneWidget);
    expect(find.text('KO-Konfiguration'), findsOneWidget);

    await _tapNext(tester); // -> Gruppenphase
    expect(find.text('Schritt 5 von 6'), findsOneWidget);
    expect(find.text('Gruppenphase'), findsWidgets);

    await _tapNext(tester); // -> summary
    expect(find.text('Schritt 6 von 6'), findsOneWidget);
    expect(find.text('Übersicht'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await tester.pumpAndSettle();
    expect(fake.callCount, 1);
    expect(fake.createdFormat, TournamentFormat.roundRobinThenKo);
  });

  testWidgets(
      'Schoch Vorrunde hides the group-phase step → 5-step flow with KO',
      (tester) async {
    final fake = await _pumpWizard(
      tester,
      extraOverrides: [
        tournamentConfigControllerProvider
            .overrideWith(_SchochSeededController.new),
      ],
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

  testWidgets('Model-B inputs only show for the Trostturnier KO type (DOD-14)',
      (tester) async {
    // Single-out seeded: no Model-B section.
    await _pumpWizard(
      tester,
      extraOverrides: [
        tournamentConfigControllerProvider
            .overrideWith(_SchochSeededController.new),
      ],
    );
    await _typeName(tester, 'Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    expect(
      find.byKey(const Key('wizardConsolationModelBSection')),
      findsNothing,
    );

    // Picking Trostturnier reveals the Model-B config inputs.
    await tester.tap(find.text('Trostturnier'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('wizardConsolationModelBSection')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('wizardConsolationDirectCountField')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('wizardConsolationNameField')),
      findsOneWidget,
    );
  });

  testWidgets('Trostturnier Model-B inputs flow into the create payload',
      (tester) async {
    final fake = await _pumpWizard(
      tester,
      extraOverrides: [
        tournamentConfigControllerProvider
            .overrideWith(_ConsolationSeededController.new),
      ],
    );
    await _typeName(tester, 'Trost Cup');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await tester.enterText(
      find.byKey(const Key('wizardConsolationNameField')),
      'Bâton Rouille',
    );
    await tester.enterText(
      find.byKey(const Key('wizardConsolationDirectCountField')),
      '4',
    );
    await tester.pumpAndSettle();

    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> summary
    await tester.tap(find.widgetWithText(FilledButton, 'Turnier anlegen'));
    await tester.pumpAndSettle();

    expect(fake.createdSetup?['ko_type'], 'consolation');
    expect(fake.createdSetup?['consolation_name'], 'Bâton Rouille');
    expect(fake.createdSetup?['consolation_direct_count'], 4);
  });

  testWidgets('submit calls createTournament with the configured draft',
      (tester) async {
    final fake = await _pumpWizard(tester);
    await _typeName(tester, 'Cup 2026');
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> Gruppenphase
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
    await _tapNext(tester); // -> Gruppenphase
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
    expect(find.text('Kein Verein (persönlich)'), findsWidgets);
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

    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> Vorrunde
    await _tapNext(tester); // -> KO config
    await _tapNext(tester); // -> Gruppenphase
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
    await _tapNext(tester); // -> Gruppenphase
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
    const initial = TournamentConfigDraft(displayName: 'Alt-Name');
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
    await _tapNext(tester); // -> Gruppenphase
    await _tapNext(tester); // -> summary

    await tester.tap(
      find.widgetWithText(FilledButton, 'Änderungen speichern'),
    );
    await tester.pumpAndSettle();

    // create must NOT be called; update must carry the changed name + id.
    expect(fake.callCount, 0);
    expect(fake.updateCallCount, 1);
    expect(fake.updatedId, editId);
    expect(fake.updatedDisplayName, 'Neuer-Name');
    expect(fake.updatedSetup, isNotNull);
    expect(find.text('detail:t-edit-1'), findsOneWidget);
  });
}
