import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// Standard sport-tournament seeding (top-seed faces top of the
/// opposite half, so seed 1 and seed 2 only meet in the final).
/// The linear pattern pairs `(seed_i, seed_{N+1-i})` straight through,
/// which lets high seeds meet earlier — easier to compute, but
/// uncommon in real tournaments.
enum BracketSeedingPattern { recursive, linear }

/// Phase marker for a [BracketRound] — see ADR-0017 §4.
enum BracketPhase { winners, thirdPlace, finals }

typedef BracketEntry = ({int seed, String? participantId, bool isBye});
typedef BracketPairing = (BracketEntry a, BracketEntry b);

@immutable
final class BracketRound {
  const BracketRound({
    required this.number,
    required this.pairings,
    this.phase = BracketPhase.winners,
  });

  final int number;
  final List<BracketPairing> pairings;
  final BracketPhase phase;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BracketRound &&
          other.number == number &&
          other.phase == phase &&
          const ListEquality<BracketPairing>()
              .equals(other.pairings, pairings);

  @override
  int get hashCode => Object.hash(number, phase, Object.hashAll(pairings));
}

@immutable
sealed class Bracket {
  const Bracket();

  factory Bracket.singleElimination(
    List<String> participantIds, {
    // Flag reserved for the third-place playoff in M1; structure unchanged
    // in M0.
    // ignore: avoid_unused_constructor_parameters
    bool withThirdPlace = false,
    BracketSeedingPattern seedingPattern = BracketSeedingPattern.recursive,
  }) {
    if (participantIds.isEmpty) {
      throw ArgumentError.value(participantIds, 'participantIds', 'is empty');
    }
    final n = participantIds.length;
    if (n == 1) return const SingleEliminationBracket(rounds: []);
    var size = 1;
    while (size < n) {
      size *= 2;
    }
    final slots = <BracketEntry>[
      for (var i = 0; i < size; i++)
        (
          seed: i + 1,
          participantId: i < n ? participantIds[i] : null,
          isBye: i >= n,
        ),
    ];
    final order = switch (seedingPattern) {
      BracketSeedingPattern.linear => [
          for (var i = 0; i < size ~/ 2; i++) ...[i + 1, size - i],
        ],
      BracketSeedingPattern.recursive => _standardBracketOrder(size),
    };
    final round1 = <BracketPairing>[
      for (var i = 0; i < size; i += 2)
        (slots[order[i] - 1], slots[order[i + 1] - 1]),
    ];
    const placeholder = (seed: 0, participantId: null, isBye: false);
    var totalRounds = 0;
    for (var x = size; x > 1; x ~/= 2) {
      totalRounds++;
    }
    final rounds = <BracketRound>[
      BracketRound(number: 1, pairings: round1),
      for (var r = 2; r <= totalRounds; r++)
        BracketRound(
          number: r,
          pairings: List.generate(
            size ~/ (1 << r),
            (_) => (placeholder, placeholder),
          ),
        ),
    ];
    return SingleEliminationBracket(rounds: rounds);
  }

  /// Place [participantId] into slot ([round], [position]). 1-based.
  Bracket fill({
    required int round,
    required int position,
    required String participantId,
  }) => throw UnimplementedError('Bracket.fill — pending TASK-M2.1-T5');
}

List<int> _standardBracketOrder(int n) {
  if (n == 1) return [1];
  final inner = _standardBracketOrder(n ~/ 2);
  return [
    for (var i = 0; i < inner.length; i++)
      if (i.isEven) ...[inner[i], n + 1 - inner[i]] else ...[
        n + 1 - inner[i],
        inner[i],
      ],
  ];
}

@immutable
final class SingleEliminationBracket extends Bracket {
  const SingleEliminationBracket({required this.rounds});

  final List<BracketRound> rounds;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SingleEliminationBracket &&
          const ListEquality<BracketRound>().equals(other.rounds, rounds);

  @override
  int get hashCode => Object.hashAll(rounds);
}
