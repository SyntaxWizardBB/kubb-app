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
  });
}
