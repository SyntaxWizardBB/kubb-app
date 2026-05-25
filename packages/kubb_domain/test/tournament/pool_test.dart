import 'package:kubb_domain/src/tournament/pool.dart';
import 'package:test/test.dart';

List<String> _ids(int n) => List.generate(n, (i) => 'P${i + 1}');

Set<String> _pairKey(PoolPairing p) =>
    {p.participantA, if (p.participantB != null) p.participantB!};

void main() {
  group('Pool.roundRobin', () {
    test('it produces 7 rounds for 8 participants', () {
      final pool = Pool.roundRobin(_ids(8));
      expect(pool.rounds, hasLength(7));
      for (final round in pool.rounds) {
        expect(round.pairings, hasLength(4));
        expect(round.pairings.any((p) => p.isBye), isFalse);
      }
    });

    test('it produces 7 rounds for 7 participants with 1 bye each round', () {
      final pool = Pool.roundRobin(_ids(7));
      expect(pool.rounds, hasLength(7));
      for (final round in pool.rounds) {
        expect(round.pairings, hasLength(4));
        expect(round.pairings.where((p) => p.isBye), hasLength(1));
      }
    });

    test('it produces 5 rounds for 6 participants', () {
      final pool = Pool.roundRobin(_ids(6));
      expect(pool.rounds, hasLength(5));
      for (final round in pool.rounds) {
        expect(round.pairings, hasLength(3));
        expect(round.pairings.any((p) => p.isBye), isFalse);
      }
    });

    test('it produces 5 rounds for 5 participants', () {
      final pool = Pool.roundRobin(_ids(5));
      expect(pool.rounds, hasLength(5));
      for (final round in pool.rounds) {
        expect(round.pairings, hasLength(3));
        expect(round.pairings.where((p) => p.isBye), hasLength(1));
      }
    });

    test('it pairs every participant against every other exactly once for n=8',
        () {
      final pool = Pool.roundRobin(_ids(8));
      final seen = <String>{};
      var count = 0;
      for (final round in pool.rounds) {
        for (final p in round.pairings) {
          final key = (_pairKey(p).toList()..sort()).join('-');
          expect(seen.add(key), isTrue, reason: 'duplicate pairing $key');
          count++;
        }
      }
      expect(count, 8 * 7 ~/ 2);
    });

    test('it gives each odd-count participant exactly one bye for n=7', () {
      final pool = Pool.roundRobin(_ids(7));
      final byeCounts = <String, int>{};
      for (final round in pool.rounds) {
        for (final p in round.pairings) {
          if (p.isBye) {
            byeCounts[p.participantA] = (byeCounts[p.participantA] ?? 0) + 1;
          }
        }
      }
      expect(byeCounts.keys.toSet(), _ids(7).toSet());
      for (final c in byeCounts.values) {
        expect(c, 1);
      }
    });

    test('it never pairs a participant with themselves', () {
      for (final n in [2, 5, 6, 7, 8, 11, 12]) {
        final pool = Pool.roundRobin(_ids(n));
        for (final round in pool.rounds) {
          for (final p in round.pairings) {
            expect(p.participantA == p.participantB, isFalse);
          }
        }
      }
    });

    test('it is deterministic across multiple generations', () {
      final ids = _ids(9);
      final a = Pool.roundRobin(ids);
      final b = Pool.roundRobin(ids);
      expect(a.rounds.length, b.rounds.length);
      for (var r = 0; r < a.rounds.length; r++) {
        final pa = a.rounds[r].pairings;
        final pb = b.rounds[r].pairings;
        expect(pa.length, pb.length);
        for (var i = 0; i < pa.length; i++) {
          expect(pa[i].participantA, pb[i].participantA);
          expect(pa[i].participantB, pb[i].participantB);
        }
      }
    });

    test('it throws on empty participants', () {
      expect(() => Pool.roundRobin(const []), throwsArgumentError);
    });

    test('it returns 0 rounds for a single participant', () {
      final pool = Pool.roundRobin(const ['solo']);
      expect(pool.rounds, isEmpty);
      expect(pool.participantCount, 1);
    });

    test('it returns 1 round with 1 pairing for n=2', () {
      final pool = Pool.roundRobin(const ['a', 'b']);
      expect(pool.rounds, hasLength(1));
      expect(pool.rounds.single.pairings, hasLength(1));
      final only = pool.rounds.single.pairings.single;
      expect({only.participantA, only.participantB}, {'a', 'b'});
    });

    test('it covers every pair exactly once for odd n=7 (ignoring byes)', () {
      final pool = Pool.roundRobin(_ids(7));
      final seen = <String>{};
      for (final round in pool.rounds) {
        for (final p in round.pairings) {
          if (p.isBye) continue;
          final key = (_pairKey(p).toList()..sort()).join('-');
          expect(seen.add(key), isTrue);
        }
      }
      expect(seen, hasLength(7 * 6 ~/ 2));
    });
  });
}
