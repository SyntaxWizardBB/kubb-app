// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player_dao.dart';

// ignore_for_file: type=lint
mixin _$PlayerDaoMixin on DatabaseAccessor<AppDatabase> {
  $PlayersTable get players => attachedDatabase.players;
  PlayerDaoManager get managers => PlayerDaoManager(this);
}

class PlayerDaoManager {
  final _$PlayerDaoMixin _db;
  PlayerDaoManager(this._db);
  $$PlayersTableTableManager get players =>
      $$PlayersTableTableManager(_db.attachedDatabase, _db.players);
}
