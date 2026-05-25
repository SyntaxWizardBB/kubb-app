import 'package:kubb_domain/src/tournament/ekc_score.dart';
import 'package:kubb_domain/src/tournament/tiebreaker.dart';
import 'package:meta/meta.dart';

/// One finished match in a tournament, used as input to standings calc.
///
/// If [participantB] is null, the match is a BYE: [participantA] advances
/// with the configured bye score and the [score] field is ignored.
@immutable
class TournamentMatchResult {
  const TournamentMatchResult({
    required this.participantA,
    required this.participantB,
    required this.score,
  });

  final String participantA;
  final String? participantB;
  final MatchEkcScore score;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TournamentMatchResult &&
          other.participantA == participantA &&
          other.participantB == participantB &&
          other.score == score;
  @override
  int get hashCode => Object.hash(participantA, participantB, score);
  @override
  String toString() =>
      'TournamentMatchResult($participantA vs ${participantB ?? "BYE"})';
}

class _Acc {
  int totalPoints = 0;
  int wins = 0;
  int kubbsScored = 0;
  int kubbsConceded = 0;
  final List<String> opponentIds = [];
  final Map<String, int> headToHead = {};
}

/// Pure ranking function (FR-RANK-3/-4). Computes per-participant stats from
/// confirmed match results, then sorts via [tiebreaker].
List<ParticipantStats> computeStandings({
  required List<String> participantIds,
  required List<TournamentMatchResult> results,
  required TiebreakerChain tiebreaker,
  int byeScoreForUnopposedParticipant = 0,
}) {
  final ids = participantIds.toSet();
  final accs = {for (final id in participantIds) id: _Acc()};
  void check(String id) {
    if (!ids.contains(id)) {
      throw ArgumentError('result references unknown participant: $id');
    }
  }

  for (final r in results) {
    check(r.participantA);
    if (r.participantB == null) {
      accs[r.participantA]!
        ..totalPoints += byeScoreForUnopposedParticipant
        ..wins += 1;
      continue;
    }
    check(r.participantB!);
    final a = accs[r.participantA]!;
    final b = accs[r.participantB!]!;
    final kA = r.score.sets.fold<int>(0, (s, x) => s + x.basekubbsKnockedByA);
    final kB = r.score.sets.fold<int>(0, (s, x) => s + x.basekubbsKnockedByB);
    final w = r.score.matchWinner;
    final d = w == null ? 0 : (w == SetWinner.teamA ? 1 : -1);
    a
      ..totalPoints += r.score.pointsForA
      ..kubbsScored += kA
      ..kubbsConceded += kB
      ..wins += w == SetWinner.teamA ? 1 : 0
      ..opponentIds.add(r.participantB!);
    b
      ..totalPoints += r.score.pointsForB
      ..kubbsScored += kB
      ..kubbsConceded += kA
      ..wins += w == SetWinner.teamB ? 1 : 0
      ..opponentIds.add(r.participantA);
    a.headToHead.update(r.participantB!, (v) => v + d, ifAbsent: () => d);
    b.headToHead.update(r.participantA, (v) => v - d, ifAbsent: () => -d);
  }

  final totals = {for (final e in accs.entries) e.key: e.value.totalPoints};
  final stats = [
    for (final id in participantIds)
      ParticipantStats(
        participantId: id,
        totalPoints: accs[id]!.totalPoints,
        wins: accs[id]!.wins,
        kubbsScored: accs[id]!.kubbsScored,
        kubbsConceded: accs[id]!.kubbsConceded,
        opponentIds: List.unmodifiable(accs[id]!.opponentIds),
        opponentTotalPointsLookup: {
          for (final o in accs[id]!.opponentIds) o: totals[o] ?? 0,
        },
        headToHeadLookup: Map.unmodifiable(accs[id]!.headToHead),
      ),
  ];
  return stats..sort(tiebreaker.compare);
}
