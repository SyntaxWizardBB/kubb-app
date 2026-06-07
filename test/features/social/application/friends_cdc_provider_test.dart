import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/social/application/social_providers.dart';
import 'package:kubb_app/features/social/data/friend_models.dart';
import 'package:kubb_app/features/social/data/friend_repository.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

/// Tests for the friends CDC discovery provider (ADR-0029 §9 SRV-05 / C2-T2).
///
/// The provider replaces the old 1 s `friendsPollingProvider`: it subscribes
/// to the per-user CDC channel `friend_edges:owner_user_id=<uid>` via the
/// App-singleton realtime adapter (here a [FakeRealtimeChannel]) and invalidates
/// [friendsListProvider] on every change. Polling is only a gated failure-mode
/// (30 s cadence).
void main() {
  const userId = 'user-friends-1';
  // Channel-key derived exclusively via the kubb_domain builder.
  final channelKey = friendsRealtimeChannelKey(const UserId(userId));

  RealtimeChange insertEvent() => RealtimeChange(
        eventType: RealtimeEventType.insert,
        table: 'friend_edges',
        rowId: '$userId/friend-1',
        newRow: const <String, Object?>{'owner_user_id': userId},
        oldRow: const <String, Object?>{},
        receivedAt: DateTime.utc(2026),
      );

  ProviderContainer makeContainer(
    FakeRealtimeChannel channel,
    _RecordingFriendRepository repo, {
    String? signedInAs = userId,
  }) {
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(signedInAs),
        isAuthenticatedProvider.overrideWithValue(signedInAs != null),
        realtimeChannelProvider.overrideWithValue(channel),
        friendRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('(a) a friend_edges CDC event invalidates friendsListProvider', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingFriendRepository();
      final container = makeContainer(channel, repo);

      // Keep both providers alive: the CDC provider drives the invalidation,
      // friendsListProvider is the data source whose re-fetch we observe.
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

      expect(repo.listCalls, 1, reason: 'initial list fetch on first watch');

      channel.emit(channelKey, insertEvent());
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(repo.listCalls, 2,
          reason: 'one CDC event → friendsListProvider invalidated + re-fetch');

      channel.emit(channelKey, insertEvent());
      async
        ..elapse(Duration.zero)
        ..flushMicrotasks();
      expect(repo.listCalls, 3,
          reason: 'each subsequent event invalidates again');
    });
  });

  test('(b) no 1 s timer runs — idle time triggers no invalidation', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingFriendRepository();
      final container = makeContainer(channel, repo);

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
      async
        ..flushMicrotasks()
        // Channel is joined (fake contract on subscribe) → fallback off.
        // Let plenty of "seconds" pass: the old poller fired ~10 times here.
        ..elapse(const Duration(seconds: 10));

      expect(repo.listCalls, 1,
          reason: 'healthy channel → no periodic discovery refresh');
    });
  });

  test('(c) fallback active → a 30 s invalidation runs (not 1 s, not 10 s)', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingFriendRepository();
      final container = makeContainer(channel, repo);

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
      expect(repo.listCalls, 1, reason: 'initial fetch');

      // Drive the channel errored long enough for the 60 s grace gate to
      // flip realtimePollingFallbackProvider to true.
      channel.setState(channelKey, RealtimeChannelState.errored);
      async
        ..elapse(const Duration(seconds: 60))
        ..flushMicrotasks()
        // No invalidation in the first 29 s after the gate opened — proves the
        // cadence is not 1 s and not 10 s.
        ..elapse(const Duration(seconds: 29));
      expect(repo.listCalls, 1,
          reason: 'fallback cadence is 30 s, nothing fires before that');

      async
        ..elapse(const Duration(seconds: 1))
        ..flushMicrotasks();
      expect(repo.listCalls, 2, reason: 'first fallback invalidation at 30 s');

      async
        ..elapse(const Duration(seconds: 30))
        ..flushMicrotasks();
      expect(repo.listCalls, 3, reason: 'fallback re-arms every 30 s');
    });
  });

  test('signed out → no subscription and no invalidation', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingFriendRepository();
      final container = makeContainer(channel, repo, signedInAs: null);

      final cdcSub = container.listen<AsyncValue<void>>(
        friendsCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(cdcSub.close);
      // Signed out: friendsListProvider returns the empty list without hitting
      // the repo, so listForCaller must never be invoked.
      final listSub = container.listen<AsyncValue<List<FriendEntry>>>(
        friendsListProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(listSub.close);
      async
        ..flushMicrotasks()
        ..elapse(const Duration(seconds: 90));

      expect(repo.listCalls, 0,
          reason: 'signed out → no list fetch, no fallback poll');
    });
  });
}

/// Test double recording every `listForCaller` call. The CDC provider only
/// drives invalidation; friendsListProvider's re-fetch is the observable proof.
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
