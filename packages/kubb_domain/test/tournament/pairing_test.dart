import 'package:kubb_domain/src/tournament/pairing.dart';
import 'package:kubb_domain/src/tournament/pool.dart';
import 'package:test/test.dart';

List<String> _ids(int n) => List.generate(n, (i) => 'P${i + 1}');

void main() {
  group('RoundRobinStrategy', () {
    const strategy = RoundRobinStrategy();

    test('it produces 7 rounds for 8 participants', () {
      final rounds = strategy.plan(_ids(8));
      expect(rounds, hasLength(7));
      for (final r in rounds) {
        expect(r.pairings, hasLength(4));
        expect(r.pairings.any((p) => p.isBye), isFalse);
      }
    });

    test('it produces N rounds for N (odd) participants with bye', () {
      final rounds = strategy.plan(_ids(7));
      expect(rounds, hasLength(7));
      for (final r in rounds) {
        expect(r.pairings, hasLength(4));
        expect(r.pairings.where((p) => p.isBye), hasLength(1));
      }
    });

    test('it numbers rounds 1-indexed', () {
      final rounds = strategy.plan(_ids(6));
      expect(rounds.map((r) => r.roundNumber).toList(), [1, 2, 3, 4, 5]);
    });

    test('it mirrors Pool.roundRobin pairings 1:1', () {
      final ids = _ids(9);
      final planned = strategy.plan(ids);
      final pool = Pool.roundRobin(ids);
      expect(planned.length, pool.rounds.length);
      for (var i = 0; i < planned.length; i++) {
        final pp = planned[i].pairings;
        final rp = pool.rounds[i].pairings;
        expect(pp.length, rp.length);
        for (var j = 0; j < pp.length; j++) {
          expect(pp[j].participantA, rp[j].participantA);
          expect(pp[j].participantB, rp[j].participantB);
        }
      }
    });

    test('it reports kind as roundRobin', () {
      expect(strategy.kind, PairingStrategyKind.roundRobin);
    });

    test('it throws on empty participants', () {
      expect(() => strategy.plan(const []), throwsArgumentError);
    });

    test('it preserves participant order for n=2', () {
      final rounds = strategy.plan(const ['a', 'b']);
      expect(rounds, hasLength(1));
      final only = rounds.single.pairings.single;
      expect(only.participantA, 'a');
      expect(only.participantB, 'b');
      expect(rounds.single.roundNumber, 1);
    });

    test('it returns 0 planned rounds for a single participant', () {
      expect(strategy.plan(const ['solo']), isEmpty);
    });
  });

  group('PlannedPairing', () {
    test('it is equal when fields match', () {
      const a = PlannedPairing(participantA: 'x', participantB: 'y');
      const b = PlannedPairing(participantA: 'x', participantB: 'y');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('it is unequal when participants differ', () {
      const a = PlannedPairing(participantA: 'x', participantB: 'y');
      const b = PlannedPairing(participantA: 'x', participantB: 'z');
      expect(a, isNot(equals(b)));
    });

    test('it marks bye when participantB is null', () {
      const p = PlannedPairing(participantA: 'x');
      expect(p.isBye, isTrue);
    });
  });

  group('PlannedRound', () {
    test('it is equal when fields match', () {
      const a = PlannedRound(
        roundNumber: 1,
        pairings: [PlannedPairing(participantA: 'x', participantB: 'y')],
      );
      const b = PlannedRound(
        roundNumber: 1,
        pairings: [PlannedPairing(participantA: 'x', participantB: 'y')],
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('it is unequal when roundNumber differs', () {
      const a = PlannedRound(
        roundNumber: 1,
        pairings: [PlannedPairing(participantA: 'x', participantB: 'y')],
      );
      const b = PlannedRound(
        roundNumber: 2,
        pairings: [PlannedPairing(participantA: 'x', participantB: 'y')],
      );
      expect(a, isNot(equals(b)));
    });
  });
}
