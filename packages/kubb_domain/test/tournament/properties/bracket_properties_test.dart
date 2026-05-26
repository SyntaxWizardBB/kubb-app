import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

import '../../_support/tournament_generators.dart';

int _expectedRoundCount(int n) {
  if (n <= 1) return 0;
  var size = 1;
  while (size < n) {
    size *= 2;
  }
  var rounds = 0;
  for (var x = size; x > 1; x ~/= 2) {
    rounds++;
  }
  return rounds;
}

int _nextPow2(int n) {
  var size = 1;
  while (size < n) {
    size *= 2;
  }
  return size;
}

void main() {
  group('Bracket.singleElimination properties', () {
    Glados<List<String>>(any.participantIds(min: 1))
        .test('is deterministic for the same participant list', (ids) {
      final a = Bracket.singleElimination(ids) as SingleEliminationBracket;
      final b = Bracket.singleElimination(ids) as SingleEliminationBracket;
      expect(a, equals(b));
    });

    Glados<List<String>>(any.participantIds())
        .test('round count equals log2 of next power of two', (ids) {
      final bracket =
          Bracket.singleElimination(ids) as SingleEliminationBracket;
      expect(bracket.rounds, hasLength(_expectedRoundCount(ids.length)));
    });

    Glados<List<String>>(any.participantIds()).test(
        'every non-bye participant appears at most once in round one', (ids) {
      final bracket =
          Bracket.singleElimination(ids) as SingleEliminationBracket;
      final seen = <String>{};
      for (final pairing in bracket.rounds.first.pairings) {
        for (final entry in [pairing.$1, pairing.$2]) {
          if (entry.isBye) continue;
          final id = entry.participantId;
          if (id == null) continue;
          expect(seen.add(id), isTrue, reason: 'duplicate $id in round 1');
        }
      }
    });

    Glados<List<String>>(any.participantIds(max: 64))
        .test('is structurally equal across two independent calls (n∈[2,64])',
            (ids) {
      final a = Bracket.singleElimination(ids);
      final b = Bracket.singleElimination(ids);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    Glados<List<String>>(any.participantIdsNonPow2()).test(
        'non-pow2 input pads with BYEs against the top seeds in round 1',
        (ids) {
      final n = ids.length;
      final size = _nextPow2(n);
      final expectedByes = size - n;
      final bracket =
          Bracket.singleElimination(ids) as SingleEliminationBracket;
      final r1Entries = bracket.rounds.first.pairings
          .expand<BracketEntry>((p) => [p.$1, p.$2])
          .toList();
      final byes = r1Entries.where((e) => e.isBye).toList();
      expect(byes, hasLength(expectedByes));
      // Each BYE's opponent must be a top seed 1..expectedByes (FR-FMT-11).
      final byeOpponents = bracket.rounds.first.pairings
          .where((p) => p.$1.isBye || p.$2.isBye)
          .map((p) => p.$1.isBye ? p.$2.seed : p.$1.seed)
          .toSet();
      expect(byeOpponents,
          equals({for (var s = 1; s <= expectedByes; s++) s}));
      // BYEs only in round 1.
      for (final r in bracket.rounds.skip(1)) {
        final laterByes = r.pairings
            .expand<BracketEntry>((p) => [p.$1, p.$2])
            .where((e) => e.isBye);
        expect(laterByes, isEmpty,
            reason: 'BYE found in round ${r.number}');
      }
    });
  });

  group('Bracket third-place playoff', () {
    test('8 ids withThirdPlace=true adds a thirdPlace round with one pairing',
        () {
      final ids = List<String>.generate(8, (i) => 'p$i', growable: false);
      final bracket = Bracket.singleElimination(ids, withThirdPlace: true)
          as SingleEliminationBracket;
      final thirdPlaceRounds = bracket.rounds
          .where((r) => r.phase == BracketPhase.thirdPlace)
          .toList();
      expect(thirdPlaceRounds, hasLength(1));
      expect(thirdPlaceRounds.single.pairings, hasLength(1));
    });

    test('withThirdPlace=false yields no thirdPlace-phase round', () {
      final ids = List<String>.generate(8, (i) => 'p$i', growable: false);
      final bracket = Bracket.singleElimination(ids) as SingleEliminationBracket;
      expect(
        bracket.rounds.where((r) => r.phase == BracketPhase.thirdPlace),
        isEmpty,
      );
    });
  });

  group('Bracket.fill semifinal → final + third-place', () {
    test('fills the final with semi winners and bronze with semi losers', () {
      final ids = List<String>.generate(4, (i) => 'p${i + 1}', growable: false);
      final base = Bracket.singleElimination(ids, withThirdPlace: true)
          as SingleEliminationBracket;
      // Semis live in round 1 for n=4 (no BYEs); identify the four ids.
      final semi1 = base.rounds.first.pairings[0];
      final semi2 = base.rounds.first.pairings[1];
      final winnerA = semi1.$1.participantId!;
      final loserA = semi1.$2.participantId!;
      final winnerB = semi2.$1.participantId!;
      final loserB = semi2.$2.participantId!;
      final filled = base
          .fill(round: 2, position: 1, participantId: winnerA)
          .fill(round: 2, position: 2, participantId: winnerB);
      final finalRound = (filled as SingleEliminationBracket)
          .rounds
          .firstWhere((r) =>
              r.phase == BracketPhase.finals ||
              (r.phase == BracketPhase.winners && r.number == 2));
      final finalPair = finalRound.pairings.single;
      expect(
        {finalPair.$1.participantId, finalPair.$2.participantId},
        equals({winnerA, winnerB}),
      );
      final bronzeRound = filled.rounds
          .firstWhere((r) => r.phase == BracketPhase.thirdPlace);
      final bronzePair = bronzeRound.pairings.single;
      expect(
        {bronzePair.$1.participantId, bronzePair.$2.participantId},
        equals({loserA, loserB}),
      );
    });
  });
}
