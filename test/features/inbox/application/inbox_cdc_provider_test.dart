import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/auth/application/auth_providers.dart';
import 'package:kubb_app/features/inbox/application/inbox_controller.dart';
import 'package:kubb_app/features/inbox/data/inbox_message.dart';
import 'package:kubb_app/features/inbox/data/inbox_repository.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

/// Tests for the inbox CDC discovery provider (ADR-0029 §(e) C1-T1).
///
/// The provider replaces the old 1 s `inboxPollingProvider`: it subscribes
/// to the single per-user CDC channel via the App-singleton realtime adapter
/// (here a [FakeRealtimeChannel]) and fires a background `refreshFromRemote`
/// on every change. Polling is only a gated failure-mode (30 s cadence).
void main() {
  const userId = 'user-cdc-1';
  // Channel-key derived exclusively via the kubb_domain builder.
  final channelKey = inboxRealtimeChannelKey(const UserId(userId));

  RealtimeChange insertEvent() => RealtimeChange(
        eventType: RealtimeEventType.insert,
        table: 'user_inbox_messages',
        rowId: 'msg-1',
        newRow: const <String, Object?>{'user_id': userId},
        oldRow: const <String, Object?>{},
        receivedAt: DateTime.utc(2026),
      );

  ProviderContainer makeContainer(
    FakeRealtimeChannel channel,
    _RecordingInboxRepository repo, {
    String? signedInAs = userId,
  }) {
    final container = ProviderContainer(
      overrides: [
        currentUserIdProvider.overrideWithValue(signedInAs),
        realtimeChannelProvider.overrideWithValue(channel),
        inboxRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('(a) a CDC event triggers refreshFromRemote', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingInboxRepository();
      final container = makeContainer(channel, repo);

      // Keep the autoDispose provider alive.
      final sub = container.listen<AsyncValue<void>>(
        inboxCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      async.flushMicrotasks();

      expect(repo.refreshCalls, isEmpty, reason: 'no refresh before any event');

      channel.emit(channelKey, insertEvent());
      async.flushMicrotasks();

      expect(repo.refreshCalls, [userId],
          reason: 'one CDC event → one refreshFromRemote(userId)');

      channel.emit(channelKey, insertEvent());
      async.flushMicrotasks();
      expect(repo.refreshCalls.length, 2,
          reason: 'each subsequent event refreshes again');
    });
  });

  test('(b) no 1 s timer runs — idle time triggers no refresh', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingInboxRepository();
      final container = makeContainer(channel, repo);

      final sub = container.listen<AsyncValue<void>>(
        inboxCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      async
        ..flushMicrotasks()
        // Channel is joined (fake contract on subscribe) → fallback off.
        // Let plenty of "seconds" pass: the old poller fired ~10 times here.
        ..elapse(const Duration(seconds: 10));

      expect(repo.refreshCalls, isEmpty,
          reason: 'healthy channel → no periodic discovery refresh');
    });
  });

  test('(c) fallback active → a 30 s refresh runs (not 1 s, not 10 s)', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingInboxRepository();
      final container = makeContainer(channel, repo);

      final sub = container.listen<AsyncValue<void>>(
        inboxCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      async.flushMicrotasks();

      // Drive the channel errored long enough for the 60 s grace gate to
      // flip realtimePollingFallbackProvider to true.
      channel.setState(channelKey, RealtimeChannelState.errored);
      async
        ..elapse(const Duration(seconds: 60))
        ..flushMicrotasks()
        // No refresh in the first 29 s after the gate opened — proves the
        // cadence is not 1 s and not 10 s.
        ..elapse(const Duration(seconds: 29));
      expect(repo.refreshCalls, isEmpty,
          reason: 'fallback cadence is 30 s, nothing fires before that');

      async.elapse(const Duration(seconds: 1));
      expect(repo.refreshCalls, [userId],
          reason: 'first fallback refresh at 30 s');

      async.elapse(const Duration(seconds: 30));
      expect(repo.refreshCalls.length, 2,
          reason: 'fallback re-arms every 30 s');
    });
  });

  test('signed out → no subscription and no refresh', () {
    fakeAsync((async) {
      final channel = FakeRealtimeChannel();
      final repo = _RecordingInboxRepository();
      final container = makeContainer(channel, repo, signedInAs: null);

      final sub = container.listen<AsyncValue<void>>(
        inboxCdcProvider,
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      async.elapse(const Duration(seconds: 90));

      expect(repo.refreshCalls, isEmpty);
    });
  });
}

/// Test double that records every `refreshFromRemote` call and otherwise
/// behaves inertly — the CDC provider only drives refresh, the drift stream
/// (unchanged) is the real data source for UI/badge.
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
