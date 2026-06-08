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
        // M2b (D1): persist the explicit king-outcome so the 'Keiner' /
        // timed-out distinction and the KO finisher result survive a
        // reload. Older rows without this key decode to [KingMissed] for
        // back-compat (see [_kingOutcomeFromJson]).
        'king_outcome': _kingOutcomeToJson(s.kingOutcome),
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
        kingOutcome: _kingOutcomeFromJson(
          json['king_outcome'] as Map<String, dynamic>?,
        ),
      );

  /// M2b (D1): encode the [KingOutcome] sealed class. [KingHitBy] carries
  /// the scoring participant id; [KingTimedOut] / [KingMissed] are tagged
  /// markers so the round-trip preserves the 'Keiner' distinction.
  Map<String, Object?> _kingOutcomeToJson(KingOutcome outcome) =>
      switch (outcome) {
        KingHitBy(:final participantId) => {
            'kind': 'hit_by',
            'participant_id': participantId.value,
          },
        KingTimedOut() => const {'kind': 'timed_out'},
        KingMissed() => const {'kind': 'missed'},
      };

  /// Decodes the persisted king-outcome. Missing / unknown payloads fall
  /// back to [KingMissed] — the historical default — so pre-M2b draft rows
  /// keep decoding cleanly.
  KingOutcome _kingOutcomeFromJson(Map<String, dynamic>? json) {
    if (json == null) return const KingMissed();
    return switch (json['kind'] as String?) {
      'hit_by' => KingHitBy(
          TournamentParticipantId(json['participant_id'] as String),
        ),
      'timed_out' => const KingTimedOut(),
      _ => const KingMissed(),
    };
  }
}
