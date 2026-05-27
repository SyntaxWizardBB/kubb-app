import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  final at = DateTime.utc(2026, 5, 27, 12);

  BracketAdvanceEvent build({
    String tournament = 't1',
    String match = 'm1',
    int round = 2,
    int matchNumber = 1,
    String winner = 'p1',
    DateTime? when,
  }) =>
      BracketAdvanceEvent(
        tournamentId: TournamentId(tournament),
        advancedMatchId: TournamentMatchId(match),
        targetRound: round,
        targetMatchNumber: matchNumber,
        winnerParticipant: TournamentParticipantId(winner),
        at: when ?? at,
      );

  group('BracketAdvanceEvent', () {
    test('exposes all fields verbatim', () {
      final event = build();
      expect(event.tournamentId, const TournamentId('t1'));
      expect(event.advancedMatchId, const TournamentMatchId('m1'));
      expect(event.targetRound, 2);
      expect(event.targetMatchNumber, 1);
      expect(event.winnerParticipant, const TournamentParticipantId('p1'));
      expect(event.at, at);
    });

    test('equality holds for identical field values', () {
      expect(build(), equals(build()));
      expect(build().hashCode, equals(build().hashCode));
    });

    test('differs when any field differs', () {
      final base = build();
      expect(base == build(tournament: 't2'), isFalse);
      expect(base == build(match: 'm2'), isFalse);
      expect(base == build(round: 3), isFalse);
      expect(base == build(matchNumber: 2), isFalse);
      expect(base == build(winner: 'p2'), isFalse);
      expect(
        base == build(when: at.add(const Duration(seconds: 1))),
        isFalse,
      );
    });
  });
}
