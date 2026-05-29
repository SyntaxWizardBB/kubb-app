import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/achievements/data/tables/badge_unlocks_table.dart';

part 'badge_unlocks_dao.g.dart';

/// DAO for the persisted badge-unlock store. Backs the Drift-backed
/// `AchievementsRepository` that landed in Sprint C W4-T1.
///
/// Every method scopes by `userId` — the table can briefly hold rows
/// for a previous account between sign-outs (the wipe-on-sign-out path
/// runs against the whole database), so the DAO never assumes an
/// implicit "current user".
@DriftAccessor(tables: [BadgeUnlocks])
class BadgeUnlocksDao extends DatabaseAccessor<AppDatabase>
    with _$BadgeUnlocksDaoMixin {
  BadgeUnlocksDao(super.attachedDatabase);

  /// Inserts an unlock row idempotently.
  ///
  /// Re-recording the same `(userId, badgeId)` pair is a no-op: the
  /// original [BadgeUnlocks.unlockedAt] is preserved and the new
  /// timestamp is dropped. This is the durable equivalent of the
  /// in-memory repo's "first write wins" rule, pushed down to SQLite via
  /// `INSERT OR IGNORE` so concurrent unlocks cannot race.
  Future<void> recordUnlock(BadgeUnlocksCompanion row) async {
    await into(badgeUnlocks).insert(
      row,
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Snapshot read of all unlocks for [userId], newest first.
  Future<List<CachedBadgeUnlock>> listFor(String userId) {
    return (select(badgeUnlocks)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.unlockedAt)]))
        .get();
  }

  /// Live view of all unlocks for [userId]. The inventory screen
  /// subscribes to this so a new unlock recorded by the trigger engine
  /// repaints the grid without a manual reload.
  Stream<List<CachedBadgeUnlock>> watchFor(String userId) {
    return (select(badgeUnlocks)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.unlockedAt)]))
        .watch();
  }
}
