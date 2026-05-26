// Repository-level e2e for the `round_robin_then_ko` format (M2.3-T16).
//
// Drives [FakeTournamentRemote] directly: wizard payload → 8-player RR →
// top-4 seeding → semis (trigger fills final + bronze) → final + bronze.
//
// Final ranking (ADR-0017 §5): 1 = final winner, 2 = final loser,
// 3 = bronze winner, 4 = bronze loser, 5..8 = RR-standings tail.
//
// Run: `flutter test test/features/tournament/integration/round_robin_then_ko_e2e_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

const _organizer = UserId('user-org');
final List<UserId> _users = [
  for (var i = 1; i <= 8; i++) UserId('user-p$i'),
];

/// Lower user-index always wins → strict 1..8 RR ranking by total points
/// (p1 wins 7, p2 wins 6, ..., p8 wins 0).
int _rankOf(UserId u) => _users.indexOf(u);

SetScore _set({required bool aWins}) => SetScore(
      basekubbsKnockedByA: aWins ? 5 : 3,
      basekubbsKnockedByB: aWins ? 3 : 5,
      winner: aWins ? SetWinner.teamA : SetWinner.teamB,
    );

/// Submits byte-equal proposals from both sides → consensus finalises.
Future<void> _agree(
  FakeTournamentRemote remote,
  TournamentMatchRef m,
  UserId a,
  UserId b, {
  required bool aWins,
}) async {
  final round = (await remote.getMatch(m.matchId))!.consensusRound;
  final sets = <SetScore>[_set(aWins: aWins)];
  for (final user in [a, b]) {
    remote.currentUser = user;
    await remote.proposeSetScores(
      matchId: m.matchId,
      consensusRound: round,
      setScores: sets,
    );
  }
}

void main() {
  test(
    'round_robin_then_ko: 8 players → RR → KO+bronze → ranking 1..8',
    () async {
      final remote = FakeTournamentRemote(initialUser: _organizer);

      // --- Wizard: format=RR-then-KO, qualifier=4, bronze=true ---
      final tid = await remote.createTournament(
        displayName: 'E2E RR→KO',
        teamSize: 1,
        minParticipants: 8,
        maxParticipants: 8,
        format: TournamentFormat.roundRobinThenKo,
        matchFormatConfig: const {'sets_to_win': 1, 'max_sets': 1},
        tiebreakerOrder: const ['total_points', 'wins'],
      );
      await remote.publish(tid);
      await remote.openRegistration(tid);

      final pids = <TournamentParticipantId>[];
      for (final u in _users) {
        remote.currentUser = u;
        pids.add(await remote.registerSingle(tid));
      }
      remote.currentUser = _organizer;
      for (final pid in pids) {
        await remote.confirmRegistration(pid);
      }
      final user = {for (var i = 0; i < pids.length; i++) pids[i]: _users[i]};

      await remote.closeRegistration(tid);
      await remote.startTournament(tid);

      // --- 1. Round-robin: 28 matches, top-seed wins each pairing ---
      final rrMatches = await remote.listMatchesForTournament(tid);
      expect(rrMatches, hasLength(28));
      for (final m in rrMatches) {
        final ua = user[m.participantA]!;
        final ub = user[m.participantB]!;
        await _agree(remote, m, ua, ub, aWins: _rankOf(ua) < _rankOf(ub));
      }

      final rrFinalised = await remote.listMatchesForTournament(tid);
      expect(
        rrFinalised.every((m) => m.status == TournamentMatchStatus.finalized),
        isTrue,
      );

      // RR-only standings — drives the seeding for the KO and the 5..8 tail.
      final rrStandings = computeStandings(
        participantIds: [for (final p in pids) p.value],
        results: [
          for (final m in rrFinalised)
            TournamentMatchResult(
              participantA: m.participantA!.value,
              participantB: m.participantB!.value,
              score: MatchEkcScore([
                _set(aWins: m.finalScoreA! >= m.finalScoreB!),
              ]),
            ),
        ],
        tiebreaker: const TiebreakerChain([
          TiebreakerCriterion.totalPoints,
          TiebreakerCriterion.wins,
        ]),
      );
      expect(
        rrStandings.map((s) => s.participantId).toList(),
        [for (final p in pids) p.value],
        reason: 'rigged outcomes → strict p1..p8 ranking',
      );

      // --- 2. Start KO with bronze ---
      await remote.startKoPhase(
        tid,
        KoPhaseConfig(
          qualifierCount: 4,
          participantCount: 8,
          withThirdPlacePlayoff: true,
        ),
      );

      final afterStart = await remote.listMatchesForTournament(tid);
      final koMatches = afterStart
          .where((m) => !rrFinalised.any((r) => r.matchId == m.matchId))
          .toList();
      // 2 semifinals + 1 final + 1 bronze = 4 KO rows.
      expect(koMatches, hasLength(4));

      // Recursive seeding for n=4 → order [1, 4, 3, 2] → pairings
      // (seed1, seed4), (seed3, seed2). seed_i == pids[i-1].
      final bracket = await remote.getBracket(tid) as SingleEliminationBracket;
      final semiRound = bracket.rounds.firstWhere((r) => r.number == 1);
      expect(
        semiRound.pairings
            .map((p) => (p.$1.participantId, p.$2.participantId)),
        [
          (pids[0].value, pids[3].value),
          (pids[2].value, pids[1].value),
        ],
      );

      // --- 3. Play semis: top seed wins. Trigger fills final + bronze. ---
      final semis = koMatches.where((m) => m.roundNumber == 1).toList()
        ..sort((a, b) => a.matchNumberInRound.compareTo(b.matchNumberInRound));
      // semi-bp1: pids[0] (A) vs pids[3] (B) → A wins (pids[0]).
      await _agree(remote, semis[0], user[semis[0].participantA]!,
          user[semis[0].participantB]!,
          aWins: true);
      // semi-bp2: pids[2] (A) vs pids[1] (B) → B wins (pids[1]).
      await _agree(remote, semis[1], user[semis[1].participantA]!,
          user[semis[1].participantB]!,
          aWins: false);

      // Trigger contract: final = (semi1-winner, semi2-winner),
      // bronze = {semi1-loser, semi2-loser}.
      final br2 = await remote.getBracket(tid) as SingleEliminationBracket;
      final finalRound =
          br2.rounds.singleWhere((r) => r.phase == BracketPhase.finals);
      final bronzeRound =
          br2.rounds.singleWhere((r) => r.phase == BracketPhase.thirdPlace);
      expect(
        (
          finalRound.pairings.single.$1.participantId,
          finalRound.pairings.single.$2.participantId,
        ),
        (pids[0].value, pids[1].value),
      );
      expect(
        {
          bronzeRound.pairings.single.$1.participantId,
          bronzeRound.pairings.single.$2.participantId,
        },
        {pids[3].value, pids[2].value},
      );

      // --- 4. Play final + bronze. Filter KO-only so the lookup doesn't
      // catch the RR match between the same pair (every RR pairing is
      // played exactly once, including the eventual finalists). ---
      final afterSemis = await remote.listMatchesForTournament(tid);
      final koOnly = afterSemis
          .where((m) => !rrFinalised.any((r) => r.matchId == m.matchId));
      final finalMatch = koOnly.firstWhere(
        (m) => m.participantA == pids[0] && m.participantB == pids[1],
      );
      final bronzeMatch = koOnly.firstWhere(
        (m) =>
            (m.participantA == pids[3] && m.participantB == pids[2]) ||
            (m.participantA == pids[2] && m.participantB == pids[3]),
      );

      // Final: pids[0] wins.
      await _agree(remote, finalMatch, user[finalMatch.participantA]!,
          user[finalMatch.participantB]!,
          aWins: true);
      // Bronze: pids[2] wins — side depends on which slot the trigger filled.
      await _agree(remote, bronzeMatch, user[bronzeMatch.participantA]!,
          user[bronzeMatch.participantB]!,
          aWins: user[bronzeMatch.participantA] == _users[2]);

      // --- 5. Endrangliste ---
      final fin = (await remote.getMatch(finalMatch.matchId))!;
      final brz = (await remote.getMatch(bronzeMatch.matchId))!;
      expect(fin.winnerParticipant, pids[0], reason: 'rank 1');
      expect(
        fin.winnerParticipant == fin.participantA
            ? fin.participantB
            : fin.participantA,
        pids[1],
        reason: 'rank 2',
      );
      expect(brz.winnerParticipant, pids[2], reason: 'rank 3');
      expect(
        brz.winnerParticipant == brz.participantA
            ? brz.participantB
            : brz.participantA,
        pids[3],
        reason: 'rank 4',
      );

      final podiumIds = {for (final p in pids.take(4)) p.value};
      final tail = rrStandings
          .where((s) => !podiumIds.contains(s.participantId))
          .map((s) => s.participantId)
          .toList();
      expect(tail, [for (final p in pids.skip(4)) p.value],
          reason: 'ranks 5..8 follow RR ordering');
    },
  );
}
