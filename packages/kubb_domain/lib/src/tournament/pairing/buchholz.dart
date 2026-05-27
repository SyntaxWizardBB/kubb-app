import 'package:meta/meta.dart';

/// Minimal match record consumed by Swiss-System pairing and Buchholz
/// tiebreak. Carries only what the algorithm needs: who played whom and
/// match-points awarded (FR-POINTS-1 schema, default 3-1-0).
///
/// [participantB] is `null` for byes; [pointsA] is the bye-point credit
/// in that case and [pointsB] is ignored.
@immutable
class MatchResult {
  const MatchResult({
    required this.participantA,
    required this.participantB,
    required this.pointsA,
    required this.pointsB,
    required this.roundNumber,
  });

  final String participantA;
  final String? participantB;
  final int pointsA;
  final int pointsB;
  final int roundNumber;

  bool get isBye => participantB == null;
}

/// Buchholz tiebreak: Σ match-points scored by all opponents a participant
/// has faced in prior rounds. Higher is better. Byes count as 0 (the bye
/// "opponent" contributes nothing). Reference: OD-M5-01 Empfehlung B.
class BuchholzCalculator {
  const BuchholzCalculator();

  /// Σ-Opponent-Punkte for [participantId] across [allMatches].
  int scoreFor(String participantId, List<MatchResult> allMatches) {
    final opponents = <String>[];
    for (final m in allMatches) {
      if (m.isBye) continue;
      if (m.participantA == participantId) {
        opponents.add(m.participantB!);
      } else if (m.participantB == participantId) {
        opponents.add(m.participantA);
      }
    }
    var sum = 0;
    for (final opp in opponents) {
      sum += _pointsOf(opp, allMatches);
    }
    return sum;
  }

  int _pointsOf(String id, List<MatchResult> matches) {
    var p = 0;
    for (final m in matches) {
      if (m.participantA == id) p += m.pointsA;
      if (m.participantB == id) p += m.pointsB;
    }
    return p;
  }
}
