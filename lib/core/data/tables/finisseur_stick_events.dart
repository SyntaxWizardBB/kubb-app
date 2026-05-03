import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/tables/sessions.dart';

class FinisseurStickEvents extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId =>
      text().references(Sessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get stickIndex => integer()();
  IntColumn get fieldKubbsHit => integer().withDefault(const Constant(0))();
  BoolColumn get eightMHit => boolean().withDefault(const Constant(false))();
  BoolColumn get heliThrow => boolean().withDefault(const Constant(false))();
  BoolColumn get kingHit => boolean().nullable()();
  TextColumn get kingPosition => text().nullable()();
  IntColumn get penaltyHits1 => integer().withDefault(const Constant(0))();
  IntColumn get penaltyHits2 => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
