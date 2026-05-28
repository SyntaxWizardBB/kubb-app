// W2-T2 (R11-F-01): generators that pin the `kingOutcome` named parameter
// on `SetScore`. The parameter lands in W2-T3; until then the ignore keeps
// `dart analyze` clean. Test loading fails until the impl is in place —
// that is the expected red-state for the test-first hand-off.
// ignore_for_file: undefined_named_parameter

import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

import 'king_outcome_stub.dart';

extension KingOutcomeAnys on Any {
  /// A set whose king-outcome is explicitly `TimedOut`. Used by the
  /// R11-F-01 property test asserting the additive-null contract.
  Generator<SetScore> get timedOutSet =>
      combine3<int, int, bool, SetScore>(
        intInRange(0, 6),
        intInRange(0, 6),
        any.bool,
        (a, b, aWon) => SetScore(
          basekubbsKnockedByA: a,
          basekubbsKnockedByB: b,
          winner: aWon ? SetWinner.teamA : SetWinner.teamB,
          kingOutcome: const KingTimedOut(),
        ),
      );

  /// An EKC match score where every set has `KingOutcome.TimedOut`.
  Generator<MatchEkcScore> timedOutMatch({int maxSets = 5}) {
    return intInRange(1, maxSets).bind(
      (n) => listWithLength(n, timedOutSet).map(MatchEkcScore.new),
    );
  }
}
