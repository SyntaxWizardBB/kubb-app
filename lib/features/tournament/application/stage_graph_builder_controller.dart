import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Immutable state of the in-progress stage-graph editor (ADR-0030
/// §Editor-Lagen / §Live-Validierung).
///
/// Holds the current [graph] and [fieldSize] plus the derived [findings]: the
/// findings are the single source of truth for editor feedback and are ALWAYS
/// computed from `validateStageGraph(graph, fieldSize: fieldSize)` — they are
/// never set independently by a caller.
@immutable
class StageGraphBuilderState {
  /// Creates a builder state. [findings] must be the result of validating
  /// [graph] for [fieldSize]; use [StageGraphBuilderState.fromGraph] to keep
  /// that invariant.
  const StageGraphBuilderState({
    required this.graph,
    required this.fieldSize,
    required this.findings,
    this.availablePitches = const <int>[],
  });

  /// Builds a state by validating [graph] for [fieldSize], so [findings] is
  /// always consistent with the graph (live validation). [availablePitches]
  /// carries through unchanged — it feeds the per-group pitch assignment in the
  /// pool node dialog and does not affect validation.
  factory StageGraphBuilderState.fromGraph(
    StageGraph graph, {
    required int fieldSize,
    List<int> availablePitches = const <int>[],
  }) =>
      StageGraphBuilderState(
        graph: graph,
        fieldSize: fieldSize,
        findings: validateStageGraph(graph, fieldSize: fieldSize),
        availablePitches: availablePitches,
      );

  /// The in-progress stage graph.
  final StageGraph graph;

  /// Number of physical fields/pitches available — drives capacity findings.
  final int fieldSize;

  /// Derived validation findings (errors + warnings), V-ORDER sorted.
  final List<ValidationFinding> findings;

  /// Pitch numbers the organizer can assign per group in a pool node (seeded
  /// from the draft's pitch plan in the wizard host). Empty in the standalone
  /// editor, where there is no pitch-plan context, so the assignment section
  /// stays hidden there.
  final List<int> availablePitches;

  /// Whether any finding is a blocking error. Warnings never block (ADR-0030
  /// §Schweregrade: only `error` is blocking).
  bool get hasErrors =>
      findings.any((f) => f.severity == ValidationSeverity.error);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageGraphBuilderState &&
          other.graph == graph &&
          other.fieldSize == fieldSize &&
          listEquals(other.findings, findings) &&
          listEquals(other.availablePitches, availablePitches);

  @override
  int get hashCode => Object.hash(
        graph,
        fieldSize,
        Object.hashAll(findings),
        Object.hashAll(availablePitches),
      );
}

/// Live-validating editor controller for an in-progress stage graph (ADR-0030
/// §Editor-Lagen). Every mutation produces a NEW [StageGraph] (the domain lists
/// are unmodifiable) and re-runs `validateStageGraph` so
/// [StageGraphBuilderState.findings] always reflects the current graph.
/// Pure/deterministic: an identical mutation
/// sequence on an identical start state yields an identical state.
///
/// Persistence (save/apply) is NOT this controller's concern — it goes through
/// `StageGraphTemplatesRepository`.
class StageGraphBuilderController extends Notifier<StageGraphBuilderState> {
  /// Optional seed (e.g. loaded from a template). When non-null, `build()`
  /// starts from this graph instead of an empty one.
  StageGraphBuilderController([this._initialGraph, this._initialFieldSize]);

  final StageGraph? _initialGraph;
  final int? _initialFieldSize;

  /// Default field count for a fresh editor when no seed is provided.
  static const int defaultFieldSize = 4;

  @override
  StageGraphBuilderState build() {
    final graph =
        _initialGraph ?? StageGraph(nodes: const [], edges: const []);
    final fieldSize = _initialFieldSize ?? defaultFieldSize;
    return StageGraphBuilderState.fromGraph(graph, fieldSize: fieldSize);
  }

  /// Sets only [StageGraphBuilderState.fieldSize] and re-validates (capacity
  /// findings depend on the field size).
  void setFieldSize(int fieldSize) {
    state = StageGraphBuilderState.fromGraph(
      state.graph,
      fieldSize: fieldSize,
      availablePitches: state.availablePitches,
    );
  }

  /// Sets the pitch numbers offered for per-group assignment in pool nodes.
  /// Does not touch the graph or re-validate (pitches don't affect validation);
  /// the wizard host seeds this from the draft's pitch plan. No-op when the new
  /// list equals the current one, to avoid needless rebuilds.
  void setAvailablePitches(List<int> pitches) {
    if (listEquals(state.availablePitches, pitches)) return;
    state = StageGraphBuilderState(
      graph: state.graph,
      fieldSize: state.fieldSize,
      findings: state.findings,
      availablePitches: List<int>.unmodifiable(pitches),
    );
  }

  /// Appends [node] and re-validates.
  void addNode(StageNode node) {
    final nodes = <StageNode>[...state.graph.nodes, node];
    _replaceGraph(nodes: nodes, edges: state.graph.edges);
  }

  /// Replaces the node whose id == [id] with [node] and re-validates. No-op
  /// (no state change) when no node matches [id].
  void updateNode(String id, StageNode node) {
    final current = state.graph.nodes;
    final index = current.indexWhere((n) => n.id == id);
    if (index < 0) return;
    final nodes = <StageNode>[...current]..[index] = node;
    _replaceGraph(nodes: nodes, edges: state.graph.edges);
  }

  /// Removes the node with id == [id] AND every incident edge
  /// (`fromNodeId == id || toNodeId == id`), then re-validates.
  void removeNode(String id) {
    final nodes = <StageNode>[
      for (final n in state.graph.nodes)
        if (n.id != id) n,
    ];
    final edges = <StageEdge>[
      for (final e in state.graph.edges)
        if (e.fromNodeId != id && e.toNodeId != id) e,
    ];
    _replaceGraph(nodes: nodes, edges: edges);
  }

  /// Appends [edge] and re-validates.
  void addEdge(StageEdge edge) {
    final edges = <StageEdge>[...state.graph.edges, edge];
    _replaceGraph(nodes: state.graph.nodes, edges: edges);
  }

  /// Replaces the edge at [index] (declaration order) with [edge] and
  /// re-validates. An out-of-range index is a no-op.
  void updateEdge(int index, StageEdge edge) {
    final current = state.graph.edges;
    if (index < 0 || index >= current.length) return;
    final edges = <StageEdge>[...current]..[index] = edge;
    _replaceGraph(nodes: state.graph.nodes, edges: edges);
  }

  /// Removes the edge at [index] (declaration order) and re-validates. An
  /// out-of-range index is a no-op.
  void removeEdge(int index) {
    final current = state.graph.edges;
    if (index < 0 || index >= current.length) return;
    final edges = <StageEdge>[...current]..removeAt(index);
    _replaceGraph(nodes: state.graph.nodes, edges: edges);
  }

  /// Replaces the entire graph (e.g. from a loaded template) and re-validates,
  /// keeping the current [StageGraphBuilderState.fieldSize].
  void loadFromGraph(StageGraph graph) {
    state = StageGraphBuilderState.fromGraph(
      graph,
      fieldSize: state.fieldSize,
      availablePitches: state.availablePitches,
    );
  }

  /// Builds a fresh immutable [StageGraph] from copied lists (the domain lists
  /// are unmodifiable, so a new instance is required) and re-validates.
  void _replaceGraph({
    required List<StageNode> nodes,
    required List<StageEdge> edges,
  }) {
    final graph = StageGraph(nodes: nodes, edges: edges);
    state = StageGraphBuilderState.fromGraph(
      graph,
      fieldSize: state.fieldSize,
      availablePitches: state.availablePitches,
    );
  }
}

/// Provider for the live-validating stage-graph editor controller (ADR-0030
/// §Editor-Lagen). Mirrors the project Notifier convention
/// (`publicLiveModeProvider`). No UI imports here.
final stageGraphBuilderProvider =
    NotifierProvider<StageGraphBuilderController, StageGraphBuilderState>(
  StageGraphBuilderController.new,
);
