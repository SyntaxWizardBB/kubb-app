import 'package:meta/meta.dart';

@immutable
final class PoolPairing {
  const PoolPairing({required this.participantA, this.participantB});

  final String participantA;
  final String? participantB;

  bool get isBye => participantB == null;
}

@immutable
final class PoolRound {
  const PoolRound({required this.pairings});

  final List<PoolPairing> pairings;
}

@immutable
sealed class Pool {
  const Pool({required this.rounds, required this.participantCount});

  /// Round-robin pool using the circle-rotation algorithm.
  /// Odd participant counts get one BYE per round (max one BYE per
  /// participant total, per FR-PAIR-4).
  factory Pool.roundRobin(List<String> participantIds) {
    if (participantIds.isEmpty) {
      throw ArgumentError('participantIds must not be empty');
    }
    if (participantIds.length == 1) {
      return const _RoundRobinPool(rounds: [], participantCount: 1);
    }
    final isOdd = participantIds.length.isOdd;
    final slots = [...participantIds, if (isOdd) null];
    final n = slots.length;
    final rounds = <PoolRound>[];
    for (var r = 0; r < n - 1; r++) {
      final pairings = <PoolPairing>[];
      for (var i = 0; i < n ~/ 2; i++) {
        final a = slots[i];
        final b = slots[n - 1 - i];
        if (a == null) {
          pairings.add(PoolPairing(participantA: b!));
        } else if (b == null) {
          pairings.add(PoolPairing(participantA: a));
        } else {
          pairings.add(PoolPairing(participantA: a, participantB: b));
        }
      }
      rounds.add(PoolRound(pairings: List.unmodifiable(pairings)));
      // Rotate all but the first slot clockwise.
      slots.insert(1, slots.removeLast());
    }
    return _RoundRobinPool(
      rounds: rounds,
      participantCount: participantIds.length,
    );
  }

  final List<PoolRound> rounds;
  final int participantCount;
}

final class _RoundRobinPool extends Pool {
  const _RoundRobinPool({required super.rounds, required super.participantCount});
}
