// Repository-level e2e for a 4-team round-robin with `team_size=3` plus
// one mid-tournament roster substitution (TASK-M3.2-T19). Mirrors the
// M2 round-robin-then-KO sibling: drives [FakeTournamentRemote] directly
// against the [TournamentRemote] port, exercising the roster methods
// landed on the T10 parallel branch (`registerTeam`, `replaceRosterSlot`,
// `getRoster`).
//
// Flow:
//   1. Organizer creates 4-team RR (team_size=3).
//   2. Each team registers via `registerTeam`. Teams 1..3 use 3 members,
//      team 4 uses 2 members + 1 guest (the guest is the substitute
//      target later).
//   3. Organizer approves all four participants and starts the
//      tournament — RR generates 6 matches (n*(n-1)/2).
//   4. First match (round 1) is played: scores submitted by a *pool
//      member* of each team, not by the captain who called
//      `registerTeam`.
//   5. Mid-tournament substitution: team-4's guest slot is replaced by
//      a fresh member via `replaceRosterSlot`.
//   6. Remaining 5 matches are played; tournament finalises.
//
// Verification:
//   * After substitution, `getRoster` no longer lists the guest at the
//     replaced slot and the new occupant is present at the same index.
//   * All 6 matches reach `finalized` status.
//   * Tournament can be finalised.
//   * Soft check: if `getTournamentDetail` is wired, the audit tail
//     contains a roster-replacement event.
//
// Run: `flutter test test/features/tournament/integration/team_round_robin_e2e_test.dart`.

import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

const _organizer = UserId('user-org');

/// 4 teams x 3 captain/pool members = 12 user ids. `team[i][j]` where
/// `i` in 0..3 is the team index, `j` in 0..2 is the slot 1..3 occupant.
List<List<UserId>> _teamMembers() => [
      for (var t = 1; t <= 4; t++)
        [for (var s = 1; s <= 3; s++) UserId('user-t$t-m$s')],
    ];

const _teamIds = [
  TeamId('team-1'),
  TeamId('team-2'),
  TeamId('team-3'),
  TeamId('team-4'),
];

/// Lower-index team wins each pairing, so all 6 matches resolve
/// deterministically and produce a strict 1..4 ranking.
SetScore _set({required bool aWins}) => SetScore(
      basekubbsKnockedByA: aWins ? 5 : 3,
      basekubbsKnockedByB: aWins ? 3 : 5,
      winner: aWins ? SetWinner.teamA : SetWinner.teamB,
    );

/// Submits byte-equal proposals from both sides → consensus finalises.
/// Both submitters are deliberately *non-captain* pool members (slot 2
/// of each team) to cover FR-TEAM "score by any pool member".
Future<void> _agree(
  FakeTournamentRemote remote,
  TournamentMatchRef match,
  UserId aSubmitter,
  UserId bSubmitter, {
  required bool aWins,
}) async {
  final round = (await remote.getMatch(match.matchId))!.consensusRound;
  final sets = <SetScore>[_set(aWins: aWins)];
  for (final user in [aSubmitter, bSubmitter]) {
    remote.currentUser = user;
    await remote.proposeSetScores(
      matchId: match.matchId,
      consensusRound: round,
      setScores: sets,
    );
  }
}

void main() {
  test(
    '4-team round-robin: team registration, mid-tournament substitution, '
    'non-captain score submission, all matches finalise',
    () async {
      final remote = FakeTournamentRemote(initialUser: _organizer);
      final members = _teamMembers();

      // --- 1. Organizer creates 4-team RR with team_size=3 ---
      final tid = await remote.createTournament(
        displayName: 'E2E 4-Team RR',
        teamSize: 3,
        minParticipants: 4,
        maxParticipants: 4,
        format: TournamentFormat.roundRobin,
        matchFormatConfig: const {'sets_to_win': 1, 'max_sets': 1},
        tiebreakerOrder: const ['total_points', 'wins'],
      );
      await remote.publish(tid);
      await remote.openRegistration(tid);

      // --- 2. Each team registers with a roster. Team 4 uses a guest
      // at slot 3 — that guest is the substitution target later. ---
      final guestId = TeamGuestPlayerId('guest-team4');
      const substituteUser = UserId('user-t4-sub');

      final pids = <TournamentParticipantId>[];
      for (var i = 0; i < 4; i++) {
        // Captain = slot-1 member of the team (the user who issues
        // `registerTeam`). FR-REG-12: at least one `member` slot.
        final captain = members[i][0];
        remote.currentUser = captain;
        final roster = <RosterSlotInput>[
          RosterSlotInput.member(1, members[i][0]),
          RosterSlotInput.member(2, members[i][1]),
          if (i == 3)
            RosterSlotInput.guest(3, guestId)
          else
            RosterSlotInput.member(3, members[i][2]),
        ];
        expect(requireAtLeastOneMember(roster), isTrue);
        final pid = await remote.registerTeam(
          tournamentId: tid,
          teamId: _teamIds[i],
          roster: roster,
        );
        pids.add(pid);
      }

      // --- 3. Organizer approves and starts ---
      remote.currentUser = _organizer;
      for (final pid in pids) {
        await remote.confirmRegistration(pid);
      }
      await remote.closeRegistration(tid);
      await remote.startTournament(tid);

      final allMatches = await remote.listMatchesForTournament(tid);
      expect(allMatches, hasLength(6),
          reason: '4 teams → C(4,2) = 6 round-robin matches');

      final teamOfParticipant = <TournamentParticipantId, int>{
        for (var i = 0; i < pids.length; i++) pids[i]: i,
      };

      // Slot-2 member (non-captain pool member) of each team is the
      // submitter we use throughout. Score submission via a non-captain
      // pool member is the FR-TEAM acceptance criterion of T19.
      UserId nonCaptainOf(TournamentParticipantId pid) =>
          members[teamOfParticipant[pid]!][1];

      // --- 4. Play the first round-1 match before the substitution ---
      final ordered = [...allMatches]..sort((a, b) {
          final byRound = a.roundNumber.compareTo(b.roundNumber);
          return byRound != 0
              ? byRound
              : a.matchNumberInRound.compareTo(b.matchNumberInRound);
        });
      final firstMatch = ordered.first;
      await _agree(
        remote,
        firstMatch,
        nonCaptainOf(firstMatch.participantA!),
        nonCaptainOf(firstMatch.participantB!),
        aWins:
            teamOfParticipant[firstMatch.participantA]! <
                teamOfParticipant[firstMatch.participantB]!,
      );
      expect(
        (await remote.getMatch(firstMatch.matchId))!.status,
        TournamentMatchStatus.finalized,
        reason: 'non-captain submission must finalise the match',
      );

      // --- 5. Mid-tournament substitution: replace team-4's guest at
      // slot 3 with `substituteUser`. The captain triggers it. ---
      final team4Pid = pids[3];
      remote.currentUser = members[3][0];
      final rosterBefore = await remote.getRoster(team4Pid);
      expect(rosterBefore, hasLength(3));
      expect(
        rosterBefore.firstWhere((s) => s.slotIndex == 3).guestPlayerId,
        guestId,
        reason: 'pre-substitution: slot 3 is the original guest',
      );

      await remote.replaceRosterSlot(
        participantId: team4Pid,
        slotIndex: 3,
        newOccupant: RosterSlotInput.member(3, substituteUser),
        reason: 'guest unavailable, M3-T19 substitution test',
      );

      final rosterAfter = await remote.getRoster(team4Pid);
      expect(rosterAfter, hasLength(3),
          reason: 'open-slot count is invariant under substitution');
      final newSlot3 = rosterAfter.firstWhere((s) => s.slotIndex == 3);
      expect(newSlot3.memberUserId, substituteUser,
          reason: 'new occupant is the substitute user');
      expect(newSlot3.guestPlayerId, isNull);
      expect(newSlot3.replacedAt, isNull,
          reason: 'new slot row is open (replaced_at == null)');
      expect(
        rosterAfter.any((s) => s.guestPlayerId == guestId),
        isFalse,
        reason: 'former guest no longer appears in the open roster',
      );

      // Soft audit check — T10 may or may not wire `getTournamentDetail`
      // in this iteration. If it does AND the fake also tracks audit
      // events, the roster-replacement event should land in the audit
      // tail. After Sprint-B-W3-T5 the fake exposes a minimal Detail-
      // Payload for the display-name lookup but still leaves auditTail
      // empty, so the assertion stays gated on a non-empty tail.
      final detail = await remote.getTournamentDetail(tid);
      if (detail != null && detail.auditTail.isNotEmpty) {
        expect(
          detail.auditTail.any((e) => e.kind.contains('roster')),
          isTrue,
          reason: 'audit tail records the roster substitution',
        );
      }

      // --- 6. Play the remaining 5 matches; substitute participates
      // in any team-4 fixture as the new slot-3 occupant. ---
      for (final m in ordered.skip(1)) {
        await _agree(
          remote,
          m,
          nonCaptainOf(m.participantA!),
          nonCaptainOf(m.participantB!),
          aWins: teamOfParticipant[m.participantA]! <
              teamOfParticipant[m.participantB]!,
        );
      }

      final finalised = await remote.listMatchesForTournament(tid);
      expect(
        finalised.every((m) => m.status == TournamentMatchStatus.finalized),
        isTrue,
        reason: 'all 6 RR matches reach `finalized`',
      );

      // --- 7. Finalise tournament ---
      remote.currentUser = _organizer;
      await remote.finalizeTournament(tid);
      final summary = await remote.getTournament(tid);
      expect(summary!.status, TournamentStatus.finalized);
    },
  );
}
