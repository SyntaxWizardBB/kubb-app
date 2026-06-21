import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Algorithm type of a tournament stage (graph node).
///
/// ADR-0030 §Modell. Each value carries a stable snake_case wire string that is
/// part of the serialization contract and is NOT derived from the enum name, so
/// a future Dart rename never breaks the JSON representation.
enum StageNodeType {
  /// Group phase (Gruppenphase).
  groupPhase('group_phase'),

  /// Round-robin (everyone plays everyone).
  roundRobin('round_robin'),

  /// Schoch system (former Swiss/Schweizer System).
  schoch('schoch'),

  /// Single-elimination bracket.
  singleElim('single_elim'),

  /// Double-elimination bracket.
  doubleElim('double_elim'),

  /// Consolation / loser bracket.
  consolation('consolation'),

  /// Shoot-out qualification stage.
  shootoutQuali('shootout_quali');

  const StageNodeType(this.wire);

  /// Stable snake_case wire string (serialization contract).
  final String wire;

  /// Serializes this value to its current wire string.
  String toWire() => wire;

  /// Parses [wire] back to a [StageNodeType].
  ///
  /// Accepts the legacy wire strings `'pool'` and `'swiss'` alongside the
  /// current `'group_phase'` and `'schoch'`, so old rows and an out-of-order
  /// migration/deploy keep parsing. Throws [ArgumentError] for an unknown
  /// string (no silent default, no null).
  static StageNodeType fromWire(String wire) {
    switch (wire) {
      case 'pool':
        return StageNodeType.groupPhase;
      case 'swiss':
        return StageNodeType.schoch;
    }
    for (final v in StageNodeType.values) {
      if (v.wire == wire) return v;
    }
    throw ArgumentError.value(wire, 'wire', 'unknown StageNodeType');
  }
}

/// How a stage seeds the participants that enter it.
///
/// ADR-0030 §Modell.
enum StageSeedingSource {
  /// Seed from ELO rating.
  fromElo('from_elo'),

  /// Seed from the ranking of the previous (incoming) stage.
  fromPrevRanking('from_prev_ranking'),

  /// Manually provided seed list.
  manual('manual'),

  /// Use the order in which routing delivered the participants.
  asRouted('as_routed');

  const StageSeedingSource(this.wire);

  /// Stable snake_case wire string (serialization contract).
  final String wire;

  /// Serializes this value to its stable wire string.
  String toWire() => wire;

  /// Parses [wire] back to a [StageSeedingSource].
  ///
  /// Throws [ArgumentError] for an unknown string.
  static StageSeedingSource fromWire(String wire) {
    for (final v in StageSeedingSource.values) {
      if (v.wire == wire) return v;
    }
    throw ArgumentError.value(wire, 'wire', 'unknown StageSeedingSource');
  }
}

const DeepCollectionEquality _configEquality = DeepCollectionEquality();

/// Recursively wraps nested [Map]s and [List]s into unmodifiable views so the
/// whole [StageNode.config] tree is immutable, not just its top level.
Map<String, Object?> _deepUnmodifiableMap(Map<String, Object?> source) =>
    Map<String, Object?>.unmodifiable(<String, Object?>{
      for (final entry in source.entries)
        entry.key: _deepUnmodifiableValue(entry.value),
    });

/// Recursively returns an unmodifiable view of a nested config value.
Object? _deepUnmodifiableValue(Object? value) {
  if (value is Map) {
    return Map<Object?, Object?>.unmodifiable(<Object?, Object?>{
      for (final entry in value.entries)
        entry.key: _deepUnmodifiableValue(entry.value),
    });
  }
  if (value is List) {
    return List<Object?>.unmodifiable(
      <Object?>[for (final element in value) _deepUnmodifiableValue(element)],
    );
  }
  return value;
}

/// Recursively produces a fresh, fully-mutable copy of a config tree, so the
/// JSON output never aliases the node's internal unmodifiable structures.
Map<String, Object?> _deepMutableMap(Map<String, Object?> source) =>
    <String, Object?>{
      for (final entry in source.entries)
        entry.key: _deepMutableValue(entry.value),
    };

/// Recursively returns a fresh, mutable copy of a nested config value.
Object? _deepMutableValue(Object? value) {
  if (value is Map) {
    return <Object?, Object?>{
      for (final entry in value.entries)
        entry.key: _deepMutableValue(entry.value),
    };
  }
  if (value is List) {
    return <Object?>[for (final element in value) _deepMutableValue(element)];
  }
  return value;
}

/// A tournament stage: a typed node in the stage graph (ADR-0030 §Modell).
///
/// Pure data: this carries the stage [type], a free-form [config] map for
/// type-specific parameters (e.g. `groupCount`, `qualifierCount`, `rounds`,
/// `withThirdPlace`, `ruleset`, `slots`), and a [seeding] source. No semantic
/// validation happens here (that is a later layer).
@immutable
class StageNode {
  /// Creates a stage node.
  ///
  /// The given [config] is deep-copied into a fully unmodifiable tree, so that
  /// later mutation of the passed-in map (or of any nested map/list it holds)
  /// cannot change this object.
  StageNode({
    required this.id,
    required this.type,
    required this.seeding,
    Map<String, Object?> config = const <String, Object?>{},
  }) : config = _deepUnmodifiableMap(config);

  /// Reconstructs a [StageNode] from its JSON form.
  factory StageNode.fromJson(Map<String, Object?> json) => StageNode(
        id: json['id']! as String,
        type: StageNodeType.fromWire(json['type']! as String),
        seeding: StageSeedingSource.fromWire(json['seeding']! as String),
        config: json['config'] as Map<String, Object?>? ??
            const <String, Object?>{},
      );

  /// Stable identifier of this stage within the graph.
  final String id;

  /// Algorithm type of the stage.
  final StageNodeType type;

  /// Free-form, type-specific parameters. Unmodifiable after construction.
  final Map<String, Object?> config;

  /// How participants entering this stage are seeded.
  final StageSeedingSource seeding;

  /// Serializes this node to a JSON-compatible map.
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'type': type.toWire(),
        // Emit a fresh, mutable deep copy so callers never alias internal state.
        'config': _deepMutableMap(config),
        'seeding': seeding.toWire(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StageNode &&
          other.id == id &&
          other.type == type &&
          other.seeding == seeding &&
          _configEquality.equals(other.config, config);

  @override
  int get hashCode =>
      Object.hash(id, type, seeding, _configEquality.hash(config));

  @override
  String toString() =>
      'StageNode(id: $id, type: ${type.wire}, seeding: ${seeding.wire}, '
      'config: $config)';
}
