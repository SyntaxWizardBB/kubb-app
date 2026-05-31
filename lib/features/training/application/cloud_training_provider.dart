import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';
import 'package:kubb_app/features/training/data/cloud_training_repository.dart';
import 'package:logging/logging.dart';

const _kindHit = 'hit';
const _kindMiss = 'miss';
const _kindHeli = 'heli';
const _modeFinisseur = 'finisseur';

/// Aggregated training statistics for one player, derived from their cloud
/// sessions. Drives the friend-profile stats section and (later) the own
/// history view.
class TrainingStats {
  const TrainingStats({
    required this.totalSessions,
    required this.sniperSessions,
    required this.finisseurSessions,
    required this.finisseurWins,
    this.avgHitRate,
    this.lastPlayedAt,
  });

  factory TrainingStats.from(List<CloudTrainingSession> sessions) {
    if (sessions.isEmpty) {
      return const TrainingStats(
        totalSessions: 0,
        sniperSessions: 0,
        finisseurSessions: 0,
        finisseurWins: 0,
      );
    }
    var sniper = 0;
    var finisseur = 0;
    var wins = 0;
    var hitRateSum = 0;
    var hitRateCount = 0;
    DateTime? last;
    for (final s in sessions) {
      if (last == null || s.completedAt.isAfter(last)) last = s.completedAt;
      if (s.isFinisseur) {
        finisseur++;
        if (s.win ?? false) wins++;
      } else {
        sniper++;
        if (s.hitRate != null) {
          hitRateSum += s.hitRate!;
          hitRateCount++;
        }
      }
    }
    return TrainingStats(
      totalSessions: sessions.length,
      sniperSessions: sniper,
      finisseurSessions: finisseur,
      finisseurWins: wins,
      avgHitRate: hitRateCount == 0 ? null : (hitRateSum / hitRateCount).round(),
      lastPlayedAt: last,
    );
  }

  final int totalSessions;
  final int sniperSessions;
  final int finisseurSessions;
  final int finisseurWins;

  /// Mean sniper hit-rate across all sniper sessions (null when none).
  final int? avgHitRate;
  final DateTime? lastPlayedAt;

  /// Finisseur win-rate in percent (null when no finisseur sessions).
  int? get finisseurWinRate => finisseurSessions == 0
      ? null
      : ((finisseurWins / finisseurSessions) * 100).round();

  bool get isEmpty => totalSessions == 0;
}

/// A player's cloud training sessions, newest first. Family key = user id.
/// Returns the caller's own rows or — when the id is an accepted friend —
/// the friend's rows. RLS yields an empty list for anyone else.
// ignore: specify_nonobvious_property_types
final playerTrainingSessionsProvider =
    FutureProvider.family<List<CloudTrainingSession>, String>(
        (ref, userId) async {
  return ref.read(cloudTrainingRepositoryProvider).listForUser(userId);
});

/// The signed-in user's own cloud sessions, newest first. Empty when signed
/// out. Backs the "Meine Online-Sessions" management view (P2: view + delete).
final myTrainingSessionsProvider =
    FutureProvider<List<CloudTrainingSession>>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return const <CloudTrainingSession>[];
  return ref.read(cloudTrainingRepositoryProvider).listForUser(userId);
});

/// Imperative uploader: pushes a just-completed local session up as an
/// aggregate. Best-effort — callers fire-and-forget so a failed upload (e.g.
/// offline at the pitch) never blocks the local completion flow.
final cloudSessionUploaderProvider = Provider<CloudSessionUploader>((ref) {
  return CloudSessionUploader(ref);
});

class CloudSessionUploader {
  CloudSessionUploader(this._ref);

  final Ref _ref;
  final Logger _log = Logger('CloudSessionUploader');

  /// Computes the aggregate for [sessionId] from the persisted drift state
  /// (same formulas as the home "recent" view) and upserts it to Supabase.
  /// Swallows and logs errors so it is safe to fire-and-forget.
  Future<void> uploadCompleted(String sessionId) async {
    try {
      final db = _ref.read(appDatabaseProvider);
      final session = await db.sessionDao.getById(sessionId);
      if (session == null) return;

      final repo = _ref.read(cloudTrainingRepositoryProvider);
      if (session.mode == _modeFinisseur) {
        await repo.upsert(await _finisseurAggregate(db, session));
      } else {
        await repo.upsert(await _sniperAggregate(db, session));
      }
    } on Object catch (e, st) {
      _log.warning('cloud session upload failed for $sessionId', e, st);
    }
  }

  Future<CloudTrainingSession> _sniperAggregate(
    AppDatabase db,
    Session session,
  ) async {
    final events = await db.sessionEventDao.forSession(session.id);
    var hits = 0;
    var misses = 0;
    var helis = 0;
    for (final e in events) {
      if (e.correctedAt != null) continue;
      switch (e.kind) {
        case _kindHit:
          hits++;
        case _kindMiss:
          misses++;
        case _kindHeli:
          helis++;
      }
    }
    // Heli always counts as a miss in the rate denominator (mirrors the
    // recent-session projection).
    final divisor = hits + misses + helis;
    final hitRate = divisor == 0 ? 0 : ((hits / divisor) * 100).round();
    return CloudTrainingSession(
      id: session.id,
      userId: session.playerId,
      mode: 'sniper',
      distanceM: session.distanceMeters,
      hitRate: hitRate,
      throws: divisor,
      startedAt: session.startedAt,
      completedAt: session.completedAt ?? session.startedAt,
    );
  }

  Future<CloudTrainingSession> _finisseurAggregate(
    AppDatabase db,
    Session session,
  ) async {
    final kingTracking =
        _ref.read(appSettingsProvider).value?.kingThrowTracking ?? true;
    final sticks = await db.finisseurStickEventDao.forSession(session.id);
    final field = session.finField ?? 0;
    final base = session.finBase ?? 0;
    final used = sticks.length;
    final fieldDown = sticks.fold<int>(0, (a, s) => a + s.fieldKubbsHit);
    final baseDown = sticks.fold<int>(0, (a, s) => a + (s.eightMHit ? 1 : 0));
    final kingHit = sticks.any((s) => s.kingHit ?? false);
    final allKubbsDown = fieldDown >= field && baseDown >= base;
    final withinRegulation = used <= ActiveFinisseurState.totalSticks;
    final win =
        allKubbsDown && (!kingTracking || kingHit) && withinRegulation;
    return CloudTrainingSession(
      id: session.id,
      userId: session.playerId,
      mode: 'finisseur',
      win: win,
      sticksUsed: used,
      fieldTarget: field,
      baseTarget: base,
      startedAt: session.startedAt,
      completedAt: session.completedAt ?? session.startedAt,
    );
  }
}
