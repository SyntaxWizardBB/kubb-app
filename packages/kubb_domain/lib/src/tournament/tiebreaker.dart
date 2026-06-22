import 'dart:math';

import 'package:kubb_domain/src/tournament/stage_graph/stage_node.dart';
import 'package:meta/meta.dart';

/// Tiebreaker criteria for tournament ranking (FR-RANK-4).
enum TiebreakerCriterion {
  totalPoints,

  /// Buchholz per schoch-swiss spec §5: opponent totals minus what each
  /// opponent scored head-to-head (the kubb.live formula). This is the
  /// Schoch criterion. Distinct from [buchholzMinusH2H], which is the older
  /// naive variant and is NOT spec-conform (vorrunde-ranking-spec §6.2).
  buchholz,

  buchholzMinusH2H,
  medianBuchholz,
  kubbDifference,
  directComparison,
  wins,

  /// Physical on-site decider (Mighty-Finisher shoot-out, decision §H,
  /// docs/P6_SHOOTOUT_TIEBREAK.md). It cannot be resolved from precomputed
  /// stats, so the in-chain comparator stays neutral (returns 0, falls through
  /// to the next criterion / the ID fallback). The actual resolution happens
  /// out-of-band: `shootout.dart` detects only the *qualification-relevant*
  /// tie groups (those straddling the cut line) and re-orders them from a
  /// recorded on-site shoot-out result, replacing the ID fallback for those
  /// groups. Cosmetic ties keep the neutral behaviour.
  mightyFinisherShootout,
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
    this.opponentScoreAgainstLookup = const {},
  });

  final String participantId;
  final int totalPoints;
  final int wins;
  final int kubbsScored;
  final int kubbsConceded;
  final List<String> opponentIds;
  final Map<String, int> opponentTotalPointsLookup;
  final Map<String, int> headToHeadLookup;

  /// Points each opponent scored against this participant in their direct
  /// match — the §5 head-to-head subtrahend. Distinct from
  /// [headToHeadLookup], which carries a win-differential for
  /// [TiebreakerCriterion.directComparison].
  final Map<String, int> opponentScoreAgainstLookup;

  /// Buchholz per schoch-swiss spec §5: opponent totals minus what each
  /// opponent scored head-to-head. Mirrors `BuchholzCalculator.scoreFor`.
  int get buchholz => opponentIds.fold(
        0,
        (s, id) =>
            s +
            (opponentTotalPointsLookup[id] ?? 0) -
            (opponentScoreAgainstLookup[id] ?? 0),
      );

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
    // Stable, deterministic fallback when the configured chain is exhausted.
    // Guarantees a total ordering even for fully-identical stats (e.g. rank
    // 3 vs. 4 with `withThirdPlace = false`, ADR-0017 §4 last paragraph) so
    // downstream league-point allocation in M5 is reproducible instead of
    // implementation-defined. See TASK-M2.1-T10.
    return a.participantId.compareTo(b.participantId);
  }

  /// Compares [a] and [b] on a single [criterion] only, without applying the
  /// participantId fallback. Returns 0 when the criterion does not separate
  /// them. Exposed so callers (e.g. the shoot-out detector) can probe "are
  /// these two exactly tied on every regular criterion?" using the chain's own
  /// semantics instead of re-implementing them. [TiebreakerCriterion
  /// .mightyFinisherShootout] is intentionally neutral here (returns 0): the
  /// shoot-out is resolved out-of-band from a recorded on-site result, not
  /// from stats.
  int compareCriterion(
    TiebreakerCriterion criterion,
    ParticipantStats a,
    ParticipantStats b,
  ) =>
      _apply(criterion, a, b);

  int _apply(TiebreakerCriterion c, ParticipantStats a, ParticipantStats b) {
    switch (c) {
      case TiebreakerCriterion.totalPoints:
        return b.totalPoints.compareTo(a.totalPoints);
      case TiebreakerCriterion.wins:
        return b.wins.compareTo(a.wins);
      case TiebreakerCriterion.kubbDifference:
        return (b.kubbsScored - b.kubbsConceded)
            .compareTo(a.kubbsScored - a.kubbsConceded);
      case TiebreakerCriterion.buchholz:
        return b.buchholz.compareTo(a.buchholz);
      case TiebreakerCriterion.buchholzMinusH2H:
        return (b._buchholz - b._h2hSubtotalAgainst(a))
            .compareTo(a._buchholz - a._h2hSubtotalAgainst(b));
      case TiebreakerCriterion.medianBuchholz:
        return b._medianBuchholz.compareTo(a._medianBuchholz);
      case TiebreakerCriterion.directComparison:
        final h = a.headToHeadLookup[b.participantId] ?? 0;
        return -h.sign;
      case TiebreakerCriterion.mightyFinisherShootout:
        // Physical decider; not resolvable from stats. Fall through so the
        // chain continues (ultimately to the deterministic ID fallback).
        return 0;
      case TiebreakerCriterion.random:
        final ids = [a.participantId, b.participantId]..sort();
        final seed = randomSeed ^ ids[0].hashCode ^ (ids[1].hashCode << 1);
        final draw = Random(seed).nextInt(2) == 0 ? -1 : 1;
        return a.participantId == ids[0] ? draw : -draw;
    }
  }
}

/// The fixed preliminary-ranking chain for a stage [type] (ADR-0035,
/// vorrunde-ranking-spec §6.2). Not user-configurable and not persisted: the
/// chain follows from the stage type alone.
///
///  * [StageNodeType.groupPhase]: points -> kubb difference -> shoot-out.
///    Buchholz is deliberately absent in every position (§4): everyone in a
///    group faces the same opponents, so it never separates them.
///  * [StageNodeType.schoch]: points -> §5 Buchholz -> shoot-out. Uses the
///    kubb.live formula via [TiebreakerCriterion.buchholz], not the naive
///    [TiebreakerCriterion.buchholzMinusH2H].
///
/// Any other stage type has no preliminary ranking and throws an
/// [ArgumentError] rather than falling back to a silent default.
TiebreakerChain chainForStageType(StageNodeType type) {
  switch (type) {
    case StageNodeType.groupPhase:
      return const TiebreakerChain([
        TiebreakerCriterion.totalPoints,
        TiebreakerCriterion.kubbDifference,
        TiebreakerCriterion.mightyFinisherShootout,
      ]);
    case StageNodeType.schoch:
      return const TiebreakerChain([
        TiebreakerCriterion.totalPoints,
        TiebreakerCriterion.buchholz,
        TiebreakerCriterion.mightyFinisherShootout,
      ]);
    case StageNodeType.roundRobin:
    case StageNodeType.singleElim:
    case StageNodeType.doubleElim:
    case StageNodeType.consolation:
    case StageNodeType.shootoutQuali:
      throw ArgumentError.value(
        type,
        'type',
        'no preliminary ranking chain for this stage type',
      );
  }
}
