import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/widgets/kubb_app_bar.dart';
import 'package:kubb_app/core/ui/widgets/kubb_empty_state.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/data/stage_graph_templates_repository.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_builder_screen.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// --- Test fixtures ---------------------------------------------------------

StageNode _pool(String id) => StageNode(
      id: id,
      type: StageNodeType.groupPhase,
      seeding: StageSeedingSource.asRouted,
      config: const <String, Object?>{'groupCount': 2, 'qualifierCount': 2},
    );

StageNode _singleElim(String id) => StageNode(
      id: id,
      type: StageNodeType.singleElim,
      seeding: StageSeedingSource.asRouted,
    );

/// A valid two-stage graph: pool -> single_elim via TopK(2). With fieldSize 8
/// this validates without errors.
StageGraph get _validGraph => StageGraph(
      nodes: <StageNode>[_pool('groups'), _singleElim('cup')],
      edges: const <StageEdge>[
        StageEdge(
          fromNodeId: 'groups',
          toNodeId: 'cup',
          selector: TopK(2),
        ),
      ],
    );

/// A graph whose node seeds `fromPrevRanking` but has no incoming ordered
/// source -> a `seeding_unresolvable` ERROR (hasErrors == true).
StageGraph get _errorGraph => StageGraph(
      nodes: <StageNode>[
        StageNode(
          id: 'needsSource',
          type: StageNodeType.singleElim,
          seeding: StageSeedingSource.fromPrevRanking,
        ),
      ],
      edges: const <StageEdge>[],
    );

/// Repository fake built on the public test seam; the rpc caller captures
/// save calls and never touches Supabase.
class _CapturingRepo {
  final List<Map<String, dynamic>> rpcCalls = <Map<String, dynamic>>[];

  StageGraphTemplatesRepository build() => StageGraphTemplatesRepository.withSeams(
        select: (_) async => const <dynamic>[],
        rpc: (fn, params) async {
          rpcCalls.add(<String, dynamic>{'fn': fn, ...params});
          return 'new-template-id';
        },
      );
}

StageGraphTemplate _template({
  required String id,
  required String name,
  required StageGraph graph,
  bool isSystem = false,
}) =>
    StageGraphTemplate(
      id: id,
      name: name,
      description: null,
      visibility: TemplateVisibility.public,
      graph: graph,
      isSystem: isSystem,
    );

/// Pumps the screen with overridden providers.
Future<StageGraphBuilderController> _pump(
  WidgetTester tester, {
  required StageGraph graph,
  int fieldSize = 8,
  List<StageGraphTemplate> templates = const <StageGraphTemplate>[],
  StageGraphTemplatesRepository? repo,
}) async {
  final controller = StageGraphBuilderController(graph, fieldSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stageGraphBuilderProvider.overrideWith(() => controller),
        stageGraphTemplatesProvider.overrideWith((_) async => templates),
        if (repo != null)
          stageGraphTemplatesRepositoryProvider.overrideWithValue(repo),
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
  return controller;
}

void main() {
  testWidgets('T1 renders nodes + edge and shows playable', (tester) async {
    final controller = await _pump(tester, graph: _validGraph);

    // Both node tiles (ids + type labels) render.
    expect(find.text('groups'), findsOneWidget);
    expect(find.text('cup'), findsOneWidget);
    expect(find.text('Gruppenphase'), findsWidgets); // pool type label / section
    expect(find.text('K.-o. (einfach)'), findsOneWidget);

    // The edge surfaces in the edges list.
    expect(find.text('groups → cup'), findsOneWidget);
    expect(find.text('Top 2'), findsOneWidget);

    // Playable indicator (no errors), not "nicht spielbar".
    expect(controller.state.hasErrors, isFalse);
    expect(find.text('Spielbar'), findsOneWidget);
    expect(find.text('Nicht spielbar'), findsNothing);
  });

  testWidgets('T2 errors -> not playable', (tester) async {
    final controller = await _pump(tester, graph: _errorGraph);

    expect(controller.state.hasErrors, isTrue);
    expect(find.text('Nicht spielbar'), findsOneWidget);
    expect(find.text('Spielbar'), findsNothing);

    // The seeding-unresolvable error finding (code) is shown.
    expect(find.text(ValidationCode.seedingUnresolvable), findsWidgets);
    expect(find.text('Fehler'), findsWidgets);
  });

  testWidgets('T3 add-node dialog -> addNode', (tester) async {
    final controller = await _pump(
      tester,
      graph: StageGraph(nodes: <StageNode>[_pool('seed')], edges: const []),
    );

    // Open the add-node dialog (the section "Stufe hinzufügen" icon button).
    final addNodeButton = find.byTooltip('Stufe hinzufügen');
    await tester.ensureVisible(addNodeButton.first);
    await tester.pumpAndSettle();
    await tester.tap(addNodeButton.first);
    await tester.pumpAndSettle();

    // Fill the id field (targeted by key, not position).
    await tester.enterText(
      find.byKey(const Key('stageGraphNodeIdField')),
      'newStage',
    );
    await tester.pumpAndSettle();

    // Confirm.
    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();

    expect(controller.state.graph.nodes.any((n) => n.id == 'newStage'), isTrue);
    expect(find.text('newStage'), findsOneWidget);
  });

  testWidgets('T4 add edge with TopK selector', (tester) async {
    final controller = await _pump(
      tester,
      graph: StageGraph(
        nodes: <StageNode>[_pool('a'), _singleElim('b')],
        edges: const [],
      ),
    );

    final addEdgeButton = find.byTooltip('Kante hinzufügen');
    await tester.ensureVisible(addEdgeButton.first);
    await tester.pumpAndSettle();
    await tester.tap(addEdgeButton.first);
    await tester.pumpAndSettle();

    // from = a (default), to = b (default second node). Selector defaults to
    // TopK; the k field defaults to 2.
    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();

    expect(controller.state.graph.edges, hasLength(1));
    final edge = controller.state.graph.edges.first;
    expect(edge.fromNodeId, 'a');
    expect(edge.toNodeId, 'b');
    expect(edge.selector, isA<TopK>());
    expect((edge.selector as TopK).k, 2);
    expect(find.text('a → b'), findsOneWidget);
    expect(find.text('Top 2'), findsOneWidget);
  });

  testWidgets('T4b edit edge -> updateEdge, prefilled, no duplicate',
      (tester) async {
    final controller = await _pump(
      tester,
      graph: StageGraph(
        nodes: <StageNode>[_pool('a'), _singleElim('b')],
        edges: const [
          StageEdge(
            fromNodeId: 'a',
            toNodeId: 'b',
            selector: Ranks(3, 5),
          ),
        ],
      ),
    );

    expect(controller.state.graph.edges, hasLength(1));
    expect(find.text('a → b'), findsOneWidget);

    // Open the edit dialog from the edge tile.
    final editButton = find.byTooltip('Kante bearbeiten');
    await tester.ensureVisible(editButton.first);
    await tester.pumpAndSettle();
    await tester.tap(editButton.first);
    await tester.pumpAndSettle();

    // Dialog opened in edit mode with the existing selector params pre-filled
    // (Ranks 3..5) and the existing endpoints (from a, to b).
    expect(find.text('Kante bearbeiten'), findsOneWidget);
    expect(find.widgetWithText(TextField, '3'), findsOneWidget);
    final rankToField = find.widgetWithText(TextField, '5');
    expect(rankToField, findsOneWidget);

    // Change the upper rank to 6 and confirm.
    await tester.enterText(rankToField, '6');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();

    // Same single edge, replaced in place with the new rank band.
    expect(controller.state.graph.edges, hasLength(1));
    final edge = controller.state.graph.edges.first;
    expect(edge.fromNodeId, 'a');
    expect(edge.toNodeId, 'b');
    expect(edge.selector, const Ranks(3, 6));
    expect(find.text('a → b'), findsOneWidget);
  });

  testWidgets('T5 apply template -> loadFromGraph', (tester) async {
    final controller = await _pump(
      tester,
      graph: StageGraph(nodes: const [], edges: const []),
      templates: [
        _template(id: 'tpl-1', name: 'System-Cup', graph: _validGraph, isSystem: true),
      ],
    );

    // Select the template in the dropdown.
    await tester.tap(find.text('Vorlage wählen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('System-Cup').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Anwenden'));
    await tester.pumpAndSettle();

    // The template graph is now loaded.
    expect(controller.state.graph.nodes.map((n) => n.id), containsAll(['groups', 'cup']));
    expect(find.text('groups'), findsOneWidget);
    expect(find.text('cup'), findsOneWidget);
    expect(find.text('groups → cup'), findsOneWidget);
  });

  testWidgets('T6 empty-state for empty graph', (tester) async {
    await _pump(
      tester,
      graph: StageGraph(nodes: const [], edges: const []),
    );

    expect(find.byType(KubbEmptyState), findsOneWidget);
    expect(find.text('Noch kein Stufen-Graph'), findsOneWidget);
    // Field size + template bar remain visible.
    expect(find.text('Feldgröße'), findsOneWidget);
    expect(find.text('Vorlagen'), findsOneWidget);
  });

  testWidgets(
      'P2.3: standalone screen reuses the shared StageGraphBuilderBody and '
      'keeps the page chrome (Scaffold + KubbAppBar) (P2_3-01 / P2_3-02)',
      (tester) async {
    await _pump(tester, graph: _validGraph);

    // The standalone screen renders the shared, extracted body...
    final bodyFinder = find.byType(StageGraphBuilderBody);
    expect(bodyFinder, findsOneWidget);
    // ...as the NON-embedded variant (the standalone page owns the scroll).
    final body = tester.widget<StageGraphBuilderBody>(bodyFinder);
    expect(body.embedded, isFalse);

    // The page chrome (Scaffold + KubbAppBar) lives in the screen, NOT in the
    // body: there must be no Scaffold/KubbAppBar BELOW the body widget.
    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.byType(KubbAppBar), findsOneWidget);
    expect(
      find.descendant(of: bodyFinder, matching: find.byType(Scaffold)),
      findsNothing,
    );
    expect(
      find.descendant(of: bodyFinder, matching: find.byType(KubbAppBar)),
      findsNothing,
    );
  });

  testWidgets(
      'P2.3: a mutation in the standalone body writes the same '
      'stageGraphBuilderProvider (P2_3-07)', (tester) async {
    final controller = await _pump(
      tester,
      graph: StageGraph(nodes: <StageNode>[_pool('seed')], edges: const []),
    );

    final addNodeButton = find.byTooltip('Stufe hinzufügen');
    await tester.ensureVisible(addNodeButton.first);
    await tester.pumpAndSettle();
    await tester.tap(addNodeButton.first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('stageGraphNodeIdField')),
      'fromBody',
    );
    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();

    expect(controller.state.graph.nodes.any((n) => n.id == 'fromBody'), isTrue);
    expect(find.text('fromBody'), findsOneWidget);
  });

  testWidgets('info button explains the selected stage type', (tester) async {
    await _pump(
      tester,
      graph: StageGraph(nodes: <StageNode>[_pool('seed')], edges: const []),
    );

    await tester.tap(find.byTooltip('Stufe hinzufügen').first);
    await tester.pumpAndSettle();

    // Default type is "Gruppe" (pool). Tap its info button.
    await tester.tap(find.byTooltip('Stufentyp'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Jeder spielt in seiner Gruppe gegen jeden'),
      findsOneWidget,
    );
  });

  testWidgets('info button explains the grouping strategy', (tester) async {
    await _pump(
      tester,
      graph: StageGraph(nodes: <StageNode>[_pool('seed')], edges: const []),
    );

    await tester.tap(find.byTooltip('Stufe hinzufügen').first);
    await tester.pumpAndSettle();

    // Pool node -> grouping strategy field is shown; default is snake.
    final groupingInfo = find.byTooltip('Gruppierungsstrategie');
    await tester.ensureVisible(groupingInfo);
    await tester.pumpAndSettle();
    await tester.tap(groupingInfo);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('abwechselnd auf die Gruppen verteilt'),
      findsOneWidget,
    );
  });

  testWidgets('info button explains the edge seeding mode', (tester) async {
    await _pump(
      tester,
      graph: StageGraph(
        nodes: <StageNode>[_pool('a'), _singleElim('b')],
        edges: const [],
      ),
    );

    final addEdgeButton = find.byTooltip('Kante hinzufügen');
    await tester.ensureVisible(addEdgeButton.first);
    await tester.pumpAndSettle();
    await tester.tap(addEdgeButton.first);
    await tester.pumpAndSettle();

    // Default seeding mode is orderPreserving.
    final seedingInfo = find.byTooltip('Seeding-Modus');
    await tester.ensureVisible(seedingInfo);
    await tester.pumpAndSettle();
    await tester.tap(seedingInfo);
    await tester.pumpAndSettle();

    expect(
      find.textContaining('behalten die Reihenfolge aus der Quell-Stufe'),
      findsOneWidget,
    );
  });

  testWidgets('optional: save template calls repo with current graph',
      (tester) async {
    final repoFake = _CapturingRepo();
    await _pump(
      tester,
      graph: _validGraph,
      repo: repoFake.build(),
    );

    await tester.tap(find.text('Als Vorlage speichern'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('stageGraphTemplateNameField')),
      'Mein Cup',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();

    expect(repoFake.rpcCalls, hasLength(1));
    final call = repoFake.rpcCalls.first;
    expect(call['fn'], StageGraphTemplatesRepository.saveRpcName);
    expect(call[StageGraphTemplatesRepository.saveNameParam], 'Mein Cup');
  });
}
