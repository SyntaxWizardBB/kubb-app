import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/core/data/realtime/supabase_realtime_channel.dart';
import 'package:kubb_domain/kubb_domain.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// Smoke-tests for the `SupabaseRealtimeChannel` T4 adapter. Three pure
/// adapter behaviours — reference-counted channel sharing (R-M4.1-2),
/// 500 ms close-debounce (R-M4.1-2 mitigation) and exponential reconnect
/// backoff `1/2/4/8/30 s` on `errored` (ADR-0021) — are pinned down here
/// without a real Supabase backend. All timing runs through [FakeAsync].
void main() {
  const table = 'tournament_matches';
  const filterColumn = 'tournament_id';
  const filterValue = 't1';
  const key = '$table:$filterColumn=$filterValue';
  const debounce = Duration(milliseconds: 500);
  const backoff = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 30),
  ];

  SupabaseRealtimeChannel build() => SupabaseRealtimeChannel(
        _MockSupabaseClient(),
        closeDebounce: debounce,
        backoffSchedule: backoff,
      );

  void subscribe(SupabaseRealtimeChannel adapter) => adapter
      .subscribe(
        table: table,
        filterColumn: filterColumn,
        filterValue: filterValue,
      )
      .listen((_) {});

  group('reference-counter', () {
    test('two subscribes share one underlying channel', () {
      final adapter = build();
      subscribe(adapter);
      subscribe(adapter);
      expect(adapter.referenceCount(key), equals(2));
    });

    test('close keeps channel open while a subscriber remains', () {
      FakeAsync().run((async) {
        final adapter = build();
        subscribe(adapter);
        subscribe(adapter);
        adapter.close(key);
        async.elapse(const Duration(seconds: 2));
        expect(adapter.referenceCount(key), equals(1));
        expect(adapter.hasChannel(key), isTrue);
      });
    });
  });

  group('close-debounce', () {
    test('500 ms after counter hits zero the channel is torn down', () {
      FakeAsync().run((async) {
        final adapter = build();
        subscribe(adapter);
        adapter.close(key);
        async.elapse(const Duration(milliseconds: 499));
        expect(adapter.hasChannel(key), isTrue);
        async.elapse(const Duration(milliseconds: 1));
        expect(adapter.hasChannel(key), isFalse);
      });
    });

    test('resubscribe within the debounce window cancels the pending close',
        () {
      FakeAsync().run((async) {
        final adapter = build();
        subscribe(adapter);
        adapter.close(key);
        async.elapse(const Duration(milliseconds: 200));
        subscribe(adapter);
        async.elapse(const Duration(seconds: 1));
        expect(adapter.referenceCount(key), equals(1));
        expect(adapter.hasChannel(key), isTrue);
      });
    });
  });

  group('reconnect-backoff', () {
    test('errored reconnects on 1/2/4/8 s then clamps to 30 s steady', () {
      FakeAsync().run((async) {
        final adapter = build();
        subscribe(adapter);
        for (final wait in backoff) {
          adapter.debugTransitionTo(key, RealtimeChannelState.errored);
          async.elapse(wait);
        }
        expect(adapter.reconnectAttempts(key), equals(backoff.length));
      });
    });

    test('successful join resets the backoff back to 1 s', () {
      FakeAsync().run((async) {
        final adapter = build();
        subscribe(adapter);
        adapter.debugTransitionTo(key, RealtimeChannelState.errored);
        async.elapse(const Duration(seconds: 1));
        adapter.debugTransitionTo(key, RealtimeChannelState.joined);
        adapter.debugTransitionTo(key, RealtimeChannelState.errored);
        async.elapse(const Duration(milliseconds: 999));
        expect(adapter.reconnectAttempts(key), equals(1));
        async.elapse(const Duration(milliseconds: 1));
        expect(adapter.reconnectAttempts(key), equals(2));
      });
    });
  });
}
