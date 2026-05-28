import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/tables/finisseur_stick_events.dart';

part 'finisseur_stick_event_dao.g.dart';

@DriftAccessor(tables: [FinisseurStickEvents])
class FinisseurStickEventDao extends DatabaseAccessor<AppDatabase>
    with _$FinisseurStickEventDaoMixin {
  FinisseurStickEventDao(super.attachedDatabase);

  Future<void> insert(FinisseurStickEventsCompanion companion) {
    return into(finisseurStickEvents).insert(companion);
  }

  /// Insert-or-replace on the natural key `(session_id, stick_index)`.
  /// A retry, crash-resume, or out-of-band write that lands on the same
  /// slot updates the existing row instead of tripping the UNIQUE index.
  Future<void> upsert(FinisseurStickEventsCompanion companion) {
    return into(finisseurStickEvents)
        .insert(companion, mode: InsertMode.insertOrReplace);
  }

  Future<List<FinisseurStickEvent>> forSession(String sessionId) {
    return (select(finisseurStickEvents)
          ..where((e) => e.sessionId.equals(sessionId))
          ..orderBy([(e) => OrderingTerm.asc(e.stickIndex)]))
        .get();
  }

  Future<int> countForSession(String sessionId) async {
    final count = finisseurStickEvents.id.count();
    final query = selectOnly(finisseurStickEvents)
      ..addColumns([count])
      ..where(finisseurStickEvents.sessionId.equals(sessionId));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  Future<int> deleteByStickIndex({
    required String sessionId,
    required int stickIndex,
  }) {
    return (delete(finisseurStickEvents)
          ..where(
            (e) =>
                e.sessionId.equals(sessionId) &
                e.stickIndex.equals(stickIndex),
          ))
        .go();
  }
}
