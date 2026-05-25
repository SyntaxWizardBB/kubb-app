import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

List<String> _ids(int n) =>
    List.generate(n, (i) => 'p${i + 1}', growable: false);

Set<int> _pairSeeds(BracketPairing p) => {p.$1.seed, p.$2.seed};

void main() {
  group('Bracket.singleElimination', () {
    test('it throws on empty participants', () {
      expect(
        () => Bracket.singleElimination(const []),
        throwsArgumentError,
      );
    });

    test('it accepts a single participant with no rounds', () {
      final b = Bracket.singleElimination(_ids(1));
      expect(b, isA<SingleEliminationBracket>());
      expect((b as SingleEliminationBracket).rounds, isEmpty);
    });

    test('it pads 5 participants to an 8-slot bracket with 3 byes', () {
      final b = Bracket.singleElimination(_ids(5)) as SingleEliminationBracket;
      final r1 = b.rounds.first;
      expect(r1.pairings, hasLength(4));
      final byeCount = r1.pairings
          .expand<BracketEntry>((p) => [p.$1, p.$2])
          .where((e) => e.isBye)
          .length;
      expect(byeCount, 3);
    });

    test('it produces 3 rounds for 8 participants', () {
      final b = Bracket.singleElimination(_ids(8)) as SingleEliminationBracket;
      expect(b.rounds.map((r) => r.number), [1, 2, 3]);
      expect(b.rounds[0].pairings, hasLength(4));
      expect(b.rounds[1].pairings, hasLength(2));
      expect(b.rounds[2].pairings, hasLength(1));
    });

    test('it produces 4 rounds for 16 participants', () {
      final b = Bracket.singleElimination(_ids(16)) as SingleEliminationBracket;
      expect(b.rounds, hasLength(4));
      expect(b.rounds.last.pairings, hasLength(1));
    });

    test('it produces 4 rounds for 9 participants padded to 16', () {
      final b = Bracket.singleElimination(_ids(9)) as SingleEliminationBracket;
      expect(b.rounds, hasLength(4));
      expect(b.rounds.first.pairings, hasLength(8));
    });

    test('it assigns byes to the top seeds first', () {
      // Pattern-agnostic: byes pair with seeds 1,2,3 (the top three) when
      // there are 3 byes; the remaining pair is between seeds 4 and 5.
      final b = Bracket.singleElimination(_ids(5)) as SingleEliminationBracket;
      final r1 = b.rounds.first;
      final byeOpponentSeeds = <int>{};
      Set<int>? nonByePairSeeds;
      for (final p in r1.pairings) {
        final entries = [p.$1, p.$2];
        final bye = entries.firstWhere((e) => e.isBye, orElse: () => p.$1);
        if (entries.any((e) => e.isBye)) {
          final other = entries.firstWhere((e) => !e.isBye);
          byeOpponentSeeds.add(other.seed);
        } else {
          nonByePairSeeds = {p.$1.seed, p.$2.seed};
        }
        // suppress unused warning when no bye on this pair
        identical(bye, bye);
      }
      expect(byeOpponentSeeds, {1, 2, 3});
      expect(nonByePairSeeds, {4, 5});
    });

    test('it pairs seed 1 against the highest non-bye opponent', () {
      // No byes: 8 participants → seed 1 vs seed 8.
      final b = Bracket.singleElimination(_ids(8)) as SingleEliminationBracket;
      final first = b.rounds.first.pairings.first;
      expect(first.$1.seed, 1);
      expect(first.$2.seed, 8);
      expect(first.$2.isBye, isFalse);
    });

    test('it places later rounds as null-id placeholders', () {
      final b = Bracket.singleElimination(_ids(8)) as SingleEliminationBracket;
      for (final p in b.rounds[1].pairings) {
        expect(p.$1.participantId, isNull);
        expect(p.$2.participantId, isNull);
      }
    });

    test('it is deterministic across multiple generations', () {
      final a = Bracket.singleElimination(const ['a', 'b', 'c', 'd']);
      final c = Bracket.singleElimination(const ['a', 'b', 'c', 'd']);
      expect(a, equals(c));
      expect(a.hashCode, equals(c.hashCode));
    });

    test('it preserves the input order as seed order', () {
      // Pattern-agnostic: the four ids must appear exactly once in round 1,
      // and pair contents match the seed mapping x=1, y=2, z=3, w=4.
      final b = Bracket.singleElimination(const ['x', 'y', 'z', 'w'])
          as SingleEliminationBracket;
      final r1 = b.rounds.first;
      final allIds = r1.pairings
          .expand<BracketEntry>((p) => [p.$1, p.$2])
          .map((e) => e.participantId)
          .toList();
      expect(allIds.toSet(), {'x', 'y', 'z', 'w'});
      // Seed map: x→1, y→2, z→3, w→4.
      final pairAsSeeds =
          r1.pairings.map(_pairSeeds).toSet();
      expect(pairAsSeeds, {
        {1, 4},
        {2, 3},
      });
    });

    group('recursive seeding', () {
      test('it is the default when seedingPattern is omitted', () {
        final defaulted =
            Bracket.singleElimination(_ids(8)) as SingleEliminationBracket;
        final explicit = Bracket.singleElimination(
          _ids(8),
          // explicit value is the point of the test
          // ignore: avoid_redundant_argument_values
          seedingPattern: BracketSeedingPattern.recursive,
        ) as SingleEliminationBracket;
        expect(defaulted, equals(explicit));
      });

      test('it places seed 1 and seed 2 in opposite halves for n=8', () {
        final b =
            Bracket.singleElimination(_ids(8)) as SingleEliminationBracket;
        final r1 = b.rounds.first;
        // Upper half: first 2 pairings; lower half: last 2 pairings.
        final upperSeeds = r1.pairings
            .take(2)
            .expand<int>((p) => [p.$1.seed, p.$2.seed])
            .toSet();
        final lowerSeeds = r1.pairings
            .skip(2)
            .expand<int>((p) => [p.$1.seed, p.$2.seed])
            .toSet();
        expect(upperSeeds.contains(1), isTrue);
        expect(lowerSeeds.contains(2), isTrue);
        expect(upperSeeds.contains(2), isFalse);
        expect(lowerSeeds.contains(1), isFalse);
      });

      test('round-1 pairings for n=8 are 1v8, 4v5, 3v6, 2v7', () {
        final b =
            Bracket.singleElimination(_ids(8)) as SingleEliminationBracket;
        final seeds = b.rounds.first.pairings.map(_pairSeeds).toList();
        expect(seeds, [
          {1, 8},
          {4, 5},
          {3, 6},
          {2, 7},
        ]);
      });

      test('round-1 pairings for n=4 are 1v4, 2v3', () {
        final b =
            Bracket.singleElimination(_ids(4)) as SingleEliminationBracket;
        final seeds = b.rounds.first.pairings.map(_pairSeeds).toList();
        expect(seeds, [
          {1, 4},
          {2, 3},
        ]);
      });

      test('round-1 for n=16 has seed 1 in slot 0 and seed 2 in last pairing',
          () {
        final b =
            Bracket.singleElimination(_ids(16)) as SingleEliminationBracket;
        final pairings = b.rounds.first.pairings;
        expect(pairings.first.$1.seed, 1);
        final last = pairings.last;
        expect({last.$1.seed, last.$2.seed}.contains(2), isTrue);
      });
    });

    group('linear seeding', () {
      test('round-1 pairings for n=8 are 1v8, 2v7, 3v6, 4v5', () {
        final b = Bracket.singleElimination(
          _ids(8),
          seedingPattern: BracketSeedingPattern.linear,
        ) as SingleEliminationBracket;
        final pairs = b.rounds.first.pairings
            .map((p) => (p.$1.seed, p.$2.seed))
            .toList();
        expect(pairs, [(1, 8), (2, 7), (3, 6), (4, 5)]);
      });

      test('it still pairs byes with top seeds for n=5', () {
        final b = Bracket.singleElimination(
          _ids(5),
          seedingPattern: BracketSeedingPattern.linear,
        ) as SingleEliminationBracket;
        final r1 = b.rounds.first;
        expect(r1.pairings[0].$1.seed, 1);
        expect(r1.pairings[0].$2.isBye, isTrue);
        expect(r1.pairings[1].$1.seed, 2);
        expect(r1.pairings[1].$2.isBye, isTrue);
        expect(r1.pairings[2].$1.seed, 3);
        expect(r1.pairings[2].$2.isBye, isTrue);
        expect(r1.pairings[3].$1.seed, 4);
        expect(r1.pairings[3].$2.seed, 5);
      });
    });
  });
}
