import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/public_tournament_polling_provider.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

/// P2 (C6-T1): the anon public-tournament poller is fallback-gated. Broadcast
/// (`tournamentBroadcastTopic`) is the live source; polling only runs while
/// the channel is unhealthy (≥60 s errored) OR the kill-switch
/// (`realtimeEnabledFlagProvider`) is off. The anon fallback cadence stays
/// 10 s (NOT the 30 s authenticated cadence).
class _StubRemote implements TournamentRemote {
  final List<String> listCalls = <String>[];

  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
    TournamentId id,
  ) async {
    listCalls.add(id.value);
    return const <TournamentMatchRef>[];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProviderContainer _container(
  TournamentRemote remote,
  FakeRealtimeChannel channel, {
  bool realtimeEnabled = true,
}) {
  final c = ProviderContainer(
    overrides: [
      tournamentRemoteProvider.overrideWithValue(remote),
      realtimeChannelProvider.overrideWithValue(channel),
      realtimeEnabledFlagProvider.overrideWithValue(realtimeEnabled),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  const tid = TournamentId('t-public');
  final key = tournamentRealtimeChannelKey(tid);

  test('joined channel → no anon poll', () {
    fakeAsync((async) {
      final remote = _StubRemote();
      final channel = FakeRealtimeChannel();
      final c = _container(remote, channel);

      final data = c.listen(tournamentMatchListProvider(tid), (_, _) {});
      addTearDown(data.close);
      final sub = c.listen(publicTournamentPollingProvider(tid), (_, _) {});
      addTearDown(sub.close);
      channel.setState(key, RealtimeChannelState.joined);
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 120))
        ..flushMicrotasks();

      expect(remote.listCalls.length, 1,
          reason: 'healthy broadcast channel → no poll, only initial fetch');
    });
  });

  test('errored ≥60 s → anon poll at 10 s cadence (not 30 s)', () {
    fakeAsync((async) {
      final remote = _StubRemote();
      final channel = FakeRealtimeChannel();
      final c = _container(remote, channel);

      final data = c.listen(tournamentMatchListProvider(tid), (_, _) {});
      addTearDown(data.close);
      final sub = c.listen(publicTournamentPollingProvider(tid), (_, _) {});
      addTearDown(sub.close);
      async.flushMicrotasks();
      expect(remote.listCalls.length, 1);

      channel.setState(key, RealtimeChannelState.errored);
      async
        ..elapse(const Duration(seconds: 60))
        ..flushMicrotasks()
        // 9 s into the open gate: nothing yet — anon cadence is 10 s.
        ..elapse(const Duration(seconds: 9))
        ..flushMicrotasks();
      expect(remote.listCalls.length, 1, reason: 'nothing before 10 s');

      async
        ..elapse(const Duration(seconds: 1))
        ..flushMicrotasks();
      expect(remote.listCalls.length, 2, reason: 'first anon poll at 10 s');

      async
        ..elapse(const Duration(seconds: 10))
        ..flushMicrotasks();
      expect(remote.listCalls.length, 3, reason: 're-arms every 10 s');
    });
  });

  test('kill-switch off (realtimeEnabledFlagProvider=false) → poll at 10 s', () {
    fakeAsync((async) {
      final remote = _StubRemote();
      final channel = FakeRealtimeChannel();
      // "Live-Modus aus": realtime disabled → gate is true immediately,
      // no 60 s grace needed.
      final c = _container(remote, channel, realtimeEnabled: false);

      final data = c.listen(tournamentMatchListProvider(tid), (_, _) {});
      addTearDown(data.close);
      final sub = c.listen(publicTournamentPollingProvider(tid), (_, _) {});
      addTearDown(sub.close);
      async.flushMicrotasks();
      expect(remote.listCalls.length, 1);

      async
        ..elapse(const Duration(seconds: 10))
        ..flushMicrotasks();
      expect(remote.listCalls.length, 2,
          reason: 'kill-switch off polls immediately at 10 s, no grace');
    });
  });
}
