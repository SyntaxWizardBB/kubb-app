import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

const SetEquality<int> _intSetEquality = SetEquality<int>();

/// Routing selector on a stage-graph edge (ADR-0030 §Edge).
///
/// A selector declares *which* participants of the source stage's final
/// ordering flow into the target stage. This is pure data: the selector is
/// carried and serialized but NOT applied to any ordering here (that is the
/// runner's job, a later layer).
///
/// Every variant serializes to a JSON map with a `kind` discriminator.
@immutable
sealed class EdgeSelector {
  const EdgeSelector();

  /// Reconstructs an [EdgeSelector] from its JSON form, dispatching on `kind`.
  ///
  /// Throws [ArgumentError] when `kind` is missing or unknown.
  static EdgeSelector fromJson(Map<String, Object?> json) {
    final kind = json['kind'];
    switch (kind) {
      case TopK._kind:
        return TopK(json['k']! as int);
      case Ranks._kind:
        return Ranks(json['from']! as int, json['to']! as int);
      case LosersOfRounds._kind:
        return LosersOfRounds(<int>{
          for (final r in json['rounds']! as List<Object?>) r! as int,
        });
      case NonQualifiers._kind:
        return const NonQualifiers();
      case Winners._kind:
        return const Winners();
      default:
        throw ArgumentError.value(
          kind,
          'kind',
          'unknown EdgeSelector kind',
        );
    }
  }

  /// Serializes this selector to a JSON-compatible map with a `kind` field.
  Map<String, Object?> toJson();
}

/// Selects the best [k] participants of the source stage's final ordering.
@immutable
class TopK extends EdgeSelector {
  /// Creates a top-K selector.
  const TopK(this.k);

  static const String _kind = 'top_k';

  /// Number of top-ranked participants to select.
  final int k;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': _kind, 'k': k};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is TopK && other.k == k;

  @override
  int get hashCode => Object.hash(_kind, k);

  @override
  String toString() => 'TopK($k)';
}

/// Selects the inclusive rank band [from]..[to] of the source ordering.
@immutable
class Ranks extends EdgeSelector {
  /// Creates a rank-band selector.
  const Ranks(this.from, this.to);

  static const String _kind = 'ranks';

  /// First rank of the band (inclusive).
  final int from;

  /// Last rank of the band (inclusive).
  final int to;

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'kind': _kind, 'from': from, 'to': to};

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Ranks && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(_kind, from, to);

  @override
  String toString() => 'Ranks($from, $to)';
}

/// Selects the losers of specific knockout [rounds] (side-cup feeder).
@immutable
class LosersOfRounds extends EdgeSelector {
  /// Creates a losers-of-rounds selector.
  ///
  /// The given [rounds] are copied into an unmodifiable set, so later mutation
  /// of the passed-in set cannot change this object.
  LosersOfRounds(Set<int> rounds)
      : rounds = Set<int>.unmodifiable(rounds);

  static const String _kind = 'losers_of_rounds';

  /// The knockout rounds whose losers are selected. Unmodifiable; equality and
  /// hashing are set-based (order independent).
  final Set<int> rounds;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'kind': _kind,
        // Deterministic, ascending order for reproducible JSON.
        'rounds': rounds.toList()..sort(),
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LosersOfRounds && _intSetEquality.equals(other.rounds, rounds);

  @override
  int get hashCode => Object.hash(_kind, _intSetEquality.hash(rounds));

  @override
  String toString() {
    final sorted = rounds.toList()..sort();
    return 'LosersOfRounds($sorted)';
  }
}

/// Selects all participants not forwarded by any other outgoing edge.
@immutable
class NonQualifiers extends EdgeSelector {
  /// Creates a non-qualifiers selector.
  const NonQualifiers();

  static const String _kind = 'non_qualifiers';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': _kind};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NonQualifiers;

  @override
  int get hashCode => _kind.hashCode;

  @override
  String toString() => 'NonQualifiers()';
}

/// Selects the winner(s) (final rank 1) of the source stage.
@immutable
class Winners extends EdgeSelector {
  /// Creates a winners selector.
  const Winners();

  static const String _kind = 'winners';

  @override
  Map<String, Object?> toJson() => <String, Object?>{'kind': _kind};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Winners;

  @override
  int get hashCode => _kind.hashCode;

  @override
  String toString() => 'Winners()';
}
