import 'dart:math';

import 'package:kubb_domain/src/tournament/pool_phase.dart';
import 'package:kubb_domain/src/tournament/tiebreaker.dart';
import 'package:meta/meta.dart';

/// Result of [selectQualifiers] (ADR-0019 §2-§4, OD-M3-03/05).
@immutable
class CutResult {
  const CutResult(this.qualifiers, this.tieResolutionNeeded);
  final List<String> qualifiers;
  final List<TieResolutionNeeded> tieResolutionNeeded;
}

/// Marker for ties the chain cannot break cross-pool (OD-M3-05).
@immutable
class TieResolutionNeeded {
  const TieResolutionNeeded(this.participantIds, this.criterion);
  final List<String> participantIds;
  final String criterion;
}

/// Top-N qualifier cut (ADR-0019 §2-§4).
///
/// 1. Each pool is sorted via [chain]; top-`qualifiersPerGroup` advance.
/// 2. All qualifiers are merged and re-sorted via a cross-pool chain that
///    skips [TiebreakerCriterion.directComparison] — undefined between
///    participants from different pools (OD-M3-03).
/// 3. Adjacent qualifiers that remain tied after every cross-pool criterion
///    are reported in [CutResult.tieResolutionNeeded] (OD-M3-05).
CutResult selectQualifiers(
  List<List<ParticipantStats>> pools,
  PoolPhaseConfig config,
  TiebreakerChain chain,
) {
  final perPool = <ParticipantStats>[];
  for (final pool in pools) {
    final sorted = [...pool]..sort(chain.compare);
    final n = config.qualifiersPerGroup.clamp(0, sorted.length);
    perPool.addAll(sorted.take(n));
  }

  final crossPoolOrder = [
    for (final c in chain.order)
      if (c != TiebreakerCriterion.directComparison) c,
  ];
  final crossPoolChain =
      TiebreakerChain(crossPoolOrder, randomSeed: chain.randomSeed);

  final merged = [...perPool]..sort(crossPoolChain.compare);

  // Tie-marker semantics (ADR-0019 §4, OD-M3-05): a tie is only escalated when
  // the organiser configured a multi-stage chain and *every* stage was
  // exhausted. A single-criterion chain is treated as "user only cares about
  // this stat" — the deterministic participantId fallback is acceptable and
  // no manual resolution is requested.
  final ties = <TieResolutionNeeded>[];
  if (crossPoolOrder.length >= 2) {
    var i = 0;
    while (i < merged.length - 1) {
      var j = i;
      while (j + 1 < merged.length &&
          _allCriteriaEqual(
              merged[j], merged[j + 1], crossPoolOrder, chain.randomSeed)) {
        j++;
      }
      if (j > i) {
        ties.add(TieResolutionNeeded(
          [for (var k = i; k <= j; k++) merged[k].participantId],
          crossPoolOrder.last.name,
        ));
        i = j + 1;
      } else {
        i++;
      }
    }
  }

  return CutResult(
    [for (final s in merged) s.participantId],
    ties,
  );
}

/// True when [a] and [b] tie on every criterion in [order] — the chain has
/// nothing left to separate them except the participantId fallback (OD-M3-05).
bool _allCriteriaEqual(
  ParticipantStats a,
  ParticipantStats b,
  List<TiebreakerCriterion> order,
  int randomSeed,
) {
  for (final c in order) {
    if (_criterionCompare(a, b, c, randomSeed) != 0) return false;
  }
  return true;
}

/// Mirrors `TiebreakerChain._apply` so we can probe a single criterion without
/// touching the participantId fallback. Keep in sync with `tiebreaker.dart`.
int _criterionCompare(
  ParticipantStats a,
  ParticipantStats b,
  TiebreakerCriterion c,
  int randomSeed,
) {
  switch (c) {
    case TiebreakerCriterion.totalPoints:
      return b.totalPoints.compareTo(a.totalPoints);
    case TiebreakerCriterion.wins:
      return b.wins.compareTo(a.wins);
    case TiebreakerCriterion.kubbDifference:
      return (b.kubbsScored - b.kubbsConceded)
          .compareTo(a.kubbsScored - a.kubbsConceded);
    case TiebreakerCriterion.directComparison:
      final h = a.headToHeadLookup[b.participantId] ?? 0;
      return -h.sign;
    case TiebreakerCriterion.mightyFinisherShootout:
      // Physical decider; not resolvable from stats (decision §H). No-op so
      // the chain continues to the next criterion / the ID fallback.
      return 0;
    case TiebreakerCriterion.buchholzMinusH2H:
      return _buchholzMinusH2H(b, a).compareTo(_buchholzMinusH2H(a, b));
    case TiebreakerCriterion.medianBuchholz:
      return _medianBuchholz(b).compareTo(_medianBuchholz(a));
    case TiebreakerCriterion.random:
      final ids = [a.participantId, b.participantId]..sort();
      final seed = randomSeed ^ ids[0].hashCode ^ (ids[1].hashCode << 1);
      final draw = Random(seed).nextInt(2) == 0 ? -1 : 1;
      return a.participantId == ids[0] ? draw : -draw;
  }
}

int _buchholz(ParticipantStats p) => p.opponentIds
    .fold(0, (s, id) => s + (p.opponentTotalPointsLookup[id] ?? 0));

int _buchholzMinusH2H(ParticipantStats p, ParticipantStats other) =>
    _buchholz(p) - (p.headToHeadLookup[other.participantId] ?? 0);

int _medianBuchholz(ParticipantStats p) {
  if (p.opponentIds.length < 2) return _buchholz(p);
  final values = [
    for (final id in p.opponentIds) p.opponentTotalPointsLookup[id] ?? 0,
  ]..sort();
  return values.sublist(1, values.length - 1).fold(0, (s, v) => s + v);
}
