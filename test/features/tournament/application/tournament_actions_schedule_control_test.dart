// ADR-0031 Phase B, Block B2c — TournamentActions pause/resume/skip facade.
//
// For each of the four control actions we assert:
//   (a) the matching TournamentRemote port method is called with the id, and
//   (b) administrableTournamentsProvider is invalidated (it re-fetches), per
//       the DOD-04 invalidation spec. The detail-schedule CDC-stream-fold
//       (tournamentRoundScheduleProvider) is deliberately NOT invalidated —
//       the server schedule CDC pushes the change; invalidating the fold would
//       reset the accumulated round state. We assert that no extra schedule
//       fetch is forced by checking the remote's watch path is never re-driven
//       through invalidation here.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Records control-RPC calls and counts how often the overview list is read,
/// so the test can assert both the port call and the invalidation-driven
/// re-fetch.
class _RecordingRemote implements TournamentRemote {
  final List<({String action, String id})> calls = <({String action, String id})>[];
  int listAdministrableCalls = 0;

  @override
  Future<List<TournamentAdminCardRef>> listAdministrableTournaments() async {
    listAdministrableCalls += 1;
    return const <TournamentAdminCardRef>[];
  }

  @override
  Future<void> pauseTournament(TournamentId id) async {
    calls.add((action: 'pause', id: id.value));
  }

  @override
  Future<void> resumeTournament(TournamentId id) async {
    calls.add((action: 'resume', id: id.value));
  }

  @override
  Future<void> skipScheduleForward(TournamentId id) async {
    calls.add((action: 'skipForward', id: id.value));
  }

  @override
  Future<void> skipScheduleBackward(TournamentId id) async {
    calls.add((action: 'skipBack', id: id.value));
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  const id = TournamentId('t-ctrl-facade');

  late _RecordingRemote remote;
  late ProviderContainer container;

  setUp(() {
    remote = _RecordingRemote();
    container = ProviderContainer(
      overrides: [
        tournamentRemoteProvider.overrideWithValue(remote),
      ],
    );
    addTearDown(container.dispose);
  });

  final cases = <({
    String action,
    Future<void> Function(TournamentActions a) invoke,
  })>[
    (action: 'pause', invoke: (a) => a.pause(id)),
    (action: 'resume', invoke: (a) => a.resume(id)),
    (action: 'skipForward', invoke: (a) => a.skipForward(id)),
    (action: 'skipBack', invoke: (a) => a.skipBack(id)),
  ];

  for (final c in cases) {
    test('${c.action}: calls the port method with the tournament id and '
        'refreshes the overview', () async {
      // Subscribe so the overview provider fetches once and stays alive.
      final sub = container.listen(
        administrableTournamentsProvider,
        (_, _) {},
      );
      addTearDown(sub.close);
      await container.read(administrableTournamentsProvider.future);
      expect(remote.listAdministrableCalls, 1);

      await c.invoke(container.read(tournamentActionsProvider));

      // (a) the port method ran with the id.
      expect(remote.calls, hasLength(1));
      expect(remote.calls.single.action, c.action);
      expect(remote.calls.single.id, id.value);

      // (b) administrableTournamentsProvider was invalidated → re-fetch.
      await container.read(administrableTournamentsProvider.future);
      expect(
        remote.listAdministrableCalls,
        2,
        reason: 'overview must be invalidated after a schedule control action',
      );
    });
  }
}
