import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

void main() {
  group('LamportClock', () {
    test('tick increments counter', () {
      final clock = LamportClock(deviceId: const DeviceId('dev-a'));
      final t1 = clock.tick();
      final t2 = clock.tick();
      expect(t1.counter, 1);
      expect(t2.counter, 2);
      expect(t1 < t2, isTrue);
    });

    test('observe jumps over remote counter and ticks', () {
      final clock = LamportClock(deviceId: const DeviceId('dev-a'))..tick();
      final after = clock.observe(
        const LamportTimestamp(counter: 10, deviceId: DeviceId('dev-b')),
      );
      expect(after.counter, 11);
    });

    test('observe of older remote still ticks local', () {
      final clock = LamportClock(deviceId: const DeviceId('dev-a'))
        ..tick()
        ..tick();
      final after = clock.observe(
        const LamportTimestamp(counter: 1, deviceId: DeviceId('dev-b')),
      );
      expect(after.counter, 3);
    });

    test('tie-break by device id when counters equal', () {
      const t1 = LamportTimestamp(counter: 5, deviceId: DeviceId('dev-a'));
      const t2 = LamportTimestamp(counter: 5, deviceId: DeviceId('dev-b'));
      expect(t1 < t2, isTrue);
      expect(t2 > t1, isTrue);
    });
  });

  group('OpeningRule', () {
    test('6-6-6 always returns 6 batons', () {
      final rule = OpeningRule.sixSixSix();
      expect(rule.batonsInRound(1), 6);
      expect(rule.batonsInRound(5), 6);
    });

    test('2-4-6 ramps up then stabilises', () {
      final rule = OpeningRule.twoFourSix();
      expect(rule.batonsInRound(1), 2);
      expect(rule.batonsInRound(2), 4);
      expect(rule.batonsInRound(3), 6);
      expect(rule.batonsInRound(99), 6);
    });

    test('minPlayersForRound: 3 players for 3+ batons, 2 for 2 batons', () {
      expect(OpeningRule.sixSixSix().minPlayersForRound(1), 3);
      expect(OpeningRule.threeSixSix().minPlayersForRound(1), 3);
      expect(OpeningRule.twoFourSix().minPlayersForRound(1), 2);
      expect(OpeningRule.twoFourSix().minPlayersForRound(2), 3);
    });
  });

  group('RuleSet.swiss', () {
    test('default opening is 6-6-6 and four openings allowed', () {
      final ruleSet = RuleSet.swiss();
      expect(ruleSet.defaultOpening.code, '6-6-6');
      expect(ruleSet.allowedOpenings, hasLength(4));
      expect(
        ruleSet.isOpeningAllowed(OpeningRule.fourSixSix()),
        isTrue,
      );
    });

    test('version id pins CH 1.11', () {
      final ruleSet = RuleSet.swiss();
      expect(ruleSet.version.id, 'kubb-ch-1.11');
    });
  });
}
