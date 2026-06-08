import 'dart:math';

/// League / category of a tournament for the SKV tour-points system.
///
/// Each league has a reference field size `B` (see [_referenceSize]): the
/// winner of a tournament with exactly `B` participants scores 100 points.
enum SkvLeague {
  /// Main tournament, league A (reference size `B = 10`).
  a,

  /// Main tournament, league B (reference size `B = 10`).
  b,

  /// Side tournament, league C (reference size `B = 20`).
  c,

  /// Individual ranking (reference size `B = 40`).
  einzel,
}

/// Reference field size `B` per league (spec §2). The winner of a tournament
/// of size `B` scores exactly 100 points; at `3·B` the winner scores 200.
int _referenceSize(SkvLeague league) {
  switch (league) {
    case SkvLeague.a:
      return 10;
    case SkvLeague.b:
      return 10;
    case SkvLeague.c:
      return 20;
    case SkvLeague.einzel:
      return 40;
  }
}

/// Fixed Masters multiplier per league (spec §5): A/C ×2, B ×1.
///
/// The spec is silent about `einzel` in the Masters case; we choose the
/// deterministic, neutral default of `1` (not covered by a mandatory test).
int _mastersMultiplier(SkvLeague league) {
  switch (league) {
    case SkvLeague.a:
      return 2;
    case SkvLeague.c:
      return 2;
    case SkvLeague.b:
      return 1;
    case SkvLeague.einzel:
      return 1;
  }
}

/// Immutable input context for the SKV tour-points engine.
class SkvTournamentContext {
  /// Creates a tournament context.
  ///
  /// [fieldSize] is `N`, the number of rated participants. [league] selects
  /// the reference size and Masters multiplier. [isMasters] switches to the
  /// fixed (non field-scaled) Masters winner points.
  const SkvTournamentContext({
    required this.fieldSize,
    required this.league,
    this.isMasters = false,
  });

  /// `N` — number of rated participants (teams or individual players).
  final int fieldSize;

  /// League / category of the tournament.
  final SkvLeague league;

  /// Whether this is a Masters tournament (fixed winner points, spec §5).
  final bool isMasters;
}

/// Computes the winner points `W` for the given [ctx] (spec §2, §5).
///
/// Normal tournaments scale linearly with the field size:
/// `round(100 * (1 + (N - B) / (2 * B)))`, with `B` the league reference
/// size. Masters tournaments use the fixed value `100 * leagueMultiplier`
/// (not field-scaled).
///
/// Throws [ArgumentError] if `fieldSize < 1`.
int skvWinnerPoints(SkvTournamentContext ctx) {
  if (ctx.fieldSize < 1) {
    throw ArgumentError.value(
      ctx.fieldSize,
      'fieldSize',
      'must be >= 1',
    );
  }
  if (ctx.isMasters) {
    return 100 * _mastersMultiplier(ctx.league);
  }
  final b = _referenceSize(ctx.league);
  return (100 * (1.0 + (ctx.fieldSize - b) / (2 * b))).round();
}

/// Placement factors for ranks 1–4 (spec §3.1).
const List<double> _topFactors = <double>[1, 0.8, 0.65, 0.5];

/// Computes the KO-tier points for a [placement] in `5..koRankCount`
/// (spec §3.2).
///
/// Tier index `t = max(1, floor(log2(placement - 1)) - 1)`; the points are
/// `round(W * 0.5^(t + 1))`. Concretely: ranks 5–8 → 0.25·W, ranks 9–16 →
/// 0.125·W, ranks 17–32 → 0.0625·W.
int _koTierPoints(int placement, int winnerPoints) {
  final t = max(1, (log(placement - 1) / ln2).floor() - 1);
  return (winnerPoints * pow(0.5, t + 1)).round();
}

/// Computes the SKV tour points for a single participant (spec §3).
///
/// [placement] is the 1-based final rank. [koRankCount] is the number of
/// top ranks determined by the KO bracket (= bracket size); ranks above it
/// form the preliminary-round tail. [pMin] is the minimum number of points
/// for the last place (default `3`).
///
/// Throws [ArgumentError] if `fieldSize < 1`, if [placement] is outside
/// `1..N`, or if [koRankCount] is outside `4..N`.
int skvPointsForPlacement({
  required SkvTournamentContext ctx,
  required int placement,
  required int koRankCount,
  int pMin = 3,
}) {
  final n = ctx.fieldSize;
  if (n < 1) {
    throw ArgumentError.value(n, 'fieldSize', 'must be >= 1');
  }
  if (placement < 1 || placement > n) {
    throw ArgumentError.value(
      placement,
      'placement',
      'must be in 1..$n',
    );
  }
  if (koRankCount < 4 || koRankCount > n) {
    throw ArgumentError.value(
      koRankCount,
      'koRankCount',
      'must be in 4..$n',
    );
  }

  final w = skvWinnerPoints(ctx);

  // Ranks 1-4: fixed factors.
  if (placement <= 4) {
    return (w * _topFactors[placement - 1]).round();
  }

  // Ranks 5..koRankCount: halving KO tiers.
  if (placement <= koRankCount) {
    return _koTierPoints(placement, w);
  }

  // Ranks > koRankCount: linear preliminary-round tail down to [pMin].
  // `pLast` is the KO-tier value at the last KO rank, computed from the tier
  // formula (never hard-coded). `m > 0` here because this branch is only
  // entered when placement > koRankCount, i.e. koRankCount < n.
  final pLast = _koTierPoints(koRankCount, w);
  final m = n - koRankCount;
  return (pLast - (pLast - pMin) * (placement - koRankCount) / m).round();
}
