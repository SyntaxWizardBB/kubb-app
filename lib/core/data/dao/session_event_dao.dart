import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/tables/session_events.dart';

part 'session_event_dao.g.dart';

@DriftAccessor(tables: [SessionEvents])
class SessionEventDao extends DatabaseAccessor<AppDatabase>
    with _$SessionEventDaoMixin {
  SessionEventDao(super.attachedDatabase);

  Future<List<SessionEvent>> forSession(String sessionId) {
    return (select(sessionEvents)
          ..where((e) => e.sessionId.equals(sessionId))
          ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]))
        .get();
  }

  Future<SessionEvent?> latestNonDeletedOfKind(
    String sessionId,
    String kind,
  ) {
    return (select(sessionEvents)
          ..where(
            (e) =>
                e.sessionId.equals(sessionId) &
                e.kind.equals(kind) &
                e.correctedAt.isNull(),
          )
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> insert(SessionEventsCompanion companion) {
    return into(sessionEvents).insert(companion);
  }

  Future<void> markCorrected(String id, DateTime correctedAt) {
    return (update(sessionEvents)..where((e) => e.id.equals(id))).write(
      SessionEventsCompanion(correctedAt: Value(correctedAt)),
    );
  }

  Future<int> countByKind(
    String sessionId,
    String kind, {
    bool excludeCorrected = true,
  }) async {
    final count = sessionEvents.id.count();
    final query = selectOnly(sessionEvents)
      ..addColumns([count])
      ..where(
        sessionEvents.sessionId.equals(sessionId) &
            sessionEvents.kind.equals(kind),
      );
    if (excludeCorrected) {
      query.where(sessionEvents.correctedAt.isNull());
    }
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }
}
