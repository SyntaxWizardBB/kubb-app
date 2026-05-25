import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('TournamentSummaryRef', () {
    final a = TournamentSummaryRef(
      tournamentId: const TournamentId('t1'),
      displayName: 'Spring Cup',
      format: TournamentFormat.swiss,
      status: TournamentStatus.published,
      startedAt: DateTime.utc(2026, 5, 3),
      completedAt: DateTime.utc(2026, 5, 2),
      participantCount: 16,
    );

    test('value equality holds for identical content', () {
      final b = TournamentSummaryRef(
        tournamentId: const TournamentId('t1'),
        displayName: 'Spring Cup',
        format: TournamentFormat.swiss,
        status: TournamentStatus.published,
        startedAt: DateTime.utc(2026, 5, 3),
        completedAt: DateTime.utc(2026, 5, 2),
        participantCount: 16,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('differing status breaks equality', () {
      final b = TournamentSummaryRef(
        tournamentId: const TournamentId('t1'),
        displayName: 'Spring Cup',
        format: TournamentFormat.swiss,
        status: TournamentStatus.live,
        startedAt: DateTime.utc(2026, 5, 3),
        completedAt: DateTime.utc(2026, 5, 2),
        participantCount: 16,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('TournamentMatchRef', () {
    test('BYE (participantB null) preserves equality semantics', () {
      const a = TournamentMatchRef(
        matchId: TournamentMatchId('m1'),
        tournamentId: TournamentId('t1'),
        roundNumber: 1,
        matchNumberInRound: 3,
        participantA: TournamentParticipantId('p1'),
        participantB: null,
        status: TournamentMatchStatus.scheduled,
        consensusRound: 1,
      );
      const b = TournamentMatchRef(
        matchId: TournamentMatchId('m1'),
        tournamentId: TournamentId('t1'),
        roundNumber: 1,
        matchNumberInRound: 3,
        participantA: TournamentParticipantId('p1'),
        participantB: null,
        status: TournamentMatchStatus.scheduled,
        consensusRound: 1,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different consensusRound breaks equality', () {
      const a = TournamentMatchRef(
        matchId: TournamentMatchId('m1'),
        tournamentId: TournamentId('t1'),
        roundNumber: 1,
        matchNumberInRound: 3,
        participantA: TournamentParticipantId('p1'),
        participantB: TournamentParticipantId('p2'),
        status: TournamentMatchStatus.awaitingResults,
        consensusRound: 1,
      );
      const b = TournamentMatchRef(
        matchId: TournamentMatchId('m1'),
        tournamentId: TournamentId('t1'),
        roundNumber: 1,
        matchNumberInRound: 3,
        participantA: TournamentParticipantId('p1'),
        participantB: TournamentParticipantId('p2'),
        status: TournamentMatchStatus.awaitingResults,
        consensusRound: 2,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('TournamentSetScoreProposal', () {
    test('equal when all fields match', () {
      final score = SetScore(
        basekubbsKnockedByA: 5,
        basekubbsKnockedByB: 3,
        winner: SetWinner.teamA,
      );
      final a = TournamentSetScoreProposal(
        matchId: const TournamentMatchId('m1'),
        consensusRound: 1,
        setNumber: 1,
        submitterUserId: const UserId('u1'),
        score: score,
      );
      final b = TournamentSetScoreProposal(
        matchId: const TournamentMatchId('m1'),
        consensusRound: 1,
        setNumber: 1,
        submitterUserId: const UserId('u1'),
        score: SetScore(
          basekubbsKnockedByA: 5,
          basekubbsKnockedByB: 3,
          winner: SetWinner.teamA,
        ),
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different submitter breaks equality', () {
      final score = SetScore(
        basekubbsKnockedByA: 5,
        basekubbsKnockedByB: 3,
        winner: SetWinner.teamA,
      );
      final a = TournamentSetScoreProposal(
        matchId: const TournamentMatchId('m1'),
        consensusRound: 1,
        setNumber: 1,
        submitterUserId: const UserId('u1'),
        score: score,
      );
      final b = TournamentSetScoreProposal(
        matchId: const TournamentMatchId('m1'),
        consensusRound: 1,
        setNumber: 1,
        submitterUserId: const UserId('u2'),
        score: score,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('new TypedId subtypes', () {
    test('TournamentParticipantId, TournamentMatchId, UserId have type-tagged equality', () {
      expect(
        const TournamentParticipantId('x'),
        equals(const TournamentParticipantId('x')),
      );
      expect(
        const TournamentMatchId('x'),
        isNot(equals(const TournamentParticipantId('x'))),
      );
      expect(const UserId('u').toString(), equals('UserId(u)'));
    });
  });
}
