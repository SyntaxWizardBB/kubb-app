import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/ui/settings/app_settings_provider.dart';
import 'package:kubb_app/features/player/application/current_profile_provider.dart';
import 'package:kubb_app/features/training/data/training_repository.dart';

const _kindHit = 'hit';
const _kindMiss = 'miss';
const _kindHeli = 'heli';
const _modeFinisseur = 'finisseur';

/// Lightweight projection of a completed training session for the home list.
///
/// Sniper rows surface `hitRatePercent`. Finisseur rows surface `binaryWin`
/// instead — the row is binary (won / lost) so a hit-rate percentage would
/// be misleading. UI picks the correct shape based on which field is set.
class RecentSessionView {
  const RecentSessionView({
    required this.modeTag,
    required this.subtitle,
    this.hitRatePercent,
    this.binaryWin,
  });

  final String modeTag;
  final String subtitle;
  final int? hitRatePercent;
  final bool? binaryWin;
}

final recentSessionsProvider =
    StreamProvider<List<RecentSessionView>>((ref) {
  final profile = ref.watch(currentProfileProvider).value;
  if (profile == null) {
    return Stream.value(const <RecentSessionView>[]);
  }

  final settings = ref.watch(appSettingsProvider).value;
  final heliTracking = settings?.heliTracking ?? true;
  final kingTracking = settings?.kingThrowTracking ?? true;
  final repo = ref.watch(trainingRepositoryProvider);
  final db = ref.watch(appDatabaseProvider);

  return repo
      .watchRecentCompleted(playerId: profile.id)
      .asyncMap((sessions) async {
    final views = <RecentSessionView>[];
    for (final session in sessions) {
      if (session.mode == _modeFinisseur) {
        views.add(await _toFinisseurView(db, session, kingTracking: kingTracking));
      } else {
        views.add(
          await _toSniperView(repo, session, heliTracking: heliTracking),
        );
      }
    }
    return views;
  });
});

Future<RecentSessionView> _toSniperView(
  TrainingRepository repo,
  Session session, {
  required bool heliTracking,
}) async {
  final events = await repo.eventsOf(session.id);
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

  // Heli always counts as a miss in the rate denominator. The setting only
  // controls whether helis show up in the throw-count subtitle.
  final divisor = hits + misses + helis;
  final hitRate = divisor == 0 ? 0 : ((hits / divisor) * 100).round();
  final totalThrows = hits + misses + (heliTracking ? helis : 0);
  final completedAt = session.completedAt ?? session.startedAt;

  return RecentSessionView(
    modeTag: 'Sniper',
    hitRatePercent: hitRate,
    subtitle: '${session.distanceMeters.toStringAsFixed(1)} m · '
        '$totalThrows Würfe · ${_relativeTime(completedAt)}',
  );
}

Future<RecentSessionView> _toFinisseurView(
  AppDatabase db,
  Session session, {
  required bool kingTracking,
}) async {
  final sticks = await db.finisseurStickEventDao.forSession(session.id);
  final used = sticks
      .where((s) =>
          s.fieldKubbsHit > 0 ||
          s.eightMHit ||
          s.heliThrow ||
          s.kingHit != null ||
          s.penaltyHits1 + s.penaltyHits2 > 0)
      .length;
  final field = session.finField ?? 0;
  final base = session.finBase ?? 0;
  final fieldDown = sticks.fold<int>(0, (a, s) => a + s.fieldKubbsHit);
  final baseDown = sticks.fold<int>(0, (a, s) => a + (s.eightMHit ? 1 : 0));
  final kingHit = sticks.any((s) => s.kingHit ?? false);
  final allKubbsDown = fieldDown >= field && baseDown >= base;
  final success =
      kingTracking ? allKubbsDown && kingHit : allKubbsDown;
  final completedAt = session.completedAt ?? session.startedAt;
  return RecentSessionView(
    modeTag: 'Finisseur',
    binaryWin: success,
    subtitle: '$field/$base · $used Stöcke · ${_relativeTime(completedAt)}',
  );
}

String _relativeTime(DateTime utc) {
  final now = DateTime.now().toUtc();
  final diff = now.difference(utc);
  if (diff.inMinutes < 1) return 'gerade eben';
  if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min';
  if (diff.inHours < 24) return 'vor ${diff.inHours} Std';
  if (diff.inDays == 1) return 'gestern';
  if (diff.inDays < 7) return 'vor ${diff.inDays} Tagen';
  if (diff.inDays < 30) return 'vor ${(diff.inDays / 7).floor()} Wochen';
  return 'vor ${(diff.inDays / 30).floor()} Monaten';
}
