import 'package:kubb_domain/src/tournament/stage_graph/edge_selector.dart';
import 'package:meta/meta.dart';

/// How participants routed along an edge are seeded into the target stage.
///
/// ADR-0030 §Edge (`seeding_in`).
enum StageSeedingIn {
  /// Keep the order in which the source ordering delivered them.
  orderPreserving('order_preserving'),

  /// Re-seed by the participants' rank in the source stage.
  reseedBySourceRank('reseed_by_source_rank'),

  /// Manually provided seed order.
  manual('manual');

  const StageSeedingIn(this.wire);

  /// Stable snake_case wire string (serialization contract).
  final String wire;

  /// Serializes this value to its stable wire string.
  String toWire() => wire;

  /// Parses [wire] back to a [StageSeedingIn].
  ///
  /// Throws [ArgumentError] for an unknown string.
  static StageSeedingIn fromWire(String wire) {
    for (final v in StageSeedingIn.values) {
      if (v.wire == wire) return v;
    }
    throw ArgumentError.value(wire, 'wire', 'unknown StageSeedingIn');
  }
}

/// A routing edge between two stages of the graph (ADR-0030 §Edge).
///
/// Pure data: it carries the source/target node ids, the [selector] deciding
/// which participants flow, and the [seedingIn] policy for the target. No
/// semantic validation is performed here (later layer).
@immutable
class StageEdge {
  /// Creates a routing edge.
  const StageEdge({
    required this.fromNodeId,
    required this.selector,
    required this.toNodeId,
    this.seedingIn = StageSeedingIn.orderPreserving,
  });

  /// Reconstructs a [StageEdge] from its JSON form.
  ///
  /// When `seeding_in` is absent, the [StageSeedingIn.orderPreserving] default
  /// applies.
  factory StageEdge.fromJson(Map<String, Object?> json) => StageEdge(
        fromNodeId: json['from_node_id']! as String,
        selector:
            EdgeSelector.fromJson(json['selector']! as Map<String, Object?>),
        toNodeId: json['to_node_id']! as String,
        seedingIn: json['seeding_in'] == null
            ? StageSeedingIn.orderPreserving
            : StageSeedingIn.fromWire(json['seeding_in']! as String),
      );

  /// Id of the source stage.
  final String fromNodeId;

  /// Selector deciding which source participants flow along this edge.
  final EdgeSelector selector;

  /// Id of the target stage.
  final String toNodeId;

  /// Seeding policy for participants entering the target stage.
  final StageSeedingIn seedingIn;

  /// Serializes this edge to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
        'from_node_id': fromNodeId,
        'selector': selector.toJson(),
        'to_node_id': toNodeId,
        'seeding_in': seedingIn.toWire(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageEdge &&
          other.fromNodeId == fromNodeId &&
          other.selector == selector &&
          other.toNodeId == toNodeId &&
          other.seedingIn == seedingIn;

  @override
  int get hashCode => Object.hash(fromNodeId, selector, toNodeId, seedingIn);

  @override
  String toString() => 'StageEdge($fromNodeId -> $toNodeId, '
      'selector: $selector, seedingIn: ${seedingIn.wire})';
}
