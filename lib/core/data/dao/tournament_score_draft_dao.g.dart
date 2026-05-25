// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tournament_score_draft_dao.dart';

// ignore_for_file: type=lint
mixin _$TournamentScoreDraftDaoMixin on DatabaseAccessor<AppDatabase> {
  $TournamentScoreDraftsTable get tournamentScoreDrafts =>
      attachedDatabase.tournamentScoreDrafts;
  TournamentScoreDraftDaoManager get managers =>
      TournamentScoreDraftDaoManager(this);
}

class TournamentScoreDraftDaoManager {
  final _$TournamentScoreDraftDaoMixin _db;
  TournamentScoreDraftDaoManager(this._db);
  $$TournamentScoreDraftsTableTableManager get tournamentScoreDrafts =>
      $$TournamentScoreDraftsTableTableManager(
        _db.attachedDatabase,
        _db.tournamentScoreDrafts,
      );
}
