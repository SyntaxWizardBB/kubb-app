import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

/// Builds a node with sensible defaults for the validation tests.
StageNode _node(
  String id,
  StageNodeType type, {
  StageSeedingSource seeding = StageSeedingSource.asRouted,
  Map<String, Object?> config = const <String, Object?>{},
}) =>
    StageNode(id: id, type: type, seeding: seeding, config: config);

/// Builds an edge between two nodes with a given selector.
StageEdge _edge(String from, String to, EdgeSelector selector) =>
    StageEdge(fromNodeId: from, selector: selector, toNodeId: to);

/// Returns the subset of findings carrying the [ValidationSeverity.error].
Iterable<ValidationFinding> _errors(List<ValidationFinding> findings) =>
    findings.where((f) => f.severity == ValidationSeverity.error);

/// Whether [findings] contains a finding with the given [code].
bool _hasCode(List<ValidationFinding> findings, String code) =>
    findings.any((f) => f.code == code);

void main() {
  group('ValidationFinding', () {
    test('value equality over all six fields', () {
      const a = ValidationFinding(
        severity: ValidationSeverity.error,
        code: 'x',
        message: 'm',
        nodeId: 'n',
        edgeFrom: 'a',
        edgeTo: 'b',
      );
      const b = ValidationFinding(
        severity: ValidationSeverity.error,
        code: 'x',
        message: 'm',
        nodeId: 'n',
        edgeFrom: 'a',
        edgeTo: 'b',
      );
      const c = ValidationFinding(
        severity: ValidationSeverity.warning,
        code: 'x',
        message: 'm',
        nodeId: 'n',
        edgeFrom: 'a',
        edgeTo: 'b',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('x'));
    });
  });

  group('validateStageGraph', () {
    test('T1 happy path: pool --TopK(2)--> singleElim has no errors', () {
      final graph = StageGraph(
        nodes: <StageNode>[
          _node('grp', StageNodeType.pool),
          _node('ko', StageNodeType.singleElim),
        ],
        edges: <StageEdge>[_edge('grp', 'ko', const TopK(2))],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(_errors(findings), isEmpty);
    });

    test('T2 cycle: a -> b -> a yields cycle error', () {
      final graph = StageGraph(
        nodes: <StageNode>[
          _node('a', StageNodeType.singleElim),
          _node('b', StageNodeType.singleElim),
        ],
        edges: <StageEdge>[
          _edge('a', 'b', const Winners()),
          _edge('b', 'a', const Winners()),
        ],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(_hasCode(findings, ValidationCode.cycle), isTrue);
    });

    test('T2b self-loop counts as cycle', () {
      final graph = StageGraph(
        nodes: <StageNode>[_node('a', StageNodeType.singleElim)],
        edges: <StageEdge>[_edge('a', 'a', const Winners())],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(_hasCode(findings, ValidationCode.cycle), isTrue);
    });

    test('T3 orphan: node only inside a detached cycle is unreachable', () {
      // root -> ko is fine; b <-> c is a detached cycle, unreachable from root.
      final graph = StageGraph(
        nodes: <StageNode>[
          _node('root', StageNodeType.pool),
          _node('ko', StageNodeType.singleElim),
          _node('b', StageNodeType.singleElim),
          _node('c', StageNodeType.singleElim),
        ],
        edges: <StageEdge>[
          _edge('root', 'ko', const TopK(2)),
          _edge('b', 'c', const Winners()),
          _edge('c', 'b', const Winners()),
        ],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(_hasCode(findings, ValidationCode.orphan), isTrue);
    });

    test('isolated node without edges is its own root (no orphan)', () {
      final graph = StageGraph(
        nodes: <StageNode>[_node('solo', StageNodeType.pool)],
        edges: const <StageEdge>[],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(_hasCode(findings, ValidationCode.orphan), isFalse);
    });

    test('T4 unknown node: edge with non-existent toNode', () {
      final graph = StageGraph(
        nodes: <StageNode>[_node('grp', StageNodeType.pool)],
        edges: <StageEdge>[_edge('grp', 'missing', const TopK(2))],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      final unknown = findings
          .where((f) => f.code == ValidationCode.unknownNode)
          .toList();
      expect(unknown, isNotEmpty);
      expect(unknown.first.edgeFrom, equals('grp'));
      expect(unknown.first.edgeTo, equals('missing'));
    });

    test('T5 seeding: fromPrevRanking root yields seeding_unresolvable', () {
      final graph = StageGraph(
        nodes: <StageNode>[
          _node(
            'grp',
            StageNodeType.pool,
            seeding: StageSeedingSource.fromPrevRanking,
          ),
        ],
        edges: const <StageEdge>[],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(_hasCode(findings, ValidationCode.seedingUnresolvable), isTrue);
    });

    test('fromPrevRanking with incoming edge does not flag seeding', () {
      final graph = StageGraph(
        nodes: <StageNode>[
          _node('grp', StageNodeType.pool),
          _node(
            'ko',
            StageNodeType.singleElim,
            seeding: StageSeedingSource.fromPrevRanking,
          ),
        ],
        edges: <StageEdge>[_edge('grp', 'ko', const TopK(2))],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(_hasCode(findings, ValidationCode.seedingUnresolvable), isFalse);
    });

    test('T6 too_few: TopK(1) into singleElim (input 1 < 2)', () {
      final graph = StageGraph(
        nodes: <StageNode>[
          _node('grp', StageNodeType.pool),
          _node('ko', StageNodeType.singleElim),
        ],
        edges: <StageEdge>[_edge('grp', 'ko', const TopK(1))],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      final tooFew = findings
          .where((f) => f.code == ValidationCode.tooFew && f.nodeId == 'ko')
          .toList();
      expect(tooFew, isNotEmpty);
    });

    test('T7 selector_overlap: TopK(2) and Ranks(1,3) from same source', () {
      final graph = StageGraph(
        nodes: <StageNode>[
          _node('grp', StageNodeType.pool),
          _node('ko1', StageNodeType.singleElim),
          _node('ko2', StageNodeType.singleElim),
        ],
        edges: <StageEdge>[
          _edge('grp', 'ko1', const TopK(2)),
          _edge('grp', 'ko2', const Ranks(1, 3)),
        ],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      final overlap = findings
          .where((f) => f.code == ValidationCode.selectorOverlap)
          .toList();
      expect(overlap, isNotEmpty);
      expect(overlap.first.severity, equals(ValidationSeverity.warning));
    });

    test('T8 LosersOfRounds -> capacity_unknown, never too_few', () {
      final graph = StageGraph(
        nodes: <StageNode>[
          _node('main', StageNodeType.singleElim),
          _node('side', StageNodeType.consolation),
        ],
        edges: <StageEdge>[
          _edge('main', 'side', LosersOfRounds(const <int>{1})),
        ],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(
        findings.any(
          (f) =>
              f.code == ValidationCode.capacityUnknown && f.nodeId == 'side',
        ),
        isTrue,
      );
      expect(
        findings.any(
          (f) => f.code == ValidationCode.tooFew && f.nodeId == 'side',
        ),
        isFalse,
      );
    });

    test('T9 determinism: repeated calls yield identical ordered list', () {
      final graph = StageGraph(
        nodes: <StageNode>[
          _node('grp', StageNodeType.pool),
          _node('ko', StageNodeType.singleElim),
          _node('b', StageNodeType.singleElim),
          _node('c', StageNodeType.singleElim),
        ],
        edges: <StageEdge>[
          _edge('grp', 'ko', const TopK(1)),
          _edge('b', 'c', const Winners()),
          _edge('c', 'b', const Winners()),
          _edge('grp', 'nope', const TopK(2)),
        ],
      );
      final r1 = validateStageGraph(graph, fieldSize: 8);
      final r2 = validateStageGraph(graph, fieldSize: 8);
      expect(r1, equals(r2));
      // Verify the list is sorted by the V-ORDER rule (code primary).
      for (var i = 1; i < r1.length; i++) {
        expect(r1[i - 1].code.compareTo(r1[i].code) <= 0, isTrue);
      }
    });

    test('T10 multi_root: two roots warns and skips capacity checks', () {
      final graph = StageGraph(
        nodes: <StageNode>[
          _node('r1', StageNodeType.pool),
          _node('r2', StageNodeType.pool),
          _node('ko', StageNodeType.singleElim),
        ],
        edges: <StageEdge>[
          _edge('r1', 'ko', const TopK(1)),
          _edge('r2', 'ko', const TopK(1)),
        ],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(_hasCode(findings, ValidationCode.multiRootCapacity), isTrue);
      // Capacity checks skipped: no too_few despite TopK(1)+TopK(1) into ko.
      expect(_hasCode(findings, ValidationCode.tooFew), isFalse);
    });

    test('T11 pool groupCount: input 3 < 2*2 yields too_few', () {
      final graph = StageGraph(
        nodes: <StageNode>[
          _node('seed', StageNodeType.singleElim),
          _node(
            'grp',
            StageNodeType.pool,
            config: const <String, Object?>{'groupCount': 2},
          ),
        ],
        edges: <StageEdge>[_edge('seed', 'grp', const TopK(3))],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(
        findings.any(
          (f) => f.code == ValidationCode.tooFew && f.nodeId == 'grp',
        ),
        isTrue,
      );
    });

    test('T11b pool groupCount: input 4 == 2*2 has no too_few', () {
      final graph = StageGraph(
        nodes: <StageNode>[
          _node('seed', StageNodeType.singleElim),
          _node(
            'grp',
            StageNodeType.pool,
            config: const <String, Object?>{'groupCount': 2},
          ),
        ],
        edges: <StageEdge>[_edge('seed', 'grp', const TopK(4))],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(
        findings.any(
          (f) => f.code == ValidationCode.tooFew && f.nodeId == 'grp',
        ),
        isFalse,
      );
    });

    test('duplicate node ids with no edges do not report a false cycle', () {
      // Regression: the cycle check compared the Kahn visit count against the
      // raw node-list length, which double-counts duplicate ids and produced a
      // spurious `cycle` ERROR for an edgeless graph.
      final graph = StageGraph(
        nodes: <StageNode>[
          _node('dup', StageNodeType.singleElim),
          _node('dup', StageNodeType.singleElim),
        ],
        edges: const <StageEdge>[],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(_hasCode(findings, ValidationCode.cycle), isFalse);
    });

    test('empty graph does not throw and yields no errors', () {
      final graph = StageGraph(
        nodes: const <StageNode>[],
        edges: const <StageEdge>[],
      );
      final findings = validateStageGraph(graph, fieldSize: 8);
      expect(_errors(findings), isEmpty);
    });
  });
}
