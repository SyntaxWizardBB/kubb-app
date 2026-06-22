import 'package:flutter/widgets.dart' show Offset;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Client-side layout state for the desktop stage-TYPE-graph canvas (Ebene 2,
/// ADR-0039 §5/§6.5). Mirrors `stage_graph_canvas_layout.dart` (Ebene 1) but
/// keys on the type-graph anchors instead of `StageNode` ids.
///
/// Pure view state: it lives outside the domain model and outside the builder
/// state. The canvas reads/mutates only this map for placement; every
/// structural mutation goes through `stageTypeGraphBuilderProvider` so both
/// editors stay in parity.
///
/// Anchor keys depend on the category, because the two categories draw
/// different node shapes (spec §5 / OFFEN-1):
///  - **KO**: one node per field; the key is the field id (`R1F3`).
///  - **Vorrunde**: one block per round; the key is `typeRoundLayoutKey(r)`.

/// Width of a node/block on the canvas. Named constant (no magic pixels): the
/// box geometry the edge painter and hit-testing both rely on.
const double kTypeCanvasNodeWidth = 188;

/// Height of a field node on the canvas.
const double kTypeCanvasNodeHeight = 84;

/// Horizontal gap between round columns. A full card plus breathing room fits.
const double kTypeCanvasColumnGap = 104;

/// Vertical gap between cards stacked in the same column.
const double kTypeCanvasRowGap = 28;

/// Outer padding of the auto-layout grid from the canvas origin.
const double kTypeCanvasPadding = 24;

/// Horizontal stride between the LEFT edges of two adjacent round columns.
const double kTypeCanvasColumnStride =
    kTypeCanvasNodeWidth + kTypeCanvasColumnGap;

/// Vertical stride between the TOP edges of two stacked cards.
const double kTypeCanvasRowStride = kTypeCanvasNodeHeight + kTypeCanvasRowGap;

/// Layout key for a Vorrunde round block (one block per round).
String typeRoundLayoutKey(int roundNumber) => 'round_$roundNumber';

/// Notifier owning the canvas anchor-position map for the type-graph editor.
/// A single editor instance is open at a time, mirroring the form view.
class StageTypeGraphCanvasLayoutController
    extends Notifier<Map<String, Offset>> {
  @override
  Map<String, Offset> build() => const <String, Offset>{};

  /// Reconciles the position map with [graph]: keep existing positions, add an
  /// auto-layout slot for new anchors, drop anchors that no longer exist. No-op
  /// state-write when nothing changed.
  void syncWithGraph(StageTypeGraph graph) {
    final next = reconcileTypeLayout(state, graph);
    if (!_sameMap(next, state)) state = next;
  }

  /// Moves [anchor] by [delta] from its current position (drag update).
  void moveBy(String anchor, Offset delta) {
    final current = state[anchor] ?? Offset.zero;
    state = <String, Offset>{...state, anchor: current + delta};
  }

  static bool _sameMap(Map<String, Offset> a, Map<String, Offset> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Provider for the type-graph canvas layout. Local to the canvas view; never
/// feeds the domain or the builder controller.
final stageTypeGraphCanvasLayoutProvider = NotifierProvider<
    StageTypeGraphCanvasLayoutController, Map<String, Offset>>(
  StageTypeGraphCanvasLayoutController.new,
);

/// Reconciles [current] positions with [graph]: keep existing, auto-place new,
/// drop removed. Pure/deterministic — exposed for tests and the controller.
Map<String, Offset> reconcileTypeLayout(
  Map<String, Offset> current,
  StageTypeGraph graph,
) {
  final auto = typeAutoLayout(graph);
  final result = <String, Offset>{};
  for (final anchor in auto.keys) {
    result[anchor] = current[anchor] ?? auto[anchor] ?? Offset.zero;
  }
  return result;
}

/// Computes deterministic auto-layout positions, one column per round.
///
/// KO places one card per field (round = column, slot order = row). Vorrunde
/// places one block per round (round = column, single row). The same graph
/// always yields the same positions, and x grows monotonically with the round.
Map<String, Offset> typeAutoLayout(StageTypeGraph graph) {
  final rounds = <TypeRound>[...graph.rounds]
    ..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
  final positions = <String, Offset>{};

  for (var col = 0; col < rounds.length; col++) {
    final round = rounds[col];
    final x = kTypeCanvasPadding + col * kTypeCanvasColumnStride;
    if (graph.category == TypeStageCategory.vorrunde) {
      positions[typeRoundLayoutKey(round.roundNumber)] =
          Offset(x, kTypeCanvasPadding);
      continue;
    }
    final sortedFields = <TypeField>[...round.fields]
      ..sort((a, b) => a.slot.compareTo(b.slot));
    for (var row = 0; row < sortedFields.length; row++) {
      positions[sortedFields[row].id] = Offset(
        x,
        kTypeCanvasPadding + row * kTypeCanvasRowStride,
      );
    }
  }
  return positions;
}
