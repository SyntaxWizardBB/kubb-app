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

/// Lightweight projection of a single completed finisseur session.
@immutable
class FinisseurSessionRow {
  const FinisseurSessionRow({
    required this.sessionId,
    required this.completedAt,
    required this.field,
    required this.base,
    required this.sticksUsed,
    required this.success,
  });

  final String sessionId;
  final DateTime completedAt;
  final int field;
  final int base;
  final int sticksUsed;
  final bool success;
}

/// Aggregate over completed finisseur sessions for one player. Mirrors the
/// shape of [StatsAggregate] but exposes finisseur-specific counters such as
/// long dubbies, helis and king hit-rate. UI is purely presentational.
@immutable
class FinisseurStatsAggregate {
  const FinisseurStatsAggregate({
    required this.totalSessions,
    required this.successCount,
    required this.totalSticks,
    required this.longDubbiesPerSession,
    required this.heliCount,
    required this.penaltyCount,
    required this.kingAttempts,
    required this.kingHits,
    required this.successTrendPercent,
    required this.sessionRows,
  });

  factory FinisseurStatsAggregate.empty() => const FinisseurStatsAggregate(
        totalSessions: 0,
        successCount: 0,
        totalSticks: 0,
        longDubbiesPerSession: 0,
        heliCount: 0,
        penaltyCount: 0,
        kingAttempts: 0,
        kingHits: 0,
        successTrendPercent: <int>[],
        sessionRows: <FinisseurSessionRow>[],
      );

  final int totalSessions;
  final int successCount;
  final int totalSticks;
  final double longDubbiesPerSession;
  final int heliCount;
  final int penaltyCount;
  final int kingAttempts;
  final int kingHits;
  final List<int> successTrendPercent;
  final List<FinisseurSessionRow> sessionRows;

  bool get isEmpty => totalSessions == 0;
  int get successRatePercent =>
      totalSessions == 0 ? 0 : ((successCount / totalSessions) * 100).round();
  double get averageSticks =>
      totalSessions == 0 ? 0 : totalSticks / totalSessions;
  int get kingHitRatePercent =>
      kingAttempts == 0 ? 0 : ((kingHits / kingAttempts) * 100).round();
}
