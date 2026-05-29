import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/dao/app_settings_dao.dart';
import 'package:kubb_app/core/data/dao/finisseur_stick_event_dao.dart';
import 'package:kubb_app/core/data/dao/player_dao.dart';
import 'package:kubb_app/core/data/dao/score_submission_outbox_dao.dart';
import 'package:kubb_app/core/data/dao/session_dao.dart';
import 'package:kubb_app/core/data/dao/session_event_dao.dart';
import 'package:kubb_app/core/data/dao/tournament_score_draft_dao.dart';
import 'package:kubb_app/core/data/tables/app_settings_table.dart';
import 'package:kubb_app/core/data/tables/finisseur_stick_events.dart';
import 'package:kubb_app/core/data/tables/players.dart';
import 'package:kubb_app/core/data/tables/score_submission_outbox.dart';
import 'package:kubb_app/core/data/tables/session_events.dart';
import 'package:kubb_app/core/data/tables/sessions.dart';
import 'package:kubb_app/core/data/tables/tournament_score_drafts.dart';
import 'package:kubb_app/features/achievements/data/dao/badge_unlocks_dao.dart';
import 'package:kubb_app/features/achievements/data/tables/badge_unlocks_table.dart';
import 'package:kubb_app/features/auth/data/dao/cached_auth_session_dao.dart';
import 'package:kubb_app/features/auth/data/tables/cached_auth_session_table.dart';
import 'package:kubb_app/features/inbox/data/dao/inbox_messages_dao.dart';
import 'package:kubb_app/features/inbox/data/tables/inbox_messages_table.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    Players,
    Sessions,
    SessionEvents,
    AppSettingsTable,
    FinisseurStickEvents,
    CachedAuthSession,
    TournamentScoreDrafts,
    ScoreSubmissionOutbox,
    InboxMessages,
    BadgeUnlocks,
  ],
  daos: [
    PlayerDao,
    SessionDao,
    SessionEventDao,
    AppSettingsDao,
    FinisseurStickEventDao,
    CachedAuthSessionDao,
    TournamentScoreDraftDao,
    ScoreSubmissionOutboxDao,
    InboxMessagesDao,
    BadgeUnlocksDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 8;

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
          if (from < 4) {
            await m.createTable(cachedAuthSession);
          }
          if (from < 5) {
            await m.createTable(tournamentScoreDrafts);
          }
          if (from < 6) {
            await m.createTable(scoreSubmissionOutbox);
          }
          if (from < 7) {
            await m.createTable(inboxMessages);
          }
          if (from < 8) {
            await m.createTable(badgeUnlocks);
          }
        },
      );

  /// Truncates every table the database owns inside a single transaction.
  ///
  /// Used by the account-deletion flow to satisfy GDPR Art. 17 — the
  /// server-side row removal handled by `deleteCurrentAccount` only takes
  /// care of cloud-persisted state, while a meaningful chunk of user data
  /// (training sessions, drafts, outbox, cached auth, app settings) lives
  /// here in drift and would otherwise survive into the next account on
  /// the same device.
  ///
  /// Iterating `allTables` keeps the wipe exhaustive without a hand-
  /// maintained list — any future `tables:` addition is covered for free.
  /// The reverse order matters when `PRAGMA foreign_keys = ON`: child
  /// tables (session_events, finisseur_stick_events) reference sessions
  /// which references players, and a restrict-action FK would refuse the
  /// delete if we processed the parent first.
  ///
  /// Wrapping the loop in a single transaction guarantees the wipe is
  /// atomic: a partial wipe would leave foreign-key fragments behind and
  /// is worse than no wipe at all.
  Future<void> wipeAll() async {
    await transaction(() async {
      for (final table in allTables.toList().reversed) {
        await delete(table).go();
      }
    });
  }
}
