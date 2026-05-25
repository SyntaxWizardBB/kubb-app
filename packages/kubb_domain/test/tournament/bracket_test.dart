import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

List<String> _ids(int n) =>
    List.generate(n, (i) => 'p${i + 1}', growable: false);

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
      final b = Bracket.singleElimination(_ids(5)) as SingleEliminationBracket;
      final r1 = b.rounds.first;
      // Pairings are (seed_i, seed_{N+1-i}); 5 ids → byes at seeds 6,7,8.
      // Top three pairings should have the bye on the b side, paired with
      // seeds 1, 2, 3 on the a side.
      expect(r1.pairings[0].$1.seed, 1);
      expect(r1.pairings[0].$2.isBye, isTrue);
      expect(r1.pairings[1].$1.seed, 2);
      expect(r1.pairings[1].$2.isBye, isTrue);
      expect(r1.pairings[2].$1.seed, 3);
      expect(r1.pairings[2].$2.isBye, isTrue);
      expect(r1.pairings[3].$1.seed, 4);
      expect(r1.pairings[3].$2.seed, 5);
      expect(r1.pairings[3].$2.isBye, isFalse);
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
      final b = Bracket.singleElimination(const ['x', 'y', 'z', 'w'])
          as SingleEliminationBracket;
      final r1 = b.rounds.first;
      expect(r1.pairings[0].$1.participantId, 'x');
      expect(r1.pairings[0].$2.participantId, 'w');
      expect(r1.pairings[1].$1.participantId, 'y');
      expect(r1.pairings[1].$2.participantId, 'z');
    });
  });
}
