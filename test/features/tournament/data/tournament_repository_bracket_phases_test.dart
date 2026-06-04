import 'package:flutter_test/flutter_test.dart';
import 'package:kubb_app/features/tournament/data/tournament_repository.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// C10 regression: the `getBracket` phase filter must list EVERY non-`group`
/// phase known to `kBracketPhaseWire`, otherwise rows of an omitted phase are
/// silently dropped before `bracketFromMatches` rebuilds the tree. The
/// ADR-0028 consolation phases were the original omission.
void main() {
  test('bracketReadPhases covers every non-group kBracketPhaseWire value', () {
    final expected = kBracketPhaseWire.keys.where((p) => p != 'group').toSet();
    expect(
      TournamentRepository.bracketReadPhases.toSet(),
      equals(expected),
      reason: 'Every bracket phase must be selected by getBracket; '
          'a missing phase would never reach the UI.',
    );
    // Explicitly assert the consolation phases are present (the C10 fix).
    expect(
      TournamentRepository.bracketReadPhases,
      containsAll(<String>['consolation', 'consolation_third_place']),
    );
  });
}
