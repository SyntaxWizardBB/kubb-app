// W2-T3 (R11-F-01): generators that pin the `kingOutcome` named parameter
// on `SetScore`. The `KingOutcome` sealed class now lives in `kubb_domain`.
import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

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
