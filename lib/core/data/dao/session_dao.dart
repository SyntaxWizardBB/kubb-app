import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/tables/sessions.dart';

part 'session_dao.g.dart';

@DriftAccessor(tables: [Sessions])
class SessionDao extends DatabaseAccessor<AppDatabase> with _$SessionDaoMixin {
  SessionDao(super.attachedDatabase);

  Future<Session?> getById(String id) {
    return (select(sessions)..where((s) => s.id.equals(id))).getSingleOrNull();
  }

  Future<Session?> activeForPlayer(String playerId) {
    return (select(sessions)
          ..where((s) => s.playerId.equals(playerId) & s.status.equals('active'))
          ..limit(1))
        .getSingleOrNull();
  }

  Stream<List<Session>> watchRecentCompleted({
    required String playerId,
    int limit = 3,
  }) {
    return (select(sessions)
          ..where(
            (s) => s.playerId.equals(playerId) & s.status.equals('completed'),
          )
          ..orderBy([(s) => OrderingTerm.desc(s.completedAt)])
          ..limit(limit))
        .watch();
  }

  Future<List<Session>> allCompletedForPlayer(String playerId) {
    return (select(sessions)
          ..where(
            (s) => s.playerId.equals(playerId) & s.status.equals('completed'),
          )
          ..orderBy([(s) => OrderingTerm.asc(s.completedAt)]))
        .get();
  }

  Future<void> insert(SessionsCompanion companion) {
    return into(sessions).insert(companion);
  }

  Future<void> updateStatus(
    String id,
    String status, {
    DateTime? completedAt,
  }) {
    return (update(sessions)..where((s) => s.id.equals(id))).write(
      SessionsCompanion(
        status: Value(status),
        completedAt: completedAt == null
            ? const Value.absent()
            : Value(completedAt),
      ),
    );
  }

  Future<void> deleteById(String id) {
    return (delete(sessions)..where((s) => s.id.equals(id))).go();
  }
}
