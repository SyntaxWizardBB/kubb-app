import 'dart:math';

import 'package:meta/meta.dart';

/// Neutral default ELO for participants without rating history
/// (P6_RULES_DECISIONS §I, `elo_default = 1200`).
const int kEloDefault = 1200;

/// How a team's seed rating is aggregated from its members' ELO values
/// (P6_RULES_DECISIONS §I, `team_rating_mode`). A solo player is treated as a
/// one-member team, so the mode is irrelevant for solo participants.
///
/// The strategy is exposed as an enum so the future weighted league variant
/// fits without touching the seeding algorithm.
enum TeamRatingMode {
  /// Plain sum of the members' ELO. Binding default per §I.
  sum,

  /// Arithmetic mean of the members' ELO.
  average,

  /// `avg(member_elo) * effective_size`, where a 2-player team counts as 2/3
  /// of a head (README "2-player teams weighted at 2/3"). For other sizes the
  /// effective size equals the head count, so this reduces to [sum].
  weighted,
}

/// A tournament participant to be seeded from ELO.
///
/// A solo player is modelled as a team with a single member ELO. Missing /
/// `null` member ratings are substituted with [kEloDefault] at aggregation
/// time, so callers may pass raw rating lookups without pre-filling defaults.
@immutable
final class EloParticipant {
  /// A team (or group) participant with the given member ELO ratings. A `null`
  /// entry in [memberElos] is treated as a missing rating ([kEloDefault]).
  const EloParticipant.team({
    required this.id,
    required this.memberElos,
  });

  /// A solo participant with a single ELO. A `null` [elo] is treated as a
  /// missing rating ([kEloDefault]).
  EloParticipant.solo({required this.id, int? elo})
      : memberElos = [elo];

  /// Stable participant id (matches the ids consumed by `seedFromStandings`
  /// and `setSeeding`).
  final String id;

  /// Member ELO ratings. `null` entries mean "no rating recorded".
  final List<int?> memberElos;

  /// `true` when no member has a recorded rating, i.e. every entry is `null`.
  /// Such participants are sorted to the bottom of the seed order per §I.
  bool get hasNoHistory => memberElos.every((e) => e == null);

  /// Aggregated seed rating per [mode], substituting [kEloDefault] for missing
  /// member ratings.
  double seedRating(TeamRatingMode mode) {
    final resolved = [for (final e in memberElos) (e ?? kEloDefault).toDouble()];
    if (resolved.isEmpty) return kEloDefault.toDouble();
    final total = resolved.fold<double>(0, (s, e) => s + e);
    switch (mode) {
      case TeamRatingMode.sum:
        return total;
      case TeamRatingMode.average:
        return total / resolved.length;
      case TeamRatingMode.weighted:
        final avg = total / resolved.length;
        // 2-player teams count as 2/3 of a head (league convention); other
        // sizes use the raw head count, collapsing to the plain sum.
        final effectiveSize =
            resolved.length == 2 ? resolved.length * (2 / 3) : resolved.length;
        return avg * effectiveSize;
    }
  }
}

/// Compute a deterministic, ELO-based seed order (P6_RULES_DECISIONS §I).
///
/// Pure: [participants] is not mutated; a fresh list is allocated and sorted.
/// Returns participant ids in best-first order — index 0 is seed 1.
///
/// Ordering rules:
///  - Higher [EloParticipant.seedRating] (under [mode]) seeds better.
///  - Participants with no rating history at all ([EloParticipant.hasNoHistory])
///    sort to the bottom regardless of their defaulted rating.
///  - Remaining ties are broken deterministically: a fixed-[randomSeed] draw
///    (reproducible per tournament) and finally the participant id, so the
///    result is a total order and identical across repeated calls.
List<String> seedFromElo(
  List<EloParticipant> participants, {
  TeamRatingMode mode = TeamRatingMode.sum,
  int randomSeed = 0,
}) {
  final sorted = [...participants]
    ..sort((a, b) => _compare(a, b, mode, randomSeed));
  return [for (final p in sorted) p.id];
}

/// Compute a 1-based `seed_position → participantId` map from ELO, matching the
/// shape consumed by `setSeeding` / `applyManualOverride`.
Map<int, String> seedMapFromElo(
  List<EloParticipant> participants, {
  TeamRatingMode mode = TeamRatingMode.sum,
  int randomSeed = 0,
}) {
  final ordered = seedFromElo(participants, mode: mode, randomSeed: randomSeed);
  return {for (var i = 0; i < ordered.length; i++) i + 1: ordered[i]};
}

int _compare(
  EloParticipant a,
  EloParticipant b,
  TeamRatingMode mode,
  int randomSeed,
) {
  // No-history participants sort last (§I), independent of their default rating.
  if (a.hasNoHistory != b.hasNoHistory) {
    return a.hasNoHistory ? 1 : -1;
  }
  // Higher rating = better seed → descending.
  final byRating = b.seedRating(mode).compareTo(a.seedRating(mode));
  if (byRating != 0) return byRating;
  // Deterministic tie-break: reproducible draw keyed on the sorted id pair.
  final ids = [a.id, b.id]..sort();
  final seed = randomSeed ^ ids[0].hashCode ^ (ids[1].hashCode << 1);
  final draw = Random(seed).nextInt(2) == 0 ? -1 : 1;
  final byDraw = a.id == ids[0] ? draw : -draw;
  if (byDraw != 0) return byDraw;
  // Final stable fallback (also covers a.id == b.id).
  return a.id.compareTo(b.id);
}
