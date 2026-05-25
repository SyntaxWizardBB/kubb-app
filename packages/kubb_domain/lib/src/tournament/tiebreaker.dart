import 'dart:math';

import 'package:meta/meta.dart';

/// Tiebreaker criteria for tournament ranking (FR-RANK-4).
enum TiebreakerCriterion {
  totalPoints,
  buchholzMinusH2H,
  medianBuchholz,
  kubbDifference,
  directComparison,
  wins,
  random,
}

/// Pre-computed inputs for the comparator chain. The orchestrator builds these
/// from confirmed matches before applying the chain.
@immutable
final class ParticipantStats {
  const ParticipantStats({
    required this.participantId,
    required this.totalPoints,
    required this.wins,
    required this.kubbsScored,
    required this.kubbsConceded,
    required this.opponentIds,
    required this.opponentTotalPointsLookup,
    required this.headToHeadLookup,
  });

  final String participantId;
  final int totalPoints;
  final int wins;
  final int kubbsScored;
  final int kubbsConceded;
  final List<String> opponentIds;
  final Map<String, int> opponentTotalPointsLookup;
  final Map<String, int> headToHeadLookup;

  int get _buchholz =>
      opponentIds.fold(0, (s, id) => s + (opponentTotalPointsLookup[id] ?? 0));

  int _h2hSubtotalAgainst(ParticipantStats other) =>
      headToHeadLookup[other.participantId] ?? 0;

  int get _medianBuchholz {
    if (opponentIds.length < 2) return _buchholz;
    final values = [
      for (final id in opponentIds) opponentTotalPointsLookup[id] ?? 0,
    ]..sort();
    return values.sublist(1, values.length - 1).fold(0, (s, v) => s + v);
  }
}

/// Configurable comparator chain. Applies each criterion in order until one
/// separates the two participants; falls through on ties.
class TiebreakerChain {
  const TiebreakerChain(this.order, {this.randomSeed = 0});

  final List<TiebreakerCriterion> order;
  final int randomSeed;

  int compare(ParticipantStats a, ParticipantStats b) {
    for (final c in order) {
      final r = _apply(c, a, b);
      if (r != 0) return r;
    }
    return 0;
  }

  int _apply(TiebreakerCriterion c, ParticipantStats a, ParticipantStats b) {
    switch (c) {
      case TiebreakerCriterion.totalPoints:
        return b.totalPoints.compareTo(a.totalPoints);
      case TiebreakerCriterion.wins:
        return b.wins.compareTo(a.wins);
      case TiebreakerCriterion.kubbDifference:
        return (b.kubbsScored - b.kubbsConceded)
            .compareTo(a.kubbsScored - a.kubbsConceded);
      case TiebreakerCriterion.buchholzMinusH2H:
        return (b._buchholz - b._h2hSubtotalAgainst(a))
            .compareTo(a._buchholz - a._h2hSubtotalAgainst(b));
      case TiebreakerCriterion.medianBuchholz:
        return b._medianBuchholz.compareTo(a._medianBuchholz);
      case TiebreakerCriterion.directComparison:
        final h = a.headToHeadLookup[b.participantId] ?? 0;
        return -h.sign;
      case TiebreakerCriterion.random:
        final ids = [a.participantId, b.participantId]..sort();
        final seed = randomSeed ^ ids[0].hashCode ^ (ids[1].hashCode << 1);
        final draw = Random(seed).nextInt(2) == 0 ? -1 : 1;
        return a.participantId == ids[0] ? draw : -draw;
    }
  }
}
