import 'package:kubb_domain/src/tournament/tournament_setup.dart';
import 'package:meta/meta.dart';

/// One match within a round that needs a pitch number assigned.
///
/// [key] is whatever identifies the match in the round (e.g.
/// `matchNumberInRound` or `bracket_position`); it is used verbatim as the
/// key of the returned map. [order] is the seeding/bracket rank used to
/// decide which pitch the match draws under
/// [PitchSortStrategy.topSeedsLowNumbers] — the LOWEST [order] is the
/// highest-ranked pairing. [group] is the pool/group label for group play;
/// it is null for bracket/KO rounds.
@immutable
final class RoundMatch {
  const RoundMatch({
    required this.key,
    required this.order,
    this.group,
  });

  /// Match identifier; becomes the key of the assignment map.
  final int key;

  /// Seeding/bracket rank within the round (lower = stronger pairing).
  final int order;

  /// Pool/group label, or null for bracket play.
  final String? group;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RoundMatch &&
          other.key == key &&
          other.order == order &&
          other.group == group;

  @override
  int get hashCode => Object.hash(key, order, group);
}

/// Assigns a pitch number to every match of a single round.
///
/// Rules (spec §"TournierStart"/§pitch + [PitchPlan]):
/// - Pitches are drawn from [PitchPlan.availablePitches]. For group play
///   with a non-empty [PitchPlan.groupAssignment], a group's matches draw
///   ONLY from that group's assigned pitches (intersected with the
///   plan-wide available list to keep the plan authoritative); the group
///   list's own ordering is preserved.
/// - [PitchSortStrategy.topSeedsLowNumbers]: matches are ranked by
///   [RoundMatch.order] ascending (lowest order = highest-ranked pairing)
///   and handed the available pitches from the front, so the strongest
///   pairing gets the lowest pitch number.
/// - [PitchSortStrategy.manual]: matches are taken in [PitchPlan.order]'s
///   pitch ordering — i.e. the pitches are consumed exactly as
///   [PitchPlan.availablePitches] yields them (which already honours
///   [PitchPlan.order]), while the matches are visited in their given list
///   order (caller-defined). No reordering by [RoundMatch.order] happens.
///
/// Wrap/queue policy (round-robin and any round with more matches than
/// pitches): pitches are assigned round-robin by index — match `i` (in the
/// visiting order described above) gets pitch `pitches[i % pitches.length]`.
/// This is deterministic and means concurrent matches that fit on distinct
/// pitches always get distinct pitches; only the overflow wraps onto the
/// lowest pitches again (later "waves" of the same round reuse the front of
/// the pitch list). The same policy applies per group.
///
/// An empty plan (no available pitches, and — for grouped matches — no
/// pitches available to the group) yields NO entry for the affected
/// matches, so the result may be smaller than [matches]. Pure and
/// deterministic: identical inputs always produce identical output.
Map<int, int> assignPitches(
  List<RoundMatch> matches,
  PitchPlan plan,
) {
  final result = <int, int>{};
  if (matches.isEmpty) return result;

  final allPitches = plan.availablePitches();
  final hasGroupAssignment = plan.groupAssignment.isNotEmpty;

  // Partition matches by the pitch pool they draw from. Bracket matches
  // (group == null) or a plan without group assignment all share the
  // plan-wide pool under the synthetic key `null`.
  final byPool = <String?, List<RoundMatch>>{};
  for (final match in matches) {
    final poolKey =
        (hasGroupAssignment && match.group != null) ? match.group : null;
    (byPool[poolKey] ??= <RoundMatch>[]).add(match);
  }

  for (final entry in byPool.entries) {
    final poolKey = entry.key;
    final poolMatches = entry.value;

    final pitches = _pitchesForPool(
      poolKey: poolKey,
      plan: plan,
      allPitches: allPitches,
    );
    if (pitches.isEmpty) continue; // empty plan -> no assignment

    // Determine the order in which matches consume pitches.
    final ordered = List<RoundMatch>.of(poolMatches);
    if (plan.sortStrategy == PitchSortStrategy.topSeedsLowNumbers) {
      // Stable sort by order ascending; ties keep input order.
      ordered.sort((a, b) => a.order.compareTo(b.order));
    }
    // manual -> keep the caller-provided list order.

    for (var i = 0; i < ordered.length; i++) {
      result[ordered[i].key] = pitches[i % pitches.length];
    }
  }

  return result;
}

/// The ordered pitch list a pool draws from. For a group pool, restrict to
/// the group's assigned pitches while preserving the group list's order and
/// keeping the plan-wide list authoritative (drop unknown numbers).
List<int> _pitchesForPool({
  required String? poolKey,
  required PitchPlan plan,
  required List<int> allPitches,
}) {
  if (poolKey == null) return allPitches;
  final assigned = plan.groupAssignment[poolKey];
  if (assigned == null || assigned.isEmpty) {
    // Group has no dedicated pitches configured -> no assignment.
    return const <int>[];
  }
  final allowed = allPitches.toSet();
  return assigned.where(allowed.contains).toList();
}
