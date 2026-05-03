import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/dao/app_settings_dao.dart';
import 'package:kubb_app/core/data/dao/finisseur_stick_event_dao.dart';
import 'package:kubb_app/core/data/dao/player_dao.dart';
import 'package:kubb_app/core/data/dao/session_dao.dart';
import 'package:kubb_app/core/data/dao/session_event_dao.dart';
import 'package:kubb_app/core/data/tables/app_settings_table.dart';
import 'package:kubb_app/core/data/tables/finisseur_stick_events.dart';
import 'package:kubb_app/core/data/tables/players.dart';
import 'package:kubb_app/core/data/tables/session_events.dart';
import 'package:kubb_app/core/data/tables/sessions.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Players,
    Sessions,
    SessionEvents,
    AppSettingsTable,
    FinisseurStickEvents,
  ],
  daos: [
    PlayerDao,
    SessionDao,
    SessionEventDao,
    AppSettingsDao,
    FinisseurStickEventDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement(
            'CREATE INDEX idx_sessions_status_completed '
            'ON sessions (status, completed_at DESC)',
          );
          await customStatement(
            'CREATE INDEX idx_session_events_session_corrected '
            'ON session_events (session_id, corrected_at, created_at DESC)',
          );
          await customStatement(
            'CREATE UNIQUE INDEX idx_finisseur_stick_session_index '
            'ON finisseur_stick_events (session_id, stick_index)',
          );
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(players, players.avatarColor);
          }
          if (from < 3) {
            await m.addColumn(sessions, sessions.mode);
            await m.addColumn(sessions, sessions.finField);
            await m.addColumn(sessions, sessions.finBase);
            await m.createTable(finisseurStickEvents);
            await customStatement(
              'CREATE UNIQUE INDEX idx_finisseur_stick_session_index '
              'ON finisseur_stick_events (session_id, stick_index)',
            );
          }
        },
      );
}
