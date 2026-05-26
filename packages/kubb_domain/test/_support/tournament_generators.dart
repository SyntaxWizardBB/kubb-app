import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// Shared glados generators for tournament property tests.
///
/// Identifiers are synthetic ('p0', 'p1', ...) so a uniqueness invariant
/// over participant lists is trivially satisfied without ad-hoc filtering.
extension TournamentAnys on Any {
  /// A bounded list of unique alphabetic participant ids.
  Generator<List<String>> participantIds({int min = 2, int max = 16}) {
    return intInRange(min, max).map(
      (n) => List<String>.generate(n, (i) => 'p$i', growable: false),
    );
  }

  /// Participant-id list whose length is **not** a power of two — keeps
  /// FR-FMT-11 BYE invariants exercised. Range [3, 63].
  Generator<List<String>> participantIdsNonPow2({int min = 3, int max = 63}) {
    return intInRange(min, max).map((n) {
      var size = 1;
      while (size < n) {
        size *= 2;
      }
      final adjusted = (n == size) ? n + 1 : n;
      return List<String>.generate(adjusted, (i) => 'p$i', growable: false);
    });
  }

  /// Power-of-two participant counts used by bracket-size invariants.
  Generator<int> get nextPow2Friendly => choose<int>([1, 2, 4, 8, 16]);

  /// A single set score with bounded basekubb counts and an explicit winner.
  Generator<SetScore> get setScore => combine3<int, int, bool, SetScore>(
        intInRange(0, 6),
        intInRange(0, 6),
        any.bool,
        (a, b, aWon) => SetScore(
          basekubbsKnockedByA: a,
          basekubbsKnockedByB: b,
          winner: aWon ? SetWinner.teamA : SetWinner.teamB,
        ),
      );

  /// An EKC match score with between 1 and [maxSets] sets.
  Generator<MatchEkcScore> matchEkcScore({int maxSets = 5}) {
    return intInRange(1, maxSets).bind(
      (n) => listWithLength(n, setScore).map(MatchEkcScore.new),
    );
  }

  /// Lightweight participant stats for tiebreaker-chain property tests.
  Generator<ParticipantStats> get participantStats => combine4<
        String,
        int,
        int,
        int,
        ParticipantStats>(
        choose<String>(const ['p0', 'p1', 'p2', 'p3', 'p4', 'p5']),
        intInRange(0, 50),
        intInRange(0, 10),
        intInRange(0, 80),
        (id, total, wins, kubbs) => ParticipantStats(
          participantId: id,
          totalPoints: total,
          wins: wins,
          kubbsScored: kubbs,
          kubbsConceded: kubbs ~/ 2,
          opponentIds: const [],
          opponentTotalPointsLookup: const {},
          headToHeadLookup: const {},
        ),
      );
}
