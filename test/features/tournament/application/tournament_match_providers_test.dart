import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

/// P2 (C4-T5): the match-list and match-detail pollers are fallback-gated —
/// they only invalidate while the per-tournament realtime channel is
/// unhealthy (≥60 s errored), at 30 s. The detail poller keeps its
/// terminal-state stop (finalized/overridden/voided ⇒ no poll).
TournamentMatchRef _match(
  TournamentId tid,
  TournamentMatchId mid,
  TournamentMatchStatus status,
) =>
    TournamentMatchRef(
      matchId: mid,
      tournamentId: tid,
      roundNumber: 1,
      matchNumberInRound: 1,
      participantA: const TournamentParticipantId('pa'),
      participantB: const TournamentParticipantId('pb'),
      status: status,
      consensusRound: 0,
    );

class _StubRemote implements TournamentRemote {
  _StubRemote({required this.match, required this.list});

  TournamentMatchRef? match;
  List<TournamentMatchRef> list;
  final List<String> listCalls = <String>[];
  final List<String> matchCalls = <String>[];

  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
    TournamentId id,
  ) async {
    listCalls.add(id.value);
    return list;
  }

  @override
  Future<TournamentMatchRef?> getMatch(TournamentMatchId id) async {
    matchCalls.add(id.value);
    return match;
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
  const tid = TournamentId('t-match');
  final key = tournamentRealtimeChannelKey(tid);

  group('tournamentMatchListPollingProvider (fallback-gated)', () {
    test('joined channel → no list poll', () {
      fakeAsync((async) {
        final remote = _StubRemote(match: null, list: const []);
        final channel = FakeRealtimeChannel();
        final c = _container(remote, channel);

        final data = c.listen(tournamentMatchListProvider(tid), (_, _) {});
        addTearDown(data.close);
        final sub = c.listen(tournamentMatchListPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        channel.setState(key, RealtimeChannelState.joined);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 120))
          ..flushMicrotasks();

        expect(remote.listCalls.length, 1,
            reason: 'only the initial fetch — healthy realtime, no poll');
      });
    });

    test('errored ≥60 s → list poll at 30 s cadence', () {
      fakeAsync((async) {
        final remote = _StubRemote(match: null, list: const []);
        final channel = FakeRealtimeChannel();
        final c = _container(remote, channel);

        final data = c.listen(tournamentMatchListProvider(tid), (_, _) {});
        addTearDown(data.close);
        final sub = c.listen(tournamentMatchListPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(remote.listCalls.length, 1);

        channel.setState(key, RealtimeChannelState.errored);
        async
          ..elapse(const Duration(seconds: 60))
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 29))
          ..flushMicrotasks();
        expect(remote.listCalls.length, 1, reason: 'nothing before 30 s');

        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(remote.listCalls.length, 2, reason: 'first poll at 30 s');
      });
    });
  });

  group('tournamentMatchPollingProvider (fallback-gated detail)', () {
    const mid = TournamentMatchId('m-1');

    test('joined channel → no detail poll', () {
      fakeAsync((async) {
        final remote = _StubRemote(
          match: _match(tid, mid, TournamentMatchStatus.scheduled),
          list: const [],
        );
        final channel = FakeRealtimeChannel();
        final c = _container(remote, channel);

        final data = c.listen(tournamentMatchDetailProvider(mid), (_, _) {});
        addTearDown(data.close);
        final sub = c.listen(tournamentMatchPollingProvider(mid), (_, _) {});
        addTearDown(sub.close);
        channel.setState(key, RealtimeChannelState.joined);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 120))
          ..flushMicrotasks();

        expect(remote.matchCalls.length, 1,
            reason: 'only the initial detail fetch');
      });
    });

    test('errored ≥60 s → detail poll at 30 s cadence', () {
      fakeAsync((async) {
        final remote = _StubRemote(
          match: _match(tid, mid, TournamentMatchStatus.scheduled),
          list: const [],
        );
        final channel = FakeRealtimeChannel();
        final c = _container(remote, channel);

        final data = c.listen(tournamentMatchDetailProvider(mid), (_, _) {});
        addTearDown(data.close);
        final sub = c.listen(tournamentMatchPollingProvider(mid), (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(remote.matchCalls.length, 1);

        channel.setState(key, RealtimeChannelState.errored);
        async
          ..elapse(const Duration(seconds: 60))
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 29))
          ..flushMicrotasks();
        expect(remote.matchCalls.length, 1, reason: 'nothing before 30 s');

        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(remote.matchCalls.length, 2, reason: 'first poll at 30 s');
      });
    });

    test('terminal status (finalized) → no poll even while fallback active',
        () {
      fakeAsync((async) {
        final remote = _StubRemote(
          match: _match(tid, mid, TournamentMatchStatus.finalized),
          list: const [],
        );
        final channel = FakeRealtimeChannel();
        final c = _container(remote, channel);

        final data = c.listen(tournamentMatchDetailProvider(mid), (_, _) {});
        addTearDown(data.close);
        final sub = c.listen(tournamentMatchPollingProvider(mid), (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(remote.matchCalls.length, 1, reason: 'initial fetch only');

        channel.setState(key, RealtimeChannelState.errored);
        async
          ..elapse(const Duration(seconds: 180))
          ..flushMicrotasks();

        expect(remote.matchCalls.length, 1,
            reason: 'finalized match never re-polls despite the open gate');
      });
    });
  });
}
