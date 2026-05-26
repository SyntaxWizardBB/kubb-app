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
      if (withThirdPlace)
        BracketRound(
          number: totalRounds,
          pairings: const [(placeholder, placeholder)],
          phase: BracketPhase.thirdPlace,
        ),
    ];
    return SingleEliminationBracket(rounds: rounds);
  }

  /// Place [participantId] into slot ([round], [position]). 1-based indices.
  ///
  /// [round] targets a [BracketRound] whose `phase` is not
  /// [BracketPhase.thirdPlace]. [position] is 1-based across the round's
  /// pairings: position 1 = first pairing's `$1`, 2 = first pairing's `$2`,
  /// 3 = second pairing's `$1`, ...
  ///
  /// Pure: returns a new [Bracket] with the slot replaced; all other slots
  /// remain identical. When the filled slot is in a non-first round of a
  /// bracket that also carries a [BracketPhase.thirdPlace] round, the
  /// corresponding loser of the source pairing is mirrored into the
  /// third-place slot — see ADR-0017 §4/§5.
  Bracket fill({
    required int round,
    required int position,
    required String participantId,
  });
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
  Bracket fill({
    required int round,
    required int position,
    required String participantId,
  }) {
    final newRounds = [...rounds];
    final entry = (seed: 0, participantId: participantId, isBye: false);
    _writeAt(newRounds, round, position, entry, allowThirdPlace: false);
    // Mirror semifinal loser into the third-place playoff slot (ADR-0017 §4).
    final thirdIdx =
        newRounds.indexWhere((r) => r.phase == BracketPhase.thirdPlace);
    if (thirdIdx >= 0 && round > 1) {
      final source = newRounds.firstWhereOrNull(
        (r) => r.number == round - 1 && r.phase != BracketPhase.thirdPlace,
      );
      final pair = source?.pairings.elementAtOrNull(position - 1);
      if (pair != null) {
        final loser = pair.$1.participantId == participantId ? pair.$2 : pair.$1;
        if (loser.participantId != null) {
          _writeAt(newRounds, newRounds[thirdIdx].number, position, loser,
              allowThirdPlace: true);
        }
      }
    }
    return SingleEliminationBracket(rounds: newRounds);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SingleEliminationBracket &&
          const ListEquality<BracketRound>().equals(other.rounds, rounds);

  @override
  int get hashCode => Object.hashAll(rounds);
}

void _writeAt(
  List<BracketRound> rounds,
  int roundNumber,
  int position,
  BracketEntry entry, {
  required bool allowThirdPlace,
}) {
  if (position < 1) {
    throw ArgumentError.value(position, 'position', 'must be >= 1');
  }
  final idx = rounds.indexWhere((r) =>
      r.number == roundNumber &&
      (allowThirdPlace
          ? r.phase == BracketPhase.thirdPlace
          : r.phase != BracketPhase.thirdPlace));
  if (idx < 0) {
    throw ArgumentError.value(roundNumber, 'round', 'no matching round');
  }
  final target = rounds[idx];
  final pairIdx = (position - 1) ~/ 2;
  final slotIdx = (position - 1) % 2;
  if (pairIdx >= target.pairings.length) {
    throw ArgumentError.value(position, 'position', 'out of range');
  }
  final newPairings = [...target.pairings];
  final cur = newPairings[pairIdx];
  newPairings[pairIdx] = (slotIdx == 0 ? entry : cur.$1, slotIdx == 1 ? entry : cur.$2);
  rounds[idx] = BracketRound(
    number: target.number,
    phase: target.phase,
    pairings: newPairings,
  );
}
