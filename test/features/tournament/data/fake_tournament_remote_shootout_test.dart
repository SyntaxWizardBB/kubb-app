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
}
