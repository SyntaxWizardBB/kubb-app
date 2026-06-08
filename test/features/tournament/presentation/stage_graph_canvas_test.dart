import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/ui/theme/kubb_theme.dart';
import 'package:kubb_app/core/ui/theme/kubb_tokens.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_builder_controller.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_canvas_layout.dart';
import 'package:kubb_app/features/tournament/presentation/stage_graph_builder_screen.dart';
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

/// Two disconnected nodes side by side (no edge), so a port-drag can create the
/// first A->B edge.
StageGraph get _twoNodesNoEdge => StageGraph(
      nodes: <StageNode>[_pool('A'), _singleElim('B')],
      edges: const <StageEdge>[],
    );

/// Drags from the OUTPUT port of [source] to [targetCenter] (global coords),
/// with an intermediate move step so the preview line is exercised mid-drag.
Future<void> dragPortToCenter(
  WidgetTester tester, {
  required String source,
  required Offset targetCenter,
}) async {
  final portTopLeft =
      tester.getTopLeft(find.byKey(Key('stageCanvasOutPort_$source')));
  // Start in the middle of the port hit box.
  final start = portTopLeft +
      const Offset(KubbTokens.touchMin / 2, KubbTokens.touchMin / 2);
  final gesture = await tester.startGesture(start);
  await tester.pump();
  await gesture.moveTo(Offset.lerp(start, targetCenter, 0.5)!);
  await tester.pump();
  await gesture.moveTo(targetCenter);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

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

  // === L4b-2 gesture edge drawing =========================================

  testWidgets('T9 port-drag onto another card opens seeded dialog -> addEdge',
      (tester) async {
    final container = await _pumpCanvas(tester, graph: _twoNodesNoEdge);
    expect(container.read(stageGraphBuilderProvider).graph.edges, isEmpty);

    final targetCenter =
        tester.getCenter(find.byKey(const Key('stageCanvasNode_B')));
    await dragPortToCenter(tester, source: 'A', targetCenter: targetCenter);

    // The existing edge dialog appears (its node dropdowns are the reliable
    // signal — the title text equals the toolbar button label), seeded
    // from=A / to=B (the dropdowns show A and B as selected values).
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    final fromDd = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    final toDd = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).at(1),
    );
    expect(fromDd.initialValue, 'A');
    expect(toDd.initialValue, 'B');

    // Confirm with the default selector (TopK(2)) -> addEdge.
    await tester.tap(find.text('Bestätigen'));
    await tester.pumpAndSettle();

    final edges = container.read(stageGraphBuilderProvider).graph.edges;
    expect(edges, hasLength(1));
    expect(edges.single.fromNodeId, 'A');
    expect(edges.single.toNodeId, 'B');
    // Preview is gone after release.
    expect(
      find.byKey(const Key('stageCanvasConnectionPreview')),
      findsOneWidget, // the CustomPaint widget stays, painter draws nothing
    );
  });

  testWidgets('T10 port-drag into empty space -> no edge, no dialog',
      (tester) async {
    final container = await _pumpCanvas(tester, graph: _twoNodesNoEdge);

    // Drop far below every card (empty canvas region).
    final emptyPoint = tester.getBottomRight(
          find.byKey(const Key('stageCanvasEdgePainter')),
        ) -
        const Offset(4, 4);
    await dragPortToCenter(tester, source: 'A', targetCenter: emptyPoint);

    // No edge dialog (its node dropdowns are absent) and no edge created.
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(container.read(stageGraphBuilderProvider).graph.edges, isEmpty);
  });

  testWidgets('T11 port-drag back onto the SAME card (self) -> no edge',
      (tester) async {
    final container = await _pumpCanvas(tester, graph: _twoNodesNoEdge);

    final selfCenter =
        tester.getCenter(find.byKey(const Key('stageCanvasNode_A')));
    await dragPortToCenter(tester, source: 'A', targetCenter: selfCenter);

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(container.read(stageGraphBuilderProvider).graph.edges, isEmpty);
  });

  testWidgets('T12 regress: card-BODY drag moves only the position, no edge',
      (tester) async {
    final container = await _pumpCanvas(tester, graph: _twoNodesNoEdge);
    final start = container.read(stageGraphCanvasLayoutProvider)['A']!;

    // Drag the card body (the text, not the port) — must still just move it.
    await tester.drag(find.text('A'), const Offset(40, 24));
    await tester.pump();

    final moved = container.read(stageGraphCanvasLayoutProvider)['A']!;
    expect(moved, start + const Offset(40, 24));
    expect(container.read(stageGraphBuilderProvider).graph.edges, isEmpty);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
  });

  testWidgets('T13 output port hit box is >= touchMin', (tester) async {
    await _pumpCanvas(tester, graph: _twoNodesNoEdge);
    final size = tester.getSize(find.byKey(const Key('stageCanvasOutPort_A')));
    expect(size.width, greaterThanOrEqualTo(KubbTokens.touchMin));
    expect(size.height, greaterThanOrEqualTo(KubbTokens.touchMin));
  });

  // === Pure resolve-function unit tests (DoD §17/§23) =====================

  group('resolveConnectionTarget', () {
    final positions = <String, Offset>{
      'A': Offset.zero,
      'B': const Offset(400, 0),
    };
    final order = ['A', 'B'];

    test('pointer inside B box, source A -> B', () {
      final r = resolveConnectionTarget(
        pointer: const Offset(410, 10),
        sourceNodeId: 'A',
        nodeOrder: order,
        positions: positions,
      );
      expect(r, 'B');
    });

    test('pointer in empty space -> null', () {
      final r = resolveConnectionTarget(
        pointer: const Offset(2000, 2000),
        sourceNodeId: 'A',
        nodeOrder: order,
        positions: positions,
      );
      expect(r, isNull);
    });

    test('pointer inside A box, source A (self) -> null', () {
      final r = resolveConnectionTarget(
        pointer: const Offset(10, 10),
        sourceNodeId: 'A',
        nodeOrder: order,
        positions: positions,
      );
      expect(r, isNull);
    });

    test('overlapping boxes: first in nodeOrder wins (deterministic)', () {
      final overlap = <String, Offset>{
        'A': Offset.zero,
        'B': const Offset(10, 10), // overlaps A
      };
      final r = resolveConnectionTarget(
        pointer: const Offset(20, 20), // inside both A and B boxes
        sourceNodeId: 'src',
        nodeOrder: ['A', 'B'],
        positions: overlap,
      );
      expect(r, 'A'); // first in order
    });
  });

  // === Dialog seed (non-regression of _EdgeDialog defaults; DoD §24) =======

  /// Pumps a button that opens [showStageEdgeAddDialog] with the given seed.
  Future<void> pumpEdgeDialog(
    WidgetTester tester, {
    String? initialFrom,
    String? initialTo,
  }) async {
    final nodes = <StageNode>[_pool('A'), _singleElim('B'), _pool('C')];
    await tester.pumpWidget(
      MaterialApp(
        theme: KubbTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showStageEdgeAddDialog(
                context,
                nodes: nodes,
                initialFrom: initialFrom,
                initialTo: initialTo,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('T14 seed defaults: no seed -> from=nodes.first, to=nodes[1]',
      (tester) async {
    await pumpEdgeDialog(tester);
    final fromDd = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    final toDd = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).at(1),
    );
    expect(fromDd.initialValue, 'A');
    expect(toDd.initialValue, 'B');
  });

  testWidgets('T15 seed honored: initialFrom/To pre-select given nodes',
      (tester) async {
    await pumpEdgeDialog(tester, initialFrom: 'C', initialTo: 'A');
    final fromDd = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).first,
    );
    final toDd = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>).at(1),
    );
    expect(fromDd.initialValue, 'C');
    expect(toDd.initialValue, 'A');
  });
}
