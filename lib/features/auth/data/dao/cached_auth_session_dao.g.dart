// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cached_auth_session_dao.dart';

// ignore_for_file: type=lint
mixin _$CachedAuthSessionDaoMixin on DatabaseAccessor<AppDatabase> {
  $CachedAuthSessionTable get cachedAuthSession =>
      attachedDatabase.cachedAuthSession;
  CachedAuthSessionDaoManager get managers => CachedAuthSessionDaoManager(this);
}

class CachedAuthSessionDaoManager {
  final _$CachedAuthSessionDaoMixin _db;
  CachedAuthSessionDaoManager(this._db);
  $$CachedAuthSessionTableTableManager get cachedAuthSession =>
      $$CachedAuthSessionTableTableManager(
        _db.attachedDatabase,
        _db.cachedAuthSession,
      );
}
