import 'package:kubb_domain/src/tournament/stage_graph/stage_type_graph.dart';
import 'package:kubb_domain/src/tournament/stage_graph/stage_validation.dart';

/// Stable validation finding codes for a stage type graph (Ebene 2, spec §7).
abstract final class TypeValidationCode {
  /// KO round field count does not strictly decrease towards the final.
  static const String koNotShrinking = 'ko_not_shrinking';

  /// KO round incoming capacity does not equal `fields * 2`.
  static const String koCapacityMismatch = 'ko_capacity_mismatch';

  /// KO last round is not a single field (final).
  static const String koFinalNotSingle = 'ko_final_not_single';

  /// Vorrunde round field count is not constant.
  static const String vorrundeNotConstant = 'vorrunde_not_constant';

  /// A non-last Vorrunde round is missing its mandatory `AdvanceAllEdge`.
  static const String advanceAllMissing = 'advance_all_missing';

  /// A Vorrunde carries a granular winner/loser field edge (not allowed).
  static const String vorrundeFieldEdgeForbidden = 'vorrunde_field_edge_forbidden';

  /// A field's winner or loser path is deliberately left open (warning).
  static const String openPath = 'open_path';

  /// The type graph rounds/edges form a cycle.
  static const String typeCycle = 'type_cycle';

  /// A field edge references a round/field that does not exist.
  static const String unknownTypeField = 'unknown_type_field';

  /// The type graph has no rounds at all.
  static const String emptyTypeGraph = 'empty_type_graph';
}

/// Validates a stage type graph (Ebene 2, spec §7). Returns ALL findings; an
/// empty error-subset means the type is savable/publishable. Never throws: a
/// degenerate graph is reported as findings, not as an exception.
///
/// KO rules: field count strictly decreases over rounds, the last round is a
/// single field, and each round's incoming capacity equals `fields * 2`.
/// Vorrunde rules: field count stays constant, each non-last round carries
/// exactly one `AdvanceAllEdge(r -> r+1)`, and granular winner/loser field edges
/// are forbidden. Shared with Ebene 1: acyclic (Kahn), an `OpenEdge` is a
/// warning (not an error), and `hasTypeErrors` blocks saving.
///
/// The returned list is stably sorted by code, then by the offending field/round
/// reference, so two calls on equal input yield a byte-identical order.
List<ValidationFinding> validateStageTypeGraph(StageTypeGraph graph) {
  final findings = <ValidationFinding>[];

  if (graph.rounds.isEmpty) {
    findings.add(
      const ValidationFinding(
        severity: ValidationSeverity.error,
        code: TypeValidationCode.emptyTypeGraph,
        message: 'The stage type graph has no rounds.',
      ),
    );
    return findings;
  }

  final rounds = <TypeRound>[...graph.rounds]
    ..sort((a, b) => a.roundNumber.compareTo(b.roundNumber));
  final fieldsById = <String, TypeField>{
    for (final f in graph.allFields) f.id: f,
  };

  _checkUnknownFieldRefs(graph, fieldsById, rounds, findings);
  _checkOpenPaths(graph, findings);

  switch (graph.category) {
    case TypeStageCategory.ko:
      _checkKo(rounds, graph, findings);
    case TypeStageCategory.vorrunde:
      _checkVorrunde(rounds, graph, findings);
  }

  _checkTypeCycle(graph, fieldsById, findings);

  _sortTypeFindings(findings);
  return findings;
}

/// Whether [findings] contains at least one [ValidationSeverity.error]. Mirrors
/// the Ebene-1 `hasErrors` gate: an error blocks save/publish, a warning does not.
bool hasTypeErrors(List<ValidationFinding> findings) =>
    findings.any((f) => f.severity == ValidationSeverity.error);

void _checkKo(
  List<TypeRound> rounds,
  StageTypeGraph graph,
  List<ValidationFinding> findings,
) {
  for (var i = 1; i < rounds.length; i++) {
    final prev = rounds[i - 1].fields.length;
    final cur = rounds[i].fields.length;
    if (cur >= prev) {
      findings.add(
        ValidationFinding(
          severity: ValidationSeverity.error,
          code: TypeValidationCode.koNotShrinking,
          message: 'KO round ${rounds[i].roundNumber} has $cur fields but the '
              'previous round had $prev; KO field count must strictly decrease.',
        ),
      );
    }
  }

  final last = rounds.last;
  if (last.fields.length != 1) {
    findings.add(
      ValidationFinding(
        severity: ValidationSeverity.error,
        code: TypeValidationCode.koFinalNotSingle,
        message: 'KO final round ${last.roundNumber} has ${last.fields.length} '
            'fields but must be a single field.',
      ),
    );
  }

  // Incoming capacity per KO round = fields * 2. Round 1 is fed by the entry
  // participants (out of scope here); rounds 2+ are fed by the prior round's
  // winner edges. Each field has two slots, so winner edges into a round must
  // fill exactly fields * 2 slots, i.e. equal twice the prior round's fields.
  for (var i = 1; i < rounds.length; i++) {
    final expected = rounds[i].fields.length * 2;
    final fedBy = rounds[i - 1].fields.length;
    if (fedBy != expected) {
      findings.add(
        ValidationFinding(
          severity: ValidationSeverity.error,
          code: TypeValidationCode.koCapacityMismatch,
          message: 'KO round ${rounds[i].roundNumber} expects $expected '
              'incoming participants (${rounds[i].fields.length} fields x 2) '
              'but the previous round produces $fedBy winners.',
        ),
      );
    }
  }

  // Granular winner edges are the KO routing language; an AdvanceAllEdge has no
  // meaning in a KO type graph.
  for (final edge in graph.edges) {
    if (edge is AdvanceAllEdge) {
      findings.add(
        ValidationFinding(
          severity: ValidationSeverity.error,
          code: TypeValidationCode.koNotShrinking,
          message: 'KO type graph carries an AdvanceAllEdge '
              '(r${edge.fromRound} -> r${edge.toRound}); KO routes winners and '
              'losers per field.',
        ),
      );
    }
  }
}

void _checkVorrunde(
  List<TypeRound> rounds,
  StageTypeGraph graph,
  List<ValidationFinding> findings,
) {
  final first = rounds.first.fields.length;
  for (final round in rounds) {
    if (round.fields.length != first) {
      findings.add(
        ValidationFinding(
          severity: ValidationSeverity.error,
          code: TypeValidationCode.vorrundeNotConstant,
          message: 'Vorrunde round ${round.roundNumber} has '
              '${round.fields.length} fields but round '
              '${rounds.first.roundNumber} has $first; Vorrunde field count '
              'must stay constant.',
        ),
      );
    }
  }

  // Granular winner/loser field edges are forbidden: nobody is eliminated in a
  // Vorrunde, so the only legal transition is AdvanceAllEdge.
  for (final edge in graph.edges) {
    if (edge is WinnerEdge || edge is LoserEdge) {
      final fromField = edge is WinnerEdge
          ? edge.fromFieldId
          : (edge as LoserEdge).fromFieldId;
      findings.add(
        ValidationFinding(
          severity: ValidationSeverity.error,
          code: TypeValidationCode.vorrundeFieldEdgeForbidden,
          message: 'Vorrunde carries a granular winner/loser edge from '
              '$fromField; Vorrunde rounds advance everyone via an '
              'AdvanceAllEdge.',
          edgeFrom: fromField,
        ),
      );
    }
  }

  // Each non-last round needs exactly one AdvanceAllEdge(r -> r+1).
  for (var i = 0; i < rounds.length - 1; i++) {
    final from = rounds[i].roundNumber;
    final to = rounds[i + 1].roundNumber;
    final matching = graph.edges.whereType<AdvanceAllEdge>().where(
          (e) => e.fromRound == from && e.toRound == to,
        );
    if (matching.length != 1) {
      findings.add(
        ValidationFinding(
          severity: ValidationSeverity.error,
          code: TypeValidationCode.advanceAllMissing,
          message: matching.isEmpty
              ? 'Vorrunde round $from is missing its AdvanceAllEdge to round '
                  '$to.'
              : 'Vorrunde round $from has ${matching.length} AdvanceAllEdges to '
                  'round $to; exactly one is required.',
        ),
      );
    }
  }
}

void _checkOpenPaths(StageTypeGraph graph, List<ValidationFinding> findings) {
  for (final edge in graph.edges) {
    if (edge is OpenEdge) {
      findings.add(
        ValidationFinding(
          severity: ValidationSeverity.warning,
          code: TypeValidationCode.openPath,
          message: 'Field ${edge.fromFieldId} leaves its ${edge.slot.wire} path '
              'deliberately open.',
          edgeFrom: edge.fromFieldId,
        ),
      );
    }
  }
}

void _checkUnknownFieldRefs(
  StageTypeGraph graph,
  Map<String, TypeField> fieldsById,
  List<TypeRound> rounds,
  List<ValidationFinding> findings,
) {
  final roundNumbers = <int>{for (final r in rounds) r.roundNumber};
  for (final edge in graph.edges) {
    switch (edge) {
      case WinnerEdge(:final fromFieldId, :final toFieldId):
        _requireField(fromFieldId, fieldsById, findings);
        _requireField(toFieldId, fieldsById, findings);
      case LoserEdge(:final fromFieldId, :final toFieldId):
        _requireField(fromFieldId, fieldsById, findings);
        _requireField(toFieldId, fieldsById, findings);
      case OpenEdge(:final fromFieldId):
        _requireField(fromFieldId, fieldsById, findings);
      case AdvanceAllEdge(:final fromRound, :final toRound):
        if (!roundNumbers.contains(fromRound) ||
            !roundNumbers.contains(toRound)) {
          findings.add(
            ValidationFinding(
              severity: ValidationSeverity.error,
              code: TypeValidationCode.unknownTypeField,
              message: 'AdvanceAllEdge r$fromRound -> r$toRound references a '
                  'round that does not exist.',
            ),
          );
        }
    }
  }
}

void _requireField(
  String fieldId,
  Map<String, TypeField> fieldsById,
  List<ValidationFinding> findings,
) {
  if (!fieldsById.containsKey(fieldId)) {
    findings.add(
      ValidationFinding(
        severity: ValidationSeverity.error,
        code: TypeValidationCode.unknownTypeField,
        message: 'Field edge references a non-existent field $fieldId.',
        edgeFrom: fieldId,
      ),
    );
  }
}

/// Detects a cycle over the round transitions implied by the field edges using
/// Kahn's algorithm — the same mechanism Ebene 1 uses. Edges only ever point
/// forward (round r to a later round) in a well-formed type graph; a backward or
/// self edge is a cycle and would make the runner loop forever.
void _checkTypeCycle(
  StageTypeGraph graph,
  Map<String, TypeField> fieldsById,
  List<ValidationFinding> findings,
) {
  final roundOf = <String, int>{
    for (final f in fieldsById.values) f.id: f.roundNumber,
  };
  final nodes = <int>{for (final r in graph.rounds) r.roundNumber};
  final adj = <int, List<int>>{for (final n in nodes) n: <int>[]};
  final inDegree = <int, int>{for (final n in nodes) n: 0};

  void addRoundEdge(int from, int to) {
    if (!nodes.contains(from) || !nodes.contains(to)) return;
    adj[from]!.add(to);
    inDegree[to] = (inDegree[to] ?? 0) + 1;
  }

  for (final edge in graph.edges) {
    switch (edge) {
      case WinnerEdge(:final fromFieldId, :final toFieldId):
      case LoserEdge(:final fromFieldId, :final toFieldId):
        final from = roundOf[fromFieldId];
        final to = roundOf[toFieldId];
        if (from != null && to != null) addRoundEdge(from, to);
      case AdvanceAllEdge(:final fromRound, :final toRound):
        addRoundEdge(fromRound, toRound);
      case OpenEdge():
        break;
    }
  }

  final queue = <int>[
    for (final entry in inDegree.entries)
      if (entry.value == 0) entry.key,
  ];
  var visited = 0;
  while (queue.isNotEmpty) {
    final node = queue.removeLast();
    visited++;
    for (final next in adj[node] ?? const <int>[]) {
      final remaining = (inDegree[next] ?? 0) - 1;
      inDegree[next] = remaining;
      if (remaining == 0) queue.add(next);
    }
  }

  if (visited != nodes.length) {
    findings.add(
      const ValidationFinding(
        severity: ValidationSeverity.error,
        code: TypeValidationCode.typeCycle,
        message: 'The stage type graph contains a cycle over its rounds.',
      ),
    );
  }
}

/// Stable sort: by code, then edgeFrom (nulls last), so equal input yields a
/// byte-identical order regardless of internal iteration order.
void _sortTypeFindings(List<ValidationFinding> findings) {
  findings.sort((a, b) {
    final byCode = a.code.compareTo(b.code);
    if (byCode != 0) return byCode;
    final af = a.edgeFrom;
    final bf = b.edgeFrom;
    if (af == null && bf == null) return 0;
    if (af == null) return 1;
    if (bf == null) return -1;
    return af.compareTo(bf);
  });
}
