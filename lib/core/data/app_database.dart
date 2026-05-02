import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/dao/app_settings_dao.dart';
import 'package:kubb_app/core/data/dao/player_dao.dart';
import 'package:kubb_app/core/data/dao/session_dao.dart';
import 'package:kubb_app/core/data/dao/session_event_dao.dart';
import 'package:kubb_app/core/data/tables/app_settings_table.dart';
import 'package:kubb_app/core/data/tables/players.dart';
import 'package:kubb_app/core/data/tables/session_events.dart';
import 'package:kubb_app/core/data/tables/sessions.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Players, Sessions, SessionEvents, AppSettingsTable],
  daos: [PlayerDao, SessionDao, SessionEventDao, AppSettingsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

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
        },
      );
}
