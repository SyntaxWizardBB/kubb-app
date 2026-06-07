import 'package:kubb_domain/src/values/broadcast_message.dart';
import 'package:test/test.dart';

void main() {
  group('BroadcastMessage', () {
    test('equality and hashCode for equal field values incl. payload map', () {
      const a = BroadcastMessage(
        topic: 'public_tournament_events:t1',
        event: 'match_status',
        payload: {'match_id': 'm1', 'status': 'live'},
      );
      const b = BroadcastMessage(
        topic: 'public_tournament_events:t1',
        event: 'match_status',
        payload: {'match_id': 'm1', 'status': 'live'},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('payload map order does not affect equality', () {
      const a = BroadcastMessage(
        topic: 't',
        event: 'e',
        payload: {'a': 1, 'b': 2},
      );
      const b = BroadcastMessage(
        topic: 't',
        event: 'e',
        payload: {'b': 2, 'a': 1},
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality on differing topic', () {
      const a = BroadcastMessage(topic: 't1', event: 'e', payload: {});
      const b = BroadcastMessage(topic: 't2', event: 'e', payload: {});
      expect(a, isNot(equals(b)));
    });

    test('inequality on differing event', () {
      const a = BroadcastMessage(topic: 't', event: 'e1', payload: {});
      const b = BroadcastMessage(topic: 't', event: 'e2', payload: {});
      expect(a, isNot(equals(b)));
    });

    test('inequality on differing payload value', () {
      const a = BroadcastMessage(topic: 't', event: 'e', payload: {'k': 1});
      const b = BroadcastMessage(topic: 't', event: 'e', payload: {'k': 2});
      expect(a, isNot(equals(b)));
    });

    test('is immutable — fields are final and ctor is const', () {
      const msg = BroadcastMessage(topic: 't', event: 'e', payload: {'k': 'v'});
      // Reassignment of a field would not compile; assert the const ctor
      // produces a canonicalised instance to document immutability.
      const same = BroadcastMessage(topic: 't', event: 'e', payload: {'k': 'v'});
      expect(identical(msg, same), isTrue);
    });
  });
}
