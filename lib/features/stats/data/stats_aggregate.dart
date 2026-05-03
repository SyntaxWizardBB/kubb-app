import 'package:flutter/foundation.dart';

/// Lightweight projection of a single completed session for the stats list.
@immutable
class StatsSessionRow {
  const StatsSessionRow({
    required this.sessionId,
    required this.completedAt,
    required this.distanceMeters,
    required this.hitRatePercent,
    required this.totalThrows,
  });

  final String sessionId;
  final DateTime completedAt;
  final double distanceMeters;
  final int hitRatePercent;
  final int totalThrows;
}

/// Result of `StatsRepository.computeAggregate`. All counts and rates already
/// respect the active filter; UI is purely presentational.
@immutable
class StatsAggregate {
  const StatsAggregate({
    required this.totalSessions,
    required this.totalThrows,
    required this.hitRatePercent,
    required this.longestHitStreak,
    required this.bestHitRatePercent,
    required this.bestHitRateDistance,
    required this.mostThrowsInOneDay,
    required this.trendPoints,
    required this.sessionRows,
  });

  factory StatsAggregate.empty() => const StatsAggregate(
        totalSessions: 0,
        totalThrows: 0,
        hitRatePercent: 0,
        longestHitStreak: 0,
        bestHitRatePercent: 0,
        bestHitRateDistance: null,
        mostThrowsInOneDay: 0,
        trendPoints: <int>[],
        sessionRows: <StatsSessionRow>[],
      );

  final int totalSessions;
  final int totalThrows;
  final int hitRatePercent;
  final int longestHitStreak;
  final int bestHitRatePercent;
  final double? bestHitRateDistance;
  final int mostThrowsInOneDay;
  final List<int> trendPoints;
  final List<StatsSessionRow> sessionRows;

  bool get isEmpty => totalSessions == 0;
}
