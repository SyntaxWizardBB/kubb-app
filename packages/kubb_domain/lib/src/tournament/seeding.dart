import 'package:kubb_domain/src/tournament/tiebreaker.dart';

/// Sort participants by [chain] and return their ids in best-first order.
List<String> seedFromStandings(
  List<ParticipantStats> stats,
  TiebreakerChain chain,
) =>
    throw UnimplementedError();

/// Swap participants in [autoSeeded] according to [overrides]
/// (1-based `seed_position → participantId`). Returns a new list.
List<String> applyManualOverride(
  List<String> autoSeeded,
  Map<int, String> overrides,
) =>
    throw UnimplementedError();
