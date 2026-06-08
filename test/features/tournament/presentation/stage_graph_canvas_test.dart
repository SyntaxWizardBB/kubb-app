import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_canvas_layout.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_canvas.dart';
import 'package:kubb_app/l10n/generated/app_localizations.dart';
import 'package:kubb_domain/kubb_domain.dart';

// --- Fixtures --------------------------------------------------------------

StageNode _pool(String id) => StageNode(
      id: id,
      type: StageNodeType.pool,
      seeding: StageSeedingSource.asRouted,
      config: const <String, Object?>{'groupCount': 2, 'qualifierCount': 2},
    );

StageNode _singleElim(String id) => StageNode(
      id: id,
      type: StageNodeType.singleElim,
      seeding: StageSeedingSource.asRouted,
    );

/// grp -> ko via TopK(2).
StageGraph get _twoStageGraph => StageGraph(
      nodes: <StageNode>[_pool('grp'), _singleElim('ko')],
      edges: const <StageEdge>[
        StageEdge(fromNodeId: 'grp', toNodeId: 'ko', selector: TopK(2)),
      ],
    );

/// grp is a root that seeds `fromPrevRanking` but has NO incoming ordered
/// source -> a `seeding_unresolvable` ERROR on node 'grp' only. ko receives the
/// full field (TopK(2) of 8) and stays error-free.
StageGraph get _errorOnGrp => StageGraph(
      nodes: <StageNode>[
        StageNode(
          id: 'grp',
          type: StageNodeType.pool,
          seeding: StageSeedingSource.fromPrevRanking,
          config: const <String, Object?>{'groupCount': 2, 'qualifierCount': 2},
        ),
        _singleElim('ko'),
      ],
      edges: const <StageEdge>[
        StageEdge(fromNodeId: 'grp', toNodeId: 'ko', selector: TopK(2)),
      ],
    );

/// Pumps the canvas with overridden builder provider. Returns a ref reader so
/// tests can read the layout provider value.
Future<ProviderContainer> _pumpCanvas(
  WidgetTester tester, {
  required StageGraph graph,
  int fieldSize = 8,
}) async {
  final controller = StageGraphBuilderController(graph, fieldSize);
  final container = ProviderContainer(
    overrides: [stageGraphBuilderProvider.overrideWith(() => controller)],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: StageGraphCanvas()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('T1 one card per node + an edge painter', (tester) async {
    await _pumpCanvas(tester, graph: _twoStageGraph);

    expect(find.text('grp'), findsOneWidget);
    expect(find.text('ko'), findsOneWidget);
    // The dedicated edge painter is present.
    expect(find.byKey(const Key('stageCanvasEdgePainter')), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('T2 auto-layout: grp col 0, ko col 1, ko.dx > grp.dx',
      (tester) async {
    final container = await _pumpCanvas(tester, graph: _twoStageGraph);

    final layout = container.read(stageGraphCanvasLayoutProvider);
    final grp = layout['grp'];
    final ko = layout['ko'];
    expect(grp, isNotNull);
    expect(ko, isNotNull);

    // Deterministic exact positions.
    expect(grp, const Offset(kStageCanvasPadding, kStageCanvasPadding));
    expect(
      ko,
      const Offset(
        kStageCanvasPadding + kStageCanvasColumnStride,
        kStageCanvasPadding,
      ),
    );
    expect(ko!.dx, greaterThan(grp!.dx));
  });

  testWidgets('T3 error highlight on offending node only', (tester) async {
    await _pumpCanvas(tester, graph: _errorOnGrp);

    // grp carries the error marker key; ko does not.
    expect(find.byKey(const Key('stageCanvasNodeError_grp')), findsOneWidget);
    expect(find.byKey(const Key('stageCanvasNodeError_ko')), findsNothing);
    expect(find.byKey(const Key('stageCanvasNode_ko')), findsOneWidget);

    // The error card (the keyed Container) uses the miss border color.
    final container = tester.widget<Container>(
      find.byKey(const Key('stageCanvasNodeError_grp')),
    );
    final border = (container.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, KubbTokens.miss);
  });

  testWidgets('T4 tap node opens edit dialog', (tester) async {
    await _pumpCanvas(tester, graph: _twoStageGraph);

    await tester.tap(find.text('grp'));
    await tester.pumpAndSettle();

    // The existing node dialog anchor is visible.
    expect(find.byKey(const Key('stageGraphNodeIdField')), findsOneWidget);
  });

  testWidgets('T5 "+ Stufe" -> addNode -> extra card', (tester) async {
    final container = await _pumpCanvas(tester, graph: _twoStageGraph);
    final before = container.read(stageGraphBuilderProvider).graph.nodes.length;

    await tester.tap(find.byKey(const Key('stageCanvasAddNode')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('stageGraphNodeIdField')),
      'extra',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();

    final after = container.read(stageGraphBuilderProvider).graph.nodes.length;
    expect(after, before + 1);
    expect(find.text('extra'), findsOneWidget);
  });

  testWidgets('T6 drag updates the position state', (tester) async {
    final container = await _pumpCanvas(tester, graph: _twoStageGraph);
    final start = container.read(stageGraphCanvasLayoutProvider)['grp']!;

    await tester.drag(find.text('grp'), const Offset(40, 24));
    await tester.pump();

    final moved = container.read(stageGraphCanvasLayoutProvider)['grp']!;
    expect(moved, start + const Offset(40, 24));
  });

  testWidgets('T7 tap edge -> confirm -> removeEdge', (tester) async {
    final container = await _pumpCanvas(tester, graph: _twoStageGraph);
    expect(container.read(stageGraphBuilderProvider).graph.edges, hasLength(1));

    // The edge midpoint between grp (col0) and ko (col1) at the same row, in
    // canvas-local coordinates...
    final layout = container.read(stageGraphCanvasLayoutProvider);
    final from = layout['grp']!;
    final to = layout['ko']!;
    final localMid = Offset(
      (from.dx + kStageCanvasNodeWidth + to.dx) / 2,
      from.dy + kStageCanvasNodeHeight / 2,
    );
    // ...translated to global via the edge painter's top-left on screen.
    final painterTopLeft = tester.getTopLeft(
      find.byKey(const Key('stageCanvasEdgePainter')),
    );
    await tester.tapAt(painterTopLeft + localMid);
    await tester.pumpAndSettle();

    // Confirm deletion (the destructive button reuses the delete-edge label).
    await tester.tap(find.text('Kante löschen').last);
    await tester.pumpAndSettle();

    expect(container.read(stageGraphBuilderProvider).graph.edges, isEmpty);
  });

  testWidgets('T8 "+ Kante" disabled with < 2 nodes', (tester) async {
    await _pumpCanvas(
      tester,
      graph: StageGraph(nodes: <StageNode>[_pool('only')], edges: const []),
    );

    final button = tester.widget<OutlinedButton>(
      find.byKey(const Key('stageCanvasAddEdge')),
    );
    expect(button.onPressed, isNull);
  });
}
