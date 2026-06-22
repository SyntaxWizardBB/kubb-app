import 'package:kubb_domain/kubb_domain.dart';
import 'package:test/test.dart';

import 'sm_einzel_2026_fixture.dart';

/// Real golden gate for the Schoch core: SM Einzel 2026 (kubb.live).
///
/// Two independent paths must reproduce kubb.live 73/73:
///   1. the pure §5 [BuchholzCalculator] over the raw match list, and
///   2. [computeStandings] with a Schoch bye worth 16 ([schochByeScore]),
///      reading the §5 [ParticipantStats.buchholz] getter.
///
/// The bye=16 credit is what links the two requirements: the +16 sits in the
/// bye player's total and so drives the Buchholz of every real opponent they
/// faced. Without it the totals — and therefore the opponents' Buchholz —
/// would be off. The naive opponent-total sum (Buschi = 746) is explicitly
/// wrong; the §5 value is 682.
void main() {
  group('SM Einzel 2026 golden — points', () {
    test('all 73 players match kubb.live via computeStandings (bye = 16)', () {
      final stats = _schochStandings();
      final mismatches = <String>[];
      for (final entry in smEinzel2026ExpectedPoints.entries) {
        final actual = stats[entry.key]!.totalPoints;
        if (actual != entry.value) {
          mismatches.add('${entry.key}: soll ${entry.value}, ist $actual');
        }
      }
      expect(
        mismatches,
        isEmpty,
        reason: 'Punkte-Abweichungen:\n${mismatches.join('\n')}',
      );
      expect(stats.length, 73);
    });

    test('spot-check leaders, mid-field and bye players', () {
      final stats = _schochStandings();
      int pts(String id) => stats[id]!.totalPoints;
      expect(pts('Buschi'), 110);
      expect(pts('Beni the Gun'), 109);
      expect(pts('Sparringspartner'), 102);
      expect(pts('Meff'), 71); // bye R5
      expect(pts('Die Nase'), 44); // bye R1
    });
  });

  group('SM Einzel 2026 golden — Buchholz §5 (pure calculator)', () {
    const calc = BuchholzCalculator();

    test('all 73 players match kubb.live (not the naive sum)', () {
      final mismatches = <String>[];
      for (final entry in smEinzel2026ExpectedBuchholz.entries) {
        final actual = calc.scoreFor(entry.key, smEinzel2026Matches);
        if (actual != entry.value) {
          mismatches.add('${entry.key}: soll ${entry.value}, ist $actual');
        }
      }
      expect(
        mismatches,
        isEmpty,
        reason: 'Buchholz-Abweichungen (§5):\n${mismatches.join('\n')}',
      );
    });

    test('Buschi §5 = 682, not the naive 746', () {
      expect(calc.scoreFor('Buschi', smEinzel2026Matches), 682);
    });

    test('bye player Meff §5 = 411 over his 7 real opponents', () {
      expect(calc.scoreFor('Meff', smEinzel2026Matches), 411);
    });
  });

  group('SM Einzel 2026 golden — Buchholz §5 (standings path)', () {
    test('ParticipantStats.buchholz matches kubb.live for all 73', () {
      final stats = _schochStandings();
      final mismatches = <String>[];
      for (final entry in smEinzel2026ExpectedBuchholz.entries) {
        final actual = stats[entry.key]!.buchholz;
        if (actual != entry.value) {
          mismatches.add('${entry.key}: soll ${entry.value}, ist $actual');
        }
      }
      expect(
        mismatches,
        isEmpty,
        reason: 'Buchholz-Abweichungen (standings):\n${mismatches.join('\n')}',
      );
    });

    test('standings path agrees with the pure calculator for all 73', () {
      const calc = BuchholzCalculator();
      final stats = _schochStandings();
      for (final id in smEinzel2026Participants) {
        expect(
          stats[id]!.buchholz,
          calc.scoreFor(id, smEinzel2026Matches),
          reason: 'standings vs calculator divergence for $id',
        );
      }
    });
  });
}

/// Feeds the 288 matches + 8 byes through [computeStandings] in Schoch mode
/// (bye = 16, [schochByeScore]) and returns the per-id stats.
///
/// kubb.live's "Punkte" are the plain sum of each player's own match scores —
/// no win bonus, no set count. To reproduce that exactly through the EKC
/// path, every match is one set with [SetWinner.none]: the EKC contribution
/// then collapses to `pointsFor = basekubbs` (no +3 winner bonus, no king
/// point), so `totalPoints` equals the recorded score sum and
/// `opponentScoreAgainstLookup` carries the raw head-to-head scores the §5
/// Buchholz getter subtracts. The bye is an empty set; its 16-point credit
/// comes from `byeScoreForUnopposedParticipant`.
Map<String, ParticipantStats> _schochStandings() {
  final results = <TournamentMatchResult>[
    for (final m in smEinzel2026Matches) _matchResult(m),
  ];
  final stats = computeStandings(
    participantIds: smEinzel2026Participants,
    results: results,
    byeScoreForUnopposedParticipant: schochByeScore,
    // Sort order is irrelevant here — the golden assertions look players up
    // by id, not by rank. A single points criterion keeps the chain valid.
    tiebreaker: const TiebreakerChain(<TiebreakerCriterion>[
      TiebreakerCriterion.totalPoints,
    ]),
  );
  return {for (final s in stats) s.participantId: s};
}

/// One match as a [TournamentMatchResult]: a single non-decisive set
/// ([SetWinner.none]) carrying the recorded scores as basekubbs, so the EKC
/// points equal the raw scores. The bye is an empty set.
TournamentMatchResult _matchResult(MatchResult m) {
  if (m.isBye) {
    return TournamentMatchResult(
      participantA: m.participantA,
      participantB: null,
      score: MatchEkcScore(const <SetScore>[]),
    );
  }
  return TournamentMatchResult(
    participantA: m.participantA,
    participantB: m.participantB,
    score: MatchEkcScore(<SetScore>[
      SetScore(
        basekubbsKnockedByA: m.pointsA,
        basekubbsKnockedByB: m.pointsB,
        winner: SetWinner.none,
      ),
    ]),
  );
}
