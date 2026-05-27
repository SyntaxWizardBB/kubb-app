import 'package:meta/meta.dart';

/// Local stub for the value object produced by `LeaguePointsEngine`
/// (TASK-M5.1-T4). The Wave-1 merge replaces this stub with the canonical
/// definition from `tournament/tournament_points_award.dart`.
///
/// Only the fields read by [SeasonStandingsAggregator] are modelled here so
/// the aggregator can be implemented and tested in parallel to T4.
@immutable
class TournamentPointsAward {
  const TournamentPointsAward({
    required this.participantId,
    required this.displayName,
    required this.tournamentId,
    required this.basePoints,
    required this.finalPoints,
  });

  final String participantId;
  final String displayName;
  final String tournamentId;
  final double basePoints;
  final double finalPoints;
}

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
      // Last writer wins for the display name; aggregator does not adjudicate
      // rename conflicts (handled upstream).
      names[award.participantId] = award.displayName;
    }

    final rows = <SeasonStandingsRow>[];
    for (final entry in byParticipant.entries) {
      var total = 0.0;
      final tournaments = <String>{};
      for (final award in entry.value) {
        total += award.finalPoints;
        tournaments.add(award.tournamentId);
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
