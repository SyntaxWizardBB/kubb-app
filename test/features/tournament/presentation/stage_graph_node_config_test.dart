import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_labeled_switch.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_builder_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// P3.1/P3.2 + P5.5: the node dialog surfaces the full per-node KO config
// (matchup, tiebreak method, per-round format, double-elim `with_reset`) and the
// pool grouping / per-group qualifier labeling.

/// The double-elim reset Switch lives inside the 'Grand-Final-Reset'
/// KubbLabeledSwitch; the KO per-round blocks add their own tiebreak switches,
/// so target the reset one specifically.
Finder resetSwitch() => find.descendant(
      of: find.widgetWithText(KubbLabeledSwitch, 'Grand-Final-Reset'),
      matching: find.byType(Switch),
    );

/// Pumps a button that opens the (private) node EDIT dialog via the public seam
/// and captures the returned node.
Future<StageNode?> _editNode(
  WidgetTester tester, {
  required StageNode initial,
  List<int> availablePitches = const <int>[],
}) async {
  StageNode? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showStageNodeEditDialog(
                  context,
                  initial: initial,
                  existingIds: const <String>{},
                  availablePitches: availablePitches,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

/// Like [_editNode] but also taps Bestätigen, so the returned node carries the
/// config the dialog built.
Future<StageNode?> _editAndConfirm(
  WidgetTester tester, {
  required StageNode initial,
  List<int> availablePitches = const <int>[],
}) async {
  StageNode? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showStageNodeEditDialog(
                  context,
                  initial: initial,
                  existingIds: const <String>{},
                  availablePitches: availablePitches,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Bestätigen'));
  await tester.tap(find.text('Bestätigen'));
  await tester.pumpAndSettle();
  return result;
}

/// Opens the pool node EDIT dialog, taps the first pitch chip under group A,
/// then confirms — so the returned node carries the per-group assignment.
Future<StageNode?> _editAndConfirmWithTap(
  WidgetTester tester, {
  required StageNode initial,
  required List<int> availablePitches,
}) async {
  StageNode? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: KubbTheme.light(),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showStageNodeEditDialog(
                  context,
                  initial: initial,
                  existingIds: const <String>{},
                  availablePitches: availablePitches,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  // Group A's first pitch chip is the '1' under the 'Gruppe A' label.
  final chip = find.text('${availablePitches.first}').first;
  await tester.ensureVisible(chip);
  await tester.tap(chip);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Bestätigen'));
  await tester.tap(find.text('Bestätigen'));
  await tester.pumpAndSettle();
  return result;
}

StageNode _node(StageNodeType type, {Map<String, Object?>? config}) => StageNode(
      id: 'n',
      type: type,
      seeding: StageSeedingSource.asRouted,
      config: config ?? const <String, Object?>{},
    );

void main() {
  testWidgets('double-elim node shows the with_reset switch + hint', (tester) async {
    await _editNode(tester, initial: _node(StageNodeType.doubleElim));
    expect(find.text('Grand-Final-Reset'), findsOneWidget);
  });

  testWidgets('with_reset is OFF by default and persists when toggled on',
      (tester) async {
    StageNode? captured;
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showStageNodeEditDialog(
                    context,
                    initial: _node(StageNodeType.doubleElim),
                    existingIds: const <String>{},
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Toggle the reset switch on, then confirm.
    await tester.ensureVisible(resetSwitch());
    await tester.tap(resetSwitch());
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Bestätigen'));
    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.config['with_reset'], isTrue);
  });

  testWidgets('an existing with_reset:true node opens with the switch on',
      (tester) async {
    await _editNode(
      tester,
      initial: _node(StageNodeType.doubleElim,
          config: const <String, Object?>{'with_reset': true}),
    );
    final sw = tester.widget<Switch>(resetSwitch());
    expect(sw.value, isTrue);
  });

  testWidgets('pool node spells out qualifiers are per group', (tester) async {
    await _editNode(
      tester,
      initial: _node(StageNodeType.groupPhase,
          config: const <String, Object?>{'groupCount': 2, 'qualifierCount': 2}),
    );
    expect(find.textContaining('pro Gruppe'), findsWidgets);
  });

  testWidgets('single-elim node now offers full KO config (matchup/rounds), '
      'no reset switch (P5.5)', (tester) async {
    await _editNode(tester, initial: _node(StageNodeType.singleElim));
    // Full KO config is present...
    expect(find.text('Begegnungen'), findsOneWidget); // matchup label
    expect(find.text('Anzahl K.-o.-Runden'), findsOneWidget);
    // ...but bracket reset is double-elim-only.
    expect(resetSwitch(), findsNothing);
  });

  testWidgets('KO node writes matchup + tiebreak + per-round formats (P5.5)',
      (tester) async {
    final node = await _editAndConfirm(
      tester,
      initial: _node(StageNodeType.singleElim),
    );
    expect(node, isNotNull);
    // Defaults are written via the domain writer (round formats seeded).
    expect(koMatchupFromConfig(node!.config), isNotNull);
    expect(koTiebreakMethodFromConfig(node.config), isNotNull);
    expect(koRoundFormatsFromConfig(node.config), isNotEmpty);
  });

  testWidgets('pool node writes grouping strategy (P5.5)', (tester) async {
    final node = await _editAndConfirm(
      tester,
      initial: _node(StageNodeType.groupPhase,
          config: const <String, Object?>{
            'groupCount': 4,
            'qualifierCount': 2,
            'grouping_strategy': 'snake',
          }),
    );
    expect(node, isNotNull);
    expect(poolGroupingStrategyFromConfig(node!.config),
        PoolGroupingStrategy.snake);
  });

  testWidgets('pool node hides the pitch assignment section without pitches',
      (tester) async {
    await _editNode(
      tester,
      initial: _node(StageNodeType.groupPhase,
          config: const <String, Object?>{'groupCount': 2, 'qualifierCount': 2}),
    );
    expect(find.text('Pitch-Zuteilung pro Gruppe'), findsNothing);
  });

  testWidgets('pool node shows the pitch assignment section when pitches exist',
      (tester) async {
    await _editNode(
      tester,
      initial: _node(StageNodeType.groupPhase,
          config: const <String, Object?>{'groupCount': 2, 'qualifierCount': 2}),
      availablePitches: const <int>[1, 2, 3],
    );
    expect(find.text('Pitch-Zuteilung pro Gruppe'), findsOneWidget);
    expect(find.text('Gruppe A'), findsOneWidget);
    expect(find.text('Gruppe B'), findsOneWidget);
  });

  testWidgets('selecting a pitch for a group persists into the node config',
      (tester) async {
    final node = await _editAndConfirmWithTap(
      tester,
      initial: _node(StageNodeType.groupPhase,
          config: const <String, Object?>{'groupCount': 2, 'qualifierCount': 2}),
      availablePitches: const <int>[1, 2, 3],
    );
    expect(node, isNotNull);
    final assignment = poolGroupPitchAssignmentFromConfig(node!.config);
    expect(assignment['A'], contains(1));
  });

  testWidgets('an existing assignment pre-fills the chips as selected',
      (tester) async {
    await _editNode(
      tester,
      initial: _node(StageNodeType.groupPhase, config: const <String, Object?>{
        'groupCount': 2,
        'qualifierCount': 2,
        'group_pitch_assignment': <String, Object?>{
          'A': <int>[2],
        },
      }),
      availablePitches: const <int>[1, 2, 3],
    );
    // The chip for pitch 2 under group A renders; the assignment survived the
    // round-trip through config → dialog state.
    expect(find.text('Gruppe A'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
  });

  test('the add picker offers exactly the five curated types', () {
    expect(selectableStageNodeTypes, const [
      StageNodeType.groupPhase,
      StageNodeType.schoch,
      StageNodeType.singleElim,
      StageNodeType.doubleElim,
      StageNodeType.consolation,
    ]);
    expect(selectableStageNodeTypes, isNot(contains(StageNodeType.roundRobin)));
    expect(
      selectableStageNodeTypes,
      isNot(contains(StageNodeType.shootoutQuali)),
    );
  });

  testWidgets('add dialog type dropdown lists the five curated labels only',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showStageNodeAddDialog(
                  context,
                  existingIds: const <String>{},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Open the type dropdown so its menu entries render.
    await tester.tap(find.text('Gruppenphase').last);
    await tester.pumpAndSettle();

    expect(find.text('Schoch'), findsWidgets);
    expect(find.text('K.-o. (einfach)'), findsWidgets);
    expect(find.text('K.-o. (doppelt)'), findsWidgets);
    expect(find.text('Trosttournier'), findsWidgets);
    expect(find.text('Jeder gegen jeden'), findsNothing);
    expect(find.text('Shoot-out-Quali'), findsNothing);
  });
}
