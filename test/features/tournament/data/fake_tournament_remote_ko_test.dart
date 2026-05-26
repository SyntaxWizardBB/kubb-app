import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

/// Verifies the in-Dart simulation of `tournament_advance_ko_winner`
/// (T4 trigger) inside [FakeTournamentRemote]. The Fake is the
/// substrate for SeedingScreen (M2.3-T11) and the M2.3-T16 e2e-Test;
/// it must reproduce the same slot-filling and status-promotion that
/// the Supabase trigger does in production.
void main() {
  group('FakeTournamentRemote — KO trigger simulation', () {
    late FakeTournamentRemote remote;
    late TournamentId tid;
    late List<TournamentParticipantId> pids;
    const organizer = UserId('user-org');
    final players = [
      for (var i = 1; i <= 4; i++) UserId('user-p$i'),
    ];

    Future<void> agreeScore(
      TournamentMatchId mid,
      UserId userA,
      UserId userB, {
      int winsForA = 2,
      int winsForB = 1,
    }) async {
      final round = (await remote.getMatch(mid))!.consensusRound;
      final scores = <SetScore>[
        for (var i = 0; i < winsForA; i++)
          SetScore(
            basekubbsKnockedByA: 5,
            basekubbsKnockedByB: 2,
            winner: SetWinner.teamA,
          ),
        for (var i = 0; i < winsForB; i++)
          SetScore(
            basekubbsKnockedByA: 2,
            basekubbsKnockedByB: 5,
            winner: SetWinner.teamB,
          ),
      ];
      remote.currentUser = userA;
      await remote.proposeSetScores(
        matchId: mid,
        consensusRound: round,
        setScores: scores,
      );
      remote.currentUser = userB;
      await remote.proposeSetScores(
        matchId: mid,
        consensusRound: round,
        setScores: scores,
      );
    }

    Future<void> setupTournamentWithFourPlayers() async {
      remote = FakeTournamentRemote(initialUser: organizer);
      tid = await remote.createTournament(
        displayName: 'KO Cup',
        teamSize: 1,
        minParticipants: 4,
        maxParticipants: 4,
        format: TournamentFormat.singleElimination,
        matchFormatConfig: const <String, Object?>{},
        tiebreakerOrder: const <String>[],
      );
      pids = <TournamentParticipantId>[];
      for (final p in players) {
        remote.currentUser = p;
        final pid = await remote.registerSingle(tid);
        pids.add(pid);
      }
      remote.currentUser = organizer;
      for (final pid in pids) {
        await remote.confirmRegistration(pid);
      }
    }

    test(
        'proposeSetScores finalising a KO match feeds the winner into the next round',
        () async {
      await setupTournamentWithFourPlayers();
      remote.setKoConfig(tid, KoPhaseConfig(
          qualifierCount: 4,
          participantCount: 4,
        ));
      await remote.startKoPhase(tid, KoPhaseConfig(
          qualifierCount: 4,
          participantCount: 4,
        ));

      // 4 R1 + 2 R2 placeholder + (no third-place) = 6 rounds total? No.
      // 4 seeds → bracket size 4 → 2 R1, 1 R2 final = 3 matches.
      final all = await remote.listMatchesForTournament(tid);
      expect(all, hasLength(3));
      final r1 = all
          .where((m) => m.roundNumber == 1)
          .toList()
        ..sort((a, b) => a.matchNumberInRound.compareTo(b.matchNumberInRound));
      final r2 = all.where((m) => m.roundNumber == 2).single;
      expect(r2.participantA, isNull);
      expect(r2.participantB, isNull);
      expect(r2.status, TournamentMatchStatus.scheduled);

      // Finalize the *first* R1 pairing → winner lands in R2 slot a
      // (bracket_position 1 is odd).
      final r1FirstMatch = r1.first;
      final r1FirstWinner = r1FirstMatch.participantA!;
      await agreeScore(
        r1FirstMatch.matchId,
        UserId('user-p${pids.indexOf(r1FirstMatch.participantA!) + 1}'),
        UserId('user-p${pids.indexOf(r1FirstMatch.participantB!) + 1}'),
      );
      var r2After = await remote.getMatch(r2.matchId);
      expect(r2After!.participantA, r1FirstWinner);
      expect(r2After.participantB, isNull);
      expect(r2After.status, TournamentMatchStatus.scheduled);

      // Finalize the *second* R1 pairing → winner lands in R2 slot b
      // (bracket_position 2 is even). Status promotes to awaiting_results.
      final r1SecondMatch = r1.last;
      final r1SecondWinner = r1SecondMatch.participantA!;
      await agreeScore(
        r1SecondMatch.matchId,
        UserId('user-p${pids.indexOf(r1SecondMatch.participantA!) + 1}'),
        UserId('user-p${pids.indexOf(r1SecondMatch.participantB!) + 1}'),
      );
      r2After = await remote.getMatch(r2.matchId);
      expect(r2After!.participantA, r1FirstWinner);
      expect(r2After.participantB, r1SecondWinner);
      expect(r2After.status, TournamentMatchStatus.awaitingResults);
    });

    test('startKoPhase creates the KO match rows in the in-memory store',
        () async {
      await setupTournamentWithFourPlayers();
      remote.setKoConfig(tid, KoPhaseConfig(
          qualifierCount: 4,
          participantCount: 4,
          withThirdPlacePlayoff: true,
        ));
      await remote.startKoPhase(tid, KoPhaseConfig(
          qualifierCount: 4,
          participantCount: 4,
          withThirdPlacePlayoff: true,
        ));

      final all = await remote.listMatchesForTournament(tid);
      // 2 R1 + 1 final + 1 third-place = 4 matches.
      expect(all, hasLength(4));

      final bracket = await remote.getBracket(tid);
      expect(bracket, isA<SingleEliminationBracket>());
      final rounds = (bracket as SingleEliminationBracket).rounds;
      // 2 winners-rounds + 1 third-place-round.
      expect(rounds.where((r) => r.phase == BracketPhase.winners), hasLength(1));
      expect(rounds.where((r) => r.phase == BracketPhase.finals), hasLength(1));
      expect(rounds.where((r) => r.phase == BracketPhase.thirdPlace),
          hasLength(1));

      // Idempotency contract: second call fails with ALREADY_STARTED
      // (mirrors Supabase ERRCODE 40001 → StateError in the Fake).
      expect(
        () => remote.startKoPhase(
          tid,
          KoPhaseConfig(
            qualifierCount: 4,
            participantCount: 4,
            withThirdPlacePlayoff: true,
          ),
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('ALREADY_STARTED'),
        )),
      );
    });

    test(
        'semifinal loser lands in third-place match when withThirdPlacePlayoff is true',
        () async {
      await setupTournamentWithFourPlayers();
      remote.setKoConfig(tid, KoPhaseConfig(
          qualifierCount: 4,
          participantCount: 4,
          withThirdPlacePlayoff: true,
        ));
      await remote.startKoPhase(tid, KoPhaseConfig(
          qualifierCount: 4,
          participantCount: 4,
          withThirdPlacePlayoff: true,
        ));

      final all = await remote.listMatchesForTournament(tid);
      final r1 = all
          .where((m) => m.roundNumber == 1)
          .toList()
        ..sort((a, b) => a.matchNumberInRound.compareTo(b.matchNumberInRound));
      // Third-place row shares round=2 with the final; disambiguate
      // downstream via `getBracket` rather than the round-only filter.

      // Finalize both R1 pairings.
      final r1A = r1.first;
      final loserA = r1A.participantB!;
      await agreeScore(
        r1A.matchId,
        UserId('user-p${pids.indexOf(r1A.participantA!) + 1}'),
        UserId('user-p${pids.indexOf(r1A.participantB!) + 1}'),
      );
      final r1B = r1.last;
      final loserB = r1B.participantB!;
      await agreeScore(
        r1B.matchId,
        UserId('user-p${pids.indexOf(r1B.participantA!) + 1}'),
        UserId('user-p${pids.indexOf(r1B.participantB!) + 1}'),
      );

      // The third-place row picks up both losers. We identify it via
      // the bracket-row dump on getBracket — third_place phase, both
      // slots filled.
      final bracket =
          await remote.getBracket(tid) as SingleEliminationBracket;
      final tpRound = bracket.rounds
          .singleWhere((r) => r.phase == BracketPhase.thirdPlace);
      expect(tpRound.pairings, hasLength(1));
      final tpPair = tpRound.pairings.single;
      expect(
        {tpPair.$1.participantId, tpPair.$2.participantId},
        {loserA.value, loserB.value},
        reason: 'both R1 losers should sit in the third-place pairing',
      );

      // The match status row should be promoted to awaiting_results.
      final allAfter = await remote.listMatchesForTournament(tid);
      final filledThirdPlace = allAfter.where(
        (m) =>
            m.participantA != null &&
            m.participantB != null &&
            (m.participantA == loserA && m.participantB == loserB ||
                m.participantA == loserB && m.participantB == loserA),
      );
      expect(filledThirdPlace, hasLength(1));
      expect(
        filledThirdPlace.single.status,
        TournamentMatchStatus.awaitingResults,
      );
    });
  });
}
