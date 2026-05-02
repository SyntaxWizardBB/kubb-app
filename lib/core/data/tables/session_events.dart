import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/tables/sessions.dart';

class SessionEvents extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get correctedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
