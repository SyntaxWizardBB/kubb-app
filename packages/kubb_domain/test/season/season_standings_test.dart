import 'package:kubb_domain/src/season/season_standings.dart';
import 'package:kubb_domain/src/tournament/tournament_points_award.dart';
import 'package:test/test.dart';

TournamentPointsAward award({
  required String participantId,
  required String tournamentId,
  required double finalPoints,
  String displayName = 'X',
  double? basePoints,
}) {
  return TournamentPointsAward(
    participantId: participantId,
    displayName: displayName,
    tournamentId: tournamentId,
    placement: 1,
    basePoints: basePoints ?? finalPoints,
    finalPoints: finalPoints,
    breakdown: '',
  );
}

void main() {
  group('SeasonStandingsAggregator', () {
    test('sums three awards for the same participant', () {
      final rows = SeasonStandingsAggregator.aggregate([
        award(participantId: 'X', tournamentId: 't1', finalPoints: 10),
        award(participantId: 'X', tournamentId: 't2', finalPoints: 10),
        award(participantId: 'X', tournamentId: 't3', finalPoints: 10),
      ]);

      expect(rows, hasLength(1));
      expect(rows.single.totalPoints, 30);
      expect(rows.single.tournamentCount, 3);
    });

    test('reversal-row with negative final points subtracts', () {
      final rows = SeasonStandingsAggregator.aggregate([
        award(participantId: 'X', tournamentId: 't1', finalPoints: 10),
        award(participantId: 'X', tournamentId: 't2', finalPoints: 7),
        // Reversal of t2 (OD-M5-07): same tournament, negated points.
        award(
          participantId: 'X',
          tournamentId: 't2',
          finalPoints: -7,
          basePoints: -7,
        ),
      ]);

      expect(rows.single.totalPoints, 10);
      // Reversal does not inflate the distinct tournament participation count.
      expect(rows.single.tournamentCount, 2);
    });

    test('ties on total points place more tournaments first', () {
      final rows = SeasonStandingsAggregator.aggregate([
        // A: 20 in one tournament.
        award(
          participantId: 'A',
          displayName: 'Alice',
          tournamentId: 't1',
          finalPoints: 20,
        ),
        // B: 10 + 10 across two tournaments → same Σ, higher count.
        award(
          participantId: 'B',
          displayName: 'Bob',
          tournamentId: 't1',
          finalPoints: 10,
        ),
        award(
          participantId: 'B',
          displayName: 'Bob',
          tournamentId: 't2',
          finalPoints: 10,
        ),
      ]);

      expect(rows.map((r) => r.participantId).toList(), ['B', 'A']);
    });
  });
}
