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

/// Buchholz tiebreak (schoch-swiss spec §5): per opponent G, add G's total
/// points minus the points G scored against this participant in their direct
/// match. Higher is better. A bye contributes nothing — it has no opponent.
/// The subtraction drops only the real head-to-head score, so an opponent's
/// own bye (the 16 in their total) still counts (§5.3 edge-case).
class BuchholzCalculator {
  const BuchholzCalculator();

  /// §5 Buchholz for [participantId] across [allMatches].
  int scoreFor(String participantId, List<MatchResult> allMatches) {
    var sum = 0;
    for (final m in allMatches) {
      if (m.isBye) continue;
      final String opp;
      final int oppVsMe;
      if (m.participantA == participantId) {
        opp = m.participantB!;
        oppVsMe = m.pointsB;
      } else if (m.participantB == participantId) {
        opp = m.participantA;
        oppVsMe = m.pointsA;
      } else {
        continue;
      }
      sum += _pointsOf(opp, allMatches) - oppVsMe;
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
