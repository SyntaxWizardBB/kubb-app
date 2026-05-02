import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Number of batons the opening team throws in each round.
///
/// The list is round-indexed: index 0 is round 1, index 1 is round 2, etc.
/// Once exhausted, all subsequent rounds use 6 batons (the standard).
@immutable
final class OpeningRule {
  const OpeningRule({required this.code, required this.batonsPerRound});

  factory OpeningRule.sixSixSix() =>
      const OpeningRule(code: '6-6-6', batonsPerRound: [6, 6, 6]);

  factory OpeningRule.fourSixSix() =>
      const OpeningRule(code: '4-6-6', batonsPerRound: [4, 6, 6]);

  factory OpeningRule.threeSixSix() =>
      const OpeningRule(code: '3-6-6', batonsPerRound: [3, 6, 6]);

  factory OpeningRule.twoFourSix() =>
      const OpeningRule(code: '2-4-6', batonsPerRound: [2, 4, 6]);

  final String code;
  final List<int> batonsPerRound;

  /// Number of batons the opening team has in the given (1-based) round.
  int batonsInRound(int round) {
    assert(round >= 1, 'round is 1-based');
    if (round - 1 < batonsPerRound.length) return batonsPerRound[round - 1];
    return 6;
  }

  /// Minimum number of distinct players that must throw the round's batons.
  /// CH rules: 6 → ≥3, 4 → ≥3, 3 → ≥3, 2 → ≥2.
  int minPlayersForRound(int round) {
    final batons = batonsInRound(round);
    return batons >= 3 ? 3 : 2;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OpeningRule &&
          other.code == code &&
          const ListEquality<int>()
              .equals(other.batonsPerRound, batonsPerRound);

  @override
  int get hashCode =>
      Object.hash(code, Object.hashAll(batonsPerRound));

  @override
  String toString() => 'OpeningRule($code)';
}
