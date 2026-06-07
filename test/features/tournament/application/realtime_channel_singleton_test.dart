// FC-7 (ADR-0029 §(c)): proves the CDC transport is an app-wide singleton.
// `realtimeChannelProvider` is a plain `Provider<RealtimeChannel>` (no
// family, no autoDispose); two reads — and two different consumers that each
// `ref.watch` it — must resolve to the `identical()` adapter so every CDC
// subscription multiplexes one WebSocket.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/application/realtime_fallback_provider.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';

/// Second, independent consumer of the singleton — stands in for any other
/// CDC feed (Lamport binder, future repositories) that also watches it.
final _secondConsumerProvider = Provider<RealtimeChannel>(
  (ref) => ref.watch(realtimeChannelProvider),
);

void main() {
  test('realtimeChannelProvider is a non-family, non-autoDispose Provider', () {
    // A `Provider` (not `Provider.family` / `.autoDispose`) caches one value
    // per container — the precondition for a singleton adapter.
    expect(realtimeChannelProvider, isA<Provider<RealtimeChannel>>());
  });

  test('default body fails (UnimplementedError) until overridden', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    // Riverpod re-throws the provider body error wrapped in a
    // ProviderException; assert the original UnimplementedError surfaces.
    expect(
      () => container.read(realtimeChannelProvider),
      throwsA(
        predicate<Object>(
          (e) => e.toString().contains('UnimplementedError'),
          'wraps the bootstrap UnimplementedError',
        ),
      ),
    );
  });

  test('two reads return the identical() adapter when overridden', () {
    final fake = FakeRealtimeChannel();
    final container = ProviderContainer(
      overrides: [realtimeChannelProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    final a = container.read(realtimeChannelProvider);
    final b = container.read(realtimeChannelProvider);
    expect(identical(a, b), isTrue);
    expect(identical(a, fake), isTrue);
  });

  test('two different consumers share the identical() adapter', () {
    final fake = FakeRealtimeChannel();
    final container = ProviderContainer(
      overrides: [realtimeChannelProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);

    final direct = container.read(realtimeChannelProvider);
    final viaConsumer = container.read(_secondConsumerProvider);
    expect(identical(direct, viaConsumer), isTrue,
        reason: 'consumers must multiplex one CDC adapter (one WebSocket)');
  });
}
