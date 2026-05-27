import 'package:kubb_domain/src/tournament/tournament_points_award.dart';
import 'package:meta/meta.dart';

/// Read-model row of the cross-tournament season standings (architecture
/// §3.3, ADR-0025 lineare Aggregation).
@immutable
class SeasonStandingsRow {
  SeasonStandingsRow({
    required this.participantId,
    required this.displayName,
    required this.totalPoints,
    required this.tournamentCount,
    required List<TournamentPointsAward> awards,
  }) : awards = List.unmodifiable(awards);

  final String participantId;
  final String displayName;
  final double totalPoints;
  final int tournamentCount;
  final List<TournamentPointsAward> awards;
}

/// Linear additive aggregator across [TournamentPointsAward]s.
///
/// Sorting (OD-M5-06 Empfehlung A):
///   1. `totalPoints` desc
///   2. `tournamentCount` desc
///   3. `displayName` asc
///
/// Reversal-Awards (negative `finalPoints`) reduce both `totalPoints` and the
/// distinct `tournamentCount` is computed over unique `tournamentId`s — a
/// reversal targets the same tournament and therefore does not inflate the
/// participation count (OD-M5-07).
class SeasonStandingsAggregator {
  const SeasonStandingsAggregator._();

  static List<SeasonStandingsRow> aggregate(
    List<TournamentPointsAward> awards,
  ) {
    final byParticipant = <String, List<TournamentPointsAward>>{};
    final names = <String, String>{};
    for (final award in awards) {
      byParticipant.putIfAbsent(award.participantId, () => []).add(award);
      if (award.displayName != null) {
        names[award.participantId] = award.displayName!;
      }
      names.putIfAbsent(award.participantId, () => award.participantId);
    }

    final rows = <SeasonStandingsRow>[];
    for (final entry in byParticipant.entries) {
      var total = 0.0;
      final tournaments = <String>{};
      for (final award in entry.value) {
        total += award.finalPoints;
        if (award.tournamentId != null) {
          tournaments.add(award.tournamentId!);
        }
      }
      rows.add(
        SeasonStandingsRow(
          participantId: entry.key,
          displayName: names[entry.key]!,
          totalPoints: total,
          tournamentCount: tournaments.length,
          awards: entry.value,
        ),
      );
    }

    rows.sort((a, b) {
      final byTotal = b.totalPoints.compareTo(a.totalPoints);
      if (byTotal != 0) return byTotal;
      final byCount = b.tournamentCount.compareTo(a.tournamentCount);
      if (byCount != 0) return byCount;
      return a.displayName.compareTo(b.displayName);
    });
    return List.unmodifiable(rows);
  }
}
