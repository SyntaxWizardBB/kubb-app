import 'package:kubb_domain/src/test_support/fake_broadcast_channel.dart';
import 'package:kubb_domain/src/values/broadcast_message.dart';
import 'package:kubb_domain/src/values/realtime_change.dart';
import 'package:test/test.dart';

BroadcastMessage _msg(String matchId) => BroadcastMessage(
      topic: 'public_tournament_events:t1',
      event: 'match_status',
      payload: {'match_id': matchId, 'status': 'live'},
    );

void main() {
  group('FakeBroadcastChannel', () {
    const topic = 'public_tournament_events:t1';

    test('two subscribers on the same topic both receive every emit',
        () async {
      final fake = FakeBroadcastChannel();
      final a = <String>[];
      final b = <String>[];
      final subA = fake
          .subscribe(topic)
          .listen((m) => a.add(m.payload['match_id']! as String));
      final subB = fake
          .subscribe(topic)
          .listen((m) => b.add(m.payload['match_id']! as String));

      fake
        ..emit(topic, _msg('m-1'))
        ..emit(topic, _msg('m-2'));
      await Future<void>.delayed(Duration.zero);

      expect(a, equals(['m-1', 'm-2']));
      expect(b, equals(['m-1', 'm-2']));
      await subA.cancel();
      await subB.cancel();
      await fake.close(topic);
    });

    test('events on a different topic are not delivered', () async {
      final fake = FakeBroadcastChannel();
      final received = <BroadcastMessage>[];
      final sub = fake.subscribe(topic).listen(received.add);

      fake.emit('public_tournament_events:t2', _msg('m-1'));
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await sub.cancel();
      await fake.close(topic);
    });

    test('setState replays the latest state to a late subscriber', () async {
      final fake = FakeBroadcastChannel()
        ..setState(topic, RealtimeChannelState.connecting)
        ..setState(topic, RealtimeChannelState.joined);

      final seen = <RealtimeChannelState>[];
      final sub = fake.stateStream(topic).listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      fake.setState(topic, RealtimeChannelState.errored);
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

    test('close tears down message and state controllers for the topic',
        () async {
      final fake = FakeBroadcastChannel();
      final messages = fake.subscribe(topic);
      final state = fake.stateStream(topic);

      final done =
          Future.wait([messages.drain<void>(), state.drain<void>()]);
      await fake.close(topic);
      await done; // completes only when both controllers closed
    });
  });
}
