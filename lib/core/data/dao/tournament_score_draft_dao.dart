import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:kubb_app/core/data/app_database.dart';
import 'package:kubb_app/core/data/tables/tournament_score_drafts.dart';
import 'package:kubb_domain/kubb_domain.dart';

part 'tournament_score_draft_dao.g.dart';

@DriftAccessor(tables: [TournamentScoreDrafts])
class TournamentScoreDraftDao extends DatabaseAccessor<AppDatabase>
    with _$TournamentScoreDraftDaoMixin {
  TournamentScoreDraftDao(super.attachedDatabase);

  Future<List<SetScore>?> load(
    TournamentMatchId matchId,
    int consensusRound,
  ) async {
    final row = await (select(tournamentScoreDrafts)
          ..where(
            (t) =>
                t.matchId.equals(matchId.value) &
                t.consensusRound.equals(consensusRound),
          ))
        .getSingleOrNull();
    if (row == null) return null;
    final decoded = jsonDecode(row.payload) as List<dynamic>;
    return decoded
        .map((e) => _setScoreFromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> save(
    TournamentMatchId matchId,
    int consensusRound,
    List<SetScore> sets,
  ) {
    return into(tournamentScoreDrafts).insertOnConflictUpdate(
      TournamentScoreDraftsCompanion.insert(
        matchId: matchId.value,
        consensusRound: consensusRound,
        payload:
            jsonEncode(sets.map(_setScoreToJson).toList(growable: false)),
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> clear(
    TournamentMatchId matchId, {
    int? consensusRound,
  }) {
    if (consensusRound == null) {
      return (delete(tournamentScoreDrafts)
            ..where((t) => t.matchId.equals(matchId.value)))
          .go();
    }
    return (delete(tournamentScoreDrafts)
          ..where(
            (t) =>
                t.matchId.equals(matchId.value) &
                t.consensusRound.equals(consensusRound),
          ))
        .go();
  }

  Map<String, Object?> _setScoreToJson(SetScore s) => {
        'a': s.basekubbsKnockedByA,
        'b': s.basekubbsKnockedByB,
        'winner': switch (s.winner) {
          SetWinner.teamA => 'teamA',
          SetWinner.teamB => 'teamB',
          // M2a: a non-decisive set (no king in the group phase) is the
          // canonical SetWinner.none; round-trip it through the draft store.
          SetWinner.none => 'none',
        },
      };

  SetScore _setScoreFromJson(Map<String, dynamic> json) => SetScore(
        basekubbsKnockedByA: json['a'] as int,
        basekubbsKnockedByB: json['b'] as int,
        winner: switch (json['winner'] as String) {
          'teamA' => SetWinner.teamA,
          'teamB' => SetWinner.teamB,
          'none' => SetWinner.none,
          final v => throw FormatException('unknown SetWinner: $v'),
        },
      );
}
