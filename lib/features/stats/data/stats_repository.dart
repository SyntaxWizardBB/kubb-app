import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/dao/session_dao.dart';
import 'package:kubb_app/core/data/dao/session_event_dao.dart';
import 'package:kubb_app/features/stats/data/stats_aggregate.dart';
import 'package:kubb_app/features/stats/data/stats_filter.dart';

const _kindHit = 'hit';
const _kindMiss = 'miss';
const _kindHeli = 'heli';
const _maxSessionRows = 20;

/// Read-only aggregator over the existing `sessions` and `session_events`
/// tables. Loads everything for the player and reduces in memory — this is
/// fine for v1 (<500 sessions per player). See architecture doc for scale plan.
class StatsRepository {
  StatsRepository({
    required SessionDao sessionDao,
    required SessionEventDao eventDao,
  })  : _sessions = sessionDao,
        _events = eventDao;

  final SessionDao _sessions;
  final SessionEventDao _events;

  Future<StatsAggregate> computeAggregate({
    required String playerId,
    required StatsFilter filter,
    required bool heliTracking,
    DateTime? now,
  }) async {
    final all = await _sessions.allCompletedForPlayer(playerId);
    final cutoff = _cutoffFor(filter.dateRange, now ?? DateTime.now().toUtc());
    final filtered = all.where((s) {
      final ts = s.completedAt ?? s.startedAt;
      if (cutoff != null && ts.isBefore(cutoff)) return false;
      if (filter.distanceMeters != null &&
          (s.distanceMeters - filter.distanceMeters!).abs() > 0.001) {
        return false;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) return StatsAggregate.empty();

    final stats = <_PerSession>[];
    for (final s in filtered) {
      stats.add(await _summarise(s, heliTracking: heliTracking));
    }

    final totalThrows = stats.fold<int>(0, (a, x) => a + x.totalThrows);
    final divisor = stats.fold<int>(0, (a, x) => a + x.hits + x.misses);
    final hitsTotal = stats.fold<int>(0, (a, x) => a + x.hits);
    final hitRate = divisor == 0 ? 0 : ((hitsTotal / divisor) * 100).round();

    final best = stats.reduce(
      (a, b) => b.hitRatePercent > a.hitRatePercent ? b : a,
    );
    final longestStreak =
        stats.map((s) => s.longestHitStreak).fold<int>(0, _max);
    final mostInOneDay = _maxThrowsPerDay(stats);

    final trend = stats.map((s) => s.hitRatePercent).toList();
    final rows = stats.reversed.take(_maxSessionRows).map((s) {
      return StatsSessionRow(
        sessionId: s.sessionId,
        completedAt: s.completedAt,
        distanceMeters: s.distance,
        hitRatePercent: s.hitRatePercent,
        totalThrows: s.totalThrows,
      );
    }).toList();

    return StatsAggregate(
      totalSessions: stats.length,
      totalThrows: totalThrows,
      hitRatePercent: hitRate,
      longestHitStreak: longestStreak,
      bestHitRatePercent: best.hitRatePercent,
      bestHitRateDistance: best.distance,
      mostThrowsInOneDay: mostInOneDay,
      trendPoints: trend,
      sessionRows: rows,
    );
  }

  Future<_PerSession> _summarise(
    Session s, {
    required bool heliTracking,
  }) async {
    final events = await _events.forSession(s.id);
    var hits = 0;
    var misses = 0;
    var helis = 0;
    var streak = 0;
    var longest = 0;
    for (final e in events) {
      if (e.correctedAt != null) continue;
      switch (e.kind) {
        case _kindHit:
          hits++;
          streak++;
          if (streak > longest) longest = streak;
        case _kindMiss:
          misses++;
          streak = 0;
        case _kindHeli:
          helis++;
          streak = 0;
      }
    }
    final divisor = hits + misses;
    final rate = divisor == 0 ? 0 : ((hits / divisor) * 100).round();
    final total = hits + misses + (heliTracking ? helis : 0);
    return _PerSession(
      sessionId: s.id,
      completedAt: s.completedAt ?? s.startedAt,
      distance: s.distanceMeters,
      hits: hits,
      misses: misses,
      hitRatePercent: rate,
      totalThrows: total,
      longestHitStreak: longest,
    );
  }

  static DateTime? _cutoffFor(StatsDateRange range, DateTime now) {
    switch (range) {
      case StatsDateRange.all:
        return null;
      case StatsDateRange.last7Days:
        return now.subtract(const Duration(days: 7));
      case StatsDateRange.last30Days:
        return now.subtract(const Duration(days: 30));
    }
  }

  static int _max(int a, int b) => a > b ? a : b;

  static int _maxThrowsPerDay(List<_PerSession> stats) {
    final perDay = <String, int>{};
    for (final s in stats) {
      final key = '${s.completedAt.toUtc().year}-'
          '${s.completedAt.toUtc().month}-${s.completedAt.toUtc().day}';
      perDay[key] = (perDay[key] ?? 0) + s.totalThrows;
    }
    return perDay.values.fold<int>(0, _max);
  }
}

class _PerSession {
  const _PerSession({
    required this.sessionId,
    required this.completedAt,
    required this.distance,
    required this.hits,
    required this.misses,
    required this.hitRatePercent,
    required this.totalThrows,
    required this.longestHitStreak,
  });

  final String sessionId;
  final DateTime completedAt;
  final double distance;
  final int hits;
  final int misses;
  final int hitRatePercent;
  final int totalThrows;
  final int longestHitStreak;
}

final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return StatsRepository(
    sessionDao: db.sessionDao,
    eventDao: db.sessionEventDao,
  );
});
