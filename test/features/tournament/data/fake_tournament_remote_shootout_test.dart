import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../../fixtures/tournament/fake_tournament_remote.dart';

/// Exercises the shoot-out report/confirm consensus state machine through the
/// FakeTournamentRemote (the in-memory mirror of the D2a server). Documents the
/// observable contract the Supabase adapter must match: pending → reported →
/// resolved, two-sided agreement, permutation + order-mismatch enforcement.
void main() {
  late FakeTournamentRemote remote;
  late TournamentId tid;
  late TournamentParticipantId p1;
  late TournamentParticipantId p2;
  late String shootoutId;

  const organizer = UserId('u-org');
  const userA = UserId('u-a');
  const userB = UserId('u-b');

  setUp(() async {
    remote = FakeTournamentRemote(initialUser: organizer);
    tid = await remote.createTournament(
      displayName: 'T',
      teamSize: 1,
      minParticipants: 2,
      maxParticipants: 4,
      format: TournamentFormat.roundRobin,
      matchFormatConfig: const <String, Object?>{},
      tiebreakerOrder: const <String>[],
    );
    // Two solo participants behind two distinct users.
    remote.currentUser = userA;
    p1 = await remote.registerSingle(tid);
    remote.currentUser = userB;
    p2 = await remote.registerSingle(tid);
    shootoutId = remote.seedShootout(
      tid,
      startRank: 1,
      tiedParticipantIds: [p1, p2],
    );
  });

  test('listPendingShootouts surfaces a pending group with display names',
      () async {
    final pending = await remote.listPendingShootouts(tid);
    expect(pending, hasLength(1));
    final s = pending.single;
    expect(s.shootoutId, shootoutId);
    expect(s.startRank, 1);
    expect(s.status, ShootoutStatus.pending);
    expect(s.tiedParticipantIds, [p1, p2]);
    // Fake projects displayName == participantId.
    expect(s.tiedParticipants.first.displayName, p1.value);
  });

  test('report then confirm by the other side resolves the group', () async {
    remote.currentUser = userA;
    await remote.reportShootoutWinners(
      shootoutId: shootoutId,
      orderedWinners: [p2, p1],
    );

    // After a report the group is 'reported' and carries the ordering.
    final afterReport = await remote.listPendingShootouts(tid);
    expect(afterReport.single.status, ShootoutStatus.reported);
    expect(afterReport.single.orderedWinners, [p2, p1]);

    // The OTHER side confirms the exact same ordering -> resolved -> drops out.
    remote.currentUser = userB;
    await remote.confirmShootout(
      shootoutId: shootoutId,
      orderedWinners: [p2, p1],
    );
    final afterConfirm = await remote.listPendingShootouts(tid);
    expect(afterConfirm, isEmpty);
  });

  test('reporter cannot self-confirm', () async {
    remote.currentUser = userA;
    await remote.reportShootoutWinners(
      shootoutId: shootoutId,
      orderedWinners: [p1, p2],
    );
    // Same user tries to confirm -> rejected.
    await expectLater(
      remote.confirmShootout(shootoutId: shootoutId, orderedWinners: [p1, p2]),
      throwsA(isA<StateError>()),
    );
  });

  test('confirmation with a mismatched ordering is rejected', () async {
    remote.currentUser = userA;
    await remote.reportShootoutWinners(
      shootoutId: shootoutId,
      orderedWinners: [p1, p2],
    );
    remote.currentUser = userB;
    await expectLater(
      remote.confirmShootout(shootoutId: shootoutId, orderedWinners: [p2, p1]),
      throwsA(isA<StateError>()),
    );
  });

  test('a partial / non-permutation ordering is rejected on report', () async {
    remote.currentUser = userA;
    // Only one of the two tied ids -> not a permutation.
    await expectLater(
      remote.reportShootoutWinners(shootoutId: shootoutId, orderedWinners: [p1]),
      throwsA(isA<StateError>()),
    );
  });

  group('C5: real two-sided consensus across open-team participants', () {
    late TournamentId teamTid;
    late TournamentParticipantId teamA;
    late TournamentParticipantId teamB;
    late String teamShootoutId;

    const a1 = UserId('u-a1');
    const a2 = UserId('u-a2');
    const b1 = UserId('u-b1');
    const b2 = UserId('u-b2');

    setUp(() async {
      remote = FakeTournamentRemote(initialUser: organizer);
      teamTid = await remote.createTournament(
        displayName: 'TeamT',
        teamSize: 2,
        minParticipants: 2,
        maxParticipants: 4,
        format: TournamentFormat.roundRobin,
        matchFormatConfig: const <String, Object?>{},
        tiebreakerOrder: const <String>[],
      );
      // Team A with two distinct members.
      remote.currentUser = a1;
      teamA = await remote.registerTeam(
        tournamentId: teamTid,
        teamId: const TeamId('team-a'),
        roster: [
          RosterSlotInput.member(1, a1),
          RosterSlotInput.member(2, a2),
        ],
      );
      // Team B with two distinct members.
      remote.currentUser = b1;
      teamB = await remote.registerTeam(
        tournamentId: teamTid,
        teamId: const TeamId('team-b'),
        roster: [
          RosterSlotInput.member(1, b1),
          RosterSlotInput.member(2, b2),
        ],
      );
      teamShootoutId = remote.seedShootout(
        teamTid,
        startRank: 1,
        tiedParticipantIds: [teamA, teamB],
      );
    });

    test('two members of the SAME team cannot report+confirm', () async {
      // A1 reports for team A...
      remote.currentUser = a1;
      await remote.reportShootoutWinners(
        shootoutId: teamShootoutId,
        orderedWinners: [teamA, teamB],
      );
      // ...A2 (same team A) must NOT be able to confirm it.
      remote.currentUser = a2;
      await expectLater(
        remote.confirmShootout(
          shootoutId: teamShootoutId,
          orderedWinners: [teamA, teamB],
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('a member of the opposing team CAN confirm', () async {
      remote.currentUser = a1;
      await remote.reportShootoutWinners(
        shootoutId: teamShootoutId,
        orderedWinners: [teamA, teamB],
      );
      // B1 (team B, the other participant) confirms -> resolved.
      remote.currentUser = b1;
      await remote.confirmShootout(
        shootoutId: teamShootoutId,
        orderedWinners: [teamA, teamB],
      );
      final pending = await remote.listPendingShootouts(teamTid);
      expect(pending, isEmpty);
    });
  });
}
