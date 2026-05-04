import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/features/auth/data/tables/cached_auth_session_table.dart';

part 'cached_auth_session_dao.g.dart';

/// DAO for the single-row [CachedAuthSession] table.
///
/// At most one row exists at any time, identified by the deterministic
/// primary key `singleton`. All writes are upserts on that key.
@DriftAccessor(tables: [CachedAuthSession])
class CachedAuthSessionDao extends DatabaseAccessor<AppDatabase>
    with _$CachedAuthSessionDaoMixin {
  CachedAuthSessionDao(super.attachedDatabase);

  Future<CachedAuthSessionData?> current() {
    return select(cachedAuthSession).getSingleOrNull();
  }

  Stream<CachedAuthSessionData?> watch() {
    return select(cachedAuthSession).watchSingleOrNull();
  }

  Future<void> upsert({
    required String userId,
    required String kind,
    required String displayName,
    required DateTime expiresAt,
    required DateTime refreshAfter,
    String? avatarColor,
  }) async {
    final now = DateTime.now().toUtc();
    final existing = await current();
    final companion = CachedAuthSessionCompanion(
      userId: Value(userId),
      kind: Value(kind),
      displayName: Value(displayName),
      avatarColor: Value(avatarColor),
      expiresAt: Value(expiresAt),
      refreshAfter: Value(refreshAfter),
      createdAt: Value(existing?.createdAt ?? now),
      updatedAt: Value(now),
    );
    await into(cachedAuthSession).insertOnConflictUpdate(companion);
  }

  Future<void> clear() async {
    await delete(cachedAuthSession).go();
  }
}
