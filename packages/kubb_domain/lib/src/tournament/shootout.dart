import 'package:kubb_domain/src/tournament/tiebreaker.dart';
import 'package:meta/meta.dart';

/// Shoot-Out tiebreak domain (P6, docs/P6_SHOOTOUT_TIEBREAK.md).
///
/// The shoot-out is the *last* preliminary-phase tiebreak stage. It only
/// settles **qualification-relevant** ties: groups of participants who are
/// exactly equal on every regular criterion of the configured
/// [TiebreakerChain] *and* whose relative order decides who qualifies for the
/// knockout (the group straddles, or sits exactly on, the qualifier cut line).
/// Ties that are purely cosmetic — entirely above the cut line (everyone
/// already in) or entirely below it (everyone already out) — never trigger a
/// shoot-out.
///
/// The shoot-out result records only *which side won* (no time, no score).
/// From the recorded winners a unique ordering of the tied participants is
/// derived, which replaces the arbitrary participantId fallback for that
/// group. This file is pure Dart (no Flutter / UI / server imports) and fully
/// deterministic: identical inputs always yield identical outputs.

/// Immutable value object: the recorded shoot-out outcome for one tie group.
///
/// [tiedParticipantIds] is the unordered set of participants that were exactly
/// tied. [orderedWinners] is the resolved order, best (qualifies first) to
/// worst, as decided on-site. A non-empty [orderedWinners] must be a
/// permutation of [tiedParticipantIds]; an empty [orderedWinners] models a
/// shoot-out that has been *requested but not yet resolved* (pending).
///
/// For a two-team tie a single recorded winner is enough; for three or more
/// teams the full ordering (e.g. derived from pairwise winners) is recorded so
/// the open qualifier slots can be filled without residual ambiguity.
@immutable
class ShootoutResult {
  ShootoutResult({
    required List<String> tiedParticipantIds,
    required List<String> orderedWinners,
  })  : tiedParticipantIds = List.unmodifiable(tiedParticipantIds),
        orderedWinners = List.unmodifiable(orderedWinners) {
    if (tiedParticipantIds.length < 2) {
      throw ArgumentError.value(
        tiedParticipantIds,
        'tiedParticipantIds',
        'a shoot-out tie group needs at least two participants',
      );
    }
    if (tiedParticipantIds.toSet().length != tiedParticipantIds.length) {
      throw ArgumentError.value(
        tiedParticipantIds,
        'tiedParticipantIds',
        'must not contain duplicates',
      );
    }
    if (orderedWinners.isNotEmpty) {
      if (orderedWinners.length != tiedParticipantIds.length ||
          orderedWinners.toSet().length != orderedWinners.length ||
          !orderedWinners.toSet().containsAll(tiedParticipantIds)) {
        throw ArgumentError.value(
          orderedWinners,
          'orderedWinners',
          'when set, must be a permutation of tiedParticipantIds',
        );
      }
    }
  }

  factory ShootoutResult.fromJson(Map<String, dynamic> json) => ShootoutResult(
        tiedParticipantIds: [
          for (final id in json['tied_participant_ids'] as List)
            id as String,
        ],
        orderedWinners: [
          for (final id in (json['ordered_winners'] as List? ?? const []))
            id as String,
        ],
      );

  /// The participants that were exactly tied (insertion order is not
  /// significant for equality; it is normalised on construction only as far as
  /// the caller passes it).
  final List<String> tiedParticipantIds;

  /// Resolved order, best first. Empty while the shoot-out is still pending.
  final List<String> orderedWinners;

  /// True when an on-site result has been recorded and the group can be
  /// ordered deterministically.
  bool get isResolved => orderedWinners.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'tied_participant_ids': tiedParticipantIds,
        'ordered_winners': orderedWinners,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShootoutResult &&
          _listEquals(other.tiedParticipantIds, tiedParticipantIds) &&
          _listEquals(other.orderedWinners, orderedWinners);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(tiedParticipantIds),
        Object.hashAll(orderedWinners),
      );

  @override
  String toString() => 'ShootoutResult(tied: $tiedParticipantIds, '
      'order: $orderedWinners)';
}

/// A detected qualification-relevant tie group that requires a shoot-out.
///
/// [participantIds] are the tied participants in their pre-shoot-out ranked
/// order (the order the chain produced before falling through to the ID
/// fallback). [startRank] is the zero-based rank of the first member in the
/// overall ranking; the group occupies ranks `startRank ..
/// startRank + participantIds.length - 1`.
@immutable
class ShootoutGroup {
  ShootoutGroup({
    required List<String> participantIds,
    required this.startRank,
  }) : participantIds = List.unmodifiable(participantIds);

  final List<String> participantIds;
  final int startRank;

  /// Whether [rank] (zero-based) falls inside this group.
  bool containsRank(int rank) =>
      rank >= startRank && rank < startRank + participantIds.length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShootoutGroup &&
          other.startRank == startRank &&
          _listEquals(other.participantIds, participantIds);

  @override
  int get hashCode =>
      Object.hash(startRank, Object.hashAll(participantIds));

  @override
  String toString() =>
      'ShootoutGroup(startRank: $startRank, ids: $participantIds)';
}

/// Detects qualification-relevant tie groups in an already-ranked list.
///
/// [ranking] must be the final ranking produced by [chain] (ascending rank,
/// best first). [qualifierCount] is the cut line: ranks `0 .. qualifierCount-1`
/// qualify. A tie group is a maximal run of consecutive entries that are equal
/// on *every* regular criterion of [chain] — exactly the place where
/// [TiebreakerChain.compare] would otherwise fall through to the deterministic
/// participantId fallback.
///
/// Only groups that **straddle the cut line** are returned: the group must
/// contain at least one member at a rank `< qualifierCount` (would-be
/// qualifier) and at least one member at a rank `>= qualifierCount` (would-be
/// non-qualifier). Such a group decides who takes the last open qualifier
/// slot(s). Groups lying entirely above the cut line (all already qualify) or
/// entirely below it (all already out) are cosmetic and are skipped.
///
/// Equality uses the same criterion comparison logic the chain itself uses
/// (via [TiebreakerChain.compareCriterion]) so the shoot-out trigger never
/// diverges from the chain's own notion of "tied". Deterministic: no wall
/// clock, no unseeded randomness.
List<ShootoutGroup> detectShootoutGroups(
  List<ParticipantStats> ranking,
  int qualifierCount,
  TiebreakerChain chain,
) {
  final groups = <ShootoutGroup>[];
  if (qualifierCount <= 0 || qualifierCount >= ranking.length) {
    // Nothing qualifies, or everyone qualifies: there is no meaningful cut
    // line, so no tie can be qualification-relevant.
    return groups;
  }

  var i = 0;
  while (i < ranking.length - 1) {
    var j = i;
    while (j + 1 < ranking.length &&
        _allCriteriaEqualForShootout(ranking[j], ranking[j + 1], chain)) {
      j++;
    }
    if (j > i) {
      // Group spans ranks [i, j]. It is qualification-relevant iff it straddles
      // the cut line: some member is in (rank < qualifierCount) and some member
      // is out (rank >= qualifierCount).
      final straddlesCut = i < qualifierCount && j >= qualifierCount;
      if (straddlesCut) {
        groups.add(ShootoutGroup(
          participantIds: [
            for (var k = i; k <= j; k++) ranking[k].participantId,
          ],
          startRank: i,
        ));
      }
      i = j + 1;
    } else {
      i++;
    }
  }
  return groups;
}

/// Result of [resolveWithShootouts]: the finalised qualifier list plus any tie
/// groups that are still pending an on-site shoot-out result.
@immutable
class ShootoutResolution {
  ShootoutResolution({
    required List<String> qualifiers,
    required List<ShootoutGroup> pending,
  })  : qualifiers = List.unmodifiable(qualifiers),
        pending = List.unmodifiable(pending);

  /// Finalised qualifier participantIds. When [pending] is empty this is the
  /// authoritative cut of length `qualifierCount`. While groups are pending the
  /// list is truncated to the authoritative prefix BEFORE the first contested
  /// rank: the contested slots are deliberately omitted rather than filled with
  /// the arbitrary participantId fallback (no silent ID fallback — see
  /// P6_SHOOTOUT_TIEBREAK §5). Callers must check [isFinal] before seeding a
  /// bracket from this list.
  final List<String> qualifiers;

  /// Qualification-relevant tie groups still awaiting a shoot-out result. The
  /// resolution intentionally does *not* fall back to the participantId order
  /// for these groups, neither in [pending] nor in [qualifiers].
  final List<ShootoutGroup> pending;

  bool get isFinal => pending.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShootoutResolution &&
          _listEquals(other.qualifiers, qualifiers) &&
          _listEquals(other.pending, pending);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(qualifiers), Object.hashAll(pending));
}

/// Resolves qualification-relevant ties using recorded shoot-out [results].
///
/// [ranking] is the chain-ordered ranking, [qualifierCount] the cut line.
/// [results] are the recorded shoot-out outcomes keyed by tie group (matched by
/// participant set). For every detected qualification-relevant group:
///   * if a matching *resolved* [ShootoutResult] is supplied, the group is
///     re-ordered by its [ShootoutResult.orderedWinners] (replacing the ID
///     fallback);
///   * otherwise the group is reported in [ShootoutResolution.pending] and the
///     contested ranks are omitted from [ShootoutResolution.qualifiers] (the
///     list is truncated at the first pending startRank — no silent ID
///     fallback).
///
/// Cosmetic ties (not straddling the cut line) keep the chain's existing order,
/// including its deterministic ID fallback, exactly as before. Deterministic.
ShootoutResolution resolveWithShootouts(
  List<ParticipantStats> ranking,
  int qualifierCount,
  TiebreakerChain chain,
  List<ShootoutResult> results,
) {
  final groups = detectShootoutGroups(ranking, qualifierCount, chain);
  // Work on a mutable copy of the participantId order.
  final order = [for (final s in ranking) s.participantId];
  final pending = <ShootoutGroup>[];

  for (final group in groups) {
    final result = _matchResult(group, results);
    if (result != null && result.isResolved) {
      // Re-place the group's participants by the recorded winner order.
      for (var k = 0; k < group.participantIds.length; k++) {
        order[group.startRank + k] = result.orderedWinners[k];
      }
    } else {
      pending.add(group);
    }
  }

  // No silent ID fallback (P6_SHOOTOUT_TIEBREAK §5): when groups are still
  // pending, only ranks BEFORE the first contested startRank are authoritative.
  // Truncating there keeps the arbitrary participantId order out of the
  // qualifier list for the undecided slots — a future consumer that ignores
  // [isFinal] then under-seeds rather than seeding the ID-fallback winner.
  var authoritativeCount = qualifierCount;
  for (final group in pending) {
    if (group.startRank < authoritativeCount) {
      authoritativeCount = group.startRank;
    }
  }

  return ShootoutResolution(
    qualifiers: order.take(authoritativeCount).toList(),
    pending: pending,
  );
}

/// Finds the recorded result whose tied set matches [group]'s participants.
ShootoutResult? _matchResult(
  ShootoutGroup group,
  List<ShootoutResult> results,
) {
  final wanted = group.participantIds.toSet();
  for (final r in results) {
    if (r.tiedParticipantIds.toSet().length == wanted.length &&
        r.tiedParticipantIds.toSet().containsAll(wanted)) {
      return r;
    }
  }
  return null;
}

/// True when [a] and [b] tie on *every* regular criterion of [chain] — i.e. the
/// chain has nothing left to separate them except the participantId fallback.
/// Delegates to the chain's own criterion comparator so the shoot-out trigger
/// stays in lockstep with [TiebreakerChain]'s ranking semantics.
bool _allCriteriaEqualForShootout(
  ParticipantStats a,
  ParticipantStats b,
  TiebreakerChain chain,
) {
  for (final c in chain.order) {
    if (chain.compareCriterion(c, a, b) != 0) return false;
  }
  return true;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
