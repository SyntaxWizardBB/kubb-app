import 'package:kubb_domain/src/ports/realtime_channel.dart';
import 'package:kubb_domain/src/test_support/fake_realtime_channel.dart';
import 'package:test/test.dart';

RealtimeChange _change(String rowId) => RealtimeChange(
  eventType: RealtimeEventType.update,
  table: 'tournament_matches',
  rowId: rowId,
  newRow: {'id': rowId, 'status': 'live'},
  oldRow: {'id': rowId, 'status': 'scheduled'},
  receivedAt: DateTime.utc(2026, 5, 27, 10),
);

void main() {
  group('FakeRealtimeChannel', () {
    test('subscriber receives changes emitted on the matching key', () async {
      final fake = FakeRealtimeChannel();
      final key = fakeRealtimeChannelKey(
        table: 'tournament_matches',
        filterColumn: 'tournament_id',
        filterValue: 't1',
      );
      final received = <RealtimeChange>[];
      final sub = fake
          .subscribe(
            table: 'tournament_matches',
            filterColumn: 'tournament_id',
            filterValue: 't1',
          )
          .listen(received.add);

      fake.emit(key, _change('m-1'));
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.rowId, equals('m-1'));
      await sub.cancel();
      await fake.close(key);
    });

    test('two subscribers on the same key both receive each event', () async {
      final fake = FakeRealtimeChannel();
      final key = fakeRealtimeChannelKey(
        table: 'tournament_matches',
        filterColumn: 'tournament_id',
        filterValue: 't1',
      );
      final a = <String>[];
      final b = <String>[];
      final subA = fake
          .subscribe(
            table: 'tournament_matches',
            filterColumn: 'tournament_id',
            filterValue: 't1',
          )
          .listen((c) => a.add(c.rowId));
      final subB = fake
          .subscribe(
            table: 'tournament_matches',
            filterColumn: 'tournament_id',
            filterValue: 't1',
          )
          .listen((c) => b.add(c.rowId));

      fake
        ..emit(key, _change('m-1'))
        ..emit(key, _change('m-2'));
      await Future<void>.delayed(Duration.zero);

      expect(a, equals(['m-1', 'm-2']));
      expect(b, equals(['m-1', 'm-2']));
      await subA.cancel();
      await subB.cancel();
      await fake.close(key);
    });

    test('events on a different key are not delivered', () async {
      final fake = FakeRealtimeChannel();
      final otherKey = fakeRealtimeChannelKey(
        table: 'tournament_matches',
        filterColumn: 'tournament_id',
        filterValue: 't2',
      );
      final received = <RealtimeChange>[];
      final sub = fake
          .subscribe(
            table: 'tournament_matches',
            filterColumn: 'tournament_id',
            filterValue: 't1',
          )
          .listen(received.add);

      fake.emit(otherKey, _change('m-1'));
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await sub.cancel();
    });

    test('stateStream replays the latest state then forwards transitions',
        () async {
      final fake = FakeRealtimeChannel();
      const key = 'tournament_matches:tournament_id=t1';
      fake
        ..setState(key, RealtimeChannelState.connecting)
        ..setState(key, RealtimeChannelState.joined);

      final seen = <RealtimeChannelState>[];
      final sub = fake.stateStream(key).listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      fake.setState(key, RealtimeChannelState.errored);
      await Future<void>.delayed(Duration.zero);

      expect(
        seen,
        equals([
          RealtimeChannelState.joined,
          RealtimeChannelState.errored,
        ]),
      );
      await sub.cancel();
    });

    test('subscribe drives initial state to joined', () async {
      final fake = FakeRealtimeChannel();
      fake
          .subscribe(
            table: 'tournament_matches',
            filterColumn: 'tournament_id',
            filterValue: 't1',
          )
          .listen((_) {});
      final key = fakeRealtimeChannelKey(
        table: 'tournament_matches',
        filterColumn: 'tournament_id',
        filterValue: 't1',
      );

      final first = await fake.stateStream(key).first;
      expect(first, equals(RealtimeChannelState.joined));
      await fake.close(key);
    });

    test('close tears down change and state streams for the key', () async {
      final fake = FakeRealtimeChannel();
      final key = fakeRealtimeChannelKey(
        table: 'tournament_matches',
        filterColumn: 'tournament_id',
        filterValue: 't1',
      );
      final changes = fake.subscribe(
        table: 'tournament_matches',
        filterColumn: 'tournament_id',
        filterValue: 't1',
      );
      final state = fake.stateStream(key);

      final done = Future.wait([changes.drain<void>(), state.drain<void>()]);
      await fake.close(key);
      await done; // completes only when both controllers closed
    });
  });
}
