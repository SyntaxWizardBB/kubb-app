import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/app_database_provider.dart';
import 'package:kubb_app/core/data/dao/finisseur_stick_event_dao.dart';
import 'package:kubb_app/core/data/dao/session_dao.dart';
import 'package:kubb_app/features/training/application/active_finisseur_state.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

const _kindFinisseur = 'finisseur';
const _statusActive = 'active';
const _statusCompleted = 'completed';

/// Persistence wrapper for a finisseur training session. Each call produces
/// UUIDv7 ids and UTC timestamps. Discard is a hard delete; FK cascade
/// removes related stick events.
class FinisseurRepository {
  FinisseurRepository({
    required SessionDao sessionDao,
    required FinisseurStickEventDao stickDao,
    Uuid? uuid,
  })  : _sessions = sessionDao,
        _sticks = stickDao,
        _uuid = uuid ?? const Uuid();

  final SessionDao _sessions;
  final FinisseurStickEventDao _sticks;
  final Uuid _uuid;
  final Logger _log = Logger('FinisseurRepository');

  Future<Session> startFinisseur({
    required String playerId,
    required int field,
    required int base,
  }) async {
    final stale = await _sessions.activeForUserInMode(playerId, _kindFinisseur);
    if (stale != null) {
      _log.warning('discarding stale active finisseur session ${stale.id}');
      await _sessions.deleteById(stale.id);
    }
    final row = Session(
      id: _uuid.v7(),
      playerId: playerId,
      kind: _kindFinisseur,
      mode: _kindFinisseur,
      distanceMeters: 8,
      finField: field,
      finBase: base,
      status: _statusActive,
      startedAt: DateTime.now().toUtc(),
    );
    await _sessions.insert(row.toCompanion(false));
    return row;
  }

  Future<void> recordStick({
    required String sessionId,
    required int stickIndex,
    required StickResult result,
  }) async {
    final entity = FinisseurStickEventsCompanion(
      id: Value(_uuid.v7()),
      sessionId: Value(sessionId),
      stickIndex: Value(stickIndex),
      fieldKubbsHit: Value(result.fieldHits),
      eightMHit: Value(result.eightMHit),
      heliThrow: Value(result.heli),
      kingHit: result.king == null
          ? const Value.absent()
          : Value(result.king!.hit),
      kingPosition: result.king == null
          ? const Value.absent()
          : Value(result.king!.position.name),
      penaltyHits1: Value(result.penalty1),
      penaltyHits2: Value(result.penalty2),
      createdAt: Value(DateTime.now().toUtc()),
    );
    // insertOrReplace defends the unique (session_id, stick_index) index
    // when a retry or out-of-band write hits the same slot — the notifier
    // mutex prevents the in-process race, this covers the rest.
    await _sticks.upsert(entity);
  }

  Future<void> markCompleted({required String sessionId}) {
    return _sessions.updateStatus(
      sessionId,
      _statusCompleted,
      completedAt: DateTime.now().toUtc(),
    );
  }

  Future<void> deleteStickAt({
    required String sessionId,
    required int stickIndex,
  }) {
    return _sticks.deleteByStickIndex(
      sessionId: sessionId,
      stickIndex: stickIndex,
    );
  }

  Future<void> discard({required String sessionId}) {
    return _sessions.deleteById(sessionId);
  }

  Future<Session?> loadActiveOrNull({required String playerId}) {
    return _sessions.activeForUserInMode(playerId, _kindFinisseur);
  }

  Future<List<FinisseurStickEvent>> loadStickEvents(String sessionId) {
    return _sticks.forSession(sessionId);
  }
}

final finisseurRepositoryProvider = Provider<FinisseurRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return FinisseurRepository(
    sessionDao: db.sessionDao,
    stickDao: db.finisseurStickEventDao,
  );
});
