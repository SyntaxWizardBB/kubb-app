import 'package:glados/glados.dart';
import 'package:kubb_domain/kubb_domain.dart';

/// TASK-M2.1-T10: deterministic tiebreaker for rank 3 vs. rank 4
/// (Halbfinal-Verlierer-Ordering when `withThirdPlace = false`).
///
/// ADR-0017 §4 last paragraph requires the chain to yield a stable order
/// for the two semifinal losers from their group-stage standings; otherwise
/// downstream league-point allocation (M5) is arbitrary.
const _chain = TiebreakerChain([
  TiebreakerCriterion.totalPoints,
  TiebreakerCriterion.buchholzMinusH2H,
  TiebreakerCriterion.medianBuchholz,
  TiebreakerCriterion.kubbDifference,
  TiebreakerCriterion.directComparison,
  TiebreakerCriterion.wins,
]);

ParticipantStats _loser(String id, {int scored = 50, int conceded = 30}) =>
    ParticipantStats(
      participantId: id,
      totalPoints: 12,
      wins: 4,
      kubbsScored: scored,
      kubbsConceded: conceded,
      opponentIds: const [],
      opponentTotalPointsLookup: const {},
      headToHeadLookup: const {},
    );

void main() {
  group('Tiebreaker determinism for rank 3 vs. 4 (withThirdPlace = false)', () {
    Glados<int>(any.intInRange(-50, 50)).test(
        'kubbDifference separates two semifinal losers otherwise identical',
        (delta) {
      if (delta == 0) return;
      final a = _loser('semi-loser-A');
      final b = _loser('semi-loser-B', conceded: 30 - delta);
      // a.diff = 20, b.diff = 20 + delta.
      final cmp = _chain.compare(a, b);
      expect(cmp, isNot(equals(0)));
      expect(cmp.sign, equals(delta.sign));
      // Repeated calls — 100 runs — must yield identical sign (purity).
      for (var i = 0; i < 100; i++) {
        expect(_chain.compare(a, b), equals(cmp));
      }
    });

    Glados2<String, String>(any.letterOrDigits, any.letterOrDigits).test(
        'fully-identical standings: stable order via participantId fallback',
        (idA, idB) {
      if (idA == idB) return;
      final a = _loser(idA);
      final b = _loser(idB);
      final cmp = _chain.compare(a, b);
      expect(cmp, isNot(equals(0)));
      expect(cmp, equals(idA.compareTo(idB)));
      expect(_chain.compare(b, a), equals(-cmp));
    });
  });
}
