import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/stage_type_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/presentation/stage_type_graph_builder_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Widget tests for the handy form-based stage-type-graph editor (Ebene 2,
/// ADR-0039 §1, spec §5). Category-aware UI mirrors the validation:
/// Vorrunde shows no granular edge options, KO shows winner/loser.

const MatchFormatSpec _matchFormat =
    StageTypeGraphBuilderController.defaultMatchFormat;

StageTypeGraph _koValid() => StageTypeGraph(
      category: TypeStageCategory.ko,
      rounds: <TypeRound>[
        TypeRound(
          roundNumber: 1,
          fields: const <TypeField>[
            TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
            TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
          ],
          matchFormat: _matchFormat,
          koMatchup: KoMatchup.seedHighVsLow,
        ),
        TypeRound(
          roundNumber: 2,
          fields: const <TypeField>[
            TypeField(id: 'R2F1', roundNumber: 2, slot: 1),
          ],
          matchFormat: _matchFormat,
          koMatchup: KoMatchup.seedHighVsLow,
        ),
      ],
      edges: const <FieldEdge>[
        WinnerEdge(fromFieldId: 'R1F1', toFieldId: 'R2F1'),
        WinnerEdge(fromFieldId: 'R1F2', toFieldId: 'R2F1'),
      ],
    );

StageTypeGraph _vorrunde() => StageTypeGraph(
      category: TypeStageCategory.vorrunde,
      rounds: <TypeRound>[
        TypeRound(
          roundNumber: 1,
          fields: const <TypeField>[
            TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
            TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
          ],
          matchFormat: _matchFormat,
          pairingRule: TypePairingRule.groupRoundRobin,
        ),
      ],
      edges: const <FieldEdge>[],
    );

Future<void> _pump(
  WidgetTester tester,
  StageTypeGraph graph, {
  ValueChanged<Map<String, Object?>>? onSave,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(390, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stageTypeGraphBuilderProvider
            .overrideWith(() => StageTypeGraphBuilderController(graph)),
      ],
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: StageTypeGraphBuilderScreen(onSave: onSave),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('KO: the field-edge add action is offered', (tester) async {
    await _pump(tester, _koValid());
    expect(find.byTooltip('Kante hinzufügen'), findsOneWidget);
  });

  testWidgets('KO edge dialog offers winner and loser kinds', (tester) async {
    await _pump(tester, _koValid());

    await tester.ensureVisible(find.byTooltip('Kante hinzufügen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kante hinzufügen'));
    await tester.pumpAndSettle();

    // The kind dropdown is the first one in the dialog; opening it shows the
    // granular KO kinds (winner / loser / open).
    final kindDropdown = find.byWidgetPredicate(
      (w) => w is DropdownButtonFormField,
    );
    await tester.tap(kindDropdown.first);
    await tester.pumpAndSettle();
    expect(find.text('Sieger'), findsWidgets);
    expect(find.text('Verlierer'), findsWidgets);
    expect(find.text('Offen lassen'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Vorrunde: no granular edge action, shows the all-weiter note',
      (tester) async {
    await _pump(tester, _vorrunde());

    // The Vorrunde must NOT offer the granular field-edge add button.
    expect(find.byTooltip('Kante hinzufügen'), findsNothing);
    // Instead it explains that everyone advances (no winner/loser edges).
    expect(
      find.textContaining('keine einzelnen Sieger-/Verlierer-Kanten'),
      findsOneWidget,
    );
  });

  testWidgets('Vorrunde round shows the re-pairing rule choice', (tester) async {
    await _pump(tester, _vorrunde());
    expect(find.text('Gruppe (jeder gegen jeden)'), findsOneWidget);
    expect(find.text('Schoch (Auslosung nach Stand)'), findsOneWidget);
  });

  testWidgets('an error finding is visible and blocks save', (tester) async {
    var saved = false;
    // A single KO round of 2 fields is final-not-single + capacity errors.
    final graph = StageTypeGraph(
      category: TypeStageCategory.ko,
      rounds: <TypeRound>[
        TypeRound(
          roundNumber: 1,
          fields: const <TypeField>[
            TypeField(id: 'R1F1', roundNumber: 1, slot: 1),
            TypeField(id: 'R1F2', roundNumber: 1, slot: 2),
          ],
          matchFormat: _matchFormat,
          koMatchup: KoMatchup.seedHighVsLow,
        ),
      ],
      edges: const <FieldEdge>[],
    );
    await _pump(tester, graph, onSave: (_) => saved = true);

    // The "not savable" status chip is shown.
    expect(find.text('Nicht speicherbar'), findsOneWidget);
    // An error finding tile is rendered.
    expect(find.text('Fehler'), findsWidgets);

    // The save button is disabled -> tapping does not call onSave.
    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(saved, isFalse);
  });

  testWidgets('a valid KO type can be saved and serializes one type_graph key',
      (tester) async {
    Map<String, Object?>? config;
    await _pump(tester, _koValid(), onSave: (c) => config = c);

    expect(find.text('Speicherbar'), findsOneWidget);

    await tester.ensureVisible(find.text('Speichern'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();

    expect(config, isNotNull);
    expect(config!.keys, <String>[stageTypeGraphConfigKey]);
  });
}
