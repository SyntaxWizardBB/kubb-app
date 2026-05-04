import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/dao/finisseur_stick_event_dao.dart';
import 'package:kubb_app/core/data/dao/session_dao.dart';
import 'package:kubb_app/core/data/dao/session_event_dao.dart';
import 'package:kubb_app/features/stats/data/stats_aggregate.dart';
import 'package:kubb_app/features/stats/data/stats_filter.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';

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
    FinisseurStickEventDao? finisseurDao,
  })  : _sessions = sessionDao,
        _events = eventDao,
        _finisseur = finisseurDao;

  final SessionDao _sessions;
  final SessionEventDao _events;
  final FinisseurStickEventDao? _finisseur;

  Future<StatsAggregate> computeAggregate({
    required String playerId,
    required StatsFilter filter,
    required bool heliTracking,
    DateTime? now,
  }) async {
    final all = await _sessions.allCompletedForPlayer(playerId);
    final cutoff = _cutoffFor(filter.dateRange, now ?? DateTime.now().toUtc());
    final filtered = all.where((s) {
      // Sniper aggregates ignore finisseur sessions — they have a separate
      // model and would otherwise blow up the hit-rate baseline.
      if (s.mode == 'finisseur') return false;
      final ts = s.completedAt ?? s.startedAt;
      if (cutoff != null && ts.isBefore(cutoff)) return false;
      final d = s.distanceMeters;
      if (d < filter.distanceMin - 0.001 || d > filter.distanceMax + 0.001) {
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
    // Heli counts as a miss for the rate denominator, regardless of whether
    // the heli setting is on (the setting only controls whether helis show
    // up in the throw count).
    final divisor = stats.fold<int>(
      0,
      (a, x) => a + x.hits + x.misses + x.helis,
    );
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
    final divisor = hits + misses + helis;
    final rate = divisor == 0 ? 0 : ((hits / divisor) * 100).round();
    final total = hits + misses + (heliTracking ? helis : 0);
    return _PerSession(
      sessionId: s.id,
      completedAt: s.completedAt ?? s.startedAt,
      distance: s.distanceMeters,
      hits: hits,
      misses: misses,
      helis: helis,
      hitRatePercent: rate,
      totalThrows: total,
      longestHitStreak: longest,
    );
  }

  /// Aggregates completed finisseur sessions for one player. Reads each
  /// session's stick events to compute totals; success means all field plus
  /// base kubbs went down before the last stick was thrown.
  Future<FinisseurStatsAggregate> computeFinisseurAggregate({
    required String playerId,
    StatsFilter filter = const StatsFilter(),
    DateTime? now,
  }) async {
    final dao = _finisseur;
    if (dao == null) return FinisseurStatsAggregate.empty();
    final all = await _sessions.allCompletedForPlayer(playerId);
    final cutoff = _cutoffFor(filter.dateRange, now ?? DateTime.now().toUtc());
    final finisseurs = all.where((s) {
      if (s.mode != 'finisseur') return false;
      final ts = s.completedAt ?? s.startedAt;
      if (cutoff != null && ts.isBefore(cutoff)) return false;
      final field = s.finField ?? 0;
      final base = s.finBase ?? 0;
      if (field < filter.finFieldMin || field > filter.finFieldMax) {
        return false;
      }
      if (base < filter.finBaseMin || base > filter.finBaseMax) {
        return false;
      }
      return true;
    }).toList();
    if (finisseurs.isEmpty) return FinisseurStatsAggregate.empty();

    var totalSticks = 0;
    var missSticks = 0;
    var successCount = 0;
    var heli = 0;
    var penalty = 0;
    var longDubbies = 0;
    var kingAttempts = 0;
    var kingHits = 0;
    final trend = <int>[];
    final rows = <FinisseurSessionRow>[];

    for (final s in finisseurs) {
      final events = await dao.forSession(s.id);
      var fieldDown = 0;
      var baseDown = 0;
      var sticksTouched = 0;
      var sessionKingAttempts = 0;
      var sessionKingHits = 0;
      for (final e in events) {
        sticksTouched++;
        fieldDown += e.fieldKubbsHit;
        if (e.eightMHit) baseDown++;
        if (e.heliThrow) heli++;
        if (e.fieldKubbsHit > 0 && e.eightMHit) longDubbies++;
        penalty += e.penaltyHits1 + e.penaltyHits2;
        final kingHit = e.kingHit;
        if (kingHit != null) {
          sessionKingAttempts++;
          if (kingHit) sessionKingHits++;
        }
        // Stick is a miss when no useful hit happened. Heli-only and full
        // duds both count, king-hit redeems a stick.
        final hadAnyHit = e.fieldKubbsHit > 0 || e.eightMHit || kingHit == true;
        if (!hadAnyHit) missSticks++;
      }
      kingAttempts += sessionKingAttempts;
      kingHits += sessionKingHits;
      final field = s.finField ?? 0;
      final base = s.finBase ?? 0;
      // A finisseur counts as a success when all kubbs went down and the
      // king-throw — if attempted at all — landed AND the player stayed
      // within the regulation six sticks. Continuing past stock 6 always
      // marks the session as a loss.
      final withinRegulation =
          sticksTouched <= ActiveFinisseurState.totalSticks;
      final success = fieldDown >= field &&
          baseDown >= base &&
          (sessionKingAttempts == 0 || sessionKingHits > 0) &&
          withinRegulation;
      if (success) successCount++;
      totalSticks += sticksTouched;
      trend.add(success ? 100 : 0);
      rows.add(FinisseurSessionRow(
        sessionId: s.id,
        completedAt: s.completedAt ?? s.startedAt,
        field: field,
        base: base,
        sticksUsed: sticksTouched,
        success: success,
      ));
    }

    final avgLong = finisseurs.isEmpty ? 0.0 : longDubbies / finisseurs.length;
    return FinisseurStatsAggregate(
      totalSessions: finisseurs.length,
      successCount: successCount,
      totalSticks: totalSticks,
      missSticks: missSticks,
      longDubbiesPerSession: avgLong,
      heliCount: heli,
      penaltyCount: penalty,
      kingAttempts: kingAttempts,
      kingHits: kingHits,
      successTrendPercent: trend,
      sessionRows: rows.reversed.take(_maxSessionRows).toList(),
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
    required this.helis,
    required this.hitRatePercent,
    required this.totalThrows,
    required this.longestHitStreak,
  });

  final String sessionId;
  final DateTime completedAt;
  final double distance;
  final int hits;
  final int misses;
  final int helis;
  final int hitRatePercent;
  final int totalThrows;
  final int longestHitStreak;
}

final statsRepositoryProvider = Provider<StatsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return StatsRepository(
    sessionDao: db.sessionDao,
    eventDao: db.sessionEventDao,
    finisseurDao: db.finisseurStickEventDao,
  );
});
