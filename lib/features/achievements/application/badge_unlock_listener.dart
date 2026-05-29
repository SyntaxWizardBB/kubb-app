import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/features/achievements/data/achievements_repository.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:logging/logging.dart';

/// Bridges the match/training lifecycle into the badge engine.
///
/// The listener is intentionally a thin orchestrator: it owns no
/// trigger logic of its own — that lives in [BadgeCatalog.evaluate]
/// inside `kubb_domain`. Its only jobs are
///   1. Read the current user from the auth provider.
///   2. Fetch the user's existing unlocks via [AchievementsRepository].
///   3. Hand the [BadgeTriggerContext] from the caller's summary to the
///      catalog and persist whatever new unlocks fall out.
///
/// Hooks call the `evaluateAfter*` methods inside a try/catch and only
/// log on failure; the badge pipeline must never block a successful
/// match-finalize or session-complete write.
class BadgeUnlockListener {
  BadgeUnlockListener({
    required AchievementsRepository repository,
    required String? Function() readCurrentUserId,
    DateTime Function()? now,
  })  : _repository = repository,
        _readCurrentUserId = readCurrentUserId,
        _now = now ?? DateTime.now;

  final AchievementsRepository _repository;
  final String? Function() _readCurrentUserId;
  final DateTime Function() _now;
  final Logger _log = Logger('BadgeUnlockListener');

  /// Match-finalize hook. Evaluates badge triggers against the
  /// aggregate snapshot in [summary] and persists every newly-earned
  /// badge for the current user. No-op when the user is not signed in.
  Future<void> evaluateAfterMatch(BadgeMatchSummary summary) {
    return _evaluate(
      context: summary.context,
      sourceSessionId: summary.sourceMatchId,
      label: 'match',
    );
  }

  /// Session-complete hook. Mirrors [evaluateAfterMatch] for training
  /// sessions, attributing unlocks to the source session id.
  Future<void> evaluateAfterSession(BadgeSessionSummary summary) {
    return _evaluate(
      context: summary.context,
      sourceSessionId: summary.sourceSessionId,
      label: 'session',
    );
  }

  Future<void> _evaluate({
    required BadgeTriggerContext context,
    required String sourceSessionId,
    required String label,
  }) async {
    final userId = _readCurrentUserId();
    if (userId == null || userId.isEmpty) {
      _log.fine('skip $label evaluation: no current user');
      return;
    }
    final user = UserId(userId);
    final existing = await _repository.listUnlocksFor(user);
    final alreadyIds = existing.map((u) => u.badgeId);
    final newlyUnlocked = BadgeCatalog.evaluate(
      context,
      alreadyUnlocked: alreadyIds,
    );
    if (newlyUnlocked.isEmpty) {
      return;
    }
    final unlockedAt = _now().toUtc();
    for (final badgeId in newlyUnlocked) {
      await _repository.recordUnlock(
        BadgeUnlock(
          userId: userId,
          badgeId: badgeId,
          unlockedAt: unlockedAt,
          sourceSessionId: sourceSessionId,
        ),
      );
    }
    _log.info(
      'unlocked ${newlyUnlocked.length} badge(s) after $label '
      '${newlyUnlocked.join(', ')}',
    );
  }
}

/// DI handle for the listener. Wired against the live auth provider and
/// the Drift-backed achievements repository. Tests override either
/// dependency by replacing this provider or its parents.
final badgeUnlockListenerProvider = Provider<BadgeUnlockListener>((ref) {
  return BadgeUnlockListener(
    repository: ref.watch(achievementsRepositoryProvider),
    readCurrentUserId: () => ref.read(currentUserIdProvider),
  );
});
