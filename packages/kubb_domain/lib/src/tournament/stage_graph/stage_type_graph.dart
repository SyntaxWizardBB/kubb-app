import 'package:collection/collection.dart';
import 'package:kubb_domain/src/tournament/tournament_setup.dart';
import 'package:meta/meta.dart';

/// Category of a stage type graph (ADR-0037, ADR-0039 §1). A KO type shrinks its
/// field count towards a single final; a Vorrunde type keeps the field count
/// constant and advances every participant via an [AdvanceAllEdge].
enum TypeStageCategory {
  /// Knockout: fields halve towards the final.
  ko('ko'),

  /// Preliminary (group / Schoch): field count stays constant.
  vorrunde('vorrunde');

  const TypeStageCategory(this.wire);

  /// Stable snake_case wire string (serialization contract).
  final String wire;

  /// Serializes this value to its wire string.
  String toWire() => wire;

  /// Parses [wire] back to a [TypeStageCategory]. Throws [ArgumentError] for an
  /// unknown string (no silent default).
  static TypeStageCategory fromWire(String wire) {
    for (final v in TypeStageCategory.values) {
      if (v.wire == wire) return v;
    }
    throw ArgumentError.value(wire, 'wire', 'unknown TypeStageCategory');
  }
}

/// How the next round of a Vorrunde is re-paired (ADR-0039 §1, OFFEN-1). Only
/// meaningful on a [TypeRound] of a [TypeStageCategory.vorrunde] graph; the KO
/// category leaves it null. The two values mirror the two Vorrunde families:
/// group round-robin and Schoch (Monrad) pairing.
enum TypePairingRule {
  /// Everyone plays everyone in their group (Gruppenphase).
  groupRoundRobin('group_round_robin'),

  /// Schoch / Monrad re-pairing by standing (per schoch-swiss-pairing spec).
  schochMonrad('schoch_monrad');

  const TypePairingRule(this.wire);

  /// Stable snake_case wire string (serialization contract).
  final String wire;

  /// Serializes this value to its wire string.
  String toWire() => wire;

  /// Parses [wire] back to a [TypePairingRule]. Throws [ArgumentError] for an
  /// unknown string.
  static TypePairingRule fromWire(String wire) {
    for (final v in TypePairingRule.values) {
      if (v.wire == wire) return v;
    }
    throw ArgumentError.value(wire, 'wire', 'unknown TypePairingRule');
  }
}

/// The slot a [OpenEdge] leaves dangling: the winner's path or the loser's.
enum OpenEdgeSlot {
  /// The winner of the source field has no target yet.
  winner('winner'),

  /// The loser of the source field has no target yet.
  loser('loser');

  const OpenEdgeSlot(this.wire);

  /// Stable snake_case wire string (serialization contract).
  final String wire;

  /// Serializes this value to its wire string.
  String toWire() => wire;

  /// Parses [wire] back to an [OpenEdgeSlot]. Throws [ArgumentError] for an
  /// unknown string.
  static OpenEdgeSlot fromWire(String wire) {
    for (final v in OpenEdgeSlot.values) {
      if (v.wire == wire) return v;
    }
    throw ArgumentError.value(wire, 'wire', 'unknown OpenEdgeSlot');
  }
}

/// A single match slot within a round of a stage type graph (ADR-0037).
///
/// Pure data: [id] is a human label (e.g. `R1F3`), [roundNumber] is the
/// 1-based round it lives in, [slot] is its 1-based position within that round.
@immutable
class TypeField {
  /// Creates a type field.
  const TypeField({
    required this.id,
    required this.roundNumber,
    required this.slot,
  });

  /// Reconstructs a [TypeField] from its JSON form.
  factory TypeField.fromJson(Map<String, Object?> json) => TypeField(
        id: json['id']! as String,
        roundNumber: (json['round_number']! as num).toInt(),
        slot: (json['slot']! as num).toInt(),
      );

  /// Stable label of the field (e.g. `R1F3`).
  final String id;

  /// 1-based round this field belongs to.
  final int roundNumber;

  /// 1-based position of this field within its round.
  final int slot;

  /// Serializes this field to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'round_number': roundNumber,
        'slot': slot,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TypeField &&
          other.id == id &&
          other.roundNumber == roundNumber &&
          other.slot == slot;

  @override
  int get hashCode => Object.hash(id, roundNumber, slot);

  @override
  String toString() => 'TypeField($id, r$roundNumber, slot$slot)';
}

/// An edge between fields of a stage type graph (ADR-0039 §1).
///
/// Every variant serializes to a JSON map with a `kind` discriminator, mirroring
/// `EdgeSelector`. KO graphs use granular [WinnerEdge]/[LoserEdge]; a deliberately
/// undecided path is an [OpenEdge] (a valid state, surfaced as a warning, never an
/// error). A Vorrunde round transition is a single [AdvanceAllEdge] ("alle
/// weiter").
@immutable
sealed class FieldEdge {
  const FieldEdge();

  /// Reconstructs a [FieldEdge] from its JSON form, dispatching on `kind`.
  /// Throws [ArgumentError] when `kind` is missing or unknown.
  static FieldEdge fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    switch (kind) {
      case WinnerEdge._kind:
        return WinnerEdge(
          fromFieldId: json['from_field_id']! as String,
          toFieldId: json['to_field_id']! as String,
        );
      case LoserEdge._kind:
        return LoserEdge(
          fromFieldId: json['from_field_id']! as String,
          toFieldId: json['to_field_id']! as String,
        );
      case OpenEdge._kind:
        return OpenEdge(
          fromFieldId: json['from_field_id']! as String,
          slot: OpenEdgeSlot.fromWire(json['slot']! as String),
        );
      case AdvanceAllEdge._kind:
        return AdvanceAllEdge(
          fromRound: (json['from_round']! as num).toInt(),
          toRound: (json['to_round']! as num).toInt(),
        );
      default:
        throw ArgumentError.value(kind, 'kind', 'unknown FieldEdge kind');
    }
  }

  /// Serializes this edge to a JSON-compatible map with a `kind` field.
  Map<String, Object?> toJson();
}

/// Routes the winner of [fromFieldId] into [toFieldId] (KO).
@immutable
class WinnerEdge extends FieldEdge {
  /// Creates a winner edge.
  const WinnerEdge({required this.fromFieldId, required this.toFieldId});

  static const String _kind = 'winner';

  /// Source field whose winner is routed.
  final String fromFieldId;

  /// Target field the winner enters.
  final String toFieldId;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': _kind,
        'from_field_id': fromFieldId,
        'to_field_id': toFieldId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WinnerEdge &&
          other.fromFieldId == fromFieldId &&
          other.toFieldId == toFieldId;

  @override
  int get hashCode => Object.hash(_kind, fromFieldId, toFieldId);

  @override
  String toString() => 'WinnerEdge($fromFieldId -> $toFieldId)';
}

/// Routes the loser of [fromFieldId] into [toFieldId] (KO side-cup feeder).
@immutable
class LoserEdge extends FieldEdge {
  /// Creates a loser edge.
  const LoserEdge({required this.fromFieldId, required this.toFieldId});

  static const String _kind = 'loser';

  /// Source field whose loser is routed.
  final String fromFieldId;

  /// Target field the loser enters.
  final String toFieldId;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': _kind,
        'from_field_id': fromFieldId,
        'to_field_id': toFieldId,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoserEdge &&
          other.fromFieldId == fromFieldId &&
          other.toFieldId == toFieldId;

  @override
  int get hashCode => Object.hash(_kind, fromFieldId, toFieldId);

  @override
  String toString() => 'LoserEdge($fromFieldId -> $toFieldId)';
}

/// Marks the [slot] (winner or loser) of [fromFieldId] as deliberately
/// undecided. A valid state per the spec — surfaced as a warning, never an error.
@immutable
class OpenEdge extends FieldEdge {
  /// Creates an open edge.
  const OpenEdge({required this.fromFieldId, required this.slot});

  static const String _kind = 'open';

  /// Source field whose [slot] has no target yet.
  final String fromFieldId;

  /// Which side of the source field is left open.
  final OpenEdgeSlot slot;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': _kind,
        'from_field_id': fromFieldId,
        'slot': slot.toWire(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpenEdge &&
          other.fromFieldId == fromFieldId &&
          other.slot == slot;

  @override
  int get hashCode => Object.hash(_kind, fromFieldId, slot);

  @override
  String toString() => 'OpenEdge($fromFieldId, ${slot.wire})';
}

/// A Vorrunde round transition: everyone in [fromRound] advances to [toRound]
/// ("alle weiter", ADR-0039 §1). The concrete re-pairing of the next round
/// follows the round's [TypeRound.pairingRule].
@immutable
class AdvanceAllEdge extends FieldEdge {
  /// Creates an advance-all edge.
  const AdvanceAllEdge({required this.fromRound, required this.toRound});

  static const String _kind = 'advance_all';

  /// 1-based source round.
  final int fromRound;

  /// 1-based target round.
  final int toRound;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': _kind,
        'from_round': fromRound,
        'to_round': toRound,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdvanceAllEdge &&
          other.fromRound == fromRound &&
          other.toRound == toRound;

  @override
  int get hashCode => Object.hash(_kind, fromRound, toRound);

  @override
  String toString() => 'AdvanceAllEdge(r$fromRound -> r$toRound)';
}

const ListEquality<TypeField> _fieldListEquality = ListEquality<TypeField>();

/// One round of a stage type graph (ADR-0037, ADR-0039 §1).
///
/// Holds the round's [fields], its [matchFormat], and the KO-only [koMatchup] /
/// [koTiebreak] config (mirrored 1:1 from `tournament_setup`). [pairingRule] is
/// Vorrunde-only and null for KO rounds.
@immutable
class TypeRound {
  /// Creates a type round.
  ///
  /// [fields] is copied into an unmodifiable list, so later mutation of the
  /// passed-in list cannot change this object.
  TypeRound({
    required this.roundNumber,
    required List<TypeField> fields,
    required this.matchFormat,
    this.koMatchup,
    this.koTiebreak,
    this.pairingRule,
  }) : fields = List<TypeField>.unmodifiable(fields);

  /// Reconstructs a [TypeRound] from its JSON form. Tolerates a missing
  /// `ko_matchup`/`ko_tiebreak_method`/`pairing_rule` (null), so partial
  /// configs hydrate cleanly.
  factory TypeRound.fromJson(Map<String, Object?> json) => TypeRound(
        roundNumber: (json['round_number']! as num).toInt(),
        fields: <TypeField>[
          for (final f in json['fields']! as List<Object?>)
            TypeField.fromJson(f! as Map<String, Object?>),
        ],
        matchFormat: MatchFormatSpec.fromJson(
          json['match_format']! as Map<String, Object?>,
        ),
        koMatchup: json['ko_matchup'] == null
            ? null
            : KoMatchup.fromWire(json['ko_matchup']! as String),
        koTiebreak: json['ko_tiebreak_method'] == null
            ? null
            : KoTiebreakMethod.fromWire(json['ko_tiebreak_method']! as String),
        pairingRule: json['pairing_rule'] == null
            ? null
            : TypePairingRule.fromWire(json['pairing_rule']! as String),
      );

  /// 1-based round number.
  final int roundNumber;

  /// The match slots of this round. Unmodifiable.
  final List<TypeField> fields;

  /// Match rules for this round (mirrors the setup's [MatchFormatSpec]).
  final MatchFormatSpec matchFormat;

  /// KO-only: how qualified participants are paired. Null for Vorrunde rounds.
  final KoMatchup? koMatchup;

  /// KO-only: how a tied KO match is decided. Null for Vorrunde rounds.
  final KoTiebreakMethod? koTiebreak;

  /// Vorrunde-only: how the next round is re-paired. Null for KO rounds.
  final TypePairingRule? pairingRule;

  /// Serializes this round to a JSON-compatible map. Only set optional fields
  /// are written, so partial configs stay clean.
  Map<String, Object?> toJson() => <String, Object?>{
        'round_number': roundNumber,
        'fields': <Object?>[for (final f in fields) f.toJson()],
        'match_format': matchFormat.toJson(),
        if (koMatchup != null) 'ko_matchup': koMatchup!.wire,
        if (koTiebreak != null) 'ko_tiebreak_method': koTiebreak!.wire,
        if (pairingRule != null) 'pairing_rule': pairingRule!.wire,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TypeRound &&
          other.roundNumber == roundNumber &&
          _fieldListEquality.equals(other.fields, fields) &&
          other.matchFormat == matchFormat &&
          other.koMatchup == koMatchup &&
          other.koTiebreak == koTiebreak &&
          other.pairingRule == pairingRule;

  @override
  int get hashCode => Object.hash(
        roundNumber,
        _fieldListEquality.hash(fields),
        matchFormat,
        koMatchup,
        koTiebreak,
        pairingRule,
      );

  @override
  String toString() =>
      'TypeRound(r$roundNumber, ${fields.length} fields, $matchFormat)';
}

const ListEquality<TypeRound> _roundListEquality = ListEquality<TypeRound>();
const ListEquality<FieldEdge> _edgeListEquality = ListEquality<FieldEdge>();

/// A stage type graph (Ebene 2): the inner structure of a single stage modelled
/// as rounds, fields and field edges (ADR-0037, ADR-0039 §1).
///
/// Pure data plus structural lookups. No semantic validation here (see
/// `validateStageTypeGraph` in `stage_type_validation.dart`). Serialized as the
/// jsonb sub-graph stored under `StageNode.config['type_graph']`.
@immutable
class StageTypeGraph {
  /// Creates a stage type graph.
  ///
  /// Both lists are copied into unmodifiable lists, so later mutation of the
  /// passed-in lists cannot change this object.
  StageTypeGraph({
    required this.category,
    required List<TypeRound> rounds,
    required List<FieldEdge> edges,
  })  : rounds = List<TypeRound>.unmodifiable(rounds),
        edges = List<FieldEdge>.unmodifiable(edges);

  /// Reconstructs a [StageTypeGraph] from its JSON form.
  factory StageTypeGraph.fromJson(Map<String, Object?> json) => StageTypeGraph(
        category: TypeStageCategory.fromWire(json['category']! as String),
        rounds: <TypeRound>[
          for (final r in json['rounds']! as List<Object?>)
            TypeRound.fromJson(r! as Map<String, Object?>),
        ],
        edges: <FieldEdge>[
          for (final e in json['edges']! as List<Object?>)
            FieldEdge.fromJson(e! as Map<String, Object?>),
        ],
      );

  /// KO or Vorrunde.
  final TypeStageCategory category;

  /// The rounds of the type graph, in ascending round order. Unmodifiable.
  final List<TypeRound> rounds;

  /// The field edges wiring the rounds. Unmodifiable.
  final List<FieldEdge> edges;

  /// All fields across all rounds, in declaration order.
  List<TypeField> get allFields =>
      <TypeField>[for (final r in rounds) ...r.fields];

  /// Serializes this graph to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
        'category': category.toWire(),
        'rounds': <Object?>[for (final r in rounds) r.toJson()],
        'edges': <Object?>[for (final e in edges) e.toJson()],
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageTypeGraph &&
          other.category == category &&
          _roundListEquality.equals(other.rounds, rounds) &&
          _edgeListEquality.equals(other.edges, edges);

  @override
  int get hashCode => Object.hash(
        category,
        _roundListEquality.hash(rounds),
        _edgeListEquality.hash(edges),
      );

  @override
  String toString() => 'StageTypeGraph(${category.wire}, '
      '${rounds.length} rounds, ${edges.length} edges)';
}

/// Generates round 1 of a stage type graph for [participantCount] (ADR-0039 §1,
/// spec §3). KO halves the field count (`F1..F(ceil(n/2))`); Vorrunde keeps a
/// constant field count (`n/2` plates). An odd participant count yields one bye
/// field whose match holds only participant A — a Schoch bye counts as a full
/// win (16 points, schoch-swiss-pairing spec §3.4, OFFEN-2).
List<TypeField> generateRound1(
  TypeStageCategory category,
  int participantCount,
) {
  if (participantCount < 1) {
    throw ArgumentError.value(
      participantCount,
      'participantCount',
      'must be at least 1',
    );
  }
  // Both categories pair two participants per field; an odd count leaves one
  // participant on a bye field. KO and Vorrunde share the same round-1 field
  // count: ceil(n / 2). KO then shrinks in later rounds, Vorrunde stays here.
  final fieldCount = (participantCount + 1) ~/ 2;
  return <TypeField>[
    for (var slot = 1; slot <= fieldCount; slot++)
      TypeField(id: 'R1F$slot', roundNumber: 1, slot: slot),
  ];
}
