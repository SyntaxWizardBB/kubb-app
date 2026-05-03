import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/tables/players.dart';

part 'player_dao.g.dart';

@DriftAccessor(tables: [Players])
class PlayerDao extends DatabaseAccessor<AppDatabase> with _$PlayerDaoMixin {
  PlayerDao(super.attachedDatabase);

  Future<Player?> getById(String id) {
    return (select(players)..where((p) => p.id.equals(id))).getSingleOrNull();
  }

  Future<List<Player>> all() {
    return (select(players)..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
        .get();
  }

  Future<void> insert(PlayersCompanion companion) {
    return into(players).insert(companion);
  }

  Future<int> updateById(String id, PlayersCompanion patch) {
    return (update(players)..where((p) => p.id.equals(id))).write(patch);
  }

  Future<void> deleteById(String id) {
    return (delete(players)..where((p) => p.id.equals(id))).go();
  }
}
