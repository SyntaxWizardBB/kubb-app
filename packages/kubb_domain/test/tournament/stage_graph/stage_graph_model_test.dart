import 'dart:convert';

import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

/// Round-trips [json] through a real `jsonEncode`/`jsonDecode` cycle, returning
/// the decoded map. This exercises the actual wire format (where nested maps and
/// lists are reconstructed as fresh `dart:convert` objects) rather than passing
/// the same in-memory object references straight back through `fromJson`.
Map<String, Object?> _wire(Map<String, Object?> json) =>
    (jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>();

void main() {
  group('Enum wire round-trips', () {
    test('StageNodeType round-trips and pins wire strings', () {
      for (final v in StageNodeType.values) {
        expect(StageNodeType.fromWire(v.toWire()), v);
      }
      expect(
        {for (final v in StageNodeType.values) v: v.toWire()},
        {
          StageNodeType.pool: 'pool',
          StageNodeType.roundRobin: 'round_robin',
          StageNodeType.swiss: 'swiss',
          StageNodeType.singleElim: 'single_elim',
          StageNodeType.doubleElim: 'double_elim',
          StageNodeType.consolation: 'consolation',
          StageNodeType.shootoutQuali: 'shootout_quali',
        },
      );
      expect(
        () => StageNodeType.fromWire('unknown'),
        throwsArgumentError,
      );
    });

    test('StageSeedingSource round-trips and pins wire strings', () {
      for (final v in StageSeedingSource.values) {
        expect(StageSeedingSource.fromWire(v.toWire()), v);
      }
      expect(
        {for (final v in StageSeedingSource.values) v: v.toWire()},
        {
          StageSeedingSource.fromElo: 'from_elo',
          StageSeedingSource.fromPrevRanking: 'from_prev_ranking',
          StageSeedingSource.manual: 'manual',
          StageSeedingSource.asRouted: 'as_routed',
        },
      );
      expect(
        () => StageSeedingSource.fromWire('unknown'),
        throwsArgumentError,
      );
    });

    test('StageSeedingIn round-trips and pins wire strings', () {
      for (final v in StageSeedingIn.values) {
        expect(StageSeedingIn.fromWire(v.toWire()), v);
      }
      expect(
        {for (final v in StageSeedingIn.values) v: v.toWire()},
        {
          StageSeedingIn.orderPreserving: 'order_preserving',
          StageSeedingIn.reseedBySourceRank: 'reseed_by_source_rank',
          StageSeedingIn.manual: 'manual',
        },
      );
      expect(
        () => StageSeedingIn.fromWire('unknown'),
        throwsArgumentError,
      );
    });
  });

  group('StageNode', () {
    test('JSON round-trip with non-empty config preserves equality', () {
      final node = StageNode(
        id: 'pool-1',
        type: StageNodeType.pool,
        seeding: StageSeedingSource.fromElo,
        config: const <String, Object?>{
          'groupCount': 4,
          'qualifiersPerGroup': 2,
          'withThirdPlace': true,
          'ruleset': <String, Object?>{'best_of': 3},
          'slots': <Object?>[1, 2, 3],
        },
      );
      expect(StageNode.fromJson(node.toJson()), node);
    });

    test('real jsonEncode/jsonDecode round-trip preserves equality', () {
      final node = StageNode(
        id: 'pool-1',
        type: StageNodeType.pool,
        seeding: StageSeedingSource.fromElo,
        config: const <String, Object?>{
          'groupCount': 4,
          'qualifiersPerGroup': 2,
          'withThirdPlace': true,
          'ruleset': <String, Object?>{'best_of': 3},
          'slots': <Object?>[1, 2, 3],
        },
      );
      // Going through the actual wire format must still compare equal, which
      // requires deep (not shallow) equality of the nested config tree.
      expect(StageNode.fromJson(_wire(node.toJson())), node);
    });

    test('toJson returns a fresh mutable deep copy (no aliasing)', () {
      final node = StageNode(
        id: 'n',
        type: StageNodeType.pool,
        seeding: StageSeedingSource.fromElo,
        config: const <String, Object?>{
          'ruleset': <String, Object?>{'best_of': 3},
        },
      );
      final json = node.toJson();
      // The emitted config (and its nested map) must be mutable and detached.
      (json['config']! as Map<String, Object?>)['extra'] = true;
      ((json['config']! as Map<String, Object?>)['ruleset']!
          as Map<Object?, Object?>)['best_of'] = 99;
      expect(node.config, <String, Object?>{
        'ruleset': <String, Object?>{'best_of': 3},
      });
    });

    test('nested config structures are deep-immutable', () {
      final inner = <String, Object?>{'best_of': 3};
      final node = StageNode(
        id: 'n',
        type: StageNodeType.pool,
        seeding: StageSeedingSource.fromElo,
        config: <String, Object?>{'ruleset': inner},
      );
      // Mutating the nested map after construction must not leak into the node.
      inner['best_of'] = 99;
      expect(
        (node.config['ruleset']! as Map<Object?, Object?>)['best_of'],
        3,
      );
      // The nested map is itself unmodifiable.
      expect(
        () => (node.config['ruleset']! as Map<Object?, Object?>)['best_of'] = 99,
        throwsUnsupportedError,
      );
    });

    test('config map is unmodifiable / immune to external mutation', () {
      final source = <String, Object?>{'a': 1};
      final node = StageNode(
        id: 'n',
        type: StageNodeType.swiss,
        seeding: StageSeedingSource.manual,
        config: source,
      );
      // External mutation of the passed-in map must not affect the node.
      source['b'] = 2;
      expect(node.config, <String, Object?>{'a': 1});
      // The exposed collection is unmodifiable.
      expect(() => node.config['c'] = 3, throwsUnsupportedError);
    });

    test('value equality covers all four fields', () {
      final base = StageNode(
        id: 'n',
        type: StageNodeType.pool,
        seeding: StageSeedingSource.fromElo,
        config: const <String, Object?>{'k': 1},
      );
      expect(
        base,
        StageNode(
          id: 'n',
          type: StageNodeType.pool,
          seeding: StageSeedingSource.fromElo,
          config: const <String, Object?>{'k': 1},
        ),
      );
      expect(
        base.hashCode,
        StageNode(
          id: 'n',
          type: StageNodeType.pool,
          seeding: StageSeedingSource.fromElo,
          config: const <String, Object?>{'k': 1},
        ).hashCode,
      );
      expect(
        base ==
            StageNode(
              id: 'n2',
              type: StageNodeType.pool,
              seeding: StageSeedingSource.fromElo,
              config: const <String, Object?>{'k': 1},
            ),
        isFalse,
      );
      expect(
        base ==
            StageNode(
              id: 'n',
              type: StageNodeType.pool,
              seeding: StageSeedingSource.fromElo,
              config: const <String, Object?>{'k': 2},
            ),
        isFalse,
      );
    });
  });

  group('EdgeSelector', () {
    final selectors = <EdgeSelector>[
      const TopK(3),
      const Ranks(1, 4),
      LosersOfRounds(const <int>{2, 1, 3}),
      const NonQualifiers(),
      const Winners(),
    ];

    for (final sel in selectors) {
      test('${sel.runtimeType} JSON round-trip preserves equality', () {
        expect(EdgeSelector.fromJson(sel.toJson()), sel);
      });
      test('${sel.runtimeType} real wire round-trip preserves equality', () {
        expect(EdgeSelector.fromJson(_wire(sel.toJson())), sel);
      });
    }

    test('exact JSON forms match the ADR', () {
      expect(const TopK(3).toJson(), {'kind': 'top_k', 'k': 3});
      expect(const Ranks(1, 3).toJson(), {'kind': 'ranks', 'from': 1, 'to': 3});
      expect(
        LosersOfRounds(const <int>{3, 1, 2}).toJson(),
        {
          'kind': 'losers_of_rounds',
          'rounds': [1, 2, 3],
        },
      );
      expect(const NonQualifiers().toJson(), {'kind': 'non_qualifiers'});
      expect(const Winners().toJson(), {'kind': 'winners'});
    });

    test('fromJson throws on unknown kind', () {
      expect(
        () => EdgeSelector.fromJson(<String, Object?>{'kind': 'bogus'}),
        throwsArgumentError,
      );
    });

    test('fromJson throws on missing kind', () {
      expect(
        () => EdgeSelector.fromJson(<String, Object?>{}),
        throwsArgumentError,
      );
    });

    test('variants compare distinctly', () {
      expect(const NonQualifiers() == const Winners(), isFalse);
      expect(const TopK(3) == const Ranks(1, 3), isFalse);
      expect(const TopK(3), const TopK(3));
      expect(const Ranks(1, 3) == const Ranks(1, 4), isFalse);
    });

    test('LosersOfRounds set is order-independent for equality', () {
      expect(
        LosersOfRounds(const <int>{1, 2, 3}),
        LosersOfRounds(const <int>{3, 2, 1}),
      );
      expect(
        LosersOfRounds(const <int>{1, 2, 3}).hashCode,
        LosersOfRounds(const <int>{3, 2, 1}).hashCode,
      );
    });

    test('LosersOfRounds.rounds is unmodifiable / immune to mutation', () {
      final source = <int>{1, 2};
      final sel = LosersOfRounds(source);
      source.add(3);
      expect(sel.rounds, <int>{1, 2});
      expect(() => sel.rounds.add(9), throwsUnsupportedError);
    });
  });

  group('StageEdge', () {
    test('round-trip with non-default seedingIn', () {
      const edge = StageEdge(
        fromNodeId: 'a',
        selector: TopK(2),
        toNodeId: 'b',
        seedingIn: StageSeedingIn.reseedBySourceRank,
      );
      expect(StageEdge.fromJson(edge.toJson()), edge);
    });

    test('round-trip with default seedingIn', () {
      const edge = StageEdge(
        fromNodeId: 'a',
        selector: Winners(),
        toNodeId: 'b',
      );
      expect(edge.seedingIn, StageSeedingIn.orderPreserving);
      expect(StageEdge.fromJson(edge.toJson()), edge);
    });

    test('real wire round-trip preserves equality', () {
      final edge = StageEdge(
        fromNodeId: 'a',
        selector: LosersOfRounds(const <int>{2, 1}),
        toNodeId: 'b',
        seedingIn: StageSeedingIn.reseedBySourceRank,
      );
      expect(StageEdge.fromJson(_wire(edge.toJson())), edge);
    });

    test('default applies when seeding_in absent in JSON', () {
      final edge = StageEdge.fromJson(<String, Object?>{
        'from_node_id': 'a',
        'selector': const NonQualifiers().toJson(),
        'to_node_id': 'b',
      });
      expect(edge.seedingIn, StageSeedingIn.orderPreserving);
    });

    test('value equality covers all four fields', () {
      const base = StageEdge(
        fromNodeId: 'a',
        selector: TopK(2),
        toNodeId: 'b',
      );
      expect(
        base,
        const StageEdge(fromNodeId: 'a', selector: TopK(2), toNodeId: 'b'),
      );
      expect(
        base ==
            const StageEdge(fromNodeId: 'a', selector: TopK(3), toNodeId: 'b'),
        isFalse,
      );
    });
  });

  group('StageGraph', () {
    StageGraph buildGraph() => StageGraph(
          nodes: <StageNode>[
            StageNode(
              id: 'pool',
              type: StageNodeType.pool,
              seeding: StageSeedingSource.fromElo,
              config: const <String, Object?>{'groupCount': 2},
            ),
            StageNode(
              id: 'main-ko',
              type: StageNodeType.singleElim,
              seeding: StageSeedingSource.fromPrevRanking,
              config: const <String, Object?>{'withThirdPlace': true},
            ),
            StageNode(
              id: 'cup',
              type: StageNodeType.consolation,
              seeding: StageSeedingSource.asRouted,
            ),
          ],
          edges: <StageEdge>[
            const StageEdge(
              fromNodeId: 'pool',
              selector: TopK(4),
              toNodeId: 'main-ko',
            ),
            StageEdge(
              fromNodeId: 'main-ko',
              selector: LosersOfRounds(const <int>{1}),
              toNodeId: 'cup',
            ),
          ],
        );

    test('round-trip with multiple nodes and edges', () {
      final graph = buildGraph();
      expect(StageGraph.fromJson(graph.toJson()), graph);
    });

    test('real jsonEncode/jsonDecode round-trip preserves equality', () {
      final graph = buildGraph();
      expect(StageGraph.fromJson(_wire(graph.toJson())), graph);
    });

    test('value equality and hashCode', () {
      expect(buildGraph(), buildGraph());
      expect(buildGraph().hashCode, buildGraph().hashCode);
    });

    test('nodeById finds existing and returns null for unknown', () {
      final graph = buildGraph();
      expect(graph.nodeById('main-ko')?.type, StageNodeType.singleElim);
      expect(graph.nodeById('missing'), isNull);
    });

    test('outgoingEdges / incomingEdges return the expected subset', () {
      final graph = StageGraph(
        nodes: <StageNode>[
          StageNode(
            id: 'a',
            type: StageNodeType.pool,
            seeding: StageSeedingSource.manual,
          ),
          StageNode(
            id: 'b',
            type: StageNodeType.singleElim,
            seeding: StageSeedingSource.asRouted,
          ),
          StageNode(
            id: 'c',
            type: StageNodeType.consolation,
            seeding: StageSeedingSource.asRouted,
          ),
        ],
        edges: const <StageEdge>[
          StageEdge(fromNodeId: 'a', selector: TopK(2), toNodeId: 'b'),
          StageEdge(
            fromNodeId: 'a',
            selector: NonQualifiers(),
            toNodeId: 'c',
          ),
          StageEdge(fromNodeId: 'b', selector: Winners(), toNodeId: 'c'),
        ],
      );

      // Deterministic order: declaration order of edges is preserved.
      expect(
        graph.outgoingEdges('a').map((e) => e.toNodeId).toList(),
        <String>['b', 'c'],
      );
      expect(
        graph.incomingEdges('c').map((e) => e.fromNodeId).toList(),
        <String>['a', 'b'],
      );
      // Empty list for a node without matching edges.
      expect(graph.outgoingEdges('c'), isEmpty);
      expect(graph.incomingEdges('a'), isEmpty);
    });

    test('nodes/edges lists are unmodifiable and immune to external mutation',
        () {
      final nodes = <StageNode>[
        StageNode(
          id: 'a',
          type: StageNodeType.pool,
          seeding: StageSeedingSource.manual,
        ),
      ];
      final edges = <StageEdge>[
        const StageEdge(fromNodeId: 'a', selector: TopK(1), toNodeId: 'a'),
      ];
      final graph = StageGraph(nodes: nodes, edges: edges);

      // Mutating the passed-in lists must not affect the graph.
      nodes.add(
        StageNode(
          id: 'x',
          type: StageNodeType.swiss,
          seeding: StageSeedingSource.manual,
        ),
      );
      edges.add(
        const StageEdge(fromNodeId: 'x', selector: Winners(), toNodeId: 'a'),
      );
      expect(graph.nodes, hasLength(1));
      expect(graph.edges, hasLength(1));

      // Exposed collections are unmodifiable.
      expect(
        () => graph.nodes.add(
          StageNode(
            id: 'y',
            type: StageNodeType.swiss,
            seeding: StageSeedingSource.manual,
          ),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => graph.edges.add(
          const StageEdge(fromNodeId: 'a', selector: Winners(), toNodeId: 'a'),
        ),
        throwsUnsupportedError,
      );
    });
  });
}
