import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/tables/players.dart';

class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get playerId =>
      text().references(Players, #id, onDelete: KeyAction.restrict)();
  TextColumn get kind => text()();
  TextColumn get mode => text().withDefault(const Constant('sniper'))();
  RealColumn get distanceMeters => real()();
  IntColumn get throwTarget => integer().nullable()();
  IntColumn get finField => integer().nullable()();
  IntColumn get finBase => integer().nullable()();
  TextColumn get status => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
