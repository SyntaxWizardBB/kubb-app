import 'package:collection/collection.dart';
import 'package:kubb_domain/src/tournament/stage_graph/stage_edge.dart';
import 'package:kubb_domain/src/tournament/stage_graph/stage_node.dart';
import 'package:meta/meta.dart';

const ListEquality<StageNode> _nodeListEquality = ListEquality<StageNode>();
const ListEquality<StageEdge> _edgeListEquality = ListEquality<StageEdge>();

/// A tournament composed as a directed graph of stages (ADR-0030 §Modell).
///
/// Pure data plus read-only lookups: this carries the [nodes] and [edges] and
/// offers structural lookup helpers. It performs NO semantic validation
/// (acyclicity, reachability, capacity, terminal mapping, ...) — those are
/// later layers.
@immutable
class StageGraph {
  /// Creates a stage graph.
  ///
  /// Both lists are copied into unmodifiable lists, so later mutation of the
  /// passed-in lists cannot change this object.
  StageGraph({
    required List<StageNode> nodes,
    required List<StageEdge> edges,
  })  : nodes = List<StageNode>.unmodifiable(nodes),
        edges = List<StageEdge>.unmodifiable(edges);

  /// Reconstructs a [StageGraph] from its JSON form.
  factory StageGraph.fromJson(Map<String, Object?> json) => StageGraph(
        nodes: <StageNode>[
          for (final n in json['nodes']! as List<Object?>)
            StageNode.fromJson(n! as Map<String, Object?>),
        ],
        edges: <StageEdge>[
          for (final e in json['edges']! as List<Object?>)
            StageEdge.fromJson(e! as Map<String, Object?>),
        ],
      );

  /// The stages of the graph. Unmodifiable.
  final List<StageNode> nodes;

  /// The routing edges of the graph. Unmodifiable.
  final List<StageEdge> edges;

  /// Serializes this graph to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
        'nodes': <Object?>[for (final n in nodes) n.toJson()],
        'edges': <Object?>[for (final e in edges) e.toJson()],
      };

  /// Returns the node with the given [id], or `null` if none matches.
  StageNode? nodeById(String id) =>
      nodes.firstWhereOrNull((n) => n.id == id);

  /// Returns all edges whose source is [nodeId], in declaration order.
  List<StageEdge> outgoingEdges(String nodeId) =>
      <StageEdge>[for (final e in edges) if (e.fromNodeId == nodeId) e];

  /// Returns all edges whose target is [nodeId], in declaration order.
  List<StageEdge> incomingEdges(String nodeId) =>
      <StageEdge>[for (final e in edges) if (e.toNodeId == nodeId) e];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageGraph &&
          _nodeListEquality.equals(other.nodes, nodes) &&
          _edgeListEquality.equals(other.edges, edges);

  @override
  int get hashCode =>
      Object.hash(_nodeListEquality.hash(nodes), _edgeListEquality.hash(edges));

  @override
  String toString() =>
      'StageGraph(nodes: ${nodes.length}, edges: ${edges.length})';
}
