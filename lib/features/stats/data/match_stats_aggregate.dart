import 'package:flutter/foundation.dart';
import 'package:kubb_app/features/match/data/match_models.dart';

/// Aggregate over finalized multi-player matches for the current caller.
/// All counts are derived from each [MatchSummary]'s `callerOutcome`; the
/// UI layer is purely presentational.
@immutable
class MatchStatsAggregate {
  const MatchStatsAggregate({
    required this.totalMatches,
    required this.wins,
    required this.losses,
    required this.ties,
    required this.recentMatches,
  });

  /// Folds a list of finalized [MatchSummary] rows into counts plus a
  /// capped "recent matches" projection. The input is expected to already
  /// be sorted by `startedAt` desc (as returned by `match_list_for_caller`).
  factory MatchStatsAggregate.from(List<MatchSummary> finalizedMatches) {
    var wins = 0;
    var losses = 0;
    var ties = 0;
    for (final match in finalizedMatches) {
      switch (match.callerOutcome) {
        case 'won':
          wins++;
        case 'lost':
          losses++;
        case 'tie':
          ties++;
        default:
          break;
      }
    }

    final recent = finalizedMatches.length <= _recentLimit
        ? List<MatchSummary>.unmodifiable(finalizedMatches)
        : List<MatchSummary>.unmodifiable(
            finalizedMatches.take(_recentLimit),
          );

    return MatchStatsAggregate(
      totalMatches: finalizedMatches.length,
      wins: wins,
      losses: losses,
      ties: ties,
      recentMatches: recent,
    );
  }

  static const empty = MatchStatsAggregate(
    totalMatches: 0,
    wins: 0,
    losses: 0,
    ties: 0,
    recentMatches: <MatchSummary>[],
  );

  static const int _recentLimit = 10;

  final int totalMatches;
  final int wins;
  final int losses;
  final int ties;
  final List<MatchSummary> recentMatches;

  bool get isEmpty => totalMatches == 0;

  /// Win rate as a percentage 0..100. Ties are excluded from the
  /// denominator; returns 0 when there are no decisive matches.
  int get winRatePercent {
    final decided = wins + losses;
    if (decided == 0) return 0;
    return ((wins * 100) / decided).round();
  }
}
