import 'package:kubb_domain/src/tournament/skv_tour_points.dart';
import 'package:meta/meta.dart';

/// Immutable final-ranking entry for a single participant.
///
/// Pairs a participant with their 1-based competition [rank] and the SKV
/// tour points awarded for that rank (computed by the Phase-A engine).
@immutable
class SkvPlacement {
  /// Creates a placement value object.
  const SkvPlacement({
    required this.participantId,
    required this.rank,
    required this.points,
  });

  /// Stable identifier of the rated participant (team or individual).
  final String participantId;

  /// 1-based competition rank. Tied participants share the same rank.
  final int rank;

  /// SKV tour points for [rank], from `skvPointsForPlacement`.
  final int points;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkvPlacement &&
          other.participantId == participantId &&
          other.rank == rank &&
          other.points == points;

  @override
  int get hashCode => Object.hash(participantId, rank, points);

  @override
  String toString() =>
      'SkvPlacement(participantId: $participantId, rank: $rank, '
      'points: $points)';
}

/// Computes the bracket-agnostic final ranking over an ordered list of tiers.
///
/// A *tier* is a list of equally-placed participant ids. [tiers] is ordered
/// best-first and must cover every participant exactly once (the KO tiers
/// followed by the non-qualified preliminary-round tail).
///
/// Standard competition ranking: the rank of tier `i` is
/// `1 + sum of the sizes of tiers 0..i-1`. All ids inside one tier share that
/// rank, and the next tier jumps by the FULL size of its predecessor (not by
/// one) — after a tier of size `k` at rank `r` the next tier sits at rank
/// `r + k`.
///
/// Points per participant come exclusively from
/// `skvPointsForPlacement(ctx: ctx, placement: rank, koRankCount: koRankCount,
/// pMin: pMin)`; equal ranks therefore yield identical points. [koRankCount]
/// (the number of top ranks the KO bracket determines, i.e. the boundary for
/// the preliminary-round tail) and [pMin] are passed through unchanged.
///
/// The result is concatenated in tier order, preserving the given id order
/// within each tier (deterministic and stable).
///
/// Throws [ArgumentError] if [tiers] is empty, if any tier is empty, if a
/// participant id appears in more than one tier, or if the total number of
/// ids does not equal `ctx.fieldSize`. Validation runs in full before any
/// point computation, so a failure produces no partial result. The Phase-A
/// invariants of `skvPointsForPlacement` (`koRankCount` in `4..N`, `placement`
/// in `1..N`) remain in force.
List<SkvPlacement> computeFinalRanking({
  required SkvTournamentContext ctx,
  required List<List<String>> tiers,
  required int koRankCount,
  int pMin = 3,
}) {
  // --- Validation (runs fully before any point computation) ---
  if (tiers.isEmpty) {
    throw ArgumentError.value(tiers, 'tiers', 'must not be empty');
  }

  var total = 0;
  final seen = <String>{};
  for (final tier in tiers) {
    if (tier.isEmpty) {
      throw ArgumentError.value(tiers, 'tiers', 'a tier must not be empty');
    }
    for (final id in tier) {
      if (!seen.add(id)) {
        throw ArgumentError.value(
          id,
          'tiers',
          'duplicate participantId across tiers',
        );
      }
    }
    total += tier.length;
  }

  if (total != ctx.fieldSize) {
    throw ArgumentError.value(
      total,
      'tiers',
      'sum of tier sizes must equal ctx.fieldSize (${ctx.fieldSize})',
    );
  }

  // --- Competition ranking + point lookup ---
  final placements = <SkvPlacement>[];
  var rank = 1;
  for (final tier in tiers) {
    final points = skvPointsForPlacement(
      ctx: ctx,
      placement: rank,
      koRankCount: koRankCount,
      pMin: pMin,
    );
    for (final id in tier) {
      placements.add(
        SkvPlacement(participantId: id, rank: rank, points: points),
      );
    }
    // Next tier jumps by the full size of this tier (competition ranking).
    rank += tier.length;
  }

  return placements;
}

/// Derives the SKV league from a tournament's master data.
///
/// Rules, in priority order:
/// - [teamSize] `== 1` ⇒ [SkvLeague.einzel] (regardless of
///   [leagueCategories]).
/// - otherwise: contains `'C'` AND neither `'A'` nor `'B'` ⇒ [SkvLeague.c].
/// - otherwise ⇒ [SkvLeague.a] (A/B both map to `a`, since B uses the same
///   reference size as A; the empty set with `teamSize > 1` also maps to `a`).
///
/// The category comparison is case-insensitive against `'A'`/`'B'`/`'C'`.
SkvLeague skvLeagueFromTournament({
  required int teamSize,
  required Set<String> leagueCategories,
}) {
  if (teamSize == 1) {
    return SkvLeague.einzel;
  }
  final upper = leagueCategories.map((c) => c.toUpperCase()).toSet();
  if (upper.contains('C') && !upper.contains('A') && !upper.contains('B')) {
    return SkvLeague.c;
  }
  return SkvLeague.a;
}
