/// Ebene-2 summary over a [StageTypeGraph]: turns the inner structure of one
/// stage (rounds, fields, routing) into a flat, complete description the setup
/// summary and the live progress view both read from (ADR-0037, ADR-0039 §1).
///
/// Pure data, Flutter-free. The Ebene-1 summary (stages + edges) stays where it
/// is; this only adds the per-stage drill-down for stages that carry a
/// `config['type_graph']`. A classic KO/RR stage has no type graph, so
/// [summarizeStageTypeGraph] is simply never called for it — the old summary is
/// untouched.
///
/// Completeness is a hard contract: every round of the graph and every field of
/// every round appears in the result, in declaration order. Edges are attached
/// to their source field (KO winner/loser/open) or to the round transition
/// (Vorrunde advance-all), so the routing is visible without a second lookup.
library;

import 'package:collection/collection.dart';
import 'package:kubb_domain/src/tournament/stage_graph/stage_type_graph.dart';
import 'package:kubb_domain/src/tournament/tournament_setup.dart';
import 'package:meta/meta.dart';

/// Lifecycle of the target match a [TypeField] feeds, as seen from the
/// materialized matches (`stage_node_id` + `round_number` + `bracket_position`,
/// U10b/U10c). A field with no match row yet is [awaiting]; once both seats are
/// known the match is [filled]; a played-out match is [done].
enum FieldMatchProgress {
  /// No match materialized for this field yet (both seats still open).
  awaiting('awaiting'),

  /// The field's match exists and both participants are known.
  filled('filled'),

  /// The field's match has been played and finalized.
  done('done');

  const FieldMatchProgress(this.wire);

  /// Stable snake_case wire string.
  final String wire;
}

/// Progress of one field's target match, keyed implicitly by its round/slot.
@immutable
class FieldProgressSummary {
  /// Creates a field progress summary.
  const FieldProgressSummary({
    required this.field,
    required this.progress,
    this.outgoing = const <FieldEdge>[],
  });

  /// The field this row describes (id / round / slot).
  final TypeField field;

  /// Lifecycle state of the field's materialized match.
  final FieldMatchProgress progress;

  /// Edges whose source is this field (winner / loser / open). Empty for a
  /// Vorrunde field — there the transition is the round-level advance-all.
  final List<FieldEdge> outgoing;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FieldProgressSummary &&
          other.field == field &&
          other.progress == progress &&
          const ListEquality<FieldEdge>().equals(other.outgoing, outgoing);

  @override
  int get hashCode => Object.hash(
        field,
        progress,
        const ListEquality<FieldEdge>().hash(outgoing),
      );
}

/// One round of the Ebene-2 summary: its fields with progress + routing, the
/// round's match-format eckdaten, KO tiebreak / matchup or Vorrunde pairing,
/// plus the round transition (advance-all) when there is one.
@immutable
class RoundSummary {
  /// Creates a round summary.
  RoundSummary({
    required this.roundNumber,
    required List<FieldProgressSummary> fields,
    required this.matchFormat,
    this.koMatchup,
    this.koTiebreak,
    this.pairingRule,
    this.advance,
  }) : fields = List<FieldProgressSummary>.unmodifiable(fields);

  /// 1-based round number.
  final int roundNumber;

  /// Every field of this round, in slot order. Unmodifiable.
  final List<FieldProgressSummary> fields;

  /// Match rules of this round.
  final MatchFormatSpec matchFormat;

  /// KO-only matchup rule, null on Vorrunde rounds.
  final KoMatchup? koMatchup;

  /// KO-only tiebreak method, null on Vorrunde rounds.
  final KoTiebreakMethod? koTiebreak;

  /// Vorrunde-only re-pairing rule, null on KO rounds.
  final TypePairingRule? pairingRule;

  /// The advance-all edge leaving this round (Vorrunde), null otherwise.
  final AdvanceAllEdge? advance;

  /// How many fields are awaiting / filled / done in this round.
  int get fieldCount => fields.length;

  /// Count of fields in [state].
  int countOf(FieldMatchProgress state) =>
      fields.where((f) => f.progress == state).length;
}

/// The full Ebene-2 summary of one stage's type graph.
@immutable
class StageTypeGraphSummary {
  /// Creates a stage type graph summary.
  StageTypeGraphSummary({
    required this.category,
    required List<RoundSummary> rounds,
  }) : rounds = List<RoundSummary>.unmodifiable(rounds);

  /// KO or Vorrunde.
  final TypeStageCategory category;

  /// Every round of the graph, in ascending order. Unmodifiable.
  final List<RoundSummary> rounds;

  /// Total field count across all rounds.
  int get totalFields =>
      rounds.fold(0, (sum, r) => sum + r.fields.length);

  /// Total field count across all rounds in [state].
  int totalOf(FieldMatchProgress state) =>
      rounds.fold(0, (sum, r) => sum + r.countOf(state));
}

/// Builds the Ebene-2 summary for [graph]. Every round and every field of the
/// graph is represented — nothing is dropped. [progressByField] supplies the
/// lifecycle of each field's materialized match, keyed by
/// `(roundNumber, slot)`; a field absent from the map defaults to
/// [FieldMatchProgress.awaiting] (no match row yet), so a not-yet-started stage
/// summarizes cleanly.
///
/// Edges are routed to their owner: a [WinnerEdge] / [LoserEdge] / [OpenEdge]
/// attaches to its source field; an [AdvanceAllEdge] attaches to its source
/// round. The order of [FieldProgressSummary.outgoing] follows the graph's edge
/// declaration order.
StageTypeGraphSummary summarizeStageTypeGraph(
  StageTypeGraph graph, {
  Map<(int, int), FieldMatchProgress> progressByField =
      const <(int, int), FieldMatchProgress>{},
}) {
  final outgoingByField = <String, List<FieldEdge>>{};
  final advanceByRound = <int, AdvanceAllEdge>{};
  for (final edge in graph.edges) {
    switch (edge) {
      case WinnerEdge(:final fromFieldId):
        (outgoingByField[fromFieldId] ??= <FieldEdge>[]).add(edge);
      case LoserEdge(:final fromFieldId):
        (outgoingByField[fromFieldId] ??= <FieldEdge>[]).add(edge);
      case OpenEdge(:final fromFieldId):
        (outgoingByField[fromFieldId] ??= <FieldEdge>[]).add(edge);
      case AdvanceAllEdge(:final fromRound):
        advanceByRound[fromRound] = edge;
    }
  }

  final rounds = <RoundSummary>[
    for (final round in graph.rounds)
      RoundSummary(
        roundNumber: round.roundNumber,
        matchFormat: round.matchFormat,
        koMatchup: round.koMatchup,
        koTiebreak: round.koTiebreak,
        pairingRule: round.pairingRule,
        advance: advanceByRound[round.roundNumber],
        fields: <FieldProgressSummary>[
          for (final field in round.fields)
            FieldProgressSummary(
              field: field,
              progress: progressByField[(field.roundNumber, field.slot)] ??
                  FieldMatchProgress.awaiting,
              outgoing: outgoingByField[field.id] ?? const <FieldEdge>[],
            ),
        ],
      ),
  ];

  return StageTypeGraphSummary(category: graph.category, rounds: rounds);
}
