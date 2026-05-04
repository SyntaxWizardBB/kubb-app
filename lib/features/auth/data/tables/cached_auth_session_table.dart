import 'package:drift/drift.dart';

/// Single-row cache of the active auth session for offline boot.
///
/// Holds enough metadata to render the UI without a server roundtrip
/// (`displayName`, `avatarColor`) and to decide whether the cached JWT
/// is still usable (`expiresAt`, `refreshAfter`). Tokens themselves
/// live in `flutter_secure_storage` — see ADR-0010 §AK-14.
class CachedAuthSession extends Table {
  TextColumn get id => text().withDefault(const Constant('singleton'))();
  TextColumn get userId => text()();
  TextColumn get kind => text()();
  TextColumn get displayName => text()();
  TextColumn get avatarColor => text().nullable()();
  DateTimeColumn get expiresAt => dateTime()();
  DateTimeColumn get refreshAfter => dateTime()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
