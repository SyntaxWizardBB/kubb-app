import 'package:meta/meta.dart';

enum SetWinner { teamA, teamB }

@immutable
class SetScore {
  SetScore({
    required this.basekubbsKnockedByA,
    required this.basekubbsKnockedByB,
    required this.winner,
  }) {
    if (basekubbsKnockedByA < 0 || basekubbsKnockedByB < 0) {
      throw ArgumentError('basekubb counts must be non-negative');
    }
  }

  final int basekubbsKnockedByA;
  final int basekubbsKnockedByB;
  final SetWinner winner;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SetScore &&
          other.basekubbsKnockedByA == basekubbsKnockedByA &&
          other.basekubbsKnockedByB == basekubbsKnockedByB &&
          other.winner == winner;

  @override
  int get hashCode =>
      Object.hash(basekubbsKnockedByA, basekubbsKnockedByB, winner);
}

@immutable
class MatchEkcScore {
  MatchEkcScore(List<SetScore> sets)
      : sets = List<SetScore>.unmodifiable(sets),
        pointsForA = sets.fold<int>(
          0,
          (acc, s) =>
              acc + s.basekubbsKnockedByA + (s.winner == SetWinner.teamA ? 3 : 0),
        ),
        pointsForB = sets.fold<int>(
          0,
          (acc, s) =>
              acc + s.basekubbsKnockedByB + (s.winner == SetWinner.teamB ? 3 : 0),
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
