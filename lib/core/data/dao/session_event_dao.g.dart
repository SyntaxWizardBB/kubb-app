// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_event_dao.dart';

// ignore_for_file: type=lint
mixin _$SessionEventDaoMixin on DatabaseAccessor<AppDatabase> {
  $PlayersTable get players => attachedDatabase.players;
  $SessionsTable get sessions => attachedDatabase.sessions;
  $SessionEventsTable get sessionEvents => attachedDatabase.sessionEvents;
  SessionEventDaoManager get managers => SessionEventDaoManager(this);
}

class SessionEventDaoManager {
  final _$SessionEventDaoMixin _db;
  SessionEventDaoManager(this._db);
  $$PlayersTableTableManager get players =>
      $$PlayersTableTableManager(_db.attachedDatabase, _db.players);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db.attachedDatabase, _db.sessions);
  $$SessionEventsTableTableManager get sessionEvents =>
      $$SessionEventsTableTableManager(_db.attachedDatabase, _db.sessionEvents);
}
