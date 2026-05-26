// Repository-level e2e for the pool-phase → KO path (M3.3-T14).
//
// Drives [FakeTournamentRemote] directly: 16 single-player participants
// land in 4 snake-seeded groups of 4; every pool match is played so each
// group produces a deterministic 1..4 ranking. Top-2 per group (8
// qualifiers) feed [startKoPhase] with bronze enabled.
//
// Verification stops at the KO-row count: detailed bracket progression
// is already covered by `round_robin_then_ko_e2e_test.dart`.
//
// Run: `flutter test test/features/tournament/integration/pool_phase_ko_e2e_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

const _organizer = UserId('user-org');
final List<UserId> _users = [
  for (var i = 1; i <= 16; i++) UserId('user-p${i.toString().padLeft(2, '0')}'),
];

/// Lower user-index always wins → strict ranking inside every group.
int _rankOf(UserId u) => _users.indexOf(u);

SetScore _set({required bool aWins}) => SetScore(
      basekubbsKnockedByA: aWins ? 5 : 3,
      basekubbsKnockedByB: aWins ? 3 : 5,
      winner: aWins ? SetWinner.teamA : SetWinner.teamB,
    );

/// Byte-equal proposals from both sides → consensus finalises.
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
    'pool_phase → KO: 16 players, 4 groups of 4, top-2 advance, KO bracket built',
    () async {
      final remote = FakeTournamentRemote(initialUser: _organizer);

      // --- Wizard: format = RR-then-KO, 16 single-player participants ---
      final tid = await remote.createTournament(
        displayName: 'E2E 16-Team Pool→KO',
        teamSize: 1,
        minParticipants: 16,
        maxParticipants: 16,
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

      // --- 1. Pool phase: 4 groups × 4 → 24 RR matches (6 per group). ---
      // The fake mirrors `tournament_start_pool_phase` by inserting the
      // per-group round-robin pairings; we deliberately skip
      // `startTournament` here so no flat 16-team RR is generated.
      await remote.startPoolPhase(
        tid,
        const PoolPhaseConfig(
          groupCount: 4,
          qualifiersPerGroup: 2,
          strategy: PoolGroupingStrategy.snake,
        ),
      );

      final poolMatches = await remote.listMatchesForTournament(tid);
      expect(poolMatches, hasLength(24),
          reason: '6 matches per group × 4 groups');

      // --- 2. Play every pool match: lower user-index wins. ---
      for (final m in poolMatches) {
        final ua = user[m.participantA]!;
        final ub = user[m.participantB]!;
        await _agree(remote, m, ua, ub, aWins: _rankOf(ua) < _rankOf(ub));
      }
      final finalised = await remote.listMatchesForTournament(tid);
      expect(
        finalised.every((m) => m.status == TournamentMatchStatus.finalized),
        isTrue,
        reason: 'all 24 pool matches reach consensus',
      );

      // --- 3. Verify pool standings shape: 4 groups, 4 stats rows each. ---
      final standings = await remote.getPoolStandings(tid);
      expect(standings, hasLength(4));
      expect(
        standings.map((s) => s.groupLabel).toList(),
        ['A', 'B', 'C', 'D'],
      );
      for (final group in standings) {
        expect(group.stats, hasLength(4));
      }

      // --- 4. Start KO with 8 qualifiers + bronze. The fake builds the
      //        full single-elimination skeleton upfront: 4 QF + 2 SF + 1
      //        final + 1 third-place = 8 KO rows. ---
      await remote.startKoPhase(
        tid,
        KoPhaseConfig(
          qualifierCount: 8,
          participantCount: 16,
          withThirdPlacePlayoff: true,
        ),
      );

      final afterStart = await remote.listMatchesForTournament(tid);
      final koMatches = afterStart
          .where((m) => !finalised.any((r) => r.matchId == m.matchId))
          .toList();
      expect(koMatches, hasLength(8),
          reason: '4 QF + 2 SF + 1 final + 1 bronze');

      // --- 5. Bracket shape: 4 QF pairings carry the 8 qualifiers, deeper
      //        rounds are placeholder-filled until matches finalize. ---
      final bracket = await remote.getBracket(tid) as SingleEliminationBracket;
      final qfRound = bracket.rounds.firstWhere((r) => r.number == 1);
      expect(qfRound.pairings, hasLength(4));
      final qfParticipants = <String>{
        for (final p in qfRound.pairings) ...[
          if (p.$1.participantId != null) p.$1.participantId!,
          if (p.$2.participantId != null) p.$2.participantId!,
        ],
      };
      expect(qfParticipants, hasLength(8),
          reason: 'every QF slot is filled by a distinct qualifier');

      final finalRound =
          bracket.rounds.singleWhere((r) => r.phase == BracketPhase.finals);
      final bronzeRound =
          bracket.rounds.singleWhere((r) => r.phase == BracketPhase.thirdPlace);
      expect(finalRound.pairings, hasLength(1));
      expect(bronzeRound.pairings, hasLength(1));
    },
  );
}
