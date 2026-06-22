import 'package:kubb_domain/src/tournament/seeding.dart';
import 'package:meta/meta.dart';

/// Strategy used to distribute participants into pool groups. See ADR-0019 §1.
enum PoolGroupingStrategy { snake, random, seeded }

/// Configuration for a pool-phase generation run.
@immutable
class PoolPhaseConfig {
  const PoolPhaseConfig({
    required this.groupCount,
    required this.qualifiersPerGroup,
    required this.strategy,
    this.randomSeed,
  });

  final int groupCount;
  final int qualifiersPerGroup;
  final PoolGroupingStrategy strategy;
  final int? randomSeed;
}

/// One bucket per group; `null` denotes a BYE-slot in a shorter group.
@immutable
class PoolPhaseResult {
  const PoolPhaseResult({required this.groups});
  final List<List<String?>> groups;
}

/// Generates pool groups from a participant id list according to [config].
///
/// Validation (mirrored 1:1 in `_tournament_compute_pools` plpgsql in T5):
///   * `groupCount >= 1`
///   * `qualifiersPerGroup >= 1`
///   * `ceil(ids.length / groupCount) >= qualifiersPerGroup`
///
/// Distribution per strategy:
///   * `snake`  — row-by-row, alternating direction (S0→G0, S1→G1, ..., Sn→Gn,
///                Sn+1→Gn, Sn+2→Gn-1, ...). Standard Schweizer-Liga pattern.
///   * `random` — `seedRandom(ids, randomSeed)` (portable LCG Fisher-Yates),
///                then snake.
///   * `seeded` — sequential block-fill, input order preserved within group.
///
/// BYE-Slots (`null`) are appended when `groupCount * groupSize > ids.length`,
/// landing in the trailing (shortest) groups so KO-seeding indices stay stable.
PoolPhaseResult generatePools(List<String> ids, PoolPhaseConfig config) {
  if (config.groupCount < 1) {
    throw ArgumentError.value(
      config.groupCount,
      'groupCount',
      'must be at least 1',
    );
  }
  if (config.qualifiersPerGroup < 1) {
    throw ArgumentError.value(
      config.qualifiersPerGroup,
      'qualifiersPerGroup',
      'must be at least 1',
    );
  }
  final groupSize = (ids.length + config.groupCount - 1) ~/ config.groupCount;
  if (groupSize < config.qualifiersPerGroup) {
    throw ArgumentError(
      'qualifiersPerGroup (${config.qualifiersPerGroup}) exceeds max group '
      'size ($groupSize) for ${ids.length} participants in '
      '${config.groupCount} groups',
    );
  }

  final ordered = switch (config.strategy) {
    PoolGroupingStrategy.snake => ids,
    PoolGroupingStrategy.seeded => ids,
    PoolGroupingStrategy.random => seedRandom(ids, config.randomSeed ?? 0),
  };

  final groups = List<List<String?>>.generate(
    config.groupCount,
    (_) => <String?>[],
    growable: false,
  );

  if (config.strategy == PoolGroupingStrategy.seeded) {
    for (var i = 0; i < ordered.length; i++) {
      groups[i ~/ groupSize].add(ordered[i]);
    }
  } else {
    // Snake (also for random after shuffle): row r, direction alternates.
    for (var i = 0; i < ordered.length; i++) {
      final row = i ~/ config.groupCount;
      final col = i % config.groupCount;
      final groupIndex =
          row.isEven ? col : config.groupCount - 1 - col;
      groups[groupIndex].add(ordered[i]);
    }
  }

  // Pad shorter groups with BYE so every bucket reaches `groupSize`. The
  // snake-last-row already places missing slots in the lowest-index groups;
  // we reorder so the shortest groups land at the end (stable for ties).
  groups.sort((a, b) => b.length.compareTo(a.length));
  for (final g in groups) {
    while (g.length < groupSize) {
      g.add(null);
    }
  }

  return PoolPhaseResult(groups: groups);
}
