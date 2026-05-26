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

/// T3 implements this body — T1 only locks the contract.
PoolPhaseResult generatePools(List<String> ids, PoolPhaseConfig config) =>
    throw UnimplementedError('generatePools is implemented in M3.3-T3');
