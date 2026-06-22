import 'package:kubb_domain/src/tournament/stage_graph/edge_selector.dart';
import 'package:kubb_domain/src/tournament/stage_graph/stage_edge.dart';
import 'package:kubb_domain/src/tournament/stage_graph/stage_graph.dart';
import 'package:kubb_domain/src/tournament/stage_graph/stage_node.dart';
import 'package:meta/meta.dart';

/// Severity of a validation finding (ADR-0030 §Schweregrade).
///
/// [error] blocks publish/start: the graph is not playable. [warning] is a
/// non-blocking, visible hint the organizer can consciously accept.
enum ValidationSeverity {
  /// Blocks publish/start.
  error,

  /// Non-blocking hint.
  warning,
}

/// Stable validation finding codes (ADR-0030 §Validierung).
///
/// Kept as named constants so a code is never spelled as a magic string in more
/// than one place.
abstract final class ValidationCode {
  /// An edge references a non-existent source or target node.
  static const String unknownNode = 'unknown_node';

  /// The directed graph contains a cycle (V1).
  static const String cycle = 'cycle';

  /// A node is not reachable from any root (V4b).
  static const String orphan = 'orphan';

  /// An edge structurally leads nowhere (reserved; see V4c).
  static const String deadEdge = 'dead_edge';

  /// A `fromPrevRanking` node has no incoming ordered source (V5).
  static const String seedingUnresolvable = 'seeding_unresolvable';

  /// A node receives fewer participants than its type's minimum.
  static const String tooFew = 'too_few';

  /// Two non-`NonQualifiers` selectors of the same source overlap (V2).
  static const String selectorOverlap = 'selector_overlap';

  /// A node's input size is not statically computable.
  static const String capacityUnknown = 'capacity_unknown';

  /// More than one root, so capacity distribution is statically unclear.
  static const String multiRootCapacity = 'multi_root_capacity';
}

/// A single validation result for a stage graph (ADR-0030 §Validierung).
///
/// Carries a [severity], a stable [code], a human-readable [message] and the
/// optional ids ([nodeId], [edgeFrom], [edgeTo]) that let the UI mark the exact
/// offending node or edge. Value-based equality over all six fields.
@immutable
class ValidationFinding {
  /// Creates a validation finding.
  const ValidationFinding({
    required this.severity,
    required this.code,
    required this.message,
    this.nodeId,
    this.edgeFrom,
    this.edgeTo,
  });

  /// Whether this finding blocks publish/start or is just a hint.
  final ValidationSeverity severity;

  /// Stable code (see [ValidationCode]).
  final String code;

  /// Human-readable description of the finding.
  final String message;

  /// Id of the affected node, if any.
  final String? nodeId;

  /// Source id of the affected edge, if any.
  final String? edgeFrom;

  /// Target id of the affected edge, if any.
  final String? edgeTo;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ValidationFinding &&
          other.severity == severity &&
          other.code == code &&
          other.message == message &&
          other.nodeId == nodeId &&
          other.edgeFrom == edgeFrom &&
          other.edgeTo == edgeTo;

  @override
  int get hashCode =>
      Object.hash(severity, code, message, nodeId, edgeFrom, edgeTo);

  @override
  String toString() => 'ValidationFinding(${severity.name}, $code, "$message", '
      'node: $nodeId, edge: $edgeFrom->$edgeTo)';
}

/// A statically computed capacity that may be unknown.
///
/// Unknown propagates through every arithmetic combination ("unknown swallows
/// known"): any selection or sum that touches an unknown size is itself
/// unknown. This is the core mechanism that keeps `LosersOfRounds`-fed nodes out
/// of false `too_few` errors.
@immutable
class _Capacity {
  const _Capacity.known(this.value) : isKnown = true;
  const _Capacity.unknown()
      : value = 0,
        isKnown = false;

  final int value;
  final bool isKnown;
}

/// Validates a stage graph for a given [fieldSize] (ADR-0030 §Validierung).
///
/// Returns ALL findings (errors and warnings). An empty error-subset means the
/// graph is publishable/startable. This function never throws: a degenerate
/// graph (empty, duplicate ids, dangling edges, ...) is reported as findings,
/// not as an exception.
///
/// The returned list is stably sorted (V-ORDER): primarily by `code`, then by
/// `nodeId`, then `edgeFrom`, then `edgeTo` (nulls last), so two calls on equal
/// input yield a byte-identical order regardless of internal iteration order.
///
/// Capacity propagation interprets ADR-0030 §Kapazitäts-Propagation as "all
/// participants of a stage are ranked", so a stage's output size equals its
/// input size. Selectors that touch a runtime-dependent source
/// (`LosersOfRounds`, or any unknown source output) make the target input
/// unknown, which yields a `capacity_unknown` WARNING instead of a `too_few`
/// ERROR.
List<ValidationFinding> validateStageGraph(
  StageGraph graph, {
  required int fieldSize,
}) {
  final findings = <ValidationFinding>[];

  final nodesById = <String, StageNode>{};
  for (final node in graph.nodes) {
    // On duplicate ids the last one wins for lookups; both still appear in the
    // node list and are validated for reachability.
    nodesById[node.id] = node;
  }

  // V4a UNKNOWN-NODE first, so later checks can safely ignore malformed edges.
  final wellFormedEdges = <StageEdge>[];
  for (final edge in graph.edges) {
    final fromOk = nodesById.containsKey(edge.fromNodeId);
    final toOk = nodesById.containsKey(edge.toNodeId);
    if (!fromOk || !toOk) {
      findings.add(
        ValidationFinding(
          severity: ValidationSeverity.error,
          code: ValidationCode.unknownNode,
          message: 'Edge ${edge.fromNodeId} -> ${edge.toNodeId} references a '
              'non-existent node.',
          edgeFrom: edge.fromNodeId,
          edgeTo: edge.toNodeId,
        ),
      );
    } else {
      wellFormedEdges.add(edge);
    }
  }

  // Adjacency over well-formed edges only.
  final outgoing = <String, List<StageEdge>>{};
  final incomingCount = <String, int>{};
  for (final node in graph.nodes) {
    outgoing.putIfAbsent(node.id, () => <StageEdge>[]);
    incomingCount.putIfAbsent(node.id, () => 0);
  }
  for (final edge in wellFormedEdges) {
    outgoing.putIfAbsent(edge.fromNodeId, () => <StageEdge>[]).add(edge);
    incomingCount[edge.toNodeId] = (incomingCount[edge.toNodeId] ?? 0) + 1;
  }

  // V1 ACYCLIC via Kahn's algorithm. A cyclic graph never terminates in the
  // runner (ADR-0030 §V1). Self-loops count as cycles.
  final hasCycle = _detectCycle(graph, wellFormedEdges, findings);

  // V4b REACHABILITY: every node must be reachable from at least one root (node
  // with no incoming edge) over from->to edges.
  _checkReachability(graph, outgoing, incomingCount, findings);

  // V5 SEEDING: a `fromPrevRanking` node needs at least one incoming ordered
  // source.
  for (final node in graph.nodes) {
    if (node.seeding == StageSeedingSource.fromPrevRanking &&
        (incomingCount[node.id] ?? 0) == 0) {
      findings.add(
        ValidationFinding(
          severity: ValidationSeverity.error,
          code: ValidationCode.seedingUnresolvable,
          message: 'Node ${node.id} seeds from previous ranking but has no '
              'incoming ordered source.',
          nodeId: node.id,
        ),
      );
    }
  }

  // V2 SELECTOR-OVERLAP: statically detectable overlap of non-NonQualifiers
  // selectors of the same source stage.
  _checkSelectorOverlap(outgoing, findings);

  // Capacity propagation + min-input constraints. Only runs when the graph is
  // acyclic (topo order is undefined otherwise; the cycle ERROR already stands).
  if (!hasCycle) {
    _checkCapacities(
      graph: graph,
      nodesById: nodesById,
      outgoing: outgoing,
      incomingCount: incomingCount,
      wellFormedEdges: wellFormedEdges,
      fieldSize: fieldSize,
      findings: findings,
    );
  }

  _sortFindings(findings);
  return findings;
}

/// The seeding sources an organizer may pick for a stage of [stageType]
/// (stage-seeding-spec §1, §6.3 Gating).
///
/// A root stage ([isRoot] true, i.e. no incoming edge) is the tournament's
/// Vorrunde: there is no previous standing to seed from, so it offers only
/// ELO, Zufall and Manuell. A follow stage ([isRoot] false, fed by an incoming
/// edge — typically KO) additionally offers `aus Vorrunde`
/// ([StageSeedingSource.fromPrevRanking]) as the first option.
///
/// [StageSeedingSource.asRouted] is the routing-internal default and is never
/// surfaced as a pickable source. [stageType] is part of the contract for
/// future per-type narrowing; today every type shares the same gating, driven
/// purely by root-vs-follow — the same root detection V5 uses (an incoming
/// edge makes a stage a follow stage).
List<StageSeedingSource> seedingSourcesFor(
  StageNodeType stageType, {
  required bool isRoot,
}) =>
    <StageSeedingSource>[
      if (!isRoot) StageSeedingSource.fromPrevRanking,
      StageSeedingSource.fromElo,
      StageSeedingSource.random,
      StageSeedingSource.manual,
    ];

/// Detects a cycle over [edges] via Kahn's algorithm. Emits one `cycle` finding
/// (with a participating node id) when a cycle remains. Returns whether a cycle
/// was found.
bool _detectCycle(
  StageGraph graph,
  List<StageEdge> edges,
  List<ValidationFinding> findings,
) {
  final inDegree = <String, int>{};
  final adj = <String, List<String>>{};
  for (final node in graph.nodes) {
    inDegree.putIfAbsent(node.id, () => 0);
    adj.putIfAbsent(node.id, () => <String>[]);
  }
  for (final edge in edges) {
    adj.putIfAbsent(edge.fromNodeId, () => <String>[]).add(edge.toNodeId);
    inDegree[edge.toNodeId] = (inDegree[edge.toNodeId] ?? 0) + 1;
  }

  // Count distinct ids, not graph.nodes.length: duplicate node ids collapse to
  // one entry in inDegree/adj, so comparing the Kahn visit count against the raw
  // node-list length would over-count and report a false `cycle`.
  final nodeCount = inDegree.length;

  final queue = <String>[
    for (final entry in inDegree.entries)
      if (entry.value == 0) entry.key,
  ];
  var visited = 0;
  while (queue.isNotEmpty) {
    final id = queue.removeLast();
    visited++;
    for (final next in adj[id] ?? const <String>[]) {
      final remaining = (inDegree[next] ?? 0) - 1;
      inDegree[next] = remaining;
      if (remaining == 0) queue.add(next);
    }
  }

  if (visited == nodeCount) return false;

  // Pick a deterministic node still part of a cycle (in-degree > 0 after Kahn),
  // choosing the lexicographically smallest id for stable output.
  String? cycleNode;
  for (final entry in inDegree.entries) {
    if (entry.value > 0) {
      if (cycleNode == null || entry.key.compareTo(cycleNode) < 0) {
        cycleNode = entry.key;
      }
    }
  }
  findings.add(
    ValidationFinding(
      severity: ValidationSeverity.error,
      code: ValidationCode.cycle,
      message: 'The stage graph contains a cycle; the runner would never '
          'terminate.',
      nodeId: cycleNode,
    ),
  );
  return true;
}

/// Emits an `orphan` ERROR for every node not reachable from any root (node
/// without an incoming edge). An isolated node without any edge is itself a root
/// and therefore reachable.
void _checkReachability(
  StageGraph graph,
  Map<String, List<StageEdge>> outgoing,
  Map<String, int> incomingCount,
  List<ValidationFinding> findings,
) {
  final reachable = <String>{};
  final stack = <String>[
    for (final node in graph.nodes)
      if ((incomingCount[node.id] ?? 0) == 0) node.id,
  ];
  while (stack.isNotEmpty) {
    final id = stack.removeLast();
    if (!reachable.add(id)) continue;
    for (final edge in outgoing[id] ?? const <StageEdge>[]) {
      if (!reachable.contains(edge.toNodeId)) stack.add(edge.toNodeId);
    }
  }

  for (final node in graph.nodes) {
    if (!reachable.contains(node.id)) {
      findings.add(
        ValidationFinding(
          severity: ValidationSeverity.error,
          code: ValidationCode.orphan,
          message: 'Node ${node.id} is not reachable from any root.',
          nodeId: node.id,
        ),
      );
    }
  }
}

/// Inclusive, possibly open rank interval modelling a selector's footprint.
class _Interval {
  const _Interval(this.from, this.to);

  final int from;
  final int to;

  bool overlaps(_Interval other) => from <= other.to && other.from <= to;
}

/// Models a selector as a rank interval, or `null` if it has no statically
/// comparable footprint (`LosersOfRounds`, `NonQualifiers`).
_Interval? _selectorInterval(EdgeSelector selector) {
  switch (selector) {
    case TopK(:final k):
      return _Interval(1, k);
    case Ranks(:final from, :final to):
      return _Interval(from, to);
    case Winners():
      return const _Interval(1, 1);
    case LosersOfRounds():
    case NonQualifiers():
      return null;
  }
}

/// Emits a `selector_overlap` WARNING when two interval-modelled selectors of
/// the same source overlap. Full set-conservation depends on runtime ranks
/// (ADR-0030 §V2); only statically detectable overlap is reported, hence a
/// WARNING rather than an ERROR.
void _checkSelectorOverlap(
  Map<String, List<StageEdge>> outgoing,
  List<ValidationFinding> findings,
) {
  for (final sourceId in outgoing.keys) {
    final edges = outgoing[sourceId]!;
    final intervals = <_Interval>[];
    final intervalEdges = <StageEdge>[];
    for (final edge in edges) {
      final interval = _selectorInterval(edge.selector);
      if (interval != null) {
        intervals.add(interval);
        intervalEdges.add(edge);
      }
    }
    for (var i = 0; i < intervals.length; i++) {
      for (var j = i + 1; j < intervals.length; j++) {
        if (intervals[i].overlaps(intervals[j])) {
          findings.add(
            ValidationFinding(
              severity: ValidationSeverity.warning,
              code: ValidationCode.selectorOverlap,
              message: 'Source $sourceId has overlapping selectors '
                  '${intervalEdges[i].selector} and '
                  '${intervalEdges[j].selector}.',
              nodeId: sourceId,
              edgeFrom: intervalEdges[i].fromNodeId,
              edgeTo: intervalEdges[i].toNodeId,
            ),
          );
        }
      }
    }
  }
}

/// Propagates capacities in topological order and checks each node's input
/// against its type's minimum. Known input below the minimum yields `too_few`
/// (ERROR); unknown input yields `capacity_unknown` (WARNING).
void _checkCapacities({
  required StageGraph graph,
  required Map<String, StageNode> nodesById,
  required Map<String, List<StageEdge>> outgoing,
  required Map<String, int> incomingCount,
  required List<StageEdge> wellFormedEdges,
  required int fieldSize,
  required List<ValidationFinding> findings,
}) {
  final roots = <String>[
    for (final node in graph.nodes)
      if ((incomingCount[node.id] ?? 0) == 0) node.id,
  ];

  // Multiple roots: distributing fieldSize across them is statically unclear.
  // Warn and skip capacity propagation to avoid guessed-input false errors.
  if (roots.length > 1) {
    findings.add(
      const ValidationFinding(
        severity: ValidationSeverity.warning,
        code: ValidationCode.multiRootCapacity,
        message: 'Graph has multiple roots; capacity distribution across roots '
            'is statically unclear, so capacity checks were skipped.',
      ),
    );
    return;
  }

  // Topological order via Kahn (the graph is acyclic here).
  final order = _topoOrder(graph, wellFormedEdges);

  // input/output sizes per node.
  final input = <String, _Capacity>{};
  for (final node in graph.nodes) {
    if ((incomingCount[node.id] ?? 0) == 0) {
      input[node.id] = _Capacity.known(fieldSize);
    }
  }

  for (final nodeId in order) {
    final inCap = input[nodeId] ?? const _Capacity.unknown();
    // Output of a stage equals its input (all participants are ranked).
    final outCap = inCap;

    // Compute the selection size produced for each outgoing edge.
    final edges = outgoing[nodeId] ?? const <StageEdge>[];

    // Sum of non-NQ selection sizes is needed for NonQualifiers.
    var knownNonNqSum = 0;
    var nonNqUnknown = false;
    for (final edge in edges) {
      if (edge.selector is NonQualifiers) continue;
      final sel = _selectionSize(edge.selector, outCap);
      if (sel.isKnown) {
        knownNonNqSum += sel.value;
      } else {
        nonNqUnknown = true;
      }
    }

    for (final edge in edges) {
      final _Capacity sel;
      if (edge.selector is NonQualifiers) {
        if (!outCap.isKnown || nonNqUnknown) {
          sel = const _Capacity.unknown();
        } else {
          final rest = outCap.value - knownNonNqSum;
          sel = _Capacity.known(rest < 0 ? 0 : rest);
        }
      } else {
        sel = _selectionSize(edge.selector, outCap);
      }
      _accumulateInput(input, edge.toNodeId, sel);
    }
  }

  // Min-input check per node.
  for (final node in graph.nodes) {
    // Roots with no incoming edge are entry stages fed by the full field; their
    // input is fieldSize and still subject to the min check.
    final cap = input[node.id] ?? const _Capacity.unknown();
    final minInput = _minInputForNode(node);
    if (cap.isKnown) {
      if (cap.value < minInput) {
        findings.add(
          ValidationFinding(
            severity: ValidationSeverity.error,
            code: ValidationCode.tooFew,
            message: 'Node ${node.id} (${node.type.wire}) receives '
                '${cap.value} participants but requires at least $minInput.',
            nodeId: node.id,
          ),
        );
      }
    } else {
      findings.add(
        ValidationFinding(
          severity: ValidationSeverity.warning,
          code: ValidationCode.capacityUnknown,
          message: 'Node ${node.id} (${node.type.wire}) has a statically '
              'unknown input size (runtime-dependent source).',
          nodeId: node.id,
        ),
      );
    }
  }
}

/// Adds [sel] to the accumulated input of [toNodeId]. Unknown swallows known.
void _accumulateInput(
  Map<String, _Capacity> input,
  String toNodeId,
  _Capacity sel,
) {
  final current = input[toNodeId];
  if (current == null) {
    input[toNodeId] = sel;
    return;
  }
  if (!current.isKnown || !sel.isKnown) {
    input[toNodeId] = const _Capacity.unknown();
    return;
  }
  input[toNodeId] = _Capacity.known(current.value + sel.value);
}

/// Selection size produced by [selector] given the source output [srcOut].
/// `LosersOfRounds` and any unknown source output yield an unknown size.
_Capacity _selectionSize(EdgeSelector selector, _Capacity srcOut) {
  switch (selector) {
    case Winners():
      // A single winner is well-defined even when the source size is unknown.
      return const _Capacity.known(1);
    case TopK(:final k):
      if (!srcOut.isKnown) return const _Capacity.unknown();
      return _Capacity.known(k < srcOut.value ? k : srcOut.value);
    case Ranks(:final from, :final to):
      if (!srcOut.isKnown) return const _Capacity.unknown();
      final upper = to < srcOut.value ? to : srcOut.value;
      final size = upper - from + 1;
      return _Capacity.known(size < 0 ? 0 : size);
    case NonQualifiers():
      // Handled by the caller (depends on sibling selections).
      if (!srcOut.isKnown) return const _Capacity.unknown();
      return srcOut;
    case LosersOfRounds():
      // Structure-/round-dependent: not statically computable.
      return const _Capacity.unknown();
  }
}

/// Minimum input participants required by a node's type (ADR-0030
/// §Spieler-Anzahl-Constraints).
///
/// `groupPhase`/`roundRobin` require `groupCount * 2` when `config['groupCount']`
/// is set (>= 1), else 2. `schoch` uses `rounds + 1` when `config['rounds']` is
/// set, else a conservative 2 (Layer 1a does not rely on a runtime round count).
int _minInputForNode(StageNode node) {
  switch (node.type) {
    case StageNodeType.singleElim:
    case StageNodeType.doubleElim:
    case StageNodeType.consolation:
    case StageNodeType.shootoutQuali:
      return 2;
    case StageNodeType.groupPhase:
    case StageNodeType.roundRobin:
      final g = _positiveInt(node.config['groupCount']);
      return g != null ? g * 2 : 2;
    case StageNodeType.schoch:
      final rounds = _positiveInt(node.config['rounds']);
      return rounds != null ? rounds + 1 : 2;
  }
}

/// Reads [value] as a positive int (>= 1), or `null` if absent/invalid.
int? _positiveInt(Object? value) {
  if (value is int && value >= 1) return value;
  return null;
}

/// Returns the node ids in a topological order (Kahn). Assumes the graph is
/// acyclic; nodes are dequeued in ascending id order for determinism.
List<String> _topoOrder(StageGraph graph, List<StageEdge> edges) {
  final inDegree = <String, int>{};
  final adj = <String, List<String>>{};
  for (final node in graph.nodes) {
    inDegree.putIfAbsent(node.id, () => 0);
    adj.putIfAbsent(node.id, () => <String>[]);
  }
  for (final edge in edges) {
    adj.putIfAbsent(edge.fromNodeId, () => <String>[]).add(edge.toNodeId);
    inDegree[edge.toNodeId] = (inDegree[edge.toNodeId] ?? 0) + 1;
  }

  final ready = <String>[
    for (final entry in inDegree.entries)
      if (entry.value == 0) entry.key,
  ]..sort();
  final order = <String>[];
  while (ready.isNotEmpty) {
    final id = ready.removeAt(0);
    order.add(id);
    final next = <String>[];
    for (final to in adj[id] ?? const <String>[]) {
      final remaining = (inDegree[to] ?? 0) - 1;
      inDegree[to] = remaining;
      if (remaining == 0) next.add(to);
    }
    if (next.isNotEmpty) {
      ready
        ..addAll(next)
        ..sort();
    }
  }
  return order;
}

/// Stable sort (V-ORDER): by code, then nodeId, then edgeFrom, then edgeTo,
/// with null treated as the largest value (sorted last).
void _sortFindings(List<ValidationFinding> findings) {
  findings.sort((a, b) {
    final byCode = a.code.compareTo(b.code);
    if (byCode != 0) return byCode;
    final byNode = _compareNullableLast(a.nodeId, b.nodeId);
    if (byNode != 0) return byNode;
    final byFrom = _compareNullableLast(a.edgeFrom, b.edgeFrom);
    if (byFrom != 0) return byFrom;
    return _compareNullableLast(a.edgeTo, b.edgeTo);
  });
}

/// Compares two nullable strings with `null` ordered last.
int _compareNullableLast(String? a, String? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}
