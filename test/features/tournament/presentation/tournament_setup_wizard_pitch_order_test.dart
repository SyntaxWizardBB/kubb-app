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

/// Minimal remote stub: the pitch-order editor never hits the network, so
/// the wizard only needs a remote that does not throw on construction.
class _StubRemote implements TournamentRemote {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Controller seeded with a manual pitch plan whose stored order (3, 1, 2)
/// differs from the natural range order, to assert the editor honours it.
class _PreseededOrderController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => const TournamentConfigDraft(
        pitchPlan: PitchPlan(
          mode: PitchMode.range,
          rangeFrom: 1,
          rangeTo: 3,
          order: <int>[3, 1, 2],
          sortStrategy: PitchSortStrategy.manual,
        ),
      );
}

/// Pumps the wizard with a [ProviderContainer] we keep, so tests can read
/// the live draft and assert the emitted `PitchPlan.order`.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<Object> extraOverrides = const <Object>[],
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: <Object>[
      tournamentRemoteProvider.overrideWithValue(_StubRemote()),
      ...extraOverrides,
    ].cast(),
  );
  addTearDown(container.dispose);

  final router = GoRouter(
    initialLocation: TournamentRoutes.newTournament,
    routes: [
      GoRoute(
        path: TournamentRoutes.newTournament,
        builder: (_, _) => const TournamentSetupWizard(),
      ),
      GoRoute(
        path: '${TournamentRoutes.detail}/:id',
        builder: (_, state) =>
            Scaffold(body: Text('detail:${state.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
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
  return container;
}

Future<void> _tapNext(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
  await tester.pumpAndSettle();
}

/// Navigates to the format step (Schritt 3) where the pitch section lives,
/// then fills a 1..3 pitch range so the editor has items to reorder.
Future<void> _goToPitchStepWithRange(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('wizardNameField')),
    'Cup',
  );
  await tester.pumpAndSettle();
  await _tapNext(tester); // -> participants
  await _tapNext(tester); // -> format (Vorrunde) with pitch section
  await tester.enterText(
    find.byKey(const Key('wizardPitchRangeFromField')),
    '1',
  );
  await tester.enterText(
    find.byKey(const Key('wizardPitchRangeToField')),
    '3',
  );
  await tester.pumpAndSettle();
}

PitchPlan? _draftPlan(ProviderContainer c) =>
    c.read(tournamentConfigControllerProvider).pitchPlan;

void main() {
  testWidgets('manual sort shows the reorder editor; top-seeds hides it',
      (tester) async {
    await _pump(tester);
    await _goToPitchStepWithRange(tester);

    // Default sort = top seeds → no editor.
    expect(find.byType(ReorderableListView), findsNothing);

    // Switch to "Manuelle Reihenfolge" → editor appears.
    await tester.tap(find.text('Manuelle Reihenfolge'));
    await tester.pumpAndSettle();
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.text('Reihenfolge der Felder'), findsOneWidget);

    // Switch back to top seeds → editor gone again.
    await tester.tap(find.text('Beste auf tiefsten Nummern'));
    await tester.pumpAndSettle();
    expect(find.byType(ReorderableListView), findsNothing);
  });

  testWidgets('editor lists available pitch numbers in order (empty start)',
      (tester) async {
    await _pump(tester);
    await _goToPitchStepWithRange(tester);

    await tester.tap(find.text('Manuelle Reihenfolge'));
    await tester.pumpAndSettle();

    expect(find.text('Feld 1'), findsOneWidget);
    expect(find.text('Feld 2'), findsOneWidget);
    expect(find.text('Feld 3'), findsOneWidget);
  });

  testWidgets('editor honours a pre-seeded order (3, 1, 2) (DOD-02)',
      (tester) async {
    await _pump(
      tester,
      extraOverrides: [
        tournamentConfigControllerProvider
            .overrideWith(_PreseededOrderController.new),
      ],
    );
    await tester.enterText(find.byKey(const Key('wizardNameField')), 'Cup');
    await tester.pumpAndSettle();
    await _tapNext(tester); // -> participants
    await _tapNext(tester); // -> format with pitch section
    await tester.pumpAndSettle();

    // Editor is visible because the seeded plan uses the manual strategy.
    expect(find.byType(ReorderableListView), findsOneWidget);

    // Stored order 3,1,2 must drive the top-to-bottom row order.
    final y1 = tester.getTopLeft(find.text('Feld 1')).dy;
    final y2 = tester.getTopLeft(find.text('Feld 2')).dy;
    final y3 = tester.getTopLeft(find.text('Feld 3')).dy;
    expect(y3, lessThan(y1));
    expect(y1, lessThan(y2));
  });

  testWidgets('reorder writes PitchPlan.order into the draft (manual only)',
      (tester) async {
    final container = await _pump(tester);
    await _goToPitchStepWithRange(tester);

    await tester.tap(find.text('Manuelle Reihenfolge'));
    await tester.pumpAndSettle();

    // Selecting manual sort emits an order = the available pitches.
    expect(_draftPlan(container)!.order, <int>[1, 2, 3]);

    final listView =
        tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    // Move the first item (Feld 1) to the end.
    listView.onReorder(0, 3);
    await tester.pumpAndSettle();

    expect(_draftPlan(container)!.order, <int>[2, 3, 1]);
    expect(
      _draftPlan(container)!.sortStrategy,
      PitchSortStrategy.manual,
    );
  });

  testWidgets('switching back to top-seeds clears the manual order (DOD-04)',
      (tester) async {
    final container = await _pump(tester);
    await _goToPitchStepWithRange(tester);

    await tester.tap(find.text('Manuelle Reihenfolge'));
    await tester.pumpAndSettle();

    final listView =
        tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    listView.onReorder(0, 3);
    await tester.pumpAndSettle();
    expect(_draftPlan(container)!.order, isNotEmpty);

    await tester.tap(find.text('Beste auf tiefsten Nummern'));
    await tester.pumpAndSettle();

    final plan = _draftPlan(container)!;
    expect(plan.sortStrategy, PitchSortStrategy.topSeedsLowNumbers);
    expect(plan.order, isEmpty);
  });
}
