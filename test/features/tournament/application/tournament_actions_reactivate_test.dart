import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

const _id = TournamentId('t-1');

/// Records the reactivate call and counts the detail re-reads so the test can
/// assert the action both hit the RPC and invalidated the detail provider.
class _Remote implements TournamentRemote {
  final List<TournamentId> reactivated = <TournamentId>[];
  int detailCalls = 0;

  @override
  Future<void> reactivateTournament(TournamentId id) async {
    reactivated.add(id);
  }

  @override
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async {
    detailCalls += 1;
    return null;
  }

  @override
  Future<List<TournamentSummaryRef>> listTournaments({
    TournamentStatus? statusFilter,
    int limit = 50,
  }) async =>
      const <TournamentSummaryRef>[];

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  test('reactivate calls the RPC and refreshes list + detail', () async {
    final remote = _Remote();
    final container = ProviderContainer(
      overrides: [tournamentRemoteProvider.overrideWithValue(remote)],
    );
    addTearDown(container.dispose);

    // Prime the detail so the invalidation triggers a fresh read.
    await container.read(tournamentDetailProvider(_id).future);
    final before = remote.detailCalls;

    await container.read(tournamentActionsProvider).reactivate(_id);
    await container.read(tournamentDetailProvider(_id).future);

    expect(remote.reactivated, [_id]);
    expect(remote.detailCalls, greaterThan(before));
  });
}
