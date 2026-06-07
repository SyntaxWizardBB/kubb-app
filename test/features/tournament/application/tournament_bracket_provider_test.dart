import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

class _StubRemote implements TournamentRemote {
  _StubRemote(this._brackets);

  final Map<String, Bracket> _brackets;
  final List<String> calls = <String>[];
  final List<String> poolCalls = <String>[];

  @override
  Future<Bracket> getBracket(TournamentId tournamentId) async {
    calls.add(tournamentId.value);
    return _brackets[tournamentId.value] ??
        Bracket.singleElimination(const <String>['p1', 'p2']);
  }

  @override
  Future<List<PoolGroupStandings>> getPoolStandings(
    TournamentId tournamentId,
  ) async {
    poolCalls.add(tournamentId.value);
    return const <PoolGroupStandings>[];
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

ProviderContainer _container(TournamentRemote remote) {
  return ProviderContainer(
    overrides: [tournamentRemoteProvider.overrideWithValue(remote)],
  );
}

ProviderContainer _gatedContainer(
  TournamentRemote remote,
  FakeRealtimeChannel channel, {
  bool realtimeEnabled = true,
}) {
  return ProviderContainer(
    overrides: [
      tournamentRemoteProvider.overrideWithValue(remote),
      realtimeChannelProvider.overrideWithValue(channel),
      realtimeEnabledFlagProvider.overrideWithValue(realtimeEnabled),
    ],
  );
}

void main() {
  group('tournamentBracketProvider', () {
    test('exposes Bracket value after fetch', () async {
      final bracket =
          Bracket.singleElimination(const <String>['a', 'b', 'c', 'd']);
      final remote = _StubRemote(<String, Bracket>{'t-1': bracket});
      final c = _container(remote);
      addTearDown(c.dispose);

      final result = await c
          .read(tournamentBracketProvider(const TournamentId('t-1')).future);

      expect(result, equals(bracket));
      expect(remote.calls, <String>['t-1']);
    });

    test('family fires anew when tournamentId changes', () async {
      final b1 = Bracket.singleElimination(const <String>['a', 'b']);
      final b2 = Bracket.singleElimination(const <String>['x', 'y', 'z', 'w']);
      final remote = _StubRemote(<String, Bracket>{'t-1': b1, 't-2': b2});
      final c = _container(remote);
      addTearDown(c.dispose);

      final r1 = await c
          .read(tournamentBracketProvider(const TournamentId('t-1')).future);
      final r2 = await c
          .read(tournamentBracketProvider(const TournamentId('t-2')).future);

      expect(r1, equals(b1));
      expect(r2, equals(b2));
      expect(remote.calls, <String>['t-1', 't-2']);
    });
  });

  // P2 (C4-T4): the bracket / pool-standings pollers are fallback-gated —
  // they only invalidate while the realtime channel is unhealthy, at 30 s.
  group('tournamentBracketPollingProvider (fallback-gated)', () {
    const tid = TournamentId('t-poll');
    final key = tournamentRealtimeChannelKey(tid);

    test('joined channel → no invalidate / no extra getBracket', () {
      fakeAsync((async) {
        final remote = _StubRemote(const <String, Bracket>{});
        final channel = FakeRealtimeChannel();
        final c = _gatedContainer(remote, channel);
        addTearDown(c.dispose);

        final sub = c.listen(tournamentBracketPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        // Drive the channel into the healthy state.
        channel.setState(key, RealtimeChannelState.joined);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 120))
          ..flushMicrotasks();

        expect(remote.calls, isEmpty,
            reason: 'healthy realtime → no fallback poll');
      });
    });

    test('errored ≥60 s → invalidate at 30 s cadence', () {
      fakeAsync((async) {
        final remote = _StubRemote(const <String, Bracket>{});
        final channel = FakeRealtimeChannel();
        final c = _gatedContainer(remote, channel);
        addTearDown(c.dispose);

        // Prime the bracket so an invalidate produces a counted refetch.
        final dataSub =
            c.listen(tournamentBracketProvider(tid), (_, _) {});
        addTearDown(dataSub.close);
        final sub = c.listen(tournamentBracketPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(remote.calls, <String>[tid.value], reason: 'initial fetch only');

        channel.setState(key, RealtimeChannelState.errored);
        async
          ..elapse(const Duration(seconds: 60))
          ..flushMicrotasks()
          // 29 s into the open gate: still nothing — cadence is 30 s not 5 s.
          ..elapse(const Duration(seconds: 29))
          ..flushMicrotasks();
        expect(remote.calls.length, 1,
            reason: 'no fallback poll before 30 s');

        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(remote.calls.length, 2, reason: 'first fallback poll at 30 s');

        async
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();
        expect(remote.calls.length, 3, reason: 'fallback re-arms every 30 s');
      });
    });

    test('recovery (joined) cancels the fallback timer', () {
      fakeAsync((async) {
        final remote = _StubRemote(const <String, Bracket>{});
        final channel = FakeRealtimeChannel();
        final c = _gatedContainer(remote, channel);
        addTearDown(c.dispose);

        final dataSub =
            c.listen(tournamentBracketProvider(tid), (_, _) {});
        addTearDown(dataSub.close);
        final sub = c.listen(tournamentBracketPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();

        channel.setState(key, RealtimeChannelState.errored);
        async
          ..elapse(const Duration(seconds: 60))
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();
        final afterFirstPoll = remote.calls.length;
        expect(afterFirstPoll, greaterThan(1));

        // Recover — the timer must stop.
        channel.setState(key, RealtimeChannelState.joined);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 120))
          ..flushMicrotasks();
        expect(remote.calls.length, afterFirstPoll,
            reason: 'no further polls after recovery');
      });
    });
  });

  group('tournamentPoolStandingsPollingProvider (fallback-gated)', () {
    const tid = TournamentId('t-pool');
    final key = tournamentRealtimeChannelKey(tid);

    test('joined channel → no getPoolStandings poll', () {
      fakeAsync((async) {
        final remote = _StubRemote(const <String, Bracket>{});
        final channel = FakeRealtimeChannel();
        final c = _gatedContainer(remote, channel);
        addTearDown(c.dispose);

        final sub =
            c.listen(tournamentPoolStandingsPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        channel.setState(key, RealtimeChannelState.joined);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 120))
          ..flushMicrotasks();

        expect(remote.poolCalls, isEmpty);
      });
    });

    test('errored ≥60 s → poll at 30 s cadence', () {
      fakeAsync((async) {
        final remote = _StubRemote(const <String, Bracket>{});
        final channel = FakeRealtimeChannel();
        final c = _gatedContainer(remote, channel);
        addTearDown(c.dispose);

        final dataSub =
            c.listen(tournamentPoolStandingsProvider(tid), (_, _) {});
        addTearDown(dataSub.close);
        final sub =
            c.listen(tournamentPoolStandingsPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(remote.poolCalls.length, 1);

        channel.setState(key, RealtimeChannelState.errored);
        async
          ..elapse(const Duration(seconds: 60))
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 29))
          ..flushMicrotasks();
        expect(remote.poolCalls.length, 1,
            reason: 'no poll before 60 s grace + 30 s cadence');

        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(remote.poolCalls.length, 2, reason: 'first poll at 30 s');
      });
    });
  });
}
