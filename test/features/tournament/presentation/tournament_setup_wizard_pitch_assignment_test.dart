import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_select_chip.dart';
import 'package:kubb_app/features/tournament/application/tournament_config_controller.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_config_draft.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_routes.dart';
import 'package:kubb_app/features/tournament/presentation/tournament_setup_wizard.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

class _StubRemote implements TournamentRemote {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

/// Two groups (A, B), a 1..3 pitch range and the group-phase Vorrunde, so the
/// per-group pitch-assignment chips render right away on the format step.
class _TwoGroupController extends TournamentConfigController {
  @override
  TournamentConfigDraft build() => _withStammdaten(
        const TournamentConfigDraft(
          displayName: 'Cup',
          pitchPlan: PitchPlan(
            mode: PitchMode.range,
            rangeFrom: 1,
            rangeTo: 3,
          ),
          poolPhaseConfig: PoolPhaseConfig(
            groupCount: 2,
            qualifiersPerGroup: 1,
            strategy: PoolGroupingStrategy.snake,
          ),
        ),
      );
}

Future<ProviderContainer> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: <Object>[
      tournamentRemoteProvider.overrideWithValue(_StubRemote()),
      tournamentConfigControllerProvider.overrideWith(_TwoGroupController.new),
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

Future<void> _goToFormatStep(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
  await tester.pumpAndSettle(); // -> participants
  await tester.tap(find.widgetWithText(FilledButton, 'Weiter'));
  await tester.pumpAndSettle(); // -> format with pitch assignment
}

PitchPlan _plan(ProviderContainer c) =>
    c.read(tournamentConfigControllerProvider).pitchPlan!;

/// The innermost Column wrapping the [group] header plus its chip Wrap.
Finder _groupColumn(String group) =>
    find.ancestor(of: find.text(group), matching: find.byType(Column)).first;

/// All chips inside the group block whose header text equals [group].
Finder _chipsOfGroup(String group) =>
    find.descendant(of: _groupColumn(group), matching: find.byType(KubbSelectChip));

/// The chip labelled [pitch] inside the [group] block.
Finder _chip(String group, String pitch) => find.descendant(
      of: _groupColumn(group),
      matching: find.widgetWithText(KubbSelectChip, pitch),
    );

void main() {
  testWidgets('a pitch picked for group A is assigned only to A', (tester) async {
    final container = await _pump(tester);
    await _goToFormatStep(tester);

    await tester.ensureVisible(_chip('Gruppe A', '2').first);
    await tester.tap(_chip('Gruppe A', '2').first);
    await tester.pumpAndSettle();

    expect(_plan(container).groupAssignment, <String, List<int>>{
      'A': <int>[2],
    });
  });

  testWidgets('picking a taken pitch for B moves it out of A (exclusive)',
      (tester) async {
    await _pump(tester);
    await _goToFormatStep(tester);

    // A claims pitch 2.
    await tester.ensureVisible(_chip('Gruppe A', '2').first);
    await tester.tap(_chip('Gruppe A', '2').first);
    await tester.pumpAndSettle();

    // Pitch 2 vanishes from B's selectable chips: B shows 1 and 3 only.
    expect(_chip('Gruppe B', '2'), findsNothing);
    expect(_chip('Gruppe B', '1'), findsOneWidget);
    expect(_chip('Gruppe B', '3'), findsOneWidget);
    // A still shows all three (its own pick stays visible + selected).
    expect(_chipsOfGroup('Gruppe A'), findsNWidgets(3));
  });

  testWidgets('deselecting a pitch frees it for every other group',
      (tester) async {
    final container = await _pump(tester);
    await _goToFormatStep(tester);

    await tester.ensureVisible(_chip('Gruppe A', '2').first);
    await tester.tap(_chip('Gruppe A', '2').first);
    await tester.pumpAndSettle();
    expect(_chip('Gruppe B', '2'), findsNothing);

    // Deselect 2 in A → it returns to B.
    await tester.ensureVisible(_chip('Gruppe A', '2').first);
    await tester.tap(_chip('Gruppe A', '2').first);
    await tester.pumpAndSettle();

    expect(_plan(container).groupAssignment, isEmpty);
    expect(_chip('Gruppe B', '2'), findsOneWidget);
  });
}
