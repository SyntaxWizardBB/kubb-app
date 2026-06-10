// ADR-0031 Phase D, Block D3 — TournamentActions.checkin / undoCheckin.
//
// Contract: each action forwards to the matching remote method
// (checkinParticipant / undoCheckin) and invalidates the detail provider for
// the passed tournamentId so the participant list re-reads — analogous to
// withdrawRegistration. No accumulating realtime fold provider is touched.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/tournament_list_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

class _RecordingRemote implements TournamentRemote {
  int detailCalls = 0;
  final List<String> checkins = <String>[];
  final List<String> undos = <String>[];

  @override
  Future<void> checkinParticipant(TournamentParticipantId id) async {
    checkins.add(id.value);
  }

  @override
  Future<void> undoCheckin(TournamentParticipantId id) async {
    undos.add(id.value);
  }

  @override
  Future<TournamentDetail?> getTournamentDetail(TournamentId id) async {
    detailCalls += 1;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  const tid = TournamentId('t-checkin');
  const pid = TournamentParticipantId('p-1');

  late _RecordingRemote remote;
  late ProviderContainer container;

  setUp(() {
    remote = _RecordingRemote();
    container = ProviderContainer(
      overrides: [tournamentRemoteProvider.overrideWithValue(remote)],
    );
    addTearDown(container.dispose);
  });

  test('checkin: calls remote.checkinParticipant + invalidates detail',
      () async {
    final sub = container.listen(tournamentDetailProvider(tid), (_, _) {});
    addTearDown(sub.close);
    await container.read(tournamentDetailProvider(tid).future);
    expect(remote.detailCalls, 1);

    await container
        .read(tournamentActionsProvider)
        .checkin(pid, tournamentId: tid);

    expect(remote.checkins, [pid.value]);

    await container.read(tournamentDetailProvider(tid).future);
    expect(
      remote.detailCalls,
      2,
      reason: 'checkin must invalidate tournamentDetailProvider',
    );
  });

  test('undoCheckin: calls remote.undoCheckin + invalidates detail', () async {
    final sub = container.listen(tournamentDetailProvider(tid), (_, _) {});
    addTearDown(sub.close);
    await container.read(tournamentDetailProvider(tid).future);
    expect(remote.detailCalls, 1);

    await container
        .read(tournamentActionsProvider)
        .undoCheckin(pid, tournamentId: tid);

    expect(remote.undos, [pid.value]);

    await container.read(tournamentDetailProvider(tid).future);
    expect(
      remote.detailCalls,
      2,
      reason: 'undoCheckin must invalidate tournamentDetailProvider',
    );
  });
}
