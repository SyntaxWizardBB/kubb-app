// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'badge_unlocks_dao.dart';

// ignore_for_file: type=lint
mixin _$BadgeUnlocksDaoMixin on DatabaseAccessor<AppDatabase> {
  $BadgeUnlocksTable get badgeUnlocks => attachedDatabase.badgeUnlocks;
  BadgeUnlocksDaoManager get managers => BadgeUnlocksDaoManager(this);
}

class BadgeUnlocksDaoManager {
  final _$BadgeUnlocksDaoMixin _db;
  BadgeUnlocksDaoManager(this._db);
  $$BadgeUnlocksTableTableManager get badgeUnlocks =>
      $$BadgeUnlocksTableTableManager(_db.attachedDatabase, _db.badgeUnlocks);
}
