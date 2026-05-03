// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'finisseur_stick_event_dao.dart';

// ignore_for_file: type=lint
mixin _$FinisseurStickEventDaoMixin on DatabaseAccessor<AppDatabase> {
  $PlayersTable get players => attachedDatabase.players;
  $SessionsTable get sessions => attachedDatabase.sessions;
  $FinisseurStickEventsTable get finisseurStickEvents =>
      attachedDatabase.finisseurStickEvents;
  FinisseurStickEventDaoManager get managers =>
      FinisseurStickEventDaoManager(this);
}

class FinisseurStickEventDaoManager {
  final _$FinisseurStickEventDaoMixin _db;
  FinisseurStickEventDaoManager(this._db);
  $$PlayersTableTableManager get players =>
      $$PlayersTableTableManager(_db.attachedDatabase, _db.players);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
  $$FinisseurStickEventsTableTableManager get finisseurStickEvents =>
      $$FinisseurStickEventsTableTableManager(
        _db.attachedDatabase,
        _db.finisseurStickEvents,
      );
}
