import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/features/achievements/data/dao/badge_unlocks_dao.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Read/write surface for badge unlocks.
///
/// Sprint B Wave 6 shipped an in-memory implementation so the providers
/// and UI could be wired and tested without persistence. Sprint C W4-T1
/// promotes the store to Drift (schema v8) via
/// [DriftAchievementsRepository]; the [InMemoryAchievementsRepository]
/// stays around as the test double for callers that do not want to spin
/// up a real database.
abstract class AchievementsRepository {
  /// One-shot read of all badges the given user has unlocked.
  Future<List<BadgeUnlock>> listUnlocksFor(UserId user);

  /// Live view used by the inventory screen. Emits once on subscribe
  /// with the current list, then again whenever an unlock is recorded.
  Stream<List<BadgeUnlock>> watchUnlocksFor(UserId user);

  /// Idempotent. Re-recording an existing `(userId, badgeId)` pair is
  /// a no-op (the original [BadgeUnlock.unlockedAt] is preserved).
  Future<void> recordUnlock(BadgeUnlock unlock);
}

/// In-memory implementation. Used by tests that don't want to stand up a
/// real database and as a fallback for ephemeral / preview contexts.
class InMemoryAchievementsRepository implements AchievementsRepository {
  InMemoryAchievementsRepository();

  final Map<String, List<BadgeUnlock>> _byUser = <String, List<BadgeUnlock>>{};
  final Map<String, StreamController<List<BadgeUnlock>>> _controllers =
      <String, StreamController<List<BadgeUnlock>>>{};

  @override
  Future<List<BadgeUnlock>> listUnlocksFor(UserId user) async {
    return List<BadgeUnlock>.unmodifiable(_byUser[user.value] ?? const []);
  }

  @override
  Stream<List<BadgeUnlock>> watchUnlocksFor(UserId user) {
    final controller = _controllers.putIfAbsent(
      user.value,
      StreamController<List<BadgeUnlock>>.broadcast,
    );
    // Emit current snapshot asynchronously so listeners receive it.
    scheduleMicrotask(() {
      if (!controller.isClosed) {
        controller.add(
          List<BadgeUnlock>.unmodifiable(_byUser[user.value] ?? const []),
        );
      }
    });
    return controller.stream;
  }

  @override
  Future<void> recordUnlock(BadgeUnlock unlock) async {
    final list = _byUser.putIfAbsent(unlock.userId, () => <BadgeUnlock>[]);
    final exists = list.any((u) => u.badgeId == unlock.badgeId);
    if (exists) return;
    list.add(unlock);
    final controller = _controllers[unlock.userId];
    if (controller != null && !controller.isClosed) {
      controller.add(List<BadgeUnlock>.unmodifiable(list));
    }
  }

  /// Releases broadcast controllers — call from tests or DI teardown.
  Future<void> dispose() async {
    for (final c in _controllers.values) {
      await c.close();
    }
    _controllers.clear();
  }
}

/// Drift-backed implementation (schema v8 `badge_unlocks` table).
///
/// Idempotency is delegated to the DAO's `INSERT OR IGNORE`, which makes
/// re-recording an existing `(userId, badgeId)` pair a no-op at the
/// SQLite level — the original `unlockedAt` is preserved without a
/// read-modify-write round-trip from application code.
class DriftAchievementsRepository implements AchievementsRepository {
  DriftAchievementsRepository(this._dao);

  final BadgeUnlocksDao _dao;

  @override
  Future<List<BadgeUnlock>> listUnlocksFor(UserId user) async {
    final rows = await _dao.listFor(user.value);
    return List<BadgeUnlock>.unmodifiable(rows.map(_toDomain));
  }

  @override
  Stream<List<BadgeUnlock>> watchUnlocksFor(UserId user) {
    return _dao.watchFor(user.value).map(
          (rows) => List<BadgeUnlock>.unmodifiable(rows.map(_toDomain)),
        );
  }

  @override
  Future<void> recordUnlock(BadgeUnlock unlock) {
    return _dao.recordUnlock(
      BadgeUnlocksCompanion(
        userId: Value(unlock.userId),
        badgeId: Value(unlock.badgeId),
        unlockedAt: Value(unlock.unlockedAt.toUtc().millisecondsSinceEpoch),
        sourceSessionId: unlock.sourceSessionId == null
            ? const Value<String?>.absent()
            : Value<String?>(unlock.sourceSessionId),
      ),
    );
  }

  static BadgeUnlock _toDomain(CachedBadgeUnlock row) {
    return BadgeUnlock(
      userId: row.userId,
      badgeId: row.badgeId,
      unlockedAt: DateTime.fromMillisecondsSinceEpoch(
        row.unlockedAt,
        isUtc: true,
      ),
      sourceSessionId: row.sourceSessionId,
    );
  }
}

/// DI handle. Defaults to the Drift-backed implementation that reads /
/// writes through the shared [AppDatabase]. Tests that need a pure
/// in-process repo can override this provider with an
/// [InMemoryAchievementsRepository] instance.
final achievementsRepositoryProvider = Provider<AchievementsRepository>((ref) {
  final dao = ref.watch(appDatabaseProvider).badgeUnlocksDao;
  return DriftAchievementsRepository(dao);
});
