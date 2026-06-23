// W2-T3 (R11-F-01): `TournamentSetScoreProposal.kingOutcome` and the
// `KingOutcome` sealed class now live in `kubb_domain`. The explicit
// `KingMissed()` below matches the field default; that is intentional —
// the test contrasts the two outcomes for equality.
// ignore_for_file: avoid_redundant_argument_values
import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('TournamentSummaryRef', () {
    final a = TournamentSummaryRef(
      tournamentId: const TournamentId('t1'),
      displayName: 'Spring Cup',
      format: TournamentFormat.schoch,
      status: TournamentStatus.published,
      startedAt: DateTime.utc(2026, 5, 3),
      completedAt: DateTime.utc(2026, 5, 2),
      participantCount: 16,
    );

    test('value equality holds for identical content', () {
      final b = TournamentSummaryRef(
        tournamentId: const TournamentId('t1'),
        displayName: 'Spring Cup',
        format: TournamentFormat.schoch,
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
        format: TournamentFormat.schoch,
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

    test('pitchNumber defaults to null and breaks equality when set', () {
      const noPitch = TournamentMatchRef(
        matchId: TournamentMatchId('m1'),
        tournamentId: TournamentId('t1'),
        roundNumber: 1,
        matchNumberInRound: 3,
        participantA: TournamentParticipantId('p1'),
        participantB: TournamentParticipantId('p2'),
        status: TournamentMatchStatus.scheduled,
        consensusRound: 1,
      );
      expect(noPitch.pitchNumber, isNull);

      const withPitch = TournamentMatchRef(
        matchId: TournamentMatchId('m1'),
        tournamentId: TournamentId('t1'),
        roundNumber: 1,
        matchNumberInRound: 3,
        participantA: TournamentParticipantId('p1'),
        participantB: TournamentParticipantId('p2'),
        status: TournamentMatchStatus.scheduled,
        consensusRound: 1,
        pitchNumber: 7,
      );
      expect(withPitch.pitchNumber, 7);
      expect(withPitch, isNot(equals(noPitch)));
      expect(withPitch.hashCode, isNot(equals(noPitch.hashCode)));
    });

    test('groupLabel defaults to null and breaks equality when set', () {
      const noGroup = TournamentMatchRef(
        matchId: TournamentMatchId('m1'),
        tournamentId: TournamentId('t1'),
        roundNumber: 1,
        matchNumberInRound: 3,
        participantA: TournamentParticipantId('p1'),
        participantB: TournamentParticipantId('p2'),
        status: TournamentMatchStatus.scheduled,
        consensusRound: 1,
      );
      expect(noGroup.groupLabel, isNull);

      const withGroup = TournamentMatchRef(
        matchId: TournamentMatchId('m1'),
        tournamentId: TournamentId('t1'),
        roundNumber: 1,
        matchNumberInRound: 3,
        participantA: TournamentParticipantId('p1'),
        participantB: TournamentParticipantId('p2'),
        status: TournamentMatchStatus.scheduled,
        consensusRound: 1,
        groupLabel: 'A',
      );
      expect(withGroup.groupLabel, 'A');
      expect(withGroup, isNot(equals(noGroup)));
      expect(withGroup.hashCode, isNot(equals(noGroup.hashCode)));
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

    test('kingOutcome is part of the proposal payload', () {
      final score = SetScore(
        basekubbsKnockedByA: 5,
        basekubbsKnockedByB: 3,
        winner: SetWinner.teamA,
      );
      final proposal = TournamentSetScoreProposal(
        matchId: const TournamentMatchId('m1'),
        consensusRound: 1,
        setNumber: 1,
        submitterUserId: const UserId('u1'),
        score: score,

        kingOutcome: const KingHitBy(TournamentParticipantId('pA')),
      );

      expect(proposal.kingOutcome, isA<KingHitBy>());
    });

    test('differing kingOutcome breaks equality', () {
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

        kingOutcome: const KingHitBy(TournamentParticipantId('pA')),
      );
      final b = TournamentSetScoreProposal(
        matchId: const TournamentMatchId('m1'),
        consensusRound: 1,
        setNumber: 1,
        submitterUserId: const UserId('u1'),
        score: score,

        kingOutcome: const KingMissed(),
      );
      expect(a, isNot(equals(b)));
    });

    test('TimedOut is a valid kingOutcome on the proposal', () {
      final score = SetScore(
        basekubbsKnockedByA: 0,
        basekubbsKnockedByB: 0,
        winner: SetWinner.teamA,
      );
      final proposal = TournamentSetScoreProposal(
        matchId: const TournamentMatchId('m1'),
        consensusRound: 1,
        setNumber: 1,
        submitterUserId: const UserId('u1'),
        score: score,

        kingOutcome: const KingTimedOut(),
      );

      expect(proposal.kingOutcome, isA<KingTimedOut>());
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

  group('TournamentDetailHeader (W3-T09)', () {
    TournamentDetailHeader header({
      int teamSize = 1,
      Map<String, Object?> setup = const <String, Object?>{},
    }) =>
        TournamentDetailHeader(
          tournamentId: 't1',
          displayName: 'Spring Cup',
          createdByUserId: 'u1',
          clubId: null,
          teamSize: teamSize,
          maxTeamSize: teamSize,
          minParticipants: 4,
          maxParticipants: 16,
          format: TournamentFormat.roundRobinThenKo,
          scoring: TournamentScoring.ekc,
          matchFormatConfig: const <String, Object?>{},
          tiebreakerOrder: const <String>[],
          byePoints: null,
          forfeitPoints: null,
          status: TournamentStatus.live,
          publishedAt: null,
          startedAt: null,
          completedAt: null,
          setup: setup,
        );

    test('isTeam is false for a solo tournament (teamSize 1)', () {
      expect(header().isTeam, isFalse);
    });

    test('isTeam is true once teamSize exceeds one', () {
      expect(header(teamSize: 2).isTeam, isTrue);
    });

    test('qualifiersPerGroup reads pool_phase_config from setup', () {
      final h = header(setup: const <String, Object?>{
        'pool_phase_config': <String, Object?>{'qualifiers_per_group': 3},
      });
      expect(h.qualifiersPerGroup, 3);
    });

    test('qualifiersPerGroup falls back to 2 when no pool config present', () {
      expect(header().qualifiersPerGroup, 2);
    });
  });
}
