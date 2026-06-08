import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/stage_graph_builder_controller.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Tests for the live-validating stage-graph editor controller (ADR-0030
/// §Editor-Lagen / §Live-Validierung).
void main() {
  StageNode poolNode({int groupCount = 1}) => StageNode(
        id: 'pool',
        type: StageNodeType.pool,
        seeding: StageSeedingSource.fromElo,
        config: <String, Object?>{'groupCount': groupCount},
      );

  StageNode koNode() => StageNode(
        id: 'ko',
        type: StageNodeType.singleElim,
        seeding: StageSeedingSource.asRouted,
      );

  const poolToKoEdge = StageEdge(
    fromNodeId: 'pool',
    selector: TopK(2),
    toNodeId: 'ko',
  );

  late ProviderContainer container;
  late StageGraphBuilderController controller;

  StageGraphBuilderState read() => container.read(stageGraphBuilderProvider);

  setUp(() {
    container = ProviderContainer();
    controller = container.read(stageGraphBuilderProvider.notifier);
  });

  tearDown(() => container.dispose());

  test('build(): empty graph, findings computed immediately, hasErrors defined',
      () {
    final state = read();

    expect(state.graph.nodes, isEmpty);
    expect(state.graph.edges, isEmpty);
    expect(state.fieldSize, StageGraphBuilderController.defaultFieldSize);
    // An empty graph has no nodes -> no errors.
    expect(state.findings, isEmpty);
    expect(state.hasErrors, isFalse);
  });

  test('addNode/addEdge: elements added; findings recomputed each mutation', () {
    controller.addNode(poolNode());
    expect(read().graph.nodes.map((n) => n.id), <String>['pool']);

    controller
      ..addNode(koNode())
      ..addEdge(poolToKoEdge);
    final state = read();
    expect(state.graph.nodes.map((n) => n.id), <String>['pool', 'ko']);
    expect(state.graph.edges, <StageEdge>[poolToKoEdge]);
    // findings are always the validateStageGraph result for the current graph.
    expect(
      state.findings,
      validateStageGraph(state.graph, fieldSize: state.fieldSize),
    );
  });

  test('valid 2-stage graph (pool -> KO, fieldSize 4) => hasErrors false', () {
    controller
      ..addNode(poolNode())
      ..addNode(koNode())
      ..addEdge(poolToKoEdge);

    final state = read();
    expect(state.fieldSize, 4);
    expect(state.hasErrors, isFalse);
  });

  test('removeNode of the source drops incident edges and re-validates', () {
    controller
      ..addNode(poolNode())
      ..addNode(koNode())
      ..addEdge(poolToKoEdge);
    expect(read().hasErrors, isFalse);

    controller.removeNode('pool');
    final state = read();

    // The incident edge is gone and the source node is removed.
    expect(state.graph.edges, isEmpty);
    expect(state.graph.nodes.map((n) => n.id), <String>['ko']);
    // Removing the source leaves NO orphan/unknown findings: the now-isolated
    // 'ko' node has no incoming edge, so validateStageGraph treats it as its own
    // root (reachable) -> hasErrors stays false. The brief's "removeNode of the
    // source -> orphan/unknown -> hasErrors true" does not hold for this domain
    // semantics; the dangling-edge test below covers the unknown_node error path.
    expect(state.hasErrors, isFalse);
    expect(
      state.findings,
      validateStageGraph(state.graph, fieldSize: state.fieldSize),
    );
  });

  test('removeNode also strips incident edges that point at the removed node',
      () {
    controller
      ..addNode(poolNode())
      ..addNode(koNode())
      ..addEdge(poolToKoEdge)
      ..removeNode('ko');

    final state = read();
    // Edge pool->ko is removed because 'ko' was deleted; no dangling edge.
    expect(state.graph.edges, isEmpty);
    expect(state.graph.nodes.map((n) => n.id), <String>['pool']);
  });

  test('a dangling edge to a non-existent node yields unknown_node => error',
      () {
    // Add nodes + an edge to a target we never create -> unknown_node error.
    controller
      ..addNode(poolNode())
      ..addNode(koNode())
      ..addEdge(const StageEdge(
        fromNodeId: 'pool',
        selector: TopK(2),
        toNodeId: 'ghost',
      ));

    final state = read();
    expect(state.hasErrors, isTrue);
    expect(
      state.findings.any((f) => f.code == ValidationCode.unknownNode),
      isTrue,
    );
  });

  test('updateNode: replaces matching node, no-op for unknown id, re-validates',
      () {
    final replacement = StageNode(
      id: 'pool',
      type: StageNodeType.swiss,
      seeding: StageSeedingSource.fromElo,
    );
    controller
      ..addNode(poolNode())
      ..updateNode('pool', replacement);
    expect(read().graph.nodes.single.type, StageNodeType.swiss);

    final before = read().graph;
    controller.updateNode('does-not-exist', koNode());
    expect(read().graph, before); // no-op
  });

  test('removeEdge: removes the right edge; out-of-range is no-op', () {
    const edgeB = StageEdge(
      fromNodeId: 'pool',
      selector: Winners(),
      toNodeId: 'ko',
    );
    controller
      ..addNode(poolNode())
      ..addNode(koNode())
      ..addEdge(poolToKoEdge)
      ..addEdge(edgeB)
      ..removeEdge(0);
    expect(read().graph.edges, <StageEdge>[edgeB]);

    final before = read().graph;
    controller.removeEdge(5); // out of range
    expect(read().graph, before);
  });

  test('setFieldSize: only changes fieldSize and re-validates capacity', () {
    // A pool with groupCount 4 needs >= 8 participants.
    controller
      ..addNode(poolNode(groupCount: 4))
      ..setFieldSize(4);
    var state = read();
    expect(state.fieldSize, 4);
    expect(state.findings.any((f) => f.code == ValidationCode.tooFew), isTrue);
    expect(state.hasErrors, isTrue);

    controller.setFieldSize(8);
    state = read();
    expect(state.fieldSize, 8);
    expect(state.findings.any((f) => f.code == ValidationCode.tooFew), isFalse);
  });

  test('loadFromGraph: replaces the whole graph and validates', () {
    // Seed some prior (erroring) state first.
    controller.addNode(poolNode(groupCount: 4));
    expect(read().hasErrors, isTrue);

    final loaded = StageGraph(
      nodes: <StageNode>[poolNode(), koNode()],
      edges: const <StageEdge>[poolToKoEdge],
    );
    controller.loadFromGraph(loaded);

    final state = read();
    expect(state.graph, loaded);
    expect(state.hasErrors, isFalse);
    expect(
      state.findings,
      validateStageGraph(loaded, fieldSize: state.fieldSize),
    );
  });

  test('determinism: identical mutation sequence => identical graph + findings',
      () {
    void mutate(StageGraphBuilderController c) {
      c
        ..addNode(poolNode())
        ..addNode(koNode())
        ..addEdge(poolToKoEdge)
        ..setFieldSize(6)
        ..removeEdge(0)
        ..addEdge(poolToKoEdge);
    }

    mutate(controller);
    final s1 = read();

    final container2 = ProviderContainer();
    addTearDown(container2.dispose);
    mutate(container2.read(stageGraphBuilderProvider.notifier));
    final s2 = container2.read(stageGraphBuilderProvider);

    expect(s1.graph, s2.graph);
    expect(s1.findings, s2.findings);
    expect(s1, s2);
  });
}
