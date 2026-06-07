import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/inbox/application/inbox_controller.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';
import 'package:kubb_app/features/inbox/data/inbox_repository.dart';
import 'package:kubb_app/features/social/application/social_providers.dart';
import 'package:kubb_app/features/social/data/friend_models.dart';
import 'package:kubb_app/features/social/data/friend_repository.dart';
import 'package:kubb_app/features/tournament/application/public_tournament_polling_provider.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_bracket_provider.dart';
import 'package:kubb_app/features/tournament/application/tournament_match_providers.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

/// Test-Klasse B (ADR-0029 §(f), Plan Phase P4) — the KILL-SWITCH harness.
///
/// For EVERY gated server-state concern-family this proves two opposite facts
/// through the SAME mechanism the production poller uses (a counted
/// refresh/invalidate), driven entirely through `fakeAsync`:
///
///  1. `realtimeEnabledFlagProvider = false` (kill-switch engaged, "Live-Modus
///     aus") => the gated fallback-poll path engages IMMEDIATELY (no 60 s
///     grace, because the gate short-circuits to `true`) with the family's
///     correct cadence: 30 s for authenticated families, 10 s for the anon
///     public family.
///  2. Healthy `joined` channel + flag on => NO fallback poll ever fires, even
///     after >60 s of fake time — the boolean gate is exclusive.
///
/// Every channel-key is built via a kubb_domain builder. No hand-built
/// `<table>:<column>=<value>` literal appears here, and the messaging-framework
/// architecture guard (which scans only `lib/`) is untouched by this file.
void main() {
  // ---- inbox (inboxCdcProvider) ------------------------------------------
  group('kill-switch — inbox (inboxCdcProvider, 30 s)', () {
    const userId = 'u-inbox';
    final channelKey = inboxRealtimeChannelKey(const UserId(userId));

    ProviderContainer makeContainer(
      FakeRealtimeChannel channel,
      _RecordingInboxRepository repo, {
      required bool realtimeEnabled,
    }) {
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue(userId),
          realtimeChannelProvider.overrideWithValue(channel),
          realtimeEnabledFlagProvider.overrideWithValue(realtimeEnabled),
          inboxRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('flag off → fallback refresh engages at 30 s (no 60 s grace)', () {
      fakeAsync((async) {
        final channel = FakeRealtimeChannel();
        final repo = _RecordingInboxRepository();
        final container =
            makeContainer(channel, repo, realtimeEnabled: false);

        final sub = container.listen<AsyncValue<void>>(
          inboxCdcProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        // Kill-switch on → gate true immediately, no grace. Nothing before 30s.
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 29))
          ..flushMicrotasks();
        expect(repo.refreshCalls, isEmpty, reason: 'nothing before 30 s');

        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(repo.refreshCalls, [userId],
            reason: 'kill-switch off → fallback poll at 30 s, no grace');

        async
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();
        expect(repo.refreshCalls.length, 2, reason: 're-arms every 30 s');
      });
    });

    test('healthy joined + flag on → no fallback poll after >60 s', () {
      fakeAsync((async) {
        final channel = FakeRealtimeChannel();
        final repo = _RecordingInboxRepository();
        final container = makeContainer(channel, repo, realtimeEnabled: true);

        final sub = container.listen<AsyncValue<void>>(
          inboxCdcProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(sub.close);
        channel.setState(channelKey, RealtimeChannelState.joined);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 90))
          ..flushMicrotasks();

        expect(repo.refreshCalls, isEmpty,
            reason: 'healthy joined → no fallback poll, no double-updates');
      });
    });
  });

  // ---- friends (friendsCdcProvider) --------------------------------------
  group('kill-switch — friends (friendsCdcProvider, 30 s)', () {
    const userId = 'u-friends';
    final channelKey = friendsRealtimeChannelKey(const UserId(userId));

    ProviderContainer makeContainer(
      FakeRealtimeChannel channel,
      _RecordingFriendRepository repo, {
      required bool realtimeEnabled,
    }) {
      final container = ProviderContainer(
        overrides: [
          currentUserIdProvider.overrideWithValue(userId),
          isAuthenticatedProvider.overrideWithValue(true),
          realtimeChannelProvider.overrideWithValue(channel),
          realtimeEnabledFlagProvider.overrideWithValue(realtimeEnabled),
          friendRepositoryProvider.overrideWithValue(repo),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('flag off → fallback invalidation engages at 30 s (no grace)', () {
      fakeAsync((async) {
        final channel = FakeRealtimeChannel();
        final repo = _RecordingFriendRepository();
        final container =
            makeContainer(channel, repo, realtimeEnabled: false);

        final cdcSub = container.listen<AsyncValue<void>>(
          friendsCdcProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(cdcSub.close);
        final listSub = container.listen<AsyncValue<List<FriendEntry>>>(
          friendsListProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(listSub.close);
        async.flushMicrotasks();
        expect(repo.listCalls, 1, reason: 'initial fetch only');

        async
          ..elapse(const Duration(seconds: 29))
          ..flushMicrotasks();
        expect(repo.listCalls, 1, reason: 'nothing before 30 s');

        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(repo.listCalls, 2,
            reason: 'kill-switch off → fallback invalidate at 30 s, no grace');

        async
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();
        expect(repo.listCalls, 3, reason: 're-arms every 30 s');
      });
    });

    test('healthy joined + flag on → no fallback invalidation after >60 s', () {
      fakeAsync((async) {
        final channel = FakeRealtimeChannel();
        final repo = _RecordingFriendRepository();
        final container = makeContainer(channel, repo, realtimeEnabled: true);

        final cdcSub = container.listen<AsyncValue<void>>(
          friendsCdcProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(cdcSub.close);
        final listSub = container.listen<AsyncValue<List<FriendEntry>>>(
          friendsListProvider,
          (_, _) {},
          fireImmediately: true,
        );
        addTearDown(listSub.close);
        channel.setState(channelKey, RealtimeChannelState.joined);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 90))
          ..flushMicrotasks();

        expect(repo.listCalls, 1,
            reason: 'healthy joined → only the initial fetch, no poll');
      });
    });
  });

  // ---- tournament bracket + pool-standings -------------------------------
  group('kill-switch — tournament bracket / pool-standings (30 s)', () {
    const tid = TournamentId('t-ko');
    final key = tournamentRealtimeChannelKey(tid);

    ProviderContainer makeContainer(
      _StubTournamentRemote remote,
      FakeRealtimeChannel channel, {
      required bool realtimeEnabled,
    }) {
      final container = ProviderContainer(
        overrides: [
          tournamentRemoteProvider.overrideWithValue(remote),
          realtimeChannelProvider.overrideWithValue(channel),
          realtimeEnabledFlagProvider.overrideWithValue(realtimeEnabled),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('bracket: flag off → fallback poll at 30 s (no grace)', () {
      fakeAsync((async) {
        final remote = _StubTournamentRemote();
        final channel = FakeRealtimeChannel();
        final container =
            makeContainer(remote, channel, realtimeEnabled: false);

        final data = container.listen(tournamentBracketProvider(tid), (_, _) {});
        addTearDown(data.close);
        final sub =
            container.listen(tournamentBracketPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(remote.bracketCalls.length, 1, reason: 'initial fetch only');

        async
          ..elapse(const Duration(seconds: 29))
          ..flushMicrotasks();
        expect(remote.bracketCalls.length, 1, reason: 'nothing before 30 s');

        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(remote.bracketCalls.length, 2,
            reason: 'kill-switch off → fallback poll at 30 s, no grace');

        async
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();
        expect(remote.bracketCalls.length, 3, reason: 're-arms every 30 s');
      });
    });

    test('bracket: healthy joined + flag on → no poll after >60 s', () {
      fakeAsync((async) {
        final remote = _StubTournamentRemote();
        final channel = FakeRealtimeChannel();
        final container =
            makeContainer(remote, channel, realtimeEnabled: true);

        final data = container.listen(tournamentBracketProvider(tid), (_, _) {});
        addTearDown(data.close);
        final sub =
            container.listen(tournamentBracketPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        channel.setState(key, RealtimeChannelState.joined);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 90))
          ..flushMicrotasks();

        expect(remote.bracketCalls.length, 1,
            reason: 'healthy joined → only initial fetch');
      });
    });

    test('pool-standings: flag off → fallback poll at 30 s (no grace)', () {
      fakeAsync((async) {
        final remote = _StubTournamentRemote();
        final channel = FakeRealtimeChannel();
        final container =
            makeContainer(remote, channel, realtimeEnabled: false);

        final data =
            container.listen(tournamentPoolStandingsProvider(tid), (_, _) {});
        addTearDown(data.close);
        final sub = container
            .listen(tournamentPoolStandingsPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(remote.poolCalls.length, 1, reason: 'initial fetch only');

        async
          ..elapse(const Duration(seconds: 29))
          ..flushMicrotasks();
        expect(remote.poolCalls.length, 1, reason: 'nothing before 30 s');

        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(remote.poolCalls.length, 2,
            reason: 'kill-switch off → fallback poll at 30 s, no grace');

        async
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();
        expect(remote.poolCalls.length, 3, reason: 're-arms every 30 s');
      });
    });

    test('pool-standings: healthy joined + flag on → no poll after >60 s', () {
      fakeAsync((async) {
        final remote = _StubTournamentRemote();
        final channel = FakeRealtimeChannel();
        final container =
            makeContainer(remote, channel, realtimeEnabled: true);

        final data =
            container.listen(tournamentPoolStandingsProvider(tid), (_, _) {});
        addTearDown(data.close);
        final sub = container
            .listen(tournamentPoolStandingsPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        channel.setState(key, RealtimeChannelState.joined);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 90))
          ..flushMicrotasks();

        expect(remote.poolCalls.length, 1,
            reason: 'healthy joined → only initial fetch');
      });
    });
  });

  // ---- tournament match-list + match-detail ------------------------------
  group('kill-switch — tournament match-list / match-detail (30 s)', () {
    const tid = TournamentId('t-match');
    const mid = TournamentMatchId('m-1');
    final key = tournamentRealtimeChannelKey(tid);

    ProviderContainer makeContainer(
      _StubTournamentRemote remote,
      FakeRealtimeChannel channel, {
      required bool realtimeEnabled,
    }) {
      final container = ProviderContainer(
        overrides: [
          tournamentRemoteProvider.overrideWithValue(remote),
          realtimeChannelProvider.overrideWithValue(channel),
          realtimeEnabledFlagProvider.overrideWithValue(realtimeEnabled),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('match-list: flag off → fallback poll at 30 s (no grace)', () {
      fakeAsync((async) {
        final remote = _StubTournamentRemote();
        final channel = FakeRealtimeChannel();
        final container =
            makeContainer(remote, channel, realtimeEnabled: false);

        final data =
            container.listen(tournamentMatchListProvider(tid), (_, _) {});
        addTearDown(data.close);
        final sub =
            container.listen(tournamentMatchListPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(remote.listCalls.length, 1, reason: 'initial fetch only');

        async
          ..elapse(const Duration(seconds: 29))
          ..flushMicrotasks();
        expect(remote.listCalls.length, 1, reason: 'nothing before 30 s');

        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(remote.listCalls.length, 2,
            reason: 'kill-switch off → fallback poll at 30 s, no grace');

        async
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();
        expect(remote.listCalls.length, 3, reason: 're-arms every 30 s');
      });
    });

    test('match-list: healthy joined + flag on → no poll after >60 s', () {
      fakeAsync((async) {
        final remote = _StubTournamentRemote();
        final channel = FakeRealtimeChannel();
        final container =
            makeContainer(remote, channel, realtimeEnabled: true);

        final data =
            container.listen(tournamentMatchListProvider(tid), (_, _) {});
        addTearDown(data.close);
        final sub =
            container.listen(tournamentMatchListPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        channel.setState(key, RealtimeChannelState.joined);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 90))
          ..flushMicrotasks();

        expect(remote.listCalls.length, 1,
            reason: 'healthy joined → only initial fetch');
      });
    });

    test('match-detail: flag off → fallback poll at 30 s (no grace)', () {
      fakeAsync((async) {
        final remote = _StubTournamentRemote(
          match: _match(tid, mid, TournamentMatchStatus.scheduled),
        );
        final channel = FakeRealtimeChannel();
        final container =
            makeContainer(remote, channel, realtimeEnabled: false);

        final data =
            container.listen(tournamentMatchDetailProvider(mid), (_, _) {});
        addTearDown(data.close);
        final sub =
            container.listen(tournamentMatchPollingProvider(mid), (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(remote.matchCalls.length, 1, reason: 'initial detail fetch only');

        async
          ..elapse(const Duration(seconds: 29))
          ..flushMicrotasks();
        expect(remote.matchCalls.length, 1, reason: 'nothing before 30 s');

        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(remote.matchCalls.length, 2,
            reason: 'kill-switch off → fallback poll at 30 s, no grace');

        async
          ..elapse(const Duration(seconds: 30))
          ..flushMicrotasks();
        expect(remote.matchCalls.length, 3, reason: 're-arms every 30 s');
      });
    });

    test('match-detail: healthy joined + flag on → no poll after >60 s', () {
      fakeAsync((async) {
        final remote = _StubTournamentRemote(
          match: _match(tid, mid, TournamentMatchStatus.scheduled),
        );
        final channel = FakeRealtimeChannel();
        final container =
            makeContainer(remote, channel, realtimeEnabled: true);

        final data =
            container.listen(tournamentMatchDetailProvider(mid), (_, _) {});
        addTearDown(data.close);
        final sub =
            container.listen(tournamentMatchPollingProvider(mid), (_, _) {});
        addTearDown(sub.close);
        channel.setState(key, RealtimeChannelState.joined);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 90))
          ..flushMicrotasks();

        expect(remote.matchCalls.length, 1,
            reason: 'healthy joined → only initial detail fetch');
      });
    });
  });

  // ---- anon public (publicTournamentPollingProvider, 10 s) ---------------
  group('kill-switch — anon public (publicTournamentPollingProvider, 10 s)', () {
    const tid = TournamentId('t-public');
    final key = tournamentRealtimeChannelKey(tid);

    ProviderContainer makeContainer(
      _StubTournamentRemote remote,
      FakeRealtimeChannel channel, {
      required bool realtimeEnabled,
    }) {
      final container = ProviderContainer(
        overrides: [
          tournamentRemoteProvider.overrideWithValue(remote),
          realtimeChannelProvider.overrideWithValue(channel),
          realtimeEnabledFlagProvider.overrideWithValue(realtimeEnabled),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('flag off → anon fallback poll at 10 s (NOT 30 s, no grace)', () {
      fakeAsync((async) {
        final remote = _StubTournamentRemote();
        final channel = FakeRealtimeChannel();
        final container =
            makeContainer(remote, channel, realtimeEnabled: false);

        final data =
            container.listen(tournamentMatchListProvider(tid), (_, _) {});
        addTearDown(data.close);
        final sub =
            container.listen(publicTournamentPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        async.flushMicrotasks();
        expect(remote.listCalls.length, 1, reason: 'initial fetch only');

        // 9 s into the open gate: nothing yet — anon cadence is 10 s.
        async
          ..elapse(const Duration(seconds: 9))
          ..flushMicrotasks();
        expect(remote.listCalls.length, 1, reason: 'nothing before 10 s');

        async
          ..elapse(const Duration(seconds: 1))
          ..flushMicrotasks();
        expect(remote.listCalls.length, 2,
            reason: 'kill-switch off → anon poll at 10 s, no grace');

        async
          ..elapse(const Duration(seconds: 10))
          ..flushMicrotasks();
        expect(remote.listCalls.length, 3, reason: 're-arms every 10 s');
      });
    });

    test('healthy joined + flag on → no anon poll after >60 s', () {
      fakeAsync((async) {
        final remote = _StubTournamentRemote();
        final channel = FakeRealtimeChannel();
        final container =
            makeContainer(remote, channel, realtimeEnabled: true);

        final data =
            container.listen(tournamentMatchListProvider(tid), (_, _) {});
        addTearDown(data.close);
        final sub =
            container.listen(publicTournamentPollingProvider(tid), (_, _) {});
        addTearDown(sub.close);
        channel.setState(key, RealtimeChannelState.joined);
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 90))
          ..flushMicrotasks();

        expect(remote.listCalls.length, 1,
            reason: 'healthy broadcast channel → only initial fetch');
      });
    });
  });
}

/// Per-tournament match ref helper for the match-detail family.
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

/// Records every refresh call; otherwise inert (the CDC provider only drives
/// refresh — the drift stream is the real, unchanged data source).
class _RecordingInboxRepository implements InboxRepository {
  final List<String> refreshCalls = <String>[];

  @override
  Future<List<InboxMessage>> refreshFromRemote(String userId) async {
    refreshCalls.add(userId);
    return const <InboxMessage>[];
  }

  @override
  Stream<List<InboxMessage>> watchForUser(String userId) =>
      const Stream<List<InboxMessage>>.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records every list fetch; the friends CDC provider drives the invalidation
/// of friendsListProvider, whose re-fetch is the observable proof.
class _RecordingFriendRepository implements FriendRepository {
  int listCalls = 0;

  @override
  Future<List<FriendEntry>> listForCaller() async {
    listCalls++;
    return const <FriendEntry>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts every server fetch the tournament fallback pollers trigger.
class _StubTournamentRemote implements TournamentRemote {
  _StubTournamentRemote({this.match});

  final TournamentMatchRef? match;
  final List<String> bracketCalls = <String>[];
  final List<String> poolCalls = <String>[];
  final List<String> listCalls = <String>[];
  final List<String> matchCalls = <String>[];

  @override
  Future<Bracket> getBracket(TournamentId tournamentId) async {
    bracketCalls.add(tournamentId.value);
    return Bracket.singleElimination(const <String>['p1', 'p2']);
  }

  @override
  Future<List<PoolGroupStandings>> getPoolStandings(
    TournamentId tournamentId,
  ) async {
    poolCalls.add(tournamentId.value);
    return const <PoolGroupStandings>[];
  }

  @override
  Future<List<TournamentMatchRef>> listMatchesForTournament(
    TournamentId id,
  ) async {
    listCalls.add(id.value);
    return const <TournamentMatchRef>[];
  }

  @override
  Future<TournamentMatchRef?> getMatch(TournamentMatchId id) async {
    matchCalls.add(id.value);
    return match;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
