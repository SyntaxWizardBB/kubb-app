import 'package:kubb_domain/src/tournament/tiebreaker.dart';

/// Deterministic seed-based shuffle of [ids] for the `random` seeding source.
///
/// Returns a fresh permutation; [ids] is not mutated. The same `(ids, seed)`
/// always yields the same order — the determinism the seeding spec §2/§7.3
/// requires so a stored seed reproduces the setlist across runs.
///
/// The PRNG is an explicit 32-bit linear congruential generator (Numerical
/// Recipes constants: `next = (state * 1664525 + 1013904223) mod 2^32`), not
/// `dart:math` `Random`. `Random` is deterministic within Dart but its internal
/// algorithm is unspecified and not reproducible byte-for-byte in plpgsql, so
/// the planned plpgsql twin (T12 parity test: SQL random == Dart `seedRandom`)
/// could never match it. The LCG is plain integer arithmetic — multiply, add,
/// mask to 32 bits — which `bigint` reproduces exactly in plpgsql.
///
/// Index draws use rejection sampling against the 32-bit range to drop the
/// modulo bias, again with arithmetic that ports verbatim. The shuffle itself
/// is the standard Fisher-Yates pass from high to low index.
List<String> seedRandom(List<String> ids, int seed) {
  final out = List<String>.of(ids);
  if (out.length < 2) return out;

  var state = seed & 0xFFFFFFFF;
  int next() => state = (state * 1664525 + 1013904223) & 0xFFFFFFFF;

  // Unbiased value in [0, bound) via rejection on the largest usable multiple.
  int nextBelow(int bound) {
    final limit = 0x100000000 - (0x100000000 % bound);
    int draw;
    do {
      draw = next();
    } while (draw >= limit);
    return draw % bound;
  }

  for (var i = out.length - 1; i > 0; i--) {
    final j = nextBelow(i + 1);
    final tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

/// Sort participants by [chain] and return their ids in best-first order.
///
/// Pure: [stats] is not mutated; a fresh list is allocated and sorted via
/// [TiebreakerChain.compare]. With a fixed [TiebreakerChain.randomSeed] the
/// `random` tie-step is deterministic, so repeated calls yield identical
/// orderings.
List<String> seedFromStandings(
  List<ParticipantStats> stats,
  TiebreakerChain chain,
) {
  final sorted = [...stats]..sort(chain.compare);
  return [for (final s in sorted) s.participantId];
}

/// Swap participants in [autoSeeded] according to [overrides]
/// (1-based `seed_position → participantId`). Returns a new list.
///
/// Empty [overrides] is idempotent (returns a copy). For each entry the
/// target participant is located in the current working list and swapped
/// with the participant at the requested 1-based position.
///
/// Throws [ArgumentError] when:
///  - a key is outside `[1, autoSeeded.length]`, or
///  - a value names a participant not present in [autoSeeded].
List<String> applyManualOverride(
  List<String> autoSeeded,
  Map<int, String> overrides,
) {
  final result = [...autoSeeded];
  for (final entry in overrides.entries) {
    final pos = entry.key;
    final participantId = entry.value;
    if (pos < 1 || pos > result.length) {
      throw ArgumentError.value(
        pos,
        'overrides.key',
        'seed position must be in [1, ${result.length}]',
      );
    }
    final currentIndex = result.indexOf(participantId);
    if (currentIndex < 0) {
      throw ArgumentError.value(
        participantId,
        'overrides.value',
        'participant is not present in autoSeeded',
      );
    }
    final targetIndex = pos - 1;
    if (currentIndex == targetIndex) continue;
    final tmp = result[targetIndex];
    result[targetIndex] = participantId;
    result[currentIndex] = tmp;
  }
  return result;
}
