import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/dao/player_dao.dart';
import 'package:uuid/uuid.dart';

/// Thin wrapper over [PlayerDao] for the single-profile MVP.
///
/// When more than one row exists, the repository returns the oldest by
/// `createdAt` ascending. F1 only ever creates a single profile; the
/// guarantee is on the caller side.
class PlayerRepository {
  PlayerRepository(this._dao, {Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final PlayerDao _dao;
  final Uuid _uuid;

  Future<Player?> currentOrNull() async {
    final rows = await _dao.all();
    return rows.isEmpty ? null : rows.first;
  }

  Future<Player> create({required String name}) async {
    final now = DateTime.now().toUtc();
    final companion = PlayersCompanion(
      id: Value(_uuid.v7()),
      name: Value(name),
      deviceId: Value(_uuid.v7()),
      createdAt: Value(now),
    );
    await _dao.insert(companion);
    final stored = await _dao.getById(companion.id.value);
    if (stored == null) {
      throw StateError('inserted player ${companion.id.value} not retrievable');
    }
    return stored;
  }

  Stream<Player?> watchCurrent() {
    final query = _dao.select(_dao.players)
      ..orderBy([(p) => OrderingTerm.asc(p.createdAt)])
      ..limit(1);
    return query.watch().map((rows) => rows.isEmpty ? null : rows.first);
  }

  Future<Player> update({
    required String id,
    required String name,
    String? avatarColor,
  }) async {
    final affected = await _dao.updateById(
      id,
      PlayersCompanion(
        name: Value(name),
        avatarColor: Value(avatarColor),
      ),
    );
    if (affected == 0) {
      throw StateError('no player row matched id $id');
    }
    final stored = await _dao.getById(id);
    if (stored == null) {
      throw StateError('updated player $id not retrievable');
    }
    return stored;
  }
}
