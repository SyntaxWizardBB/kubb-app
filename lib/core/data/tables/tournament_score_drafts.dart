import 'package:drift/drift.dart';

/// Per-match per-consensus-round draft of the score entry.
///
/// Persists unsubmitted score input so it survives app-kill, reconnect
/// or screen pop (DSCORE-19/20). Submission or consensus round bump
/// removes the relevant rows (DSCORE-21/22).
@DataClassName('TournamentScoreDraftRow')
class TournamentScoreDrafts extends Table {
  TextColumn get matchId => text()();
  IntColumn get consensusRound => integer()();
  TextColumn get payload => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {matchId, consensusRound};
}
