import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/inbox/data/tables/inbox_messages_table.dart';

part 'inbox_messages_dao.g.dart';

/// DAO for the local inbox cache. Backs the hydrate-on-open path in
/// `InboxRepository` that satisfies ADR-0012's offline requirement
/// (bug-hunt R20-F-03).
///
/// Queries are always scoped to a `userId` — RLS on Supabase already
/// guarantees that the rows pulled down belong to the caller, but the
/// local table can briefly hold rows for a previous account between
/// sign-outs, so the DAO never trusts a global "current user" implicit
/// scope.
@DriftAccessor(tables: [InboxMessages])
class InboxMessagesDao extends DatabaseAccessor<AppDatabase>
    with _$InboxMessagesDaoMixin {
  InboxMessagesDao(super.attachedDatabase);

  /// Insert-or-update a batch of cached rows. Used by the repository
  /// after a successful Supabase refresh — every row from the network
  /// answer is upserted on its primary key so existing entries pick up
  /// any `readAt` / `repliedAt` changes the server has stamped.
  Future<void> upsertMany(List<InboxMessagesCompanion> rows) async {
    if (rows.isEmpty) return;
    await batch((b) {
      b.insertAllOnConflictUpdate(inboxMessages, rows);
    });
  }

  /// Live view of the cached inbox for [userId], newest message first.
  /// The screen subscribes to this stream so the first frame after
  /// app-launch can paint from disk without waiting for Supabase.
  Stream<List<CachedInboxMessage>> watchByUser(String userId) {
    return (select(inboxMessages)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Snapshot variant of [watchByUser] for callsites that want a
  /// single read without keeping a subscription open.
  Future<List<CachedInboxMessage>> listByUser(String userId) {
    return (select(inboxMessages)
          ..where((t) => t.userId.equals(userId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
  }

  /// Drops every cached row owned by [userId]. Called on sign-out so
  /// the next account that signs in on the same device cannot see the
  /// previous user's messages through the local cache.
  Future<int> deleteForUser(String userId) {
    return (delete(inboxMessages)..where((t) => t.userId.equals(userId))).go();
  }

  /// Removes the cached row for [id] regardless of owner. Mirrors the
  /// archive action: an archived message disappears from the inbox
  /// view, so the local cache should follow the same model rather than
  /// keeping a stale entry around.
  Future<int> deleteById(String id) {
    return (delete(inboxMessages)..where((t) => t.id.equals(id))).go();
  }

  /// Updates the read / replied timestamps on the cached row for [id].
  /// Used after a mutating Supabase call (markRead / reply) so the
  /// local mirror stays in sync without a full refresh. No-op when the
  /// row is not cached locally.
  Future<int> stampTimestamps(
    String id, {
    DateTime? readAt,
    DateTime? repliedAt,
  }) {
    final companion = InboxMessagesCompanion(
      readAt: readAt == null
          ? const Value.absent()
          : Value(readAt.toUtc().millisecondsSinceEpoch),
      repliedAt: repliedAt == null
          ? const Value.absent()
          : Value(repliedAt.toUtc().millisecondsSinceEpoch),
    );
    return (update(inboxMessages)..where((t) => t.id.equals(id)))
        .write(companion);
  }
}
