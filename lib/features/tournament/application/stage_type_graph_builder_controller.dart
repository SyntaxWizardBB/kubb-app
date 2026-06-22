import 'package:flutter/foundation.dart' show immutable, listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Config key under which a stage's type graph (Ebene 2) is serialized into the
/// owning `StageNode.config` map (ADR-0037 / ADR-0039 §1). One key, one
/// serialization: the controller is the single source that writes it, so the
/// later canvas editor (U8) mutates the same state and stays in parity.
const String stageTypeGraphConfigKey = 'type_graph';

/// Immutable state of the in-progress stage-type-graph editor (Ebene 2,
/// ADR-0039 §6.5). Holds the current [graph] plus the derived [findings]: the
/// findings are the single source of truth for editor feedback and are ALWAYS
/// computed from `validateStageTypeGraph(graph)` — a caller never sets them
/// independently. Mirrors the Ebene-1 `StageGraphBuilderState`.
@immutable
class StageTypeGraphBuilderState {
  /// Creates a builder state. [findings] must be the result of validating
  /// [graph]; use [StageTypeGraphBuilderState.fromGraph] to keep that invariant.
  const StageTypeGraphBuilderState({
    required this.graph,
    required this.findings,
  });

  /// Builds a state by validating [graph], so [findings] is always consistent
  /// with the graph (live validation).
  factory StageTypeGraphBuilderState.fromGraph(StageTypeGraph graph) =>
      StageTypeGraphBuilderState(
        graph: graph,
        findings: validateStageTypeGraph(graph),
      );

  /// The in-progress stage type graph.
  final StageTypeGraph graph;

  /// Derived validation findings (errors + warnings), code-sorted.
  final List<ValidationFinding> findings;

  /// Whether any finding is a blocking error. Warnings never block (spec §7:
  /// an `OpenEdge` is a warning, not an error).
  bool get hasErrors => hasTypeErrors(findings);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageTypeGraphBuilderState &&
          other.graph == graph &&
          listEquals(other.findings, findings);

  @override
  int get hashCode => Object.hash(graph, Object.hashAll(findings));
}

/// Live-validating editor controller for an in-progress stage type graph
/// (Ebene 2, ADR-0039 §1). One provider, one serialization: every mutation
/// produces a NEW [StageTypeGraph] (the domain lists are unmodifiable) and
/// re-runs `validateStageTypeGraph`, so [StageTypeGraphBuilderState.findings]
/// always reflects the current graph. Pure/deterministic: an identical mutation
/// sequence on an identical start state yields an identical state.
///
/// This is the single source the form editor (U7) and the later canvas (U8)
/// both mutate — the editor-parity precondition from ADR-0039 §6.5. Persistence
/// (writing into the owning `StageNode.config`) goes through [toConfig].
class StageTypeGraphBuilderController
    extends Notifier<StageTypeGraphBuilderState> {
  /// Optional seed (e.g. loaded from a template or an existing stage config).
  /// When non-null, `build()` starts from this graph instead of a fresh one.
  StageTypeGraphBuilderController([this._initialGraph]);

  final StageTypeGraph? _initialGraph;

  /// Field count of round 1 for a fresh KO editor (16 participants -> F1..F8,
  /// the spec §9.1 worked example).
  static const int defaultParticipantCount = 16;

  /// Default category of a fresh editor.
  static const TypeStageCategory defaultCategory = TypeStageCategory.ko;

  /// Default per-round match format for a freshly-added round (Bo3, 30 min, no
  /// tiebreak), matching the classic KO step's bare fallback.
  static const MatchFormatSpec defaultMatchFormat = MatchFormatSpec(
    setsToWin: 2,
    maxSets: 3,
    timeLimitSeconds: 1800,
    tiebreakEnabled: false,
  );

  @override
  StageTypeGraphBuilderState build() {
    final graph = _initialGraph ?? _freshGraph(defaultCategory);
    return StageTypeGraphBuilderState.fromGraph(graph);
  }

  /// Replaces the whole graph with a fresh round 1 of [participantCount]
  /// participants in [category], discarding all rounds/edges. Used when the
  /// owner switches the category or re-enters the participant count (spec §3
  /// steps 1-3).
  void resetTo({
    required TypeStageCategory category,
    int participantCount = defaultParticipantCount,
  }) {
    state = StageTypeGraphBuilderState.fromGraph(
      _freshGraph(category, participantCount: participantCount),
    );
  }

  /// Replaces the entire graph (e.g. from a loaded template) and re-validates.
  void loadFromGraph(StageTypeGraph graph) {
    state = StageTypeGraphBuilderState.fromGraph(graph);
  }

  /// Appends a round with [fields] and re-validates. The round number is the
  /// next free one after the current last round. [pairingRule] is meaningful
  /// only for Vorrunde, [koMatchup]/[koTiebreak] only for KO; pass the ones the
  /// current category uses.
  void addRound({
    required List<TypeField> fields,
    required MatchFormatSpec matchFormat,
    KoMatchup? koMatchup,
    KoTiebreakMethod? koTiebreak,
    TypePairingRule? pairingRule,
  }) {
    final next = _nextRoundNumber();
    final round = TypeRound(
      roundNumber: next,
      fields: fields,
      matchFormat: matchFormat,
      koMatchup: koMatchup,
      koTiebreak: koTiebreak,
      pairingRule: pairingRule,
    );
    _replaceGraph(
      rounds: <TypeRound>[...state.graph.rounds, round],
      edges: state.graph.edges,
    );
  }

  /// Replaces the round numbered [roundNumber] with [round] and re-validates.
  /// No-op when no round matches. The replacement keeps its own round number,
  /// so callers should not renumber via this path.
  void updateRound(int roundNumber, TypeRound round) {
    final rounds = state.graph.rounds;
    final index = rounds.indexWhere((r) => r.roundNumber == roundNumber);
    if (index < 0) return;
    final next = <TypeRound>[...rounds]..[index] = round;
    _replaceGraph(rounds: next, edges: state.graph.edges);
  }

  /// Removes the round numbered [roundNumber] AND every edge that touches one
  /// of its fields or references it as an `AdvanceAllEdge` endpoint, then
  /// re-validates.
  void removeRound(int roundNumber) {
    final removedFieldIds = <String>{
      for (final r in state.graph.rounds)
        if (r.roundNumber == roundNumber)
          for (final f in r.fields) f.id,
    };
    final rounds = <TypeRound>[
      for (final r in state.graph.rounds)
        if (r.roundNumber != roundNumber) r,
    ];
    final edges = <FieldEdge>[
      for (final e in state.graph.edges)
        if (!_edgeTouchesRound(e, roundNumber, removedFieldIds)) e,
    ];
    _replaceGraph(rounds: rounds, edges: edges);
  }

  /// Appends [edge] and re-validates.
  void addEdge(FieldEdge edge) {
    _replaceGraph(
      rounds: state.graph.rounds,
      edges: <FieldEdge>[...state.graph.edges, edge],
    );
  }

  /// Replaces the edge at [index] (declaration order) with [edge] and
  /// re-validates. An out-of-range index is a no-op.
  void updateEdge(int index, FieldEdge edge) {
    final edges = state.graph.edges;
    if (index < 0 || index >= edges.length) return;
    final next = <FieldEdge>[...edges]..[index] = edge;
    _replaceGraph(rounds: state.graph.rounds, edges: next);
  }

  /// Removes the edge at [index] (declaration order) and re-validates. An
  /// out-of-range index is a no-op.
  void removeEdge(int index) {
    final edges = state.graph.edges;
    if (index < 0 || index >= edges.length) return;
    final next = <FieldEdge>[...edges]..removeAt(index);
    _replaceGraph(rounds: state.graph.rounds, edges: next);
  }

  /// Serializes the current graph for storage under [stageTypeGraphConfigKey]
  /// in the owning `StageNode.config`. The single serialization the spec §9.5 /
  /// ADR-0039 §6.5 parity check relies on — both editors round-trip through it.
  Map<String, Object?> toConfig() => <String, Object?>{
        stageTypeGraphConfigKey: state.graph.toJson(),
      };

  StageTypeGraph _freshGraph(
    TypeStageCategory category, {
    int participantCount = defaultParticipantCount,
  }) {
    final round1 = TypeRound(
      roundNumber: 1,
      fields: generateRound1(category, participantCount),
      matchFormat: defaultMatchFormat,
      koMatchup: category == TypeStageCategory.ko
          ? KoMatchup.seedHighVsLow
          : null,
      koTiebreak: category == TypeStageCategory.ko
          ? KoTiebreakMethod.classicKingtossRemoval
          : null,
      pairingRule: category == TypeStageCategory.vorrunde
          ? TypePairingRule.groupRoundRobin
          : null,
    );
    return StageTypeGraph(
      category: category,
      rounds: <TypeRound>[round1],
      edges: const <FieldEdge>[],
    );
  }

  int _nextRoundNumber() {
    var max = 0;
    for (final r in state.graph.rounds) {
      if (r.roundNumber > max) max = r.roundNumber;
    }
    return max + 1;
  }

  static bool _edgeTouchesRound(
    FieldEdge edge,
    int roundNumber,
    Set<String> roundFieldIds,
  ) {
    switch (edge) {
      case WinnerEdge(:final fromFieldId, :final toFieldId):
      case LoserEdge(:final fromFieldId, :final toFieldId):
        return roundFieldIds.contains(fromFieldId) ||
            roundFieldIds.contains(toFieldId);
      case OpenEdge(:final fromFieldId):
        return roundFieldIds.contains(fromFieldId);
      case AdvanceAllEdge(:final fromRound, :final toRound):
        return fromRound == roundNumber || toRound == roundNumber;
    }
  }

  void _replaceGraph({
    required List<TypeRound> rounds,
    required List<FieldEdge> edges,
  }) {
    final graph = StageTypeGraph(
      category: state.graph.category,
      rounds: rounds,
      edges: edges,
    );
    state = StageTypeGraphBuilderState.fromGraph(graph);
  }
}

/// Provider for the live-validating stage-type-graph editor controller
/// (Ebene 2, ADR-0039 §1 / §6.5). One provider, one serialization — both the
/// form editor (U7) and the later canvas (U8) read/mutate THIS provider. No UI
/// imports here. Mirrors the Ebene-1 `stageGraphBuilderProvider`.
final stageTypeGraphBuilderProvider = NotifierProvider<
    StageTypeGraphBuilderController, StageTypeGraphBuilderState>(
  StageTypeGraphBuilderController.new,
);
