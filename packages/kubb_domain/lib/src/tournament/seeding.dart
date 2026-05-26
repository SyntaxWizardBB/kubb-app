import 'package:kubb_domain/src/tournament/tiebreaker.dart';

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
