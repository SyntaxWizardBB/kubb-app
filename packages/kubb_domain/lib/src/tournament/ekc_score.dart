import 'package:kubb_domain/src/tournament/king_outcome.dart';
import 'package:meta/meta.dart';

enum SetWinner { teamA, teamB }

@immutable
class SetScore {
  SetScore({
    required this.basekubbsKnockedByA,
    required this.basekubbsKnockedByB,
    required this.winner,
    this.kingOutcome = const KingMissed(),
  }) {
    if (basekubbsKnockedByA < 0 || basekubbsKnockedByB < 0) {
      throw ArgumentError('basekubb counts must be non-negative');
    }
  }

  final int basekubbsKnockedByA;
  final int basekubbsKnockedByB;
  final SetWinner winner;

  /// Per R11-F-01: how the King was dealt with in this set. Defaults to
  /// [KingMissed] — the historical implicit behaviour, where the set ends
  /// on a regular win without crediting any king-points.
  final KingOutcome kingOutcome;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetScore &&
          other.basekubbsKnockedByA == basekubbsKnockedByA &&
          other.basekubbsKnockedByB == basekubbsKnockedByB &&
          other.winner == winner &&
          other.kingOutcome == kingOutcome;

  @override
  int get hashCode => Object.hash(
        basekubbsKnockedByA,
        basekubbsKnockedByB,
        winner,
        kingOutcome,
      );
}

/// Per R11-F-01: the EKC contribution of one set, decomposed into the
/// per-team points for A and B. A [KingTimedOut] outcome short-circuits
/// the set to a 0:0 contribution; otherwise basekubbs + 3-point winner
/// bonus apply, plus a single +1 king-point for the set winner on
/// [KingHitBy].
({int pointsA, int pointsB}) _setContribution(SetScore set) {
  return switch (set.kingOutcome) {
    KingTimedOut() => (pointsA: 0, pointsB: 0),
    KingHitBy() || KingMissed() => () {
        final winnerBonusA = set.winner == SetWinner.teamA ? 3 : 0;
        final winnerBonusB = set.winner == SetWinner.teamB ? 3 : 0;
        final kingBonusA = set.kingOutcome is KingHitBy &&
                set.winner == SetWinner.teamA
            ? 1
            : 0;
        final kingBonusB = set.kingOutcome is KingHitBy &&
                set.winner == SetWinner.teamB
            ? 1
            : 0;
        return (
          pointsA: set.basekubbsKnockedByA + winnerBonusA + kingBonusA,
          pointsB: set.basekubbsKnockedByB + winnerBonusB + kingBonusB,
        );
      }(),
  };
}

@immutable
class MatchEkcScore {
  MatchEkcScore(List<SetScore> sets)
      : sets = List<SetScore>.unmodifiable(sets),
        pointsForA = sets.fold<int>(
          0,
          (acc, s) => acc + _setContribution(s).pointsA,
        ),
        pointsForB = sets.fold<int>(
          0,
          (acc, s) => acc + _setContribution(s).pointsB,
        ),
        setsWonA = sets.where((s) => s.winner == SetWinner.teamA).length,
        setsWonB = sets.where((s) => s.winner == SetWinner.teamB).length;

  final List<SetScore> sets;
  final int pointsForA;
  final int pointsForB;
  final int setsWonA;
  final int setsWonB;

  SetWinner? get matchWinner {
    if (setsWonA == setsWonB) return null;
    return setsWonA > setsWonB ? SetWinner.teamA : SetWinner.teamB;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MatchEkcScore &&
          other.sets.length == sets.length &&
          _listEquals(other.sets, sets);

  @override
  int get hashCode => Object.hashAll(sets);

  static bool _listEquals(List<SetScore> a, List<SetScore> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

MatchEkcScore computeEkc(List<SetScore> sets) => MatchEkcScore(sets);
