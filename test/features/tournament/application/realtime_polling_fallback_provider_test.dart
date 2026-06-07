import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_domain/kubb_domain.dart' hide tournamentRealtimeChannelKey;
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

/// Boolean-gate tests for the generalised `realtimePollingFallbackProvider`
/// (ADR-0029 §(c) FC-6) plus the legacy `realtimeFallbackProvider` delegator.
///
/// The gate watches `stateStream(channelKey)` of the App-singleton realtime
/// adapter (here a [FakeRealtimeChannel]). All timing — including the 60 s
/// errored-grace — runs through `fakeAsync`.
void main() {
  const tid = TournamentId('t-fallback');
  // Channel-key built exclusively via the kubb_domain builder.
  final key = tournamentRealtimeChannelKey(tid);

  ProviderContainer makeContainer(
    FakeRealtimeChannel channel, {
    bool realtimeEnabled = true,
  }) {
    final container = ProviderContainer(
      overrides: [
        realtimeChannelProvider.overrideWithValue(channel),
        realtimeEnabledFlagProvider.overrideWithValue(realtimeEnabled),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('realtimePollingFallbackProvider (generalised gate)', () {
    test(
        'joined → false; errored+59 s → false; +1 s → true; '
        'reconnect/joined → cancel + false', () {
      fakeAsync((async) {
        final channel = FakeRealtimeChannel();
        final container = makeContainer(channel);
        final emitted = <bool>[];

        // Subscribe primes the channel-key to `joined` (fake contract).
        container
          ..read(realtimePollingFallbackProvider(key))
          ..listen<AsyncValue<bool>>(
            realtimePollingFallbackProvider(key),
            (previous, next) => next.whenData(emitted.add),
            fireImmediately: true,
          );
        // Prime the underlying channel into `joined`.
        channel
          ..subscribe(
            table: 'tournament_matches',
            filterColumn: 'tournament_id',
            filterValue: tid.value,
          )
          ..setState(key, RealtimeChannelState.joined);
        async.flushMicrotasks();
        expect(emitted.last, isFalse, reason: 'joined → false');

        // Errored, but still inside the 60 s grace window.
        channel.setState(key, RealtimeChannelState.errored);
        async.elapse(const Duration(seconds: 59));
        expect(emitted.last, isFalse, reason: 'errored+59 s → still false');

        // Cross the 60 s boundary → flip to polling.
        async.elapse(const Duration(seconds: 1));
        expect(emitted.last, isTrue, reason: 'errored ≥60 s → true');

        // Reconnect → cancel the flip and report healthy again.
        channel.setState(key, RealtimeChannelState.joined);
        async.flushMicrotasks();
        expect(emitted.last, isFalse, reason: 'reconnect/joined → false');
      });
    });

    test('errored then joined inside grace never flips to true', () {
      fakeAsync((async) {
        final channel = FakeRealtimeChannel();
        final container = makeContainer(channel);
        final emitted = <bool>[];

        container.listen<AsyncValue<bool>>(
          realtimePollingFallbackProvider(key),
          (previous, next) => next.whenData(emitted.add),
          fireImmediately: true,
        );
        channel
          ..subscribe(
            table: 'tournament_matches',
            filterColumn: 'tournament_id',
            filterValue: tid.value,
          )
          ..setState(key, RealtimeChannelState.joined);
        async.flushMicrotasks();

        channel.setState(key, RealtimeChannelState.errored);
        async.elapse(const Duration(seconds: 30));
        channel.setState(key, RealtimeChannelState.joined);
        async.elapse(const Duration(seconds: 60));
        expect(emitted, everyElement(isFalse));
      });
    });

    test('realtimeEnabledFlagProvider off → always true', () {
      fakeAsync((async) {
        final channel = FakeRealtimeChannel();
        final container = makeContainer(channel, realtimeEnabled: false);
        final emitted = <bool>[];

        container.listen<AsyncValue<bool>>(
          realtimePollingFallbackProvider(key),
          (previous, next) => next.whenData(emitted.add),
          fireImmediately: true,
        );
        async.flushMicrotasks();
        expect(emitted.last, isTrue, reason: 'flag off → true');
      });
    });
  });

  group('realtimeFallbackProvider (legacy TournamentId delegator)', () {
    test('identical false/true sequence for one TournamentId', () {
      fakeAsync((async) {
        final channel = FakeRealtimeChannel();
        final container = makeContainer(channel);
        final emitted = <bool>[];

        container
          ..read(realtimeFallbackProvider(tid))
          ..listen<AsyncValue<bool>>(
            realtimeFallbackProvider(tid),
            (previous, next) => next.whenData(emitted.add),
            fireImmediately: true,
          );
        channel
          ..subscribe(
            table: 'tournament_matches',
            filterColumn: 'tournament_id',
            filterValue: tid.value,
          )
          ..setState(key, RealtimeChannelState.joined);
        async.flushMicrotasks();
        expect(emitted.last, isFalse);

        channel.setState(key, RealtimeChannelState.errored);
        async.elapse(const Duration(seconds: 59));
        expect(emitted.last, isFalse);

        async.elapse(const Duration(seconds: 1));
        expect(emitted.last, isTrue);

        channel.setState(key, RealtimeChannelState.joined);
        async.flushMicrotasks();
        expect(emitted.last, isFalse);
      });
    });

    test('flag off → true (delegator parity)', () {
      fakeAsync((async) {
        final channel = FakeRealtimeChannel();
        final container = makeContainer(channel, realtimeEnabled: false);
        final emitted = <bool>[];

        container.listen<AsyncValue<bool>>(
          realtimeFallbackProvider(tid),
          (previous, next) => next.whenData(emitted.add),
          fireImmediately: true,
        );
        async.flushMicrotasks();
        expect(emitted.last, isTrue);
      });
    });
  });
}
