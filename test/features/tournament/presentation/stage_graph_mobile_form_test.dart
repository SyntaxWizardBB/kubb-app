import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/data/stage_graph_templates_repository.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_builder_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// P4.2: on a phone the guided FORM is the only editor (no canvas toggle) and its
// dialogs must fit the narrow viewport without overflowing.

StageGraph get _graph => StageGraph(
      nodes: <StageNode>[
        StageNode(
          id: 'groups',
          type: StageNodeType.pool,
          seeding: StageSeedingSource.asRouted,
          config: const <String, Object?>{'groupCount': 2, 'qualifierCount': 2},
        ),
      ],
      edges: const <StageEdge>[],
    );

Future<void> _pumpPhone(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(360, 720);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stageGraphBuilderProvider
            .overrideWith(() => StageGraphBuilderController(_graph, 8)),
        stageGraphTemplatesProvider
            .overrideWith((_) async => const <StageGraphTemplate>[]),
      ],
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const StageGraphBuilderScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('phone shows the form only — no canvas toggle', (tester) async {
    await _pumpPhone(tester);
    expect(find.byWidgetPredicate((w) => w is SegmentedButton), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('add-node dialog opens on a phone without overflow',
      (tester) async {
    await _pumpPhone(tester);

    final addNodeButton = find.byTooltip('Stufe hinzufügen');
    await tester.ensureVisible(addNodeButton.first);
    await tester.pumpAndSettle();
    await tester.tap(addNodeButton.first);
    await tester.pumpAndSettle();

    // The dialog rendered (id field present) and painting raised no overflow.
    expect(find.byKey(const Key('stageGraphNodeIdField')), findsOneWidget);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('add-edge dialog opens on a phone without overflow',
      (tester) async {
    // A two-node graph so the add-edge action is enabled.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(360, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final graph = StageGraph(
      nodes: <StageNode>[
        StageNode(
            id: 'a',
            type: StageNodeType.pool,
            seeding: StageSeedingSource.asRouted),
        StageNode(
            id: 'b',
            type: StageNodeType.singleElim,
            seeding: StageSeedingSource.asRouted),
      ],
      edges: const <StageEdge>[],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stageGraphBuilderProvider
              .overrideWith(() => StageGraphBuilderController(graph, 8)),
          stageGraphTemplatesProvider
              .overrideWith((_) async => const <StageGraphTemplate>[]),
        ],
        child: MaterialApp(
          theme: KubbTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const StageGraphBuilderScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addEdgeButton = find.byTooltip('Kante hinzufügen');
    await tester.ensureVisible(addEdgeButton.first);
    await tester.pumpAndSettle();
    await tester.tap(addEdgeButton.first);
    await tester.pumpAndSettle();

    expect(find.text('Selektor'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
