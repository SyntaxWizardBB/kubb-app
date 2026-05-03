import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/dao/session_dao.dart';
import 'package:kubb_app/core/data/dao/session_event_dao.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

const _kindSniper = 'sniper';
const _statusActive = 'active';
const _statusCompleted = 'completed';

/// Thin wrapper over `SessionDao` + `SessionEventDao`. All write paths produce
/// UUIDv7 ids and UTC timestamps. `discard` is a hard delete; FK cascade
/// removes related events.
class TrainingRepository {
  TrainingRepository({
    required SessionDao sessionDao,
    required SessionEventDao eventDao,
    Uuid? uuid,
  })  : _sessions = sessionDao,
        _events = eventDao,
        _uuid = uuid ?? const Uuid();

  final SessionDao _sessions;
  final SessionEventDao _events;
  final Uuid _uuid;
  final Logger _log = Logger('TrainingRepository');

  Future<Session> startSession({
    required String playerId,
    required double distance,
    int? throwTarget,
  }) async {
    final stale = await _sessions.activeForPlayer(playerId);
    if (stale != null) {
      _log.warning('discarding stale active session ${stale.id}');
      await _sessions.deleteById(stale.id);
    }
    final row = Session(
      id: _uuid.v7(),
      playerId: playerId,
      kind: _kindSniper,
      distanceMeters: distance,
      throwTarget: throwTarget,
      status: _statusActive,
      startedAt: DateTime.now().toUtc(),
    );
    await _sessions.insert(row.toCompanion(false));
    return row;
  }

  Future<SessionEvent> appendEvent({
    required String sessionId,
    required String kind,
  }) async {
    final event = SessionEvent(
      id: _uuid.v7(),
      sessionId: sessionId,
      kind: kind,
      createdAt: DateTime.now().toUtc(),
    );
    await _events.insert(event.toCompanion(false));
    return event;
  }

  Future<void> softDeleteLastEvent({
    required String sessionId,
    required String kind,
  }) async {
    final latest = await _events.latestNonDeletedOfKind(sessionId, kind);
    if (latest == null) return;
    await _events.markCorrected(latest.id, DateTime.now().toUtc());
  }

  Future<void> markCompleted({required String sessionId}) {
    return _sessions.updateStatus(
      sessionId,
      _statusCompleted,
      completedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> discard({required String sessionId}) {
    return _sessions.deleteById(sessionId);
  }

  Stream<Session?> watchActiveSession({required String playerId}) {
    final query = _sessions.select(_sessions.sessions)
      ..where(
        (s) => s.playerId.equals(playerId) & s.status.equals(_statusActive),
      )
      ..limit(1);
    return query.watch().map((rows) => rows.isEmpty ? null : rows.first);
  }

  Stream<List<Session>> watchRecentCompleted({
    required String playerId,
    int limit = 3,
  }) {
    return _sessions.watchRecentCompleted(playerId: playerId, limit: limit);
  }

  Future<Session?> loadActiveOrNull({required String playerId}) {
    return _sessions.activeForPlayer(playerId);
  }

  Future<List<SessionEvent>> eventsOf(String sessionId) {
    return _events.forSession(sessionId);
  }
}

final trainingRepositoryProvider = Provider<TrainingRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TrainingRepository(
    sessionDao: db.sessionDao,
    eventDao: db.sessionEventDao,
  );
});
