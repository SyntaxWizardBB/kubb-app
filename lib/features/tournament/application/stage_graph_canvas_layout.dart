import 'package:flutter/widgets.dart' show Offset;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Client-side layout state for the visual stage-graph canvas (ADR-0030
/// §Editor, Lage 4 — freier DAG-Editor / Offener Punkt 5 Editor-UX).
///
/// Holds one `Offset` per node id. This is PURE client/view state: it lives
/// outside the domain model and outside `StageGraphBuilderState`. `StageGraph`
/// / `StageNode` stay position-free; the canvas reads/mutates only this map.
///
/// Reconciliation strategy (`syncWithGraph`):
///  - A node that already has a position keeps it (manual drags are preserved).
///  - A node without a position gets an auto-layout slot (topological depth).
///  - A node id that no longer exists in the graph is dropped from the map.
///
/// Auto-layout is deterministic and idempotent: the same graph always yields
/// the same positions, and x grows strictly monotonically with topo depth
/// (column n+1 .dx > column n .dx).

/// Width of a node card on the canvas. Named constant (no magic pixels): the
/// box geometry the edge painter and hit-testing both rely on.
const double kStageCanvasNodeWidth = 200;

/// Height of a node card on the canvas.
const double kStageCanvasNodeHeight = 92;

/// Horizontal gap between topological columns. Derived from the node width so a
/// full card plus breathing room fits between columns.
const double kStageCanvasColumnGap = 96;

/// Vertical gap between cards stacked in the same column.
const double kStageCanvasRowGap = 32;

/// Outer padding of the auto-layout grid from the canvas origin.
const double kStageCanvasPadding = 24;

/// Horizontal stride between the LEFT edges of two adjacent columns.
const double kStageCanvasColumnStride =
    kStageCanvasNodeWidth + kStageCanvasColumnGap;

/// Vertical stride between the TOP edges of two stacked cards.
const double kStageCanvasRowStride = kStageCanvasNodeHeight + kStageCanvasRowGap;

/// Notifier owning the canvas node-position map (family-keyed nowhere: a single
/// editor instance is open at a time, mirroring the form view).
class StageGraphCanvasLayoutController extends Notifier<Map<String, Offset>> {
  @override
  Map<String, Offset> build() => const <String, Offset>{};

  /// Reconciles the position map with [graph] (see file doc). Returns a new map
  /// keeping existing positions, adding auto-layout slots for new nodes and
  /// removing positions of deleted nodes. No-op state-write when unchanged.
  void syncWithGraph(StageGraph graph) {
    final next = reconcile(state, graph);
    // Avoid a redundant state write (and rebuild) when nothing changed.
    if (!_sameMap(next, state)) state = next;
  }

  /// Sets the absolute position of [nodeId] (e.g. from a drag end). Unknown ids
  /// are still accepted so a drag is never lost; [syncWithGraph] prunes orphans.
  void setPosition(String nodeId, Offset position) {
    state = <String, Offset>{...state, nodeId: position};
  }

  /// Moves [nodeId] by [delta] from its current position (drag update). If the
  /// node has no position yet, [delta] is applied to the origin.
  void moveBy(String nodeId, Offset delta) {
    final current = state[nodeId] ?? Offset.zero;
    setPosition(nodeId, current + delta);
  }

  static bool _sameMap(Map<String, Offset> a, Map<String, Offset> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Provider for the canvas layout state. Local to the canvas view; never feeds
/// the domain or the builder controller.
final stageGraphCanvasLayoutProvider =
    NotifierProvider<StageGraphCanvasLayoutController, Map<String, Offset>>(
  StageGraphCanvasLayoutController.new,
);

/// Reconciles [current] positions with [graph]: keep existing, auto-place new,
/// drop removed. Pure/deterministic — exposed for tests and the controller.
Map<String, Offset> reconcile(
  Map<String, Offset> current,
  StageGraph graph,
) {
  final auto = autoLayout(graph);
  final result = <String, Offset>{};
  for (final node in graph.nodes) {
    // Keep a manually-set position; otherwise fall back to the auto slot.
    result[node.id] = current[node.id] ?? auto[node.id] ?? Offset.zero;
  }
  return result;
}

/// Computes deterministic auto-layout positions by topological depth.
///
/// Roots (no incoming edge) are column 0. A target's column is
/// `max(source columns) + 1`. Within a column, nodes are stacked vertically in
/// stable node-declaration order. Cyclic / dangling edges are tolerated: nodes
/// that never resolve a depth fall back to depth 0.
Map<String, Offset> autoLayout(StageGraph graph) {
  final depth = topoDepths(graph);

  // Group node ids by column, preserving declaration order within a column.
  final byColumn = <int, List<String>>{};
  for (final node in graph.nodes) {
    final col = depth[node.id] ?? 0;
    byColumn.putIfAbsent(col, () => <String>[]).add(node.id);
  }

  final positions = <String, Offset>{};
  for (final entry in byColumn.entries) {
    final col = entry.key;
    final ids = entry.value;
    for (var row = 0; row < ids.length; row++) {
      positions[ids[row]] = Offset(
        kStageCanvasPadding + col * kStageCanvasColumnStride,
        kStageCanvasPadding + row * kStageCanvasRowStride,
      );
    }
  }
  return positions;
}

/// Returns the topological depth (column index) of every node.
///
/// Roots have depth 0; a target depth is `max(source depth) + 1`. Computed by
/// longest-path relaxation over the well-formed edges, iterating until a fixed
/// point. Edges to/from unknown nodes are ignored. Deterministic regardless of
/// edge iteration order; cycle members keep their last relaxed value (bounded
/// by node count) without looping forever.
Map<String, int> topoDepths(StageGraph graph) {
  final ids = <String>{for (final n in graph.nodes) n.id};
  final depth = <String, int>{for (final n in graph.nodes) n.id: 0};

  // Relax up to N times (longest path in a DAG of N nodes has < N edges).
  // A bounded loop also keeps cyclic input terminating.
  final passes = graph.nodes.length;
  for (var i = 0; i < passes; i++) {
    var changed = false;
    for (final edge in graph.edges) {
      if (!ids.contains(edge.fromNodeId) || !ids.contains(edge.toNodeId)) {
        continue;
      }
      final candidate = depth[edge.fromNodeId]! + 1;
      if (candidate > depth[edge.toNodeId]!) {
        depth[edge.toNodeId] = candidate;
        changed = true;
      }
    }
    if (!changed) break;
  }
  return depth;
}
