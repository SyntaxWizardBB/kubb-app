// M2a / WIRE-1: the propose RPC payload must map the set winner as
// 'A' | 'B' | 'none' (no 2-way ternary), so a non-decisive group set
// travels as 'none' instead of being forced to 'B'.
import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

void main() {
  group('TournamentRepository.setScoreToWireForTest', () {
    test('SetWinner.none -> winner "none"', () {
      final wire = TournamentRepository.setScoreToWireForTest(
        1,
        SetScore(
          basekubbsKnockedByA: 3,
          basekubbsKnockedByB: 3,
          winner: SetWinner.none,
        ),
      );
      expect(wire['winner'], 'none');
      expect(wire['basekubbs_a'], 3);
      expect(wire['basekubbs_b'], 3);
      expect(wire['king_outcome'], 'missed');
    });

    test('SetWinner.teamA -> "A", teamB -> "B"', () {
      expect(
        TournamentRepository.setScoreToWireForTest(
          1,
          SetScore(
            basekubbsKnockedByA: 5,
            basekubbsKnockedByB: 1,
            winner: SetWinner.teamA,
          ),
        )['winner'],
        'A',
      );
      expect(
        TournamentRepository.setScoreToWireForTest(
          2,
          SetScore(
            basekubbsKnockedByA: 1,
            basekubbsKnockedByB: 5,
            winner: SetWinner.teamB,
          ),
        )['winner'],
        'B',
      );
    });
  });
}
