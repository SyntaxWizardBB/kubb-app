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
      initial: _node(StageNodeType.pool,
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
      initial: _node(StageNodeType.pool,
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
}
