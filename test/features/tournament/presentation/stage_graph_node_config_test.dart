import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_builder_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// P3.1/P3.2: the node dialog must surface the engine-consumed KO config
// (double-elim `with_reset`) and the per-group qualifier labeling.

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
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
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
    final sw = tester.widget<Switch>(find.byType(Switch));
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

  testWidgets('single-elim node shows the bracket-auto caption (no extra config)',
      (tester) async {
    await _editNode(tester, initial: _node(StageNodeType.singleElim));
    expect(find.textContaining('automatisch aus der Setzliste'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });
}
