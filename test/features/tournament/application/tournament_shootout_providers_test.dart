import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_shootout_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Stub that records report/confirm calls and returns a configurable pending
/// list. The list it returns can be swapped between loads so the provider test
/// can prove an invalidation actually re-fetches.
class _StubRemote implements TournamentRemote {
  _StubRemote(this.pending);

  /// Mutable so a test can swap the result between loads to prove a
  /// re-fetch happened after invalidation.
  List<PendingShootout> pending;
  int loadCount = 0;
  final List<({String shootoutId, List<TournamentParticipantId> order})>
      reportCalls = [];
  final List<({String shootoutId, List<TournamentParticipantId> order})>
      confirmCalls = [];

  @override
  Future<List<PendingShootout>> listPendingShootouts(
    TournamentId tournamentId,
  ) async {
    loadCount += 1;
    return pending;
  }

  @override
  Future<void> reportShootoutWinners({
    required String shootoutId,
    required List<TournamentParticipantId> orderedWinners,
  }) async {
    reportCalls.add((shootoutId: shootoutId, order: orderedWinners));
  }

  @override
  Future<void> confirmShootout({
    required String shootoutId,
    required List<TournamentParticipantId> orderedWinners,
  }) async {
    confirmCalls.add((shootoutId: shootoutId, order: orderedWinners));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

PendingShootout _so({
  String id = 'so-1',
  String tid = 't-1',
  int startRank = 1,
  List<String> tied = const ['p1', 'p2'],
  List<String> ordered = const [],
  ShootoutStatus status = ShootoutStatus.pending,
}) {
  return PendingShootout(
    shootoutId: id,
    tournamentId: TournamentId(tid),
    startRank: startRank,
    tiedParticipants: [
      for (final p in tied)
        ShootoutParticipantRef(
          participantId: TournamentParticipantId(p),
          displayName: 'Name $p',
        ),
    ],
    orderedWinners: [for (final p in ordered) TournamentParticipantId(p)],
    status: status,
  );
}

ProviderContainer _container(TournamentRemote remote) {
  return ProviderContainer(
    overrides: [tournamentRemoteProvider.overrideWithValue(remote)],
  );
}

void main() {
  const tid = TournamentId('t-1');

  test('pendingShootoutsProvider loads from the remote', () async {
    final remote = _StubRemote([_so()]);
    final c = _container(remote);
    addTearDown(c.dispose);

    final result = await c.read(pendingShootoutsProvider(tid).future);

    expect(result, hasLength(1));
    expect(result.first.shootoutId, 'so-1');
    expect(remote.loadCount, 1);
  });

  test('reportWinners calls the remote and invalidates the pending provider',
      () async {
    final remote = _StubRemote([_so()]);
    final c = _container(remote);
    addTearDown(c.dispose);

    // Prime the provider.
    await c.read(pendingShootoutsProvider(tid).future);
    expect(remote.loadCount, 1);

    // After the report the group resolves and drops out of the list.
    remote.pending = const <PendingShootout>[];
    await c.read(tournamentShootoutActionsProvider).reportWinners(
      tournamentId: tid,
      shootoutId: 'so-1',
      orderedWinners: const [
        TournamentParticipantId('p2'),
        TournamentParticipantId('p1'),
      ],
    );

    expect(remote.reportCalls, hasLength(1));
    expect(remote.reportCalls.first.shootoutId, 'so-1');
    expect(
      remote.reportCalls.first.order.map((e) => e.value).toList(),
      ['p2', 'p1'],
    );

    // The invalidation forces a re-fetch on next read.
    final after = await c.read(pendingShootoutsProvider(tid).future);
    expect(remote.loadCount, 2);
    expect(after, isEmpty);
  });

  test('confirm calls the remote and invalidates the pending provider',
      () async {
    final remote = _StubRemote([_so(status: ShootoutStatus.reported)]);
    final c = _container(remote);
    addTearDown(c.dispose);

    await c.read(pendingShootoutsProvider(tid).future);
    expect(remote.loadCount, 1);

    remote.pending = const <PendingShootout>[];
    await c.read(tournamentShootoutActionsProvider).confirm(
      tournamentId: tid,
      shootoutId: 'so-1',
      orderedWinners: const [
        TournamentParticipantId('p1'),
        TournamentParticipantId('p2'),
      ],
    );

    expect(remote.confirmCalls, hasLength(1));
    final after = await c.read(pendingShootoutsProvider(tid).future);
    expect(remote.loadCount, 2);
    expect(after, isEmpty);
  });
}
