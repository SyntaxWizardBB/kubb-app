// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inbox_messages_dao.dart';

// ignore_for_file: type=lint
mixin _$InboxMessagesDaoMixin on DatabaseAccessor<AppDatabase> {
  $InboxMessagesTable get inboxMessages => attachedDatabase.inboxMessages;
  InboxMessagesDaoManager get managers => InboxMessagesDaoManager(this);
}

class InboxMessagesDaoManager {
  final _$InboxMessagesDaoMixin _db;
  InboxMessagesDaoManager(this._db);
  $$InboxMessagesTableTableManager get inboxMessages =>
      $$InboxMessagesTableTableManager(_db.attachedDatabase, _db.inboxMessages);
}
