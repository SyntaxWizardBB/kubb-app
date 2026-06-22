import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

import '../golden/sm_einzel_2026_fixture.dart';

/// Builds [ParticipantStats] for [id] from the real SM-Einzel-2026 match list,
/// mirroring what `computeStandings` accumulates: per-opponent totals plus the
/// points the opponent scored against [id] (the §5 H2H subtrahend). Bye
/// matches add nothing on the bye player's side but their 16-point credit
/// stays in the bye player's total (and so in everyone else's opponent total).
ParticipantStats _statsFromFixture(String id, Map<String, int> totals) {
  final opponentIds = <String>[];
  final scoreAgainst = <String, int>{};
  for (final m in smEinzel2026Matches) {
    if (m.isBye) continue;
    final String opp;
    final int oppPoints;
    if (m.participantA == id) {
      opp = m.participantB!;
      oppPoints = m.pointsB;
    } else if (m.participantB == id) {
      opp = m.participantA;
      oppPoints = m.pointsA;
    } else {
      continue;
    }
    opponentIds.add(opp);
    scoreAgainst.update(opp, (v) => v + oppPoints, ifAbsent: () => oppPoints);
  }
  return ParticipantStats(
    participantId: id,
    totalPoints: totals[id]!,
    wins: 0,
    kubbsScored: 0,
    kubbsConceded: 0,
    opponentIds: opponentIds,
    opponentTotalPointsLookup: {
      for (final o in opponentIds) o: totals[o]!,
    },
    opponentScoreAgainstLookup: scoreAgainst,
    headToHeadLookup: const {},
  );
}

/// Player totals = own score sum over all rounds, bye = 16. Computed straight
/// from the fixture so the parity check does not lean on the expected vectors.
Map<String, int> _totals() {
  final totals = {for (final id in smEinzel2026Participants) id: 0};
  for (final m in smEinzel2026Matches) {
    if (m.isBye) {
      totals[m.participantA] = totals[m.participantA]! + m.pointsA;
      continue;
    }
    totals[m.participantA] = totals[m.participantA]! + m.pointsA;
    totals[m.participantB!] = totals[m.participantB!]! + m.pointsB;
  }
  return totals;
}

void main() {
  group('ParticipantStats.buchholz parity with calculator', () {
    const calc = BuchholzCalculator();
    final totals = _totals();

    for (final id in smEinzel2026Participants) {
      test('$id: stats.buchholz equals BuchholzCalculator.scoreFor', () {
        final stats = _statsFromFixture(id, totals);
        expect(
          stats.buchholz,
          equals(calc.scoreFor(id, smEinzel2026Matches)),
        );
      });
    }
  });
}
